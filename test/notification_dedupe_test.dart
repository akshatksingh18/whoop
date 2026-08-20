// Tests for the persistent fire-once dedupe guard added for issue #136.
//
// NotificationCenter.emit must present a given dedupeKey to the OS at most once,
// persisted across restarts, while a fresh (e.g. next-day) key still fires and
// the existing category/quiet-hours gating is untouched. We inject a fake
// present sink (counts calls, no device) and a mocked SharedPreferences.
//
// NOTE — this suite runs with NO sqlite factory registered, so FiredKeyStore's
// atomic SQLite claim is unavailable and every test here exercises its DEGRADED
// SharedPreferences fallback. That's deliberate: the fallback is what runs when
// the DB is torn down mid-background-pass, and it must still dedupe. The atomic
// claim itself (and the legacy-list migration) is covered against a real DB in
// notification_claim_atomic_test.dart.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:openstrap_edge/data/day_label.dart';

import 'package:openstrap_edge/notify/fired_keys.dart';
import 'package:openstrap_edge/notify/notification_center.dart';
import 'package:openstrap_edge/notify/notification_event.dart';
import 'package:openstrap_edge/notify/tap_router.dart';

/// Records every event handed to the OS layer so tests can assert call counts.
class _FakeSink {
  final List<NotificationEvent> shown = [];
  bool grant; // false simulates permission-denied (nothing actually shown)

  _FakeSink({this.grant = true});

  Future<bool> call(NotificationEvent e, {bool allowPermissionPrompt = true}) async {
    if (!grant) return false;
    shown.add(e);
    return true;
  }
}

/// A sink that parks inside the present call until [release] is called, so a
/// test can hold one emit mid-critical-section and prove a second overlapping
/// emit is serialised behind it. [calls] counts entries into present.
///
/// [entered] fires the moment an emit first reaches the parked point, so tests
/// order on that signal rather than a scheduler-dependent delay.
class _GatedSink {
  int calls = 0;
  final List<String> keys = [];
  final Completer<void> _gate = Completer<void>();
  final Completer<void> _entered = Completer<void>();

  /// Completes when the first emit reaches (enters) the present call.
  Future<void> get entered => _entered.future;

  Future<bool> call(NotificationEvent e, {bool allowPermissionPrompt = true}) async {
    calls++;
    keys.add(e.dedupeKey);
    if (!_entered.isCompleted) _entered.complete();
    await _gate.future;
    return true;
  }

  void release() => _gate.complete();
}

/// TODAY's label, never a hardcoded date.
///
/// These keys are date-PREFIXED, and `FiredKeyStore` prunes dated flags older
/// than [FiredKeyStore.retentionDays] (14). A literal date is therefore a time
/// bomb: it works while it is recent, then on one particular morning ages out
/// of the retention window and every dedupe assertion in this file starts
/// failing at once -- with no code change and nothing to point at.
///
/// That is exactly what happened. This suite was written around a fixed date in
/// July, passed CI on 2026-08-04 while it was 12 days old, and began failing
/// once it fell outside the window. Anchoring to `todayLabel()` keeps the keys
/// inside the retention window permanently, which is the condition the dedupe
/// guard is actually specified against.
final String _today = todayLabel();
final String _tomorrow = _dayLabelOffset(1);

