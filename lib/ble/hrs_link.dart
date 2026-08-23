// The HOST for a standard Bluetooth heart-rate sensor: connect it, drive
// [BleHrsAdapter] over the link, and write what comes back into the substrate.
//
// WHAT MOVED, AND WHY IT MATTERS. The decode and the session used to be in
// this file. They are now `adapters/ble_hrs.dart` — a 40-line
// `Stream<BandEvent> run(BandLink)` — and everything left here is host work a
// contributor must never see: `flutter_blue_plus`, the paired-device row,
// `sqflite`, the per-second write buffer, `device_id` discipline. The seam
// between the two halves is `adapters/adapter.dart`, and this is its first
// caller.
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
import 'adapters/adapter.dart';
import 'adapters/ble_hrs.dart';
import 'adapters/gatt_link.dart';

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

  /// Kept only so [disarm] can [GattBandLink.close] it. Closing is what stops a
  /// write the adapter queued before the teardown from landing on a LATER
  /// connection to the same strap — see the field's own doc.
  GattBandLink? _link;
  StreamSubscription<BandEvent>? _runSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  Completer<void>? _runDone;
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
      if (r['adapter_id'] == kBleHrsAdapter.id) return r;
    }
    return null;
  }

  /// Connect to the paired sensor and start logging.
  /// No-op (returns false) when nothing is paired — this is opt-in hardware.
  ///
  /// Never scans: it connects straight to the stored remote id, so arming a
  /// workout cannot contend with the band's scan.
  ///
  /// SERIALISED, because every caller fires it `unawaited` and the body awaits
  /// a database read, a 12 s connect and service discovery before it publishes
  /// anything. A second call used to sail past the `_armed` check while the
  /// first was still connecting and overwrite `_device`, `_link`, `_runSub` and
  /// `_flushTimer` — the first one's timer and subscription then ran forever
  /// with nothing holding them.
  Future<bool> arm() {
    if (_armed) return Future.value(true);
    return _arming ??= _arm().whenComplete(() => _arming = null);
  }

  /// The in-flight [arm], or null. See [arm].
  Future<bool>? _arming;

  /// How many times [disarm] has run. An [arm] whose count moved under it has
  /// been cancelled and must not publish — see the check in [_arm].
  int _disarms = 0;

  Future<bool> _arm() async {
    final disarmsAtStart = _disarms;
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
      // Connect, bond, MTU and discovery are HOST work and stay on this side
      // of the seam. The adapter is handed the result and nothing else.
      final services = await device.discoverServices();
      // A `disarm()` that landed WHILE this was connecting has already torn the
      // session down — it nulls `_device` and `_deviceId`. Publishing on top of
      // it would set `_armed = true` over no device and no `_deviceId`, so
      // `_flush` would discard every second and every later `arm()` would
      // short-circuit on `_armed`: the sensor stays dead for the rest of the
      // process. Reachable by the most ordinary thing a user does — start a
      // workout and stop it inside twelve seconds.
      if (_disarms != disarmsAtStart) {
        debugPrint('[hrs] arm abandoned: it was disarmed while connecting.');
        try {
          await device.disconnect();
        } catch (_) {/* already gone */}
        return false;
      }
      final link = GattBandLink(
        entry: kBleHrsAdapter.entry,
        services: services,
        onLog: (m) => debugPrint('[hrs] $m'),
      );
      _link = link;
      final missing =
          link.missingCharacteristics(kBleHrsAdapter.entry.requiredCharacteristics);
      if (missing.isNotEmpty) {
        debugPrint('[hrs] ${kBleHrsAdapter.label}: missing required '
            'characteristic(s) ${missing.map((u) => u.substring(0, 8)).join(", ")}.');
        await disarm();
        return false;
      }
      _startRun(link);
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
    _disarms++;
    _flushTimer?.cancel();
    _flushTimer = null;
    // Before the run subscription is cancelled: an adapter's `finally` can
    // still write on the way out, and that write must not reach the radio.
    _link?.close();
    _link = null;
    await _stopRun();
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

  /// Drive the adapter over [link]. Cancelling [_runSub] is the ONLY way the
  /// session ends from this side — an adapter does not get to hang up, so
  /// every timer and buffer it owns dies with its `async*` body.
  void _startRun(BandLink link) {
    final done = Completer<void>();
    _runDone = done;
    void finish() {
      if (!done.isCompleted) done.complete();
    }

    _runSub = kBleHrsAdapter.run(link).listen(
      _onEvent,
      onDone: finish,
      onError: (Object e) {
        debugPrint('[hrs] session ended on error: $e');
        finish();
        // ponytail: `setNotifyValue` is now awaited inside the link's stream
        // rather than inside [arm], so a rejected subscribe surfaces HERE
        // instead of propagating out of `arm()` as a `false`. The ceiling is
        // that `arm()` can briefly answer true for a session that is already
        // dying; the callers all ignore its result. Tearing down here is what
        // stops the link sitting "armed" over a dead stream. Give `arm()` back
        // its answer only if a caller ever starts reading it.
        if (_armed) unawaited(disarm());
      },
      cancelOnError: true,
    );
  }

  Future<void> _stopRun() async {
    await _runSub?.cancel();
    _runSub = null;
    _runDone = null;
  }

  void _onEvent(BandEvent e) {
    switch (e) {
      case SampleBatch(:final samples, :final ephemeral):
        // EPHEMERAL IS NEVER PERSISTED, and the check is the HOST's, not the
        // adapter's promise. This band always sends false; the line exists so
        // the one place that decides what reaches the database is the one
        // place that reads the flag.
        if (ephemeral) return;
        for (final s in samples) {
          final slot = _pending.putIfAbsent(s.tsEpoch, _Second.new);
          // Last notification in the second wins.
          if (s.hr != null) slot.hr = s.hr;
          slot.rr.addAll(s.rrMs);
        }
      case OffloadCheckpoint():
        // A sensor with no flash cannot have anything to forget. If this ever
        // fires, the adapter grew a store and this host has no
        // commit-then-confirm path to honour the safe-trim invariant with —
        // so it must NOT be confirmed. Dropping it stalls; confirming it would
        // authorise a delete of data we never banked.
        assert(false, 'ble_hrs emitted an OffloadCheckpoint; it stores nothing');
      case BandNote(:final key, :final value):
        debugPrint('[hrs] $key = $value');
    }
  }

  /// Feed raw notification bytes as if a sensor with [deviceId] were armed,
  /// and write them. The only way in: the real entry point is a BLE
  /// notification and `flutter_blue_plus` has no simulator path, so without
  /// this seam nothing below the parser could be exercised at all.
  ///
  /// It replays through the SAME [BleHrsAdapter.run] the radio drives, over a
  /// [ReplayBandLink]. A test seam that skipped the adapter would prove the
  /// wrong thing.
  @visibleForTesting
  Future<void> ingestForTest(
    String deviceId,
    List<(int, List<int>)> arrivals,
  ) async {
    _deviceId = deviceId;
    final link = ReplayBandLink();
    _startRun(link);
    for (final (sec, value) in arrivals) {
      link.feed(kHeartRateMeasurementUuid, value, atSec: sec);
    }
    // Close, then wait for `run()` to actually finish, rather than guessing at
    // a delay: the adapter's `await for` is asynchronous and a flush racing it
    // would silently drop the tail.
    await link.close();
    await _runDone?.future;
    await _flush(all: true);
    await _stopRun();
    _deviceId = null;
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
    assert(kBleHrsAdapter.entry.timeAnchor == TimeAnchor.arrival);
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
              'device_family': kBleHrsAdapter.id,
              'source': kBleHrsAdapter.id,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          // CLEAR THE SECOND BEFORE REINSERTING, exactly as `_queueRrBeats`
          // does on the band path and for the same reason: REPLACE only
          // overwrites `beat_index` 0..n-1, so a second that once carried more
          // beats keeps the stale tail and reports beats the sensor never sent.
          // Within one armed session a second is written once (`_pending`
          // removes it), but re-arming inside the same second is not — and the
          // 15 s flush cadence means the second on either side of a stop is
          // exactly the one at risk. Scoped to THIS device, so it can never
          // reach the band's beats for the same second.
          b.rawDelete(
            'DELETE FROM decoded_rr WHERE device_id = ? AND ts_ms = ?',
            [deviceId, sec * 1000],
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
                'device_family': kBleHrsAdapter.id,
                'source': kBleHrsAdapter.id,
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
