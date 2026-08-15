// Regression tests for the once-per-day notification guard.
//
// AppState's "your recovery is ready" (_kLastRecoveryNotifDay) and "step goal
// reached" (_kLastStepGoalDay) used to write their persisted day-guard BEFORE
// calling NotificationCenter.emit. emit DROPS the event outright when
// NotificationPrefs.shouldFireOs says no — and the DEFAULT quiet window is
// 22:00–07:00, which a band syncing at 06:40 (the heavy finalize that computes
// the new day's recovery) sits squarely inside. So the guard was burned on a
// notification that never reached the user, and it then blocked every retry for
// the rest of the day: "Your recovery is ready" simply never fired.
//
// NotificationCenter.emitOncePerDay is the fixed sequencing (claim the guard
// only on a real present) and emit now REPORTS whether it presented.
//
// The event used here is the day's aggregated health EXCEPTION rather than the
// old "your recovery is ready", which is no longer one of the three sanctioned
// notification classes and is now dropped by shouldFireOs. The sequencing under
// test is the same: a non-critical event, suppressible by quiet hours, guarded
// once per day.
//
// NOTE — no sqlite factory is registered here, so FiredKeyStore runs in its
// degraded shared_preferences mode. That's fine: this suite is about the DAY
// guard, not the cross-isolate claim (see notification_claim_atomic_test.dart).

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/notify/notification_center.dart';
import 'package:openstrap_edge/notify/notification_event.dart';
import 'package:openstrap_edge/notify/notification_ids.dart';
import 'package:openstrap_edge/notify/notification_service.dart';

const String kGuardKey = 'last_recovery_notif_day';
final String kDay = todayLabel();
final String kTomorrow = dayLabelOf(DateTime.now().add(const Duration(days: 1)));

NotificationEvent _dayException({String? day}) {
  final d = day ?? kDay;
  return NotificationEvent(
    dedupeKey: '$d:exception',
    category: NotifCategory.health,
    priority: NotifPriority.normal,
    title: 'Low readiness today',
    body: 'Your recovery markers are below your usual range — ease off.',
    date: d,
    route: '/heart',
  );
}

class _Sink {
  final List<String> shown = [];
  bool grant;
  _Sink({this.grant = true});
  Future<bool> call(NotificationEvent e,
      {bool allowPermissionPrompt = true}) async {
    if (!grant) return false;
    shown.add(e.dedupeKey);
    return true;
  }
}

/// Prefs values that make the quiet window cover the entire 24 h, so a
/// non-critical event is deterministically suppressed regardless of the
/// wall-clock the test happens to run at.
Map<String, Object> _quietAllDay() => {
      'notif_quiet_enabled': true,
      'notif_quiet_start': 0,
      'notif_quiet_end': 1440,
    };

