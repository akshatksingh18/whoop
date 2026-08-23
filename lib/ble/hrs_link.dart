// A standard Bluetooth heart-rate sensor (GATT Heart Rate Service, 0x180D) as
// a SESSION-SCOPED second opinion on exercise heart rate.
//
// This replaces `hr_sensor.dart`, which was a second, parallel 314-line
// `flutter_blue_plus` stack. It existed for one reason: `_doConnect` demanded
// four WHOOP characteristics or aborted, so a device with one notify
// characteristic could not go through the engine at all. Wave 1 made that
// requirement registry data (`BandEntry.requiredCharacteristics`), so the
// parallel stack is gone — this file is the small remainder: connect, notify,
// decode, write.
//
// WHAT IT IS NOT.
//  * NOT a background source. Armed by a workout, disarmed when the workout
//    ends — the same rule GPS follows, for the same reason: a second GATT link
//    held open all day is a battery cost and a scan/connect fight with the
//    band's own link.
//  * NOT better than the band overnight. A chest strap is better at exercise
//    HR and beat timing; that is the whole of the claim.
//  * NOT baseline input, and not yet input to anything. Its rows land in
//    `decoded_onehz` / `decoded_rr` — the real substrate, not a side table —
//    stamped `source = 'ble_hrs'`, and every derive/export read filters
//    `source IS NULL`. Resting HR from a chest strap and from wrist PPG differ
//    systematically, and merging them quietly is how a step change lands in
//    every long-horizon number with no visible cause.
//  * NOT REACHABLE TODAY. There is no pairing screen, so nothing writes the
//    `device` row [HrsLink.arm] reads, and arming is a no-op — exactly as it
//    was before, when `PairedHrSensor.save()` had zero callers.
//  * NOT hardware-verified. Nobody on this project owns a strap. Everything
//    below is verified by the SIG spec, the fixtures in
//    `test/hrs_link_test.dart` and the compiler. It ships EXPERIMENTAL
//    (ASSUMPTIONS R6).
//
// BEAT TIME. A 0x2A37 strap reports beat-to-beat DURATIONS and carries no
// clock. The durations are exact and land in `decoded_rr.rr_ms`; the only time
// we can attach is the arrival of the notification, which BLE delivery jitter
// and stack batching move by tens of milliseconds. That anchor goes in
// `rr_ts_ms` (the whole-second column, which is what it is) and `beat_ts_ms` —
// the column that means "where the beat actually WAS" — stays NULL, because we
// do not know. `TimeAnchor.arrival` on the registry entry is the machine-
// readable form of that sentence: RMSSD and pNN50 are correct on it,
// Lomb-Scargle / `cvhr_per_hour` / `spanSec` must refuse on it.

import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import '../data/db.dart';
import 'adapters/_registry.dart';

/// One Heart Rate Measurement notification.
class HrsSample {
  /// Beats per minute as the sensor reported it.
  final int hr;

  /// Beat-to-beat DURATIONS in milliseconds carried by this notification, in
  /// the order the sensor sent them. Empty when the sensor does not report RR
  /// (the flag is OPTIONAL in the SIG spec and plenty of straps send only a
  /// bpm) — empty is "not reported", never "zero".
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

/// One arrival second's worth of notifications.
class _Second {
  int? hr;
  final List<int> rr = [];
}

/// The live link to a paired heart-rate sensor. One instance; a second
/// concurrent sensor is not a thing anyone asked for.
class HrsLink {
  HrsLink._();
  static final HrsLink instance = HrsLink._();

  /// Flush cadence for the write buffer. A sensor notifies ~1 Hz, and one
  /// transaction per beat on the UI isolate is the mistake `commitSyncBatch`
  /// already chunks around.
  static const Duration _flushEvery = Duration(seconds: 15);

  BluetoothDevice? _device;
  StreamSubscription<List<int>>? _valueSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  Timer? _flushTimer;

  /// Arrival second -> that second's readings. Keyed by second because that is
  /// the key `decoded_onehz` / `decoded_rr` are written under: accumulating
  /// per second is what stops two notifications landing in the same second
  /// from REPLACE-ing each other's beat 0.
  final Map<int, _Second> _pending = {};

  /// `device.id` of the paired sensor — the `device_id` every row it writes
  /// carries. Never [LocalDb.kPrimaryDeviceId]: `''` is the primary band,
  /// permanently (ASSUMPTIONS A1).
  String? _deviceId;

  bool _armed = false;

  /// The `device` row for the paired heart-rate sensor, or null.
  ///
  /// The `device` table (schema 49) IS the pairing store now — this is what
  /// replaced `PairedHrSensor`'s two SharedPreferences scalars, which could
  /// hold one sensor, could not be joined to the rows it wrote, and had no
  /// writer anyway. A pairing screen creates the row with
  /// `LocalDb.upsertDevice(id: mintedId, adapterId: 'ble_hrs', remoteId:
  /// bleId, label: advertisedName, tier: 'beatToBeat')`.
  ///
  /// `id` must be MINTED at pairing (e.g. `hrs-0a1b2c3d`), not the BLE remote
  /// id: a remote id is a per-app CBPeripheral UUID on iOS and a rotating RPA
  /// on Android, and letting one become the storage key fragments one strap
  /// into N identities. `remote_id` is the column that may change under the
  /// same row, and that is what this reads to connect.
  static Future<Map<String, Object?>?> pairedSensorRow() async {
    for (final r in await LocalDb.deviceRows()) {
      if (r['adapter_id'] == kBleHrs.id) return r;
    }
    return null;
  }