String _dayLabelOffset(int days) {
  final d = DateTime.now().add(Duration(days: days));
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

NotificationEvent _ev(
  String dedupeKey, {
  NotifCategory category = NotifCategory.health,
  NotifPriority priority = NotifPriority.critical,
  String? date,
}) =>
    NotificationEvent(
      dedupeKey: dedupeKey,
      category: category,
      priority: priority,
      title: 't',
      body: 'b',
      date: date ?? _today,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final center = NotificationCenter.instance;
  late Future<bool> Function(NotificationEvent, {bool allowPermissionPrompt})
      original;

  setUp(() {
    // Quiet hours off + all categories on, so gating never interferes with the
    // dedupe-focused tests (the gating tests set their own values).
    SharedPreferences.setMockInitialValues({'notif_quiet_enabled': false});
    original = center.presentSink;
  });

  tearDown(() {
    center.presentSink = original;
  });

  group('emit dedupe (issue #136)', () {
    test('same dedupeKey fires the OS notification exactly once', () async {
      final sink = _FakeSink();
      center.presentSink = sink.call;

      final e = _ev('$_today:irregular');
      await center.emit(e);
      await center.emit(e); // re-derive would re-emit the same key
      await center.emit(e);

      expect(sink.shown.length, 1);
    });

    test('a different (next-day) key fires again', () async {
      final sink = _FakeSink();
      center.presentSink = sink.call;

      await center.emit(_ev('$_today:irregular', date: _today));
      await center.emit(_ev('$_tomorrow:irregular', date: _tomorrow));

      expect(sink.shown.length, 2);
      expect(
        sink.shown.map((e) => e.dedupeKey),
        containsAll(['$_today:irregular', '$_tomorrow:irregular']),
      );
    });

    test('the guard survives via SharedPreferences (restart-safe)', () async {
      // First "session": key fires once and is recorded to SharedPreferences —
      // the same on-disk store that survives an app restart on-device.
      final sink1 = _FakeSink();
      center.presentSink = sink1.call;
      await center.emit(_ev('$_today:illness'));
      expect(sink1.shown.length, 1);

      // Second "session": same persisted store — the key is still remembered,
      // so it must NOT fire again.
      final sink2 = _FakeSink();
      center.presentSink = sink2.call;
      await center.emit(_ev('$_today:illness'));
      expect(sink2.shown, isEmpty);
    });

    test('a permission-denied no-op does not consume the key', () async {
      // Present fails (permission denied) → key not recorded → a later grant
      // still lets it fire.
      final denied = _FakeSink(grant: false);
      center.presentSink = denied.call;
      await center.emit(_ev('$_today:temp'));

      final granted = _FakeSink();
      center.presentSink = granted.call;
      await center.emit(_ev('$_today:temp'));
      expect(granted.shown.length, 1);
    });

    // DerivationEngine._runNotifications keys the day's health exception on its
    // highest severity class, so an ESCALATION (plain → medical) gets through
    // once. The reverse used to buzz too: the morning fires ':exception:medical'
    // for a red illness flag, the evening re-derive de-escalates to "low
    // readiness" and the plain ':exception' key was still unclaimed. It now
    // burns the plain slot after a real medical present — this is that sequence.
    test('a de-escalated re-derive does not buzz a second time', () async {
      final sink = _FakeSink();
      center.presentSink = sink.call;

      expect(await center.emit(_ev('$_today:exception:medical')), isTrue);
      await const FiredKeyStore().recordFired('$_today:exception');

      await center.emit(_ev('$_today:exception'));
      expect(sink.shown.length, 1);

      // The other direction still works: tomorrow is a fresh day.
      await center.emit(_ev('$_tomorrow:exception', date: _tomorrow));
      expect(sink.shown.length, 2);
    });
  });

  group('emit still respects gating', () {
    test('a disabled category never presents (and is not recorded)', () async {
      SharedPreferences.setMockInitialValues({'notif_health': false});
      final sink = _FakeSink();
      center.presentSink = sink.call;

      await center.emit(_ev('$_today:illness', category: NotifCategory.health));
      expect(sink.shown, isEmpty);

      // Re-enabling the category later must let the key fire — the gate, not the
      // dedupe guard, suppressed it, so no key should have been recorded.
      expect(await const FiredKeyStore().hasFired('$_today:illness'), isFalse);
    });

    test('quiet hours suppress a non-critical event', () async {
      // A window covering the whole day → now is always inside quiet hours.
      SharedPreferences.setMockInitialValues({
        'notif_quiet_enabled': true,
        'notif_quiet_start': 0,
        'notif_quiet_end': 1440,
      });
      final sink = _FakeSink();
      center.presentSink = sink.call;

      await center.emit(_ev(
        '$_today:recovery',
        category: NotifCategory.recovery,
        priority: NotifPriority.normal,
      ));
      expect(sink.shown, isEmpty);
    });

    test('a critical event overrides quiet hours (default) and still fires once',
        () async {
      SharedPreferences.setMockInitialValues({
        'notif_quiet_enabled': true,
        'notif_quiet_start': 0,
        'notif_quiet_end': 1440,
      });
      final sink = _FakeSink();
      center.presentSink = sink.call;

      final e = _ev('$_today:illness', priority: NotifPriority.critical);
      await center.emit(e);
      await center.emit(e);
      expect(sink.shown.length, 1);
    });
  });

  group('concurrent emit serialisation', () {
    test('two overlapping emits of the SAME key present exactly once',
        () async {
      final sink = _GatedSink();
      center.presentSink = sink.call;

      final e = _ev('$_today:irregular');
      final f1 = center.emit(e);
      final f2 = center.emit(e);
      // Order on the sink's entry signal, not a timer: once the first emit is
      // parked inside present, the second is provably held on the lock (it
      // can't have reached the fired-key check), so exactly one entered.
      await sink.entered;
      expect(sink.calls, 1);
      sink.release();
      await Future.wait([f1, f2]);

      // Second emit saw the now-recorded key and never presented.
      expect(sink.calls, 1);
    });

    test('two overlapping emits of DIFFERENT keys both record (no clobber)',
        () async {
      final sink = _GatedSink();
      center.presentSink = sink.call;

      final f1 = center.emit(_ev('$_today:a'));
      final f2 = center.emit(_ev('$_today:b'));
      // First emit is parked inside present; the second is held on the lock, so
      // its record-key write can only run after the first's — no interleaving.
      await sink.entered;
      sink.release();
      await Future.wait([f1, f2]);

      expect(sink.calls, 2);
      // Independent per-key flags: neither key clobbered the other.
      const store = FiredKeyStore();
      expect(await store.hasFired('$_today:a'), isTrue);
      expect(await store.hasFired('$_today:b'), isTrue);
    });
  });

  group('stress-screen high-stress alert (now routed through emit)', () {
    // The exact event stress_screen.dart builds: health category, default
    // (normal) priority, no route. It used to call presentEvent directly,
    // bypassing both the gate and the dedupe guard — now it goes through emit.
    NotificationEvent highStress() => NotificationEvent(
          dedupeKey: '$_today:high_stress',
          category: NotifCategory.health,
          title: 'High Stress Detected',
          body: 'Your stress score is 82. Consider taking a moment to breathe.',
          date: _today,
        );

    test('dedupes on repeat (was previously re-alerting per screen visit)',
        () async {
      final sink = _FakeSink();
      center.presentSink = sink.call;
      await center.emit(highStress());
      await center.emit(highStress());
      await center.emit(highStress());
      expect(sink.shown.length, 1);
    });

    test('now respects quiet hours (normal priority, no longer bypassing)',
        () async {
      SharedPreferences.setMockInitialValues({
        'notif_quiet_enabled': true,
        'notif_quiet_start': 0,
        'notif_quiet_end': 1440,
      });
      final sink = _FakeSink();
      center.presentSink = sink.call;
      await center.emit(highStress());
      expect(sink.shown, isEmpty);
    });
  });

  group('the auto-detected workout actually reaches the shade', () {
    // The exact event derivation_engine builds for a detected bout. It was
    // emitted on NotifCategory.recovery, which `classOf` maps to null, so
    // `shouldFireOs` dropped it: the suggestion row was written on every derive
    // and the user was never told, in any build. A test that only asserts the
    // row exists passes on that broken code — this one asserts the OS saw it.
    const sugId = '2026-08-19:1755625800';
    NotificationEvent detected() => NotificationEvent(
          dedupeKey: '$_today:$sugId:auto_workout',
          category: NotifCategory.reminders,
          title: 'Did you work out?',
          body: 'We spotted ~42 min of elevated activity. Tap to log it.',
          date: _today,
          route: workoutSuggestionRoute(sugId),
        );

    test('it fires, and it carries the bout it is about', () async {
      final sink = _FakeSink();
      center.presentSink = sink.call;
      expect(await center.emit(detected()), isTrue);
      // The payload is what the OS hands back on the tap; the id has to survive
      // it (the colon in the row id is percent-encoded in the query).
      expect(routeId(sink.shown.single.route!), sugId);
    });

    test('one detected workout, one notification — never per derive pass',
        () async {
      final sink = _FakeSink();
      center.presentSink = sink.call;
      // Derivation re-detects the same bout on every drain and every 15-min
      // background pass. The key is the suggestion id, so they all collapse.
      for (var i = 0; i < 5; i++) {
        await center.emit(detected());
      }
      expect(sink.shown.length, 1);
    });

    test('the auto-detect switch silences it', () async {
      SharedPreferences.setMockInitialValues({
        'notif_quiet_enabled': false,
        'notif_auto_detect': false,
      });
      final sink = _FakeSink();
      center.presentSink = sink.call;
      expect(await center.emit(detected()), isFalse);
      expect(sink.shown, isEmpty);
    });

    test('quiet hours silence it — it is a prompt, not the alarm', () async {
      SharedPreferences.setMockInitialValues({
        'notif_quiet_enabled': true,
        'notif_quiet_start': 0,
        'notif_quiet_end': 1440,
      });
      final sink = _FakeSink();
      center.presentSink = sink.call;
      expect(await center.emit(detected()), isFalse);
    });
  });

  group('FiredKeyStore per-key + retention (degraded mode)', () {
    // A local YYYY-MM-DD offset from today, for retention-window assertions.
    // dayLabelOf, not raw toIso8601String: day labels are LOCAL everywhere, and
    // the store's own cutoff is computed the same way.
    String dayOffset(int days) =>
        dayLabelOf(DateTime.now().add(Duration(days: days)));

    test('hasFired reflects recordFired', () async {
      SharedPreferences.setMockInitialValues({});
      const store = FiredKeyStore();
      expect(await store.hasFired('a'), isFalse);
      await store.recordFired('a');
      expect(await store.hasFired('a'), isTrue);
    });

    test('independent per-key flags — a record never clobbers another key',
        () async {
      SharedPreferences.setMockInitialValues({});
      const store = FiredKeyStore();
      await store.recordFired('${dayOffset(0)}:a');
      await store.recordFired('${dayOffset(0)}:b');
      await store.recordFired('${dayOffset(0)}:a'); // repeat — idempotent no-op
      expect(await store.hasFired('${dayOffset(0)}:a'), isTrue);
      expect(await store.hasFired('${dayOffset(0)}:b'), isTrue);
    });

    test('prune drops date-prefixed flags older than the retention window',
        () async {
      // Seed a clearly-stale dated flag directly (bypassing recordFired, whose
      // own prune would eat it immediately), plus a within-window one.
      final stale = '${dayOffset(-(FiredKeyStore.retentionDays + 5))}:low_read';
      final fresh = '${dayOffset(-1)}:low_read';
      SharedPreferences.setMockInitialValues({
        'notif_fired:$stale': true,
        'notif_fired:$fresh': true,
      });
      const store = FiredKeyStore();
      // Any record triggers a prune pass.
      await store.recordFired('${dayOffset(0)}:trigger');
      expect(await store.hasFired(stale), isFalse); // pruned
      expect(await store.hasFired(fresh), isTrue); // retained
    });

    test('prune leaves undated keys (e.g. alarm_fired:<epoch>) untouched',
        () async {
      SharedPreferences.setMockInitialValues({
        'notif_fired:alarm_fired:12345': true,
      });
      const store = FiredKeyStore();
      await store.recordFired('${dayOffset(0)}:trigger');
      expect(await store.hasFired('alarm_fired:12345'), isTrue);
    });
  });
}
