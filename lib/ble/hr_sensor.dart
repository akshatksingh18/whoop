// HrSensor — a standard Bluetooth heart-rate sensor (GATT Heart Rate Service,
// 0x180D) as a SESSION-SCOPED second opinion on exercise HR.
//
// WHY THIS EXISTS. The public positioning says "works with any standard
// Bluetooth heart rate sensor", and until this file there was no `180d`, no
// `2a37` and no Heart Rate Service anywhere in the tree. That made the claim
// false in code, which is a correctness problem before it is a feature gap.
//
// WHAT IT IS NOT.
//  * NOT a background source. It is armed by a workout and disarmed when the
//    workout ends — the same rule GPS follows, for the same reason: a second
//    GATT link held open all day is a battery cost and a scan/connect fight
//    with the band's own link.
//  * NOT better than the band overnight. A chest strap is better at exercise HR
//    and beat timing; that is the whole of the claim.
//  * NOT a WHOOP replacement, and NOT baseline input. Its rows land in
//    `external_hr` with the sensor's name attached and NOTHING derives from
//    them. `decoded_onehz`/`decoded_rr` carry a `source` column so that even if
//    a future version does route these into the substrate, every baseline read
//    is already filtering them out — resting HR from a chest strap and from
//    wrist PPG differ systematically, and merging them quietly is how a step
//    change lands in every long-horizon number with no visible cause.
//  * NOT a sub-second beat timeline. The sensor reports RR *durations* and we
//    store durations. Beat TIMES are `decoded_rr`'s key and every consumer of
//    it; that is a separate change.
//
// PAIRING IS USER-INITIATED AND SEPARATE FROM ARMING. `scan()` runs only when
// the user asks for it from a settings screen; arming connects straight to the
// stored remote id with no scan at all, so a workout start never contends with
// the band's service-filtered scan.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/db.dart';
import '../sync/paired_device.dart' show cleanDeviceLabel;
import 'ble_state.dart' show withScanLock;

/// GATT Heart Rate Service and its Heart Rate Measurement characteristic.
/// Written out in full 128-bit form rather than the 16-bit shorthand: the
/// shorthand's expansion is a platform detail we should not depend on.
const String kHeartRateServiceUuid = '0000180d-0000-1000-8000-00805f9b34fb';
const String kHeartRateMeasurementUuid = '00002a37-0000-1000-8000-00805f9b34fb';

/// One Heart Rate Measurement notification.
@immutable
class HrsSample {
  /// Beats per minute as the sensor reported it.
  final int hr;

  /// Beat-to-beat DURATIONS in milliseconds carried by this notification, in
  /// the order the sensor sent them. Empty when the sensor does not report RR
  /// (many optical armbands do not) — empty is "not reported", never "zero".
  final List<int> rrMs;

  /// The sensor's own contact claim: true/false when it reports one, null when
  /// it does not support the field at all. Never inferred from HR.
  final bool? contact;

  const HrsSample({required this.hr, required this.rrMs, this.contact});
}

/// Parse a Heart Rate Measurement (0x2A37) value.
///
/// Layout (Bluetooth SIG, Heart Rate Service 1.0):
///   byte 0  flags
///     bit 0  HR format: 0 = uint8, 1 = uint16 little-endian
///     bits 1-2  sensor contact: 0b00/0b01 = not supported, 0b10 = no contact,
///               0b11 = contact
///     bit 3  Energy Expended present (uint16, kJ) — skipped, we do not use it
///     bit 4  RR-Interval present (one or more uint16, units of 1/1024 s)
///   then HR, then energy expended if present, then RR intervals to the end.
///
/// Returns null for a value that cannot be read as this characteristic (too
/// short, or a truncated field). A malformed notification is DROPPED, never
/// patched up into a plausible-looking beat.
HrsSample? parseHeartRateMeasurement(List<int> value) {
  if (value.length < 2) return null;
  final flags = value[0];
  final wide = (flags & 0x01) != 0;
  var i = 1;
  final int hr;
  if (wide) {
    if (value.length < 3) return null;
    hr = value[1] | (value[2] << 8);
    i = 3;
  } else {
    hr = value[1];
    i = 2;
  }
  // 0 bpm is not a measurement. Sensors emit it while searching for a signal;
  // storing it would put a real-looking zero into a heart-rate series.
  if (hr <= 0 || hr > 300) return null;

  final contactBits = (flags >> 1) & 0x03;
  final contact = contactBits < 2 ? null : contactBits == 3;

  if ((flags & 0x08) != 0) i += 2; // energy expended — present, not used
  final rr = <int>[];
  if ((flags & 0x10) != 0) {
    // Trailing RR intervals, uint16 LE, 1/1024 s each. A trailing odd byte is a
    // malformed value: stop rather than reading past it.
    while (i + 1 < value.length) {
      final ticks = value[i] | (value[i + 1] << 8);
      i += 2;
      // 1024 ticks = 1 s. Round to the nearest millisecond.
      final ms = (ticks * 1000 + 512) ~/ 1024;
      // 250-3000 ms is 20-240 bpm. Outside that the value is not a beat
      // interval, and a chest strap emits exactly this junk on a dropped beat.
      if (ms >= 250 && ms <= 3000) rr.add(ms);
    }
  }
  return HrsSample(hr: hr, rrMs: rr, contact: contact);
}

