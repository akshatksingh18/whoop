// device_alerts.dart — turns the band's battery/charging state into OS alerts.
//
// Fed the latest DeviceState on every BLE update (AppState._onEngineState), but
// it is EDGE-TRIGGERED and de-duped, so it fires at most once per real event —
// never on every tick:
//   • Low battery (< 15%, not charging): once per drain. Re-arms only after the
//     battery recovers past 25% (hysteresis) or goes back on the charger.
//   • Charging started: once per plug-in, gated by [ChargeAlertPolicy].
//
// THE EDGE STATE IS PERSISTED (issue #179). It used to live only in RAM, which
// is wrong on Android specifically: EdgeApplication pre-warms a Dart engine on
// every process create, and KeepAliveWorker + the START_STICKY foreground
// service mean the process is recreated routinely. Each restart reset
// `_wasCharging` to null and re-armed the low-battery hysteresis, so the next
// replayed chargingOn from the strap's flash backlog buzzed all over again —
// the "repeated 'band is on the charger'" report. Anything that must fire "once
// per real event" cannot key off in-memory state alone here.
//
// Presentation goes through NotificationService, the single display layer that a
// future FCM/server-push system also uses — so adding push later doesn't touch
// this file or risk colliding with these alerts.

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

import 'charge_alert_policy.dart';
import 'notification_service.dart';

/// Narrow presentation seam. [NotificationService] has a private constructor and
/// cannot be subclassed from a test, so the alert logic would otherwise only be
/// exercisable against the real platform plugin.
abstract class DeviceAlertSink {
  Future<void> show({
    required int id,
    required String title,
    required String body,
  });
  Future<void> cancel(int id);
}

class _NotificationServiceSink implements DeviceAlertSink {
  const _NotificationServiceSink();

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
  }) =>
      NotificationService.instance.showDevice(id: id, title: title, body: body);

  @override
  Future<void> cancel(int id) => NotificationService.instance.cancel(id);
}

/// Narrow persistence seam for the alert edge state (see the header note on why
/// it must outlive the process).
abstract class DeviceAlertStore {
  Future<int?> readInt(String key);
  Future<void> writeInt(String key, int value);
}

class _PrefsDeviceAlertStore implements DeviceAlertStore {
  const _PrefsDeviceAlertStore();

  @override
  Future<int?> readInt(String key) async {
    try {
      return (await SharedPreferences.getInstance()).getInt(key);
    } catch (_) {
      return null; // a notification must never take down the state update
    }
  }

  @override
  Future<void> writeInt(String key, int value) async {
    try {
      await (await SharedPreferences.getInstance()).setInt(key, value);
    } catch (_) {}
  }
}

class DeviceAlerts {
  static const double _lowPct = 15;
  static const double _rearmPct = 25; // hysteresis so we don't re-fire near 15%

  static const String _kLastChargeTs = 'device_alerts.last_charge_event_ts';
  static const String _kLastChargeWall = 'device_alerts.last_charge_wall_sec';
  static const String _kLowArmed = 'device_alerts.low_armed';

  bool _lowArmed = true; // may we raise a low-battery alert?
  bool? _wasCharging; // previous charging state (null = not seen yet)
  int? _lastAnnouncedEventTs; // strap ts of the last announced charge session
  int? _lastAnnouncedWallSec; // wall time of that announcement

  final DeviceAlertSink _notes;
  final DeviceAlertStore _store;

  /// Guards the restore so a burst of BLE updates arriving before the first
  /// read completes can't each decide independently to announce. Every entry
  /// into [onDeviceState]'s async body awaits it.
  Future<void>? _restored;

  /// Serializes the async bodies. Without it, two updates in the same event-loop
  /// turn both pass the checks before either has written back its state — which
  /// is exactly the double-notification this file exists to prevent, just at a
  /// smaller time scale.
  Future<void> _queue = Future<void>.value();