/// The mirror of [_quietAllDay], for the cases that expect a present to SUCCEED.
///
/// These used to pass `{}` and inherit the DEFAULT quiet window of 22:00–07:00.
/// Since nothing here stubs the clock, every "returns true on a real present"
/// assertion failed for nine hours a night on a developer machine and passed on
/// CI purely because CI happened to run at a different hour. Pin the window off
/// so the outcome depends on the code under test, not on what time it is.
Map<String, Object> _quietNever() => {'notif_quiet_enabled': false};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final original = NotificationCenter.instance.presentSink;
  tearDown(() => NotificationCenter.instance.presentSink = original);

  setUp(() {
    NotificationIds.instance.resetForTest();
  });

  group('emit reports whether the event actually reached the OS', () {
    test('returns false when quiet hours suppress it', () async {
      SharedPreferences.setMockInitialValues(_quietAllDay());
      final sink = _Sink();
      NotificationCenter.instance.presentSink = sink.call;
      expect(await NotificationCenter.instance.emit(_dayException()), isFalse);
      expect(sink.shown, isEmpty);
    });

    test('returns false when the OS present is refused (permission denied)',
        () async {
      SharedPreferences.setMockInitialValues(_quietNever());
      final sink = _Sink(grant: false);
      NotificationCenter.instance.presentSink = sink.call;
      expect(await NotificationCenter.instance.emit(_dayException()), isFalse);
    });

    test('returns true on a real present', () async {
      SharedPreferences.setMockInitialValues(_quietNever());
      final sink = _Sink();
      NotificationCenter.instance.presentSink = sink.call;
      expect(await NotificationCenter.instance.emit(_dayException()), isTrue);
      expect(sink.shown, ['$kDay:exception']);
    });
  });

  group('emitOncePerDay consumes the guard only on a real present', () {
    test('a quiet-hours suppression does NOT burn the day guard, and the '
        'retry once quiet hours end still fires', () async {
      SharedPreferences.setMockInitialValues(_quietAllDay());
      final sink = _Sink();
      NotificationCenter.instance.presentSink = sink.call;

      // 06:40 sync inside the quiet window → suppressed.
      final firstTry = await NotificationCenter.instance.emitOncePerDay(
        prefsKey: kGuardKey,
        dayId: kDay,
        e: _dayException(),
      );
      expect(firstTry, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kGuardKey), isNull,
          reason: 'the guard must not be consumed by an event that never '
              'reached the user');

      // Quiet hours over — the next derive pass must still be able to fire.
      await prefs.setBool('notif_quiet_enabled', false);
      final retry = await NotificationCenter.instance.emitOncePerDay(
        prefsKey: kGuardKey,
        dayId: kDay,
        e: _dayException(),
      );
      expect(retry, isTrue);
      expect(sink.shown, ['$kDay:exception']);
      expect(prefs.getString(kGuardKey), kDay);
    });

    test('a permission-denied no-op does NOT burn the day guard either',
        () async {
      SharedPreferences.setMockInitialValues(_quietNever());
      final sink = _Sink(grant: false);
      NotificationCenter.instance.presentSink = sink.call;

      expect(
        await NotificationCenter.instance.emitOncePerDay(
            prefsKey: kGuardKey, dayId: kDay, e: _dayException()),
        isFalse,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kGuardKey), isNull);

      sink.grant = true;
      expect(
        await NotificationCenter.instance.emitOncePerDay(
            prefsKey: kGuardKey, dayId: kDay, e: _dayException()),
        isTrue,
      );
      expect(prefs.getString(kGuardKey), kDay);
    });

    test('a real present consumes the guard, and the same day never re-fires',
        () async {
      SharedPreferences.setMockInitialValues(_quietNever());
      final sink = _Sink();
      NotificationCenter.instance.presentSink = sink.call;

      expect(
        await NotificationCenter.instance.emitOncePerDay(
            prefsKey: kGuardKey, dayId: kDay, e: _dayException()),
        isTrue,
      );
      expect(
        await NotificationCenter.instance.emitOncePerDay(
            prefsKey: kGuardKey, dayId: kDay, e: _dayException()),
        isFalse,
      );
      expect(sink.shown.length, 1);
    });

    test('a NEW day is a fresh guard', () async {
      SharedPreferences.setMockInitialValues({
        ..._quietNever(),
        kGuardKey: kDay,
      });
      final sink = _Sink();
      NotificationCenter.instance.presentSink = sink.call;

      expect(
        await NotificationCenter.instance.emitOncePerDay(
            prefsKey: kGuardKey, dayId: kDay, e: _dayException()),
        isFalse,
      );
      expect(
        await NotificationCenter.instance.emitOncePerDay(
            prefsKey: kGuardKey,
            dayId: kTomorrow,
            e: _dayException(day: kTomorrow)),
        isTrue,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kGuardKey), kTomorrow);
    });
  });

  // Sanity: the service singleton's permission cache must not leak between the
  // suites in this file (emitOncePerDay never touches it, but presentSink does
  // in production).
  tearDownAll(() => NotificationService.instance.invalidatePermissionCache());
}