  /// Connect to the paired sensor and start logging.
  /// No-op (returns false) when nothing is paired — this is opt-in hardware.
  ///
  /// Never scans: it connects straight to the stored remote id, so arming a
  /// workout cannot contend with the band's scan.
  Future<bool> arm() async {
    if (_armed) return true;
    final row = await pairedSensorRow();
    if (row == null) return false;
    final deviceId = row['id'] as String?;
    final remoteId = row['remote_id'] as String?;
    if (deviceId == null || remoteId == null || remoteId.isEmpty) return false;
    if (deviceId == LocalDb.kPrimaryDeviceId) {
      // The primary band's id, permanently. A sensor writing under it would
      // interleave its seconds with the band's in one REPLACE-keyed table.
      debugPrint('[hrs] refusing to arm: the sensor row claims the primary '
          'device id — re-pair it with a minted id.');
      return false;
    }
    _deviceId = deviceId;
    try {
      final device = BluetoothDevice.fromId(remoteId);
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
      // than leaving the link claiming to be armed when it is gone.
      _connSub = device.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected) unawaited(disarm());
      });
      _flushTimer = Timer.periodic(_flushEvery, (_) => unawaited(_flush()));
      _armed = true;
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
    await _flush(all: true);
    final d = _device;
    _device = null;
    _deviceId = null;
    _armed = false;
    if (d != null) {
      try {
        await d.disconnect();
      } catch (_) {/* already gone */}
    }
  }

  /// Feed raw notification bytes as if a sensor with [deviceId] were armed,
  /// and write them. The only way in: the real entry point is a BLE
  /// notification and `flutter_blue_plus` has no simulator path, so without
  /// this seam nothing below the parser could be exercised at all.
  @visibleForTesting
  Future<void> ingestForTest(
    String deviceId,
    List<(int, List<int>)> arrivals,
  ) async {
    _deviceId = deviceId;
    for (final (sec, value) in arrivals) {
      _onValue(value, sec);
    }
    await _flush(all: true);
    _deviceId = null;
  }

  void _onValue(List<int> value, [int? atSec]) {
    final s = parseHeartRateMeasurement(value);
    if (s == null) return;
    // The sensor's own "no skin contact" is a refusal, not a low reading: a
    // chest strap off the chest reports confident nonsense. Drop the sample.
    if (s.contact == false) return;
    // ARRIVAL, not measurement — see the header. This is the whole reason the
    // registry entry declares `TimeAnchor.arrival`.
    final sec = atSec ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final slot = _pending.putIfAbsent(sec, _Second.new);
    slot.hr = s.hr; // last notification in the second wins
    slot.rr.addAll(s.rrMs);
  }

  /// Write out every second that can no longer receive more notifications.
  ///
  /// The CURRENT second is held back unless [all]: a second written twice
  /// would restart `beat_index` at 0 and REPLACE the beats already stored for
  /// it. `disarm` passes `all: true` because nothing more is coming.
  Future<void> _flush({bool all = false}) async {
    final deviceId = _deviceId;
    if (_pending.isEmpty) return;
    if (deviceId == null) {
      _pending.clear();
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final ready = _pending.keys.where((s) => all || s < now).toList()..sort();
    if (ready.isEmpty) return;
    // Taken out of the buffer BEFORE the await: losing a batch to a failed
    // write is better than replaying it under a later second's beat indices.
    final batchRows = [for (final s in ready) (s, _pending.remove(s)!)];
    // `beat_ts_ms` is deliberately absent from every row below. It means "where
    // the beat actually was", and for an arrival-anchored source we do not know
    // — anchor-minus-durations would be a measured claim we cannot make. NULL
    // is the column's own word for "not kept".
    assert(kBleHrs.timeAnchor == TimeAnchor.arrival);
    // Its own transaction, NOT `commitSyncBatch`: that path is the ACK-gating
    // commit, it raises `synchronous` for the duration and it refuses a
    // non-primary `device_id` outright (the `sync_cursor` namespace is global).
    // Nothing here trims a band's flash, so none of the safe-trim invariant is
    // in play — this only has to queue politely behind a drain on the shared
    // connection, which sqflite does.
    try {
      final db = await LocalDb.instance;
      await db.transaction((txn) async {
        final b = txn.batch();
        for (final (sec, slot) in batchRows) {
          b.insert(
            'decoded_onehz',
            {
              'device_id': deviceId,
              'ts_ms': sec * 1000,
              'rec_ts': sec,
              // ponytail: `counter` is NOT NULL and is a WHOOP flash-record
              // number this sensor does not have. 0 for every row is a
              // constant, not a measurement, and nothing reads the column
              // except `ORDER BY rec_ts, counter`. Make it nullable when
              // db.dart is next open.
              'counter': 0,
              'hr': slot.hr,
              'device_family': kBleHrs.id,
              'source': kBleHrs.id,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          for (var i = 0; i < slot.rr.length; i++) {
            b.insert(
              'decoded_rr',
              {
                'device_id': deviceId,
                'ts_ms': sec * 1000,
                'rec_ts': sec,
                'beat_index': i,
                'rr_ts_ms': sec * 1000,
                'rr_ms': slot.rr[i],
                'device_family': kBleHrs.id,
                'source': kBleHrs.id,
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        }
        await b.commit(noResult: true);
      });
    } catch (e) {
      // Losing a buffered batch is better than throwing out of a timer on the
      // UI isolate; the next flush carries on.
      debugPrint('[hrs] flush failed, ${batchRows.length} second(s) lost: $e');
    }
  }
}