/// The heart-rate sensor the user paired, if any. Separate keys from
/// [PairedDevice] — the band and a sensor are two different links and pairing
/// one must never disturb the other.
class PairedHrSensor {
  static const String _kId = 'hrs_remote_id';
  static const String _kName = 'hrs_name';

  final String remoteId;
  final String name;
  const PairedHrSensor(this.remoteId, this.name);

  static Future<PairedHrSensor?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_kId);
    if (id == null || id.isEmpty) return null;
    return PairedHrSensor(id, prefs.getString(_kName) ?? 'Heart rate sensor');
  }

  static Future<void> save(String remoteId, String? name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kId, remoteId);
    // Same sanitiser the band label uses: a garbled advertised name must never
    // become the `source` string stamped on stored rows.
    await prefs.setString(_kName, cleanDeviceLabel(name) ?? 'Heart rate sensor');
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kId);
    await prefs.remove(_kName);
  }
}

/// The live link to a paired heart-rate sensor. One instance; a second
/// concurrent sensor is not a thing anyone asked for.
class HrSensorLink {
  HrSensorLink._();
  static final HrSensorLink instance = HrSensorLink._();

  /// Flush cadence for the write buffer. A sensor notifies ~1 Hz, and one
  /// transaction per beat on the UI isolate is the mistake `commitSyncBatch`
  /// already chunks around.
  static const Duration _flushEvery = Duration(seconds: 15);

  BluetoothDevice? _device;
  StreamSubscription<List<int>>? _valueSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  Timer? _flushTimer;
  final List<Map<String, Object?>> _pending = [];
  String? _sessionId;
  String? _source;

  /// The most recent bpm the sensor reported, for a live readout. Null when no
  /// sensor is armed or none has reported yet — an armed-but-silent sensor is
  /// absent, not zero.
  final ValueNotifier<int?> liveHr = ValueNotifier<int?>(null);

  /// True once the sensor link is up and notifications are subscribed.
  final ValueNotifier<bool> armed = ValueNotifier<bool>(false);

  /// The sensor's name, used as the `source` on every row it produces.
  String? get sourceName => _source;

  /// Scan for heart-rate sensors. USER-INITIATED ONLY (a settings screen), never
  /// on the workout path — it shares one radio scanner with the band's own scan.
  ///
  /// Returns (remoteId, name) pairs, deduplicated, strongest first.
  ///
  /// Serialised process-wide through [withScanLock] against the band's scan:
  /// one radio scanner, and the `isScanning == false` await below completes on
  /// the OTHER scan's `stopScan` — which ends this one early with an empty
  /// list that looks exactly like "no sensor is nearby".
  Future<List<(String, String)>> scan({
    Duration timeout = const Duration(seconds: 8),
  }) =>
      withScanLock(() => _scanLocked(timeout));

