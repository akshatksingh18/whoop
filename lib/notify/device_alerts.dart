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

  /// Note the asymmetry if the store is ever unavailable: the charging alert
  /// still has the recency window as a second line of defence, but a battery
  /// percentage carries no timestamp, so low-battery has only this key. With a
  /// dead store it degrades to the pre-#179 behaviour (re-armed per process),
  /// which is the right way to fail — there is no way to remember a latch
  /// without somewhere to remember it.
  static const String _kLowArmed = 'device_alerts.low_armed';

  @visibleForTesting
  static const String debugLastChargeTsKey = _kLastChargeTs;
  @visibleForTesting
  static const String debugLastChargeWallKey = _kLastChargeWall;

  bool _lowArmed = true; // may we raise a low-battery alert?
  bool? _wasCharging; // previous charging state (null = not seen yet)
  bool _cancelledForOff = false; // already cleared the card for this off-state
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
      final eventTs = await _store.readInt(_kLastChargeTs);
      final wallSec = await _store.readInt(_kLastChargeWall);
      final armed = await _store.readInt(_kLowArmed);
      // Assigned together so the identity pair is never half-applied by a read
      // that throws part-way. (With the read order above the dangerous
      // half — wall set, event ts null, which would disable the identity check
      // — is already unreachable; keeping the invariant local means it stays
      // unreachable if someone reorders the reads.)
      // 0 is the "cleared" sentinel written by an untimed announcement.
      _lastAnnouncedEventTs = (eventTs != null && eventTs > 0) ? eventTs : null;
      _lastAnnouncedWallSec = wallSec;
      if (armed != null) _lowArmed = armed != 0;
    } catch (_) {
      _lastAnnouncedEventTs = null;
      _lastAnnouncedWallSec = null;
    }
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
    // ── DECIDE ────────────────────────────────────────────────────────────────
    // Every latch is committed BEFORE the first await. AGENTS.md §4.3 ("sticky
    // boolean latches never reset on the failure path") is the exact hazard: a
    // flag written after an await is a flag a throwing sink or store leaves
    // un-written, and onDeviceState's catchError makes that silent — the alert
    // then re-fires on the very next update, which is the bug this file exists
    // to prevent. Nothing below reads the results of the I/O, so deciding first
    // costs nothing.

    // Charger removed → clear the "Charging" card. It is a STATE claim, so
    // leaving it in the tray after the puck comes off is wrong on its own; it
    // also re-arms `onlyAlertOnce`, which only suppresses re-alerting while a
    // notification with that id is still showing.
    //
    // A STALE chargingOff must not clear it: the strap replays old events, so a
    // chargingOff from a previous session can arrive while the band is genuinely
    // on the charger right now, and cancelling then would hide a card that is
    // telling the truth.
    //
    // The "already cancelled" latch is separate from [_wasCharging] on purpose.
    // Keying the cancel off the charging TRANSITION looks equivalent and isn't:
    // a stale chargingOff still has to update _wasCharging (it is the latest
    // known state), which consumes the transition, and the real removal that
    // follows would then find nothing to act on and leave the card stranded.
    final cancelChargingCard = charging == false &&
        !_cancelledForOff &&
        !ChargeAlertPolicy.isStale(chargingTs, wallNowSec: nowSec);
    if (cancelChargingCard) _cancelledForOff = true;
    // Any chargingOn — even one too stale to announce — means a card may exist
    // again, so the next removal must be free to clear it.
    if (charging == true) _cancelledForOff = false;

    final announce = charging == true &&
        ChargeAlertPolicy.evaluate(
              eventTsEpoch: chargingTs,
              wallNowSec: nowSec,
              wasCharging: _wasCharging,
              lastAnnouncedEventTs: _lastAnnouncedEventTs,
              lastAnnouncedWallSec: _lastAnnouncedWallSec,
            ) ==
            ChargeAlertVerdict.announce;

    int? persistEventTs;
    if (announce) {
      _lastAnnouncedWallSec = nowSec;
      if (ChargeAlertPolicy.timestampUsable(chargingTs, wallNowSec: nowSec)) {
        _lastAnnouncedEventTs = chargingTs;
        persistEventTs = chargingTs;
      } else {
        // Announced without a usable clock, so we have no identity for THIS
        // session. Leaving the previous high-water in place would let it judge a
        // session it knows nothing about: the next usable timestamp that happens
        // to fall at or below it gets suppressed, and the user silently loses a
        // real "on the charger" confirmation. Clear it (0 = none; every real
        // strap timestamp is far above it) so only the wall-clock cooldown
        // guards this path — which is exactly what the untimed branch of
        // ChargeAlertPolicy assumes.
        _lastAnnouncedEventTs = null;
        persistEventTs = 0;
      }
    }
    // Tracks the LATEST KNOWN charging state, including from events too stale to
    // announce — otherwise a stale on/off pair would leave us believing we are
    // still charging and swallow the next genuine plug-in as `alreadyCharging`.
    if (charging != null) _wasCharging = charging;

    // Low-battery hysteresis, same precedence as before: a real plug-in re-arms
    // the next drain, so does a battery that recovered past the ceiling.
    var lowArmed = _lowArmed;
    if (announce) lowArmed = true;
    if (batteryPct != null && batteryPct >= _rearmPct) lowArmed = true;
    final fireLow = batteryPct != null &&
        charging != true &&
        batteryPct < _lowPct &&
        lowArmed;
    if (fireLow) lowArmed = false;
    final lowArmedChanged = lowArmed != _lowArmed;
    _lowArmed = lowArmed;

    // ── ACT ───────────────────────────────────────────────────────────────────
    if (cancelChargingCard) {
      await _notes.cancel(NotificationService.idCharging);
    }
    if (announce) {
      await _notes.show(
        id: NotificationService.idCharging,
        title: 'Charging',
        body: 'Your band is on the charger.',
      );
      await _store.writeInt(_kLastChargeWall, nowSec);
      if (persistEventTs != null) {
        await _store.writeInt(_kLastChargeTs, persistEventTs);
      }
      // A real plug-in clears any stale low alert.
      await _notes.cancel(NotificationService.idLowBattery);
    }
    if (fireLow) {
      await _notes.show(
        id: NotificationService.idLowBattery,
        title: 'Low battery',
        body: 'Your band is at ${batteryPct.round()}%. Charge it soon.',
      );
    }
    if (lowArmedChanged) {
      await _store.writeInt(_kLowArmed, lowArmed ? 1 : 0);
    }
  }
}
