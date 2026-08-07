// Tests for the charging/low-battery alert de-dupe (issue #179 — "repeated
// 'band is on the charger' well after the charger was removed").
//
// The strap dumps its buffered event log on connect and re-sends events it has
// already delivered, so DeviceAlerts cannot treat a chargingOn frame as proof
// that the puck went on just now. Two guards are asserted here:
//   • RECENCY — an hours-old chargingOn is a backlog replay, not news.
//   • IDENTITY — a charge session already announced never announces again, and
//     the record of that survives a process restart (the Android failure: the
//     pre-warmed engine + KeepAliveWorker + START_STICKY FGS recreate the
//     process routinely, and the edge state used to live only in RAM).
//
// Both fakes are injected, so nothing here touches the platform plugin or real
// SharedPreferences.

import 'package:flutter_test/flutter_test.dart';

import 'package:openstrap_edge/notify/charge_alert_policy.dart';
import 'package:openstrap_edge/notify/device_alerts.dart';
import 'package:openstrap_edge/notify/notification_service.dart';

class _Shown {
  final int id;
  final String title;
  _Shown(this.id, this.title);
}

class _FakeSink implements DeviceAlertSink {
  final List<_Shown> shown = [];
  final List<int> cancelled = [];

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
  }) async {
    shown.add(_Shown(id, title));
  }

  @override
  Future<void> cancel(int id) async => cancelled.add(id);

  int countOf(int id) => shown.where((s) => s.id == id).length;
}

/// Survives across DeviceAlerts instances, exactly like SharedPreferences does
/// across Android process restarts.
class _FakeStore implements DeviceAlertStore {
  final Map<String, int> values = {};

  @override
  Future<int?> readInt(String key) async => values[key];

  @override
  Future<void> writeInt(String key, int value) async => values[key] = value;
}

/// A sink whose presentation always fails — the platform plugin unavailable in
/// a headless wake. Counts attempts so a stuck latch shows up as a retry storm.
class _ThrowingSink implements DeviceAlertSink {
  int attempts = 0;

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
  }) async {
    attempts++;
    throw StateError('unavailable');
  }

  @override
  Future<void> cancel(int id) async {}
}

/// A store whose reads always fail — e.g. SharedPreferences unavailable during a
/// headless wake. Alerts must degrade to "no persisted history", not stop.
class _ThrowingStore implements DeviceAlertStore {
  @override
  Future<int?> readInt(String key) async => throw StateError('unavailable');

  @override
  Future<void> writeInt(String key, int value) async =>
      throw StateError('unavailable');
}

/// Strap timestamp [ageSec] seconds in the past, relative to the wall clock the
/// production code reads.
int tsAged(int ageSec) =>
    (DateTime.now().millisecondsSinceEpoch ~/ 1000) - ageSec;