  DeviceAlerts({DeviceAlertSink? sink, DeviceAlertStore? store})
      : _notes = sink ?? const _NotificationServiceSink(),
        _store = store ?? const _PrefsDeviceAlertStore();

  /// Completes when all queued alert work has settled. Tests only.
  @visibleForTesting
  Future<void> get settled => _queue;

  /// Never completes with an error. [_restored] is memoised, so a failed restore
  /// would otherwise be re-awaited — and re-thrown — by every later update,
  /// silently killing ALL alerts for the life of the process. Falling back to
  /// defaults costs at most one duplicate announcement.
  Future<void> _restore() async {
    try {
      _lastAnnouncedEventTs = await _store.readInt(_kLastChargeTs);
      _lastAnnouncedWallSec = await _store.readInt(_kLastChargeWall);
      final armed = await _store.readInt(_kLowArmed);
      if (armed != null) _lowArmed = armed != 0;
    } catch (_) {}
  }

  Future<void> _setLowArmed(bool armed) async {
    if (_lowArmed == armed) return;
    _lowArmed = armed;
    await _store.writeInt(_kLowArmed, armed ? 1 : 0);
  }

  /// Call with the latest device state. Cheap and safe to call on every update.
  ///
  /// [chargingTs] is the strap timestamp of the event that last set [charging]
  /// (see DeviceState.chargingTs) — the signal that separates a live plug-in
  /// from a replayed one.
  void onDeviceState({double? batteryPct, bool? charging, int? chargingTs}) {
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    _queue = _queue.then((_) async {
      _restored ??= _restore();
      await _restored;
      await _apply(
        batteryPct: batteryPct,
        charging: charging,
        chargingTs: chargingTs,
        nowSec: nowSec,
      );
    }).catchError((_) {
      // An alert is a nicety; it must never break the state pipeline, and a
      // throw must not poison the queue for every later update.
    });
  }

  Future<void> _apply({
    required double? batteryPct,
    required bool? charging,
    required int? chargingTs,
    required int nowSec,
  }) async {
    // Charger removed → clear the "Charging" card. It is a STATE claim, so
    // leaving it in the tray after the puck comes off is wrong on its own; it
    // also re-arms `onlyAlertOnce`, which only suppresses re-alerting while a
    // notification with that id is still showing.
    if (charging == false && _wasCharging != false) {
      await _notes.cancel(NotificationService.idCharging);
    }

    if (charging == true) {
      final verdict = ChargeAlertPolicy.evaluate(
        eventTsEpoch: chargingTs,
        wallNowSec: nowSec,
        wasCharging: _wasCharging,
        lastAnnouncedEventTs: _lastAnnouncedEventTs,
        lastAnnouncedWallSec: _lastAnnouncedWallSec,
      );
      if (verdict == ChargeAlertVerdict.announce) {
        await _notes.show(
          id: NotificationService.idCharging,
          title: 'Charging',
          body: 'Your band is on the charger.',
        );
        _lastAnnouncedWallSec = nowSec;
        await _store.writeInt(_kLastChargeWall, nowSec);
        if (ChargeAlertPolicy.timestampUsable(chargingTs, wallNowSec: nowSec)) {
          _lastAnnouncedEventTs = chargingTs;
          await _store.writeInt(_kLastChargeTs, chargingTs!);
        }
        // A real plug-in clears any stale low alert and re-arms the next drain.
        await _notes.cancel(NotificationService.idLowBattery);
        await _setLowArmed(true);
      }
    }
    if (charging != null) _wasCharging = charging;

    if (batteryPct == null) return;
    if (batteryPct >= _rearmPct) {
      await _setLowArmed(true); // recovered → arm for next time
    }
    if (charging != true && batteryPct < _lowPct && _lowArmed) {
      await _notes.show(
        id: NotificationService.idLowBattery,
        title: 'Low battery',
        body: 'Your band is at ${batteryPct.round()}%. Charge it soon.',
      );
      await _setLowArmed(false);
    }
  }
}