  Future<List<(String, String)>> _scanLocked(Duration timeout) async {
    if (FlutterBluePlus.isScanningNow) await FlutterBluePlus.stopScan();
    final found = <String, (String, int)>{};
    final sub = FlutterBluePlus.onScanResults.listen((results) {
      for (final r in results) {
        final name = cleanDeviceLabel(r.device.platformName) ??
            cleanDeviceLabel(r.advertisementData.advName);
        if (name == null) continue;
        found[r.device.remoteId.str] = (name, r.rssi);
      }
    });
    try {
      await FlutterBluePlus.startScan(
        withServices: [Guid(kHeartRateServiceUuid)],
        timeout: timeout,
      );
      await FlutterBluePlus.isScanning.where((on) => on == false).first;
    } catch (_) {
      // A revoked permission or a disabled adapter surfaces here on Android.
      // The band engine already owns the blocker classification and the copy
      // for it; from here an empty list is the honest answer.
    } finally {
      await sub.cancel();
    }
    final entries = found.entries.toList()
      ..sort((a, b) => b.value.$2.compareTo(a.value.$2));
    return [for (final e in entries) (e.key, e.value.$1)];
  }

  /// Connect to the paired sensor and start logging for [sessionId].
  /// No-op (returns false) when nothing is paired — this is opt-in hardware.
  ///
  /// Never scans: it connects straight to the stored remote id, so arming a
  /// workout cannot contend with the band's scan.
  Future<bool> arm(String sessionId) async {
    if (armed.value) {
      // Re-arm on a link that is already up: keep the link, REBIND the session.
      // Returning early without this filed every beat of the next workout under
      // the previous workout's id. Nothing needs flushing first — `_onValue`
      // stamps each buffered row with the id it was recorded under, so rows
      // already queued keep pointing at the session they belong to.
      _sessionId = sessionId;
      return true;
    }
    final paired = await PairedHrSensor.load();
    if (paired == null) return false;
    _sessionId = sessionId;
    _source = paired.name;
    try {
      final device = BluetoothDevice.fromId(paired.remoteId);
      _device = device;
      await device.connect(timeout: const Duration(seconds: 12));
      final services = await device.discoverServices();
      BluetoothCharacteristic? measure;
      for (final s in services) {
        if (s.uuid != Guid(kHeartRateServiceUuid)) continue;
        for (final c in s.characteristics) {
          if (c.uuid == Guid(kHeartRateMeasurementUuid)) measure = c;
        }
      }
      if (measure == null) {
        await disarm();
        return false;
      }
      _valueSub = measure.onValueReceived.listen(_onValue);
      await measure.setNotifyValue(true);
      // A sensor that walks out of range mid-session ends the log there rather
      // than leaving `armed` claiming a link that is gone.
      _connSub = device.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected) unawaited(disarm());
      });
      _flushTimer = Timer.periodic(_flushEvery, (_) => unawaited(_flush()));
      armed.value = true;
      return true;
    } catch (_) {
      await disarm();
      return false;
    }
  }

  /// Stop logging, flush the tail and drop the link. Safe to call when not
  /// armed. AWAIT it before a finish screen reads the session back — an
  /// unawaited stop is how the last buffered batch goes missing.
  Future<void> disarm() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    await _valueSub?.cancel();
    _valueSub = null;
    await _connSub?.cancel();
    _connSub = null;
    await _flush();
    final d = _device;
    _device = null;
    _sessionId = null;
    _source = null;
    armed.value = false;
    liveHr.value = null;
    if (d != null) {
      try {
        await d.disconnect();
      } catch (_) {/* already gone */}
    }
  }

  void _onValue(List<int> value) {
    final s = parseHeartRateMeasurement(value);
    if (s == null) return;
    // The sensor's own "no skin contact" is a refusal, not a low reading: a
    // chest strap off the chest reports confident nonsense. Drop the sample and
    // do not show it.
    if (s.contact == false) return;
    liveHr.value = s.hr;
    final source = _source;
    if (source == null) return;
    _pending.add({
      'ts': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'source': source,
      'hr': s.hr,
      'rr_ms': s.rrMs.isEmpty ? null : jsonEncode(s.rrMs),
      'session_id': _sessionId,
    });
  }

  Future<void> _flush() async {
    if (_pending.isEmpty) return;
    final batch = List<Map<String, Object?>>.from(_pending);
    _pending.clear();
    try {
      await LocalDb.appendExternalHr(batch);
    } catch (_) {
      // Losing a buffered batch is better than throwing out of a timer on the
      // UI isolate; the next flush carries on.
    }
  }
}