void main() {
  group('ChargeAlertPolicy', () {
    const now = 1800000000;

    ChargeAlertVerdict verdict({
      int? eventTs,
      bool? wasCharging,
      int? lastTs,
      int? lastWall,
    }) =>
        ChargeAlertPolicy.evaluate(
          eventTsEpoch: eventTs,
          wallNowSec: now,
          wasCharging: wasCharging,
          lastAnnouncedEventTs: lastTs,
          lastAnnouncedWallSec: lastWall,
        );

    test('a fresh plug-in announces', () {
      expect(verdict(eventTs: now - 5), ChargeAlertVerdict.announce);
    });

    test('a delayed-but-real delivery still announces', () {
      // Real first-delivery lags measured in a user export: 0 s, 105 s, 226 s
      // (the app reconnecting minutes after the puck went on). These are the
      // alerts a naive tight window would silence while fixing nothing.
      for (final lag in [0, 105, 226]) {
        expect(verdict(eventTs: now - lag), ChargeAlertVerdict.announce,
            reason: 'lag=${lag}s is a real plug-in, not a replay');
      }
    });

    test('an hours-old backlog replay is stale', () {
      expect(verdict(eventTs: now - 3600), ChargeAlertVerdict.stale);
      expect(verdict(eventTs: now - 30367), ChargeAlertVerdict.stale);
    });

    test('a replay older than a day is still stale, not "cannot tell"', () {
      // Regression: an earlier draft capped usability at 24 h (mirroring
      // GestureDispatcher), which sent a multi-day-old event down the UNTIMED
      // path — where it announced. The strap banks days of data, so an old
      // plausible timestamp is a real old event, not a broken clock.
      expect(verdict(eventTs: now - 2 * 86400), ChargeAlertVerdict.stale);
      expect(verdict(eventTs: now - 7 * 86400), ChargeAlertVerdict.stale);
    });

    test('already charging suppresses regardless of timestamp', () {
      expect(verdict(eventTs: now, wasCharging: true),
          ChargeAlertVerdict.alreadyCharging);
    });

    test('a re-send of an announced session is suppressed by identity', () {
      final ts = now - 60;
      expect(verdict(eventTs: ts, lastTs: ts, lastWall: now - 60),
          ChargeAlertVerdict.alreadyAnnounced);
      // An OLDER session replayed after a newer one was announced.
      expect(verdict(eventTs: ts - 30, lastTs: ts, lastWall: now - 60),
          ChargeAlertVerdict.alreadyAnnounced);
    });

    test('a genuinely newer session beats the identity high-water', () {
      expect(verdict(eventTs: now - 10, lastTs: now - 600, lastWall: now - 600),
          ChargeAlertVerdict.announce);
    });

    test('identity suppression expires so a backwards strap clock cannot '
        'silence alerts forever', () {
      // A strap clock that jumps backwards into a still-plausible range would
      // otherwise never beat the stored high-water again.
      final stale = now - ChargeAlertPolicy.identityExpirySec - 1;
      expect(verdict(eventTs: now - 10, lastTs: now + 999999, lastWall: stale),
          ChargeAlertVerdict.announce);
    });

    test('an unusable strap timestamp falls back to a cooldown', () {
      // Unset RTC (below the plausible-unix floor) — cannot judge staleness.
      expect(verdict(eventTs: 42), ChargeAlertVerdict.announce);
      expect(verdict(eventTs: 42, lastWall: now - 60), ChargeAlertVerdict.cooldown);
      expect(verdict(eventTs: null, lastWall: now - 60),
          ChargeAlertVerdict.cooldown);
      expect(
          verdict(
              eventTs: 42,
              lastWall: now - ChargeAlertPolicy.untimedCooldownSec - 1),
          ChargeAlertVerdict.announce);
    });

    test('timestampUsable rejects unset and far-future clocks', () {
      expect(ChargeAlertPolicy.timestampUsable(null, wallNowSec: now), isFalse);
      expect(ChargeAlertPolicy.timestampUsable(42, wallNowSec: now), isFalse);
      expect(
          ChargeAlertPolicy.timestampUsable(now + 99999, wallNowSec: now),
          isFalse);
      expect(ChargeAlertPolicy.timestampUsable(now - 60, wallNowSec: now),
          isTrue);
      // Inside the tolerance for a strap clock running slightly fast.
      expect(ChargeAlertPolicy.timestampUsable(now + 60, wallNowSec: now),
          isTrue);
      // Old but plausible is USABLE (and therefore judged stale, not guessed at).
      expect(ChargeAlertPolicy.timestampUsable(now - 200000, wallNowSec: now),
          isTrue);
    });

    test('isStale only judges timestamps it can trust', () {
      expect(ChargeAlertPolicy.isStale(now - 3600, wallNowSec: now), isTrue);
      expect(ChargeAlertPolicy.isStale(now - 60, wallNowSec: now), isFalse);
      // Unset RTC → no opinion, so callers fall back rather than act on a guess.
      expect(ChargeAlertPolicy.isStale(42, wallNowSec: now), isFalse);
      expect(ChargeAlertPolicy.isStale(null, wallNowSec: now), isFalse);
    });
  });

  group('DeviceAlerts charging', () {
    late _FakeSink sink;
    late _FakeStore store;

    setUp(() {
      sink = _FakeSink();
      store = _FakeStore();
    });

    DeviceAlerts alerts() => DeviceAlerts(sink: sink, store: store);

    test('a live plug-in notifies exactly once', () async {
      final a = alerts();
      a.onDeviceState(charging: true, chargingTs: tsAged(2));
      await a.settled;
      expect(sink.countOf(NotificationService.idCharging), 1);

      // Later updates carry the same unchanged charging flag.
      a.onDeviceState(batteryPct: 40, charging: true, chargingTs: tsAged(2));
      a.onDeviceState(batteryPct: 41, charging: true, chargingTs: tsAged(2));
      await a.settled;
      expect(sink.countOf(NotificationService.idCharging), 1);
    });

    test('an hours-old replayed chargingOn never notifies', () async {
      final a = alerts();
      a.onDeviceState(charging: true, chargingTs: tsAged(8 * 3600));
      await a.settled;
      expect(sink.countOf(NotificationService.idCharging), 0);
    });

    test('the reported #179 loop: replay after removal, across restarts',
        () async {
      // Morning: the puck really does go on → one legitimate alert.
      final morning = alerts();
      final chargeTs = tsAged(4);
      morning.onDeviceState(charging: true, chargingTs: chargeTs);
      await morning.settled;
      expect(sink.countOf(NotificationService.idCharging), 1);

      // Charger removed.
      morning.onDeviceState(charging: false, chargingTs: tsAged(1));
      await morning.settled;
      expect(sink.cancelled, contains(NotificationService.idCharging));

      // The strap re-sends the SAME chargingOn (measured: up to 4x, each with a
      // different frame seq so nothing upstream de-dupes them).
      for (var i = 0; i < 4; i++) {
        morning.onDeviceState(charging: true, chargingTs: chargeTs);
        morning.onDeviceState(charging: false, chargingTs: chargeTs + 1);
        await morning.settled;
      }
      expect(sink.countOf(NotificationService.idCharging), 1);

      // Android recreates the process repeatedly; each restart used to re-arm
      // the alert and the next replay buzzed again.
      for (var i = 0; i < 5; i++) {
        final restarted = alerts();
        restarted.onDeviceState(charging: true, chargingTs: chargeTs);
        await restarted.settled;
      }
      expect(sink.countOf(NotificationService.idCharging), 1);
    });

    test('a genuinely new charge session still notifies after a restart',
        () async {
      final first = alerts();
      first.onDeviceState(charging: true, chargingTs: tsAged(600));
      await first.settled;
      first.onDeviceState(charging: false, chargingTs: tsAged(500));
      await first.settled;
      expect(sink.countOf(NotificationService.idCharging), 1);

      final later = alerts(); // new process, same persisted store
      later.onDeviceState(charging: true, chargingTs: tsAged(3));
      await later.settled;
      expect(sink.countOf(NotificationService.idCharging), 2);
    });

    test('charging off clears the card even on a fresh process', () async {
      final a = alerts();
      // _wasCharging is null here — a restart while the card sits in the tray.
      a.onDeviceState(charging: false, chargingTs: tsAged(5));
      await a.settled;
      expect(sink.cancelled, contains(NotificationService.idCharging));
    });

    test('an unset strap RTC notifies once, then holds off', () async {
      final a = alerts();
      a.onDeviceState(charging: true, chargingTs: 0);
      await a.settled;
      a.onDeviceState(charging: false, chargingTs: 0);
      await a.settled;
      a.onDeviceState(charging: true, chargingTs: 0);
      await a.settled;
      expect(sink.countOf(NotificationService.idCharging), 1);
    });

    test('a replayed chargingOff does not clear a live Charging card',
        () async {
      final a = alerts();
      a.onDeviceState(charging: true, chargingTs: tsAged(3));
      await a.settled;
      expect(sink.countOf(NotificationService.idCharging), 1);

      // The strap replays a chargingOff from a PREVIOUS session while the band
      // is genuinely on the charger right now.
      a.onDeviceState(charging: false, chargingTs: tsAged(9 * 3600));
      await a.settled;
      expect(sink.cancelled, isNot(contains(NotificationService.idCharging)));

      // The real removal still clears it.
      a.onDeviceState(charging: false, chargingTs: tsAged(2));
      await a.settled;
      expect(sink.cancelled, contains(NotificationService.idCharging));
    });

    test('a stale on/off pair does not swallow the next genuine plug-in',
        () async {
      final a = alerts();
      // Whole backlogged charge session replayed at once — neither announces.
      a.onDeviceState(charging: true, chargingTs: tsAged(9 * 3600));
      a.onDeviceState(charging: false, chargingTs: tsAged(8 * 3600));
      await a.settled;
      expect(sink.countOf(NotificationService.idCharging), 0);

      // A stale chargingOn re-opens the cancel latch; the stale chargingOff that
      // follows must still not clear a card. Pinned because the interaction
      // between the two latches is subtle enough to break silently.
      expect(sink.cancelled, isNot(contains(NotificationService.idCharging)));

      // The band really goes on the charger now.
      a.onDeviceState(charging: true, chargingTs: tsAged(2));
      await a.settled;
      expect(sink.countOf(NotificationService.idCharging), 1);
    });

    test('a failing sink still lets the announcement persist', () async {
      // Presentation and persistence must not take each other down: a throwing
      // plugin used to skip the writes below it, so the session re-announced
      // after a restart.
      final failing = _ThrowingSink();
      final a = DeviceAlerts(sink: failing, store: store);
      a.onDeviceState(charging: true, chargingTs: tsAged(3));
      await a.settled;
      expect(failing.attempts, 1);
      expect(store.values[DeviceAlerts.debugLastChargeWallKey], isNotNull);
      expect(store.values[DeviceAlerts.debugLastChargeTsKey], isNotNull);

      // A restart therefore knows the session was already announced.
      final restarted = DeviceAlerts(sink: sink, store: store);
      restarted.onDeviceState(charging: true, chargingTs: tsAged(3));
      await restarted.settled;
      expect(sink.countOf(NotificationService.idCharging), 0);
    });

    test('an untimed announce clears the identity high-water', () async {
      // A session announced with no usable clock has no identity of its own.
      // Keeping the previous high-water would let it judge a session it knows
      // nothing about and silently swallow a real confirmation.
      // A session announced two hours ago, whose strap timestamp landed at the
      // top of the allowed slightly-ahead-of-phone tolerance.
      store.values[DeviceAlerts.debugLastChargeTsKey] = tsAged(-240);
      store.values[DeviceAlerts.debugLastChargeWallKey] = tsAged(2 * 3600);

      // RTC lost → announced via the untimed path (past the untimed cooldown).
      final untimed = alerts();
      untimed.onDeviceState(charging: true, chargingTs: 0);
      await untimed.settled;
      expect(sink.countOf(NotificationService.idCharging), 1);
      expect(store.values[DeviceAlerts.debugLastChargeTsKey], 0);

      // RTC restored. This session is genuinely new, but its timestamp is BELOW
      // the old high-water, so an uncleared identity check would suppress it.
      final restored = alerts();
      restored.onDeviceState(charging: true, chargingTs: tsAged(5));
      await restored.settled;
      expect(sink.countOf(NotificationService.idCharging), 2);
    });

    test('a broken store never re-announces the same session', () async {
      // Persistence is dead, so only the in-process latches stand between the
      // strap's re-sends and a repeat. They must be committed before the I/O
      // that throws (AGENTS.md 4.3).
      final a = DeviceAlerts(sink: sink, store: _ThrowingStore());
      final ts = tsAged(3);
      for (var i = 0; i < 4; i++) {
        a.onDeviceState(charging: true, chargingTs: ts);
        await a.settled;
      }
      expect(sink.countOf(NotificationService.idCharging), 1);
    });

    test('a broken store degrades to working alerts, not silence', () async {
      // The restore future is memoised, so a failure that escaped would be
      // re-thrown on every later update and kill alerts for the whole process.
      final a = DeviceAlerts(sink: sink, store: _ThrowingStore());
      a.onDeviceState(charging: true, chargingTs: tsAged(2));
      await a.settled;
      expect(sink.countOf(NotificationService.idCharging), 1);

      a.onDeviceState(charging: false, chargingTs: tsAged(1));
      await a.settled;
      a.onDeviceState(batteryPct: 12);
      await a.settled;
      expect(sink.countOf(NotificationService.idLowBattery), 1);
    });

    test('a burst arriving before the restore resolves notifies once',
        () async {
      final a = alerts();
      final ts = tsAged(2);
      // No await between them: both enter while the persisted read is in flight.
      a.onDeviceState(charging: true, chargingTs: ts);
      a.onDeviceState(charging: true, chargingTs: ts);
      a.onDeviceState(charging: true, chargingTs: ts);
      await a.settled;
      expect(sink.countOf(NotificationService.idCharging), 1);
    });
  });

  group('DeviceAlerts low battery', () {
    late _FakeSink sink;
    late _FakeStore store;

    setUp(() {
      sink = _FakeSink();
      store = _FakeStore();
    });

    DeviceAlerts alerts() => DeviceAlerts(sink: sink, store: store);

    test('fires once per drain', () async {
      final a = alerts();
      a.onDeviceState(batteryPct: 12);
      a.onDeviceState(batteryPct: 11);
      a.onDeviceState(batteryPct: 10);
      await a.settled;
      expect(sink.countOf(NotificationService.idLowBattery), 1);
    });

    test('the once-per-drain guard survives a process restart', () async {
      final first = alerts();
      first.onDeviceState(batteryPct: 12);
      await first.settled;
      expect(sink.countOf(NotificationService.idLowBattery), 1);

      // Same defect class as the charging repeat: RAM-only hysteresis re-armed
      // on every process create.
      for (var i = 0; i < 3; i++) {
        final restarted = alerts();
        restarted.onDeviceState(batteryPct: 11);
        await restarted.settled;
      }
      expect(sink.countOf(NotificationService.idLowBattery), 1);
    });

    test('re-arms after recovering past the hysteresis point', () async {
      final a = alerts();
      a.onDeviceState(batteryPct: 12);
      await a.settled;
      a.onDeviceState(batteryPct: 30);
      await a.settled;
      a.onDeviceState(batteryPct: 12);
      await a.settled;
      expect(sink.countOf(NotificationService.idLowBattery), 2);
    });

    test('a real plug-in re-arms and clears the low card', () async {
      final a = alerts();
      a.onDeviceState(batteryPct: 12);
      await a.settled;
      a.onDeviceState(batteryPct: 12, charging: true, chargingTs: tsAged(2));
      await a.settled;
      expect(sink.cancelled, contains(NotificationService.idLowBattery));

      a.onDeviceState(batteryPct: 12, charging: false, chargingTs: tsAged(1));
      await a.settled;
      expect(sink.countOf(NotificationService.idLowBattery), 2);
    });

    test('a failing sink does not leave the low latch stuck armed', () async {
      // AGENTS.md 4.3: the disarm used to happen after the show, so a throwing
      // sink meant _lowArmed stayed true and the alert was retried on every
      // single update — an alert storm behind a swallowed error.
      final failing = _ThrowingSink();
      final a = DeviceAlerts(sink: failing, store: store);
      for (var i = 0; i < 3; i++) {
        a.onDeviceState(batteryPct: 12);
        await a.settled;
      }
      expect(failing.attempts, 1);
    });

    test('a replayed plug-in does not re-arm the low alert', () async {
      final a = alerts();
      a.onDeviceState(batteryPct: 12);
      await a.settled;
      expect(sink.countOf(NotificationService.idLowBattery), 1);

      // Stale chargingOn: not news, and must not silently reset hysteresis.
      a.onDeviceState(batteryPct: 12, charging: true, chargingTs: tsAged(8 * 3600));
      await a.settled;
      a.onDeviceState(batteryPct: 12, charging: false, chargingTs: tsAged(8 * 3600));
      await a.settled;
      expect(sink.countOf(NotificationService.idLowBattery), 1);
    });

    test('no low alert while charging', () async {
      final a = alerts();
      a.onDeviceState(batteryPct: 12, charging: true, chargingTs: tsAged(2));
      await a.settled;
      expect(sink.countOf(NotificationService.idLowBattery), 0);
    });
  });
}
