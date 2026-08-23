// The HOST for the Oura ring: hold the pairing key, hold the drain cursor,
// hold the time anchor, connect, drive [OuraAdapter] over the link, and bank
// what comes back.
//
// NOTHING HERE HAS MET HARDWARE. Nobody on this project owns a ring (owner
// ruling R6), so not one byte of this path has been exercised against one. The
// registry entry stays EXPERIMENTAL, `OuraAdapter.signals` stays `const {}`,
// and nothing this file writes becomes a number: its rows carry a non-null
// `source`, and every derive/export read filters `source IS NULL`. That is
// correct behaviour for an uncalibrated decoder, not a limitation to route
// around.
//
// THE SHAPE, AND WHY IT IS NOT `HrsLink`'s. A heart-rate strap is a live
// session armed by a workout; the ring is a FETCH-BY-CURSOR store. So this is
// a one-shot [OuraLink.sync] — connect, drain to the end of history, tear down
// — rather than an arm/disarm pair. Everything else is the same host work in
// the same order: read the `device` row, connect by `remote_id`, discover,
// check [GattBandLink.missingCharacteristics], drive `run()`, buffer, commit,
// disconnect.
//
// WHAT THIS FILE OWNS THAT THE ADAPTER DELIBERATELY CANNOT (see `oura.dart`'s
// own header):
//
//  1. THE 16-BYTE PAIRING KEY, in the platform keychain/keystore — never in
//     the database. See [_readKey].
//  2. THE DRAIN CURSOR, a decisecond on the ring's own clock, in `sync_cursor`
//     so a drain resumes instead of re-fetching.
//  3. THE TIME ANCHOR, the `(ring decisecond, Unix second)` pair, persisted
//     beside the cursor and handed back in at the next connect. This is the fix
//     for the cross-session origin hazard — see below.
//
// THE HOST HOLDS THE ORIGIN, THE ADAPTER STAMPS WITH IT. There is exactly one
// implementation of "which second is this decisecond", and it is
// `OuraAdapter._anchorUnixFor`. The host reads the stored `(ds, unix)` pair,
// hands it in at construction, and writes back the better one the adapter
// reports when a `time_sync` event gives it a measured pair — inside the same
// transaction as the rows that pair stamped. Two implementations of an origin
// would be two origins, which is the whole failure this mechanism exists to
// stop: the same physiological second written under two different `ts_ms`,
// which REPLACE cannot collapse because they no longer share a key.
//
// ABSTAINING IS THE CORRECT ANSWER WHEN THERE IS NO ORIGIN. A session with no
// measured `time_sync` and nothing stored writes NO timestamped row. The frames
// are still archived verbatim — the bytes are banked, and a plausible wrong
// `ts_ms` is worse than a missing one.
//
// THE DESTRUCTIVE COMMANDS ARE UNREACHABLE FROM HERE, and their absence is the
// only thing making that true. `GattBandLink`'s dangerous-opcode block reads an
// opcode out of a WHOOP envelope and answers null for an unframed band, so it
// does NOT cover this ring (ASSUMPTIONS I1). The ring has a factory reset, a
// DFU state machine, a flight mode, a manufacturing-mode setter and a
// bulk-sampler erase. This file writes NOTHING it did not get from a builder in
// `oura_wire.dart`, that file has no builder for any of them, and
// `oura_link_test.dart` asserts that every byte this host puts on the wire came
// from a builder that exists. The one command here that writes ring state is
// the key install, and it writes a credential rather than erasing anything.

import 'dart:async';
import 'dart:math' show Random;

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import '../data/db.dart';
import 'adapters/_registry.dart';
import 'adapters/adapter.dart';
import 'adapters/gatt_link.dart';
import 'adapters/oura.dart';
import 'adapters/oura_wire.dart';

/// Keychain item name for one ring's pairing key. Suffixed with the MINTED
/// device id, never the BLE remote id — that rotates.
String _keyItem(String deviceId) => 'oura_pairing_key:$deviceId';

/// `sync_cursor` names. Both are per-device: two rings are not a thing anyone
/// asked for, but a second one must not silently inherit the first's bookmark.
String _cursorItem(String deviceId) => 'oura_cursor_ds:$deviceId';
String _anchorItem(String deviceId) => 'oura_anchor:$deviceId';

/// FIRST-UNLOCK, not the plugin's default WHEN-UNLOCKED — the same choice, for
/// the same reason, that `CoachConfig` documents at length. This app is
/// relaunched in the background constantly (BGProcessingTask, the BLE restore
/// central waking on a link drop) and those relaunches routinely happen while
/// the phone is LOCKED, i.e. exactly when a `whenUnlocked` item cannot be read.
/// A background sync that read nothing would conclude the ring is unpaired.
const IOSOptions _kApple = IOSOptions(
  accessibility: KeychainAccessibility.first_unlock,
);
const MacOsOptions _kMacos = MacOsOptions(
  accessibility: KeychainAccessibility.first_unlock,
);

const FlutterSecureStorage _secure = FlutterSecureStorage();

/// THE ORDER IS THE WHOLE MESSAGE. A ring only accepts a new key while it is
/// factory reset, so the reset comes FIRST and pairing second — reversed, the
/// user resets a ring this app has just keyed and loses both.
const String _kResetFirst =
    'The ring would not take a new key. It only accepts one while it is '
    'factory reset, so reset it first and then pair here — that is the order, '
    'and resetting is what frees the ring from whatever set it up before.';

String _hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

List<int>? _unhex(String s) {
  if (s.length.isOdd || s.isEmpty) return null;
  final out = <int>[];
  for (var i = 0; i + 1 < s.length; i += 2) {
    final v = int.tryParse(s.substring(i, i + 2), radix: 16);
    if (v == null) return null;
    out.add(v);
  }
  return out;
}

/// The live link to a paired Oura ring. One instance; a second concurrent ring
/// is not a thing anyone asked for.
class OuraLink {
  OuraLink._();
  static final OuraLink instance = OuraLink._();

  /// The `device` row for the paired ring, or null.
  ///
  /// `id` is MINTED at pairing (`oura-0a1b2c3d`), never the BLE remote id: a
  /// remote id is a per-app CBPeripheral UUID on iOS and a rotating RPA on
  /// Android, and letting one become the storage key fragments one ring into N
  /// identities. `remote_id` is the column that may change under the same row.
  static Future<Map<String, Object?>?> pairedRingRow() async {
    for (final r in await LocalDb.deviceRows()) {
      if (r['adapter_id'] == kOura.id) return r;
    }
    return null;
  }

  /// The most recent battery reading the ring reported, or null.
  ///
  /// DELIBERATELY NOT WRITTEN TO `band_battery`. That table has no `device_id`
  /// column and `LocalDb.batteryHealth()` reads it unfiltered — `MAX(millivolts)
  /// WHERE charging = 1` across every row — so a ring cell's voltage would land
  /// in the WHOOP band's pack-health series as the band's own full-charge
  /// voltage, and the charge-cycle count beside it comes from `band_events`,
  /// which the ring cannot contribute to. Two different cells reported as one
  /// pack is a wrong number with no way to notice it. Held here instead.
  int? get batteryPct => _batteryPct;
  int? get batteryMv => _batteryMv;
  int? _batteryPct;
  int? _batteryMv;

  BluetoothDevice? _device;

  /// Kept only so teardown can [GattBandLink.close] it — that is what stops a
  /// write the adapter queued before teardown from landing on a LATER
  /// connection to the same ring.
  GattBandLink? _link;
  StreamSubscription<BandEvent>? _runSub;
  Completer<void>? _runDone;

  /// `device.id` of the paired ring — the `device_id` every row it writes
  /// carries. Never [LocalDb.kPrimaryDeviceId]: `''` is the primary band,
  /// permanently (ASSUMPTIONS A1).
  String? _deviceId;

  /// Wall-clock now, in Unix seconds. A field so a replay is deterministic.
  int Function() _now =
      () => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  /// The `(ring decisecond, Unix second)` origin, as it is stored: `"ds,unix"`.
  ///
  /// Read from `sync_cursor` at the start of a session and handed to the
  /// adapter, which stamps against it and hands back a better one when a
  /// `time_sync` event gives it a measured pair. The host keeps the STRING
  /// because keeping it is all it does — parsing it into two ints and stamping
  /// with them here would be a second implementation of an origin, and two
  /// origins is the bug this whole mechanism exists to prevent.
  String? _anchor;

  /// Rows waiting for the batch's durable commit: `raw_archive` frames and
  /// whatever could be stamped.
  final List<Map<String, Object?>> _pendingArchive = [];
  final List<(int sec, double tempC)> _pendingTemp = [];

  /// Cursor writes, in arrival order, so teardown can wait for them.
  ///
  /// SERIALISED AND AWAITED, both load-bearing. The bookmark is written from an
  /// event callback that nothing awaits, so fire-and-forget let a teardown run
  /// first — and `stop()` clears `_deviceId`, which made the write a silent
  /// no-op. It also let a stranded-bookmark RESET be overtaken by an ordinary
  /// advance arriving after it, putting the useless bookmark straight back.
  Future<void> _cursorWrites = Future.value();

  void _writeCursor(int ds) {
    _cursorWrites =
        _cursorWrites.then((_) => _persistCursor(ds)).catchError((_) {});
  }

  bool _busy = false;

  /// Connect to the paired ring, drain its history to the end, disconnect.
  ///
  /// Returns false when nothing is paired, the key is unreadable, or the
  /// connect failed. SERIALISED: a second call while one is in flight is a
  /// no-op rather than a second radio session over the same peripheral.
  Future<bool> sync() {
    if (_busy) return Future.value(false);
    _busy = true;
    return _sync().whenComplete(() => _busy = false);
  }

  Future<bool> _sync() async {
    final row = await pairedRingRow();
    if (row == null) return false;
    final deviceId = row['id'] as String?;
    final remoteId = row['remote_id'] as String?;
    if (deviceId == null || remoteId == null || remoteId.isEmpty) return false;
    if (deviceId == LocalDb.kPrimaryDeviceId) {
      // The primary band's id, permanently. A ring writing under it would
      // interleave its seconds with the band's in one REPLACE-keyed table.
      debugPrint('[oura] refusing to sync: the ring row claims the primary '
          'device id — re-pair it with a minted id.');
      return false;
    }
    final key = await _readKey(deviceId);
    if (key == null) {
      // Distinct from "not paired": the row exists, so the user believes they
      // paired it. A locked keystore fixes itself on the next unlocked run.
      debugPrint('[oura] paired, but the pairing key could not be read. '
          'Nothing is written and nothing is re-keyed.');
      return false;
    }

    _deviceId = deviceId;
    await _loadAnchor(deviceId);
    final cursor = await LocalDb.getCursorInt(_cursorItem(deviceId)) ?? 0;

    try {
      final device = BluetoothDevice.fromId(remoteId);
      _device = device;
      await device.connect(timeout: const Duration(seconds: 20));
      final services = await device.discoverServices();
      final link = GattBandLink(
        entry: kOura,
        services: services,
        onLog: (m) => debugPrint('[oura] $m'),
      );
      _link = link;
      final missing = link.missingCharacteristics(kOura.requiredCharacteristics);
      if (missing.isNotEmpty) {
        debugPrint('[oura] ${kOura.label}: missing required characteristic(s) '
            '${missing.map((u) => u.substring(0, 8)).join(", ")}.');
        await stop();
        return false;
      }
      _startRun(
        link,
        OuraAdapter(
          key: key,
          startCursorDs: cursor,
          anchor: _parseAnchor(_anchor),
          nowSeconds: _now,
        ),
      );
      await _runDone?.future;
      return true;
    } catch (e) {
      debugPrint('[oura] sync failed: $e');
      return false;
    } finally {
      await stop();
    }
  }

  /// Drop the link, flush what the session can still stamp, disconnect.
  /// Safe to call when nothing is connected.
  Future<void> stop() async {
    // Before the run subscription is cancelled: an adapter's `finally` can
    // still write on the way out, and that write must not reach the radio.
    _link?.close();
    _link = null;
    await _runSub?.cancel();
    _runSub = null;
    _runDone = null;
    await _flushPending();
    await _cursorWrites;
    _pendingArchive.clear();
    _pendingTemp.clear();
    _anchor = null;
    _deviceId = null;
    final d = _device;
    _device = null;
    if (d != null) {
      try {
        await d.disconnect();
      } catch (_) {/* already gone */}
    }
  }

  /// Drive [adapter] over [link]. Cancelling [_runSub] is the ONLY way the
  /// session ends from this side — an adapter does not get to hang up.
  void _startRun(BandLink link, OuraAdapter adapter) {
    final done = Completer<void>();
    _runDone = done;
    void finish() {
      if (!done.isCompleted) done.complete();
    }

    _runSub = adapter.run(link).listen(
      _onEvent,
      onDone: finish,
      onError: (Object e) {
        debugPrint('[oura] session ended on error: $e');
        finish();
      },
      cancelOnError: true,
    );
  }

  /// SYNCHRONOUS on purpose, apart from the checkpoint. `listen` does not await
  /// its callback, so anything asynchronous here could interleave with the next
  /// event; buffering is pure. The checkpoint is the exception and it is safe —
  /// the adapter blocks on its own completer until `confirm()` resolves, so no
  /// second checkpoint can arrive while one is being committed.
  void _onEvent(BandEvent e) {
    switch (e) {
      case SampleBatch(:final samples, :final raw, :final ephemeral):
        // EPHEMERAL IS NEVER PERSISTED, and the check is the HOST's rather than
        // the adapter's promise. This band always sends false; the line exists
        // so the one place that decides what reaches the database is the one
        // place that reads the flag.
        if (ephemeral) return;
        _archive(raw ?? const []);
        for (final s in samples) {
          if (s.skinTempC == null) continue;
          // NO RECORD IS FROM THE FUTURE. The only plausibility bound available
          // for free, and the one that catches a stale origin extrapolating
          // FORWARD after a ring reboot. The backwards direction has no free
          // bound — the ring's history depth is not a number this project knows
          // — so the lower bound is only the "an absolute Unix second in this
          // decade" window an origin has to be inside to be an origin at all.
          if (s.tsEpoch > _now() + 300 || s.tsEpoch < 1700000000) {
            debugPrint('[oura] refusing an implausible second (${s.tsEpoch}); '
                'the bytes are archived, the reading is not stored.');
            continue;
          }
          _pendingTemp.add((s.tsEpoch, s.skinTempC!));
        }
      case OffloadCheckpoint():
        unawaited(_commitThenConfirm(e));
      case BandNote(:final key, :final value):
        switch (key) {
          case 'oura_cursor_ds':
            // Emitted only AFTER the host confirmed, which is only after the
            // commit landed. Persisting it here is therefore always behind the
            // durable data, never ahead of it — see [_commitThenConfirm].
            if (value is int) _writeCursor(value);
          case 'oura_anchor':
            // The origin the adapter measured. Persisted inside the SAME
            // transaction as the rows it stamped — see [_commit] — so an origin
            // can never survive a commit its own rows did not.
            if (value is String) _anchor = value;
          case 'oura_cursor_stranded':
            // The bookmark points past everything the ring holds, which happens
            // when the ring reboots and its decisecond counter restarts below
            // it. Dropping it costs one full re-read and is otherwise free: a
            // re-read is idempotent here (`decoded_onehz` REPLACEs by second,
            // `raw_archive` dedups on the frame bytes). Leaving it costs every
            // record the ring takes from here on, silently.
            debugPrint('[oura] the bookmark is past the end of the ring — '
                'dropping it so the next sync re-reads from the beginning.');
            _writeCursor(0);
          case 'battery':
            if (value is int) _batteryPct = value;
          case 'battery_mv':
            if (value is int) _batteryMv = value;
          default:
            debugPrint('[oura] $key = $value');
        }
    }
  }

  /// Bank one batch's verbatim frames.
  ///
  /// EVERY frame is archived, decoded or not (owner rulings R1-R3): the beat
  /// intervals, SpO2, the hypnogram and the steps are all in here undecoded and
  /// the bytes are banked now so a decoder written when someone owns a ring can
  /// be run over them.
  void _archive(List<List<int>> raw) {
    final capturedAt = _now() * 1000;
    for (final bytes in raw) {
      final f = parseFrame(bytes);
      if (f == null) continue;
      _pendingArchive.add({
        'hex': _hex(bytes),
        // NULL, not 0. This band has no flash-record counter, and `counter` is
        // what `thinRawArchiveBefore` samples on — a 0 for every row would make
        // every Oura frame `0 % 60 == 0`, i.e. permanently exempt, which is
        // accidental policy. NULL never matches its WHERE clause either, but it
        // says so honestly, and the thinning is reason-scoped anyway.
        'counter': null,
        // The frame TAG. `packet_type` is documented as a WHOOP inner[0], and
        // this is the same thing one layer over: the byte that says what the
        // record is. Safe to share the column because `reason` below is what
        // every reader of this table actually selects on.
        'packet_type': f.tag,
        // NULL, and it stays NULL. `rec_ts` would be this frame's wall-clock
        // second, which is exactly the thing that may not be knowable — and it
        // is NULL on every archived row this app has ever written.
        'rec_ts': null,
        'captured_at': capturedAt,
        // ONE REASON PER TAG, so a decoder written later finds its records by
        // name instead of re-scanning the table. NOT in
        // `LocalDb.redrivableArchiveReasons`, deliberately and permanently:
        // `redriveArchivedRecords` replays a row's `hex` through
        // `_decodeOneHzSample`, which is the WHOOP R24 chain. Handing it an
        // Oura frame would run the wrong decoder over the right bytes, which is
        // the one failure this project treats as worse than an absent number.
        'reason': 'oura_evt_0x${f.tag.toRadixString(16).padLeft(2, '0')}',
      });
    }
  }

  /// THE ORDERING IS THE POINT, and it is the safe-trim invariant in the only
  /// currency this band has.
  ///
  /// The ring never trims: there is no acknowledgement in the protocol and
  /// nothing this host writes causes it to delete anything. But the PERSISTED
  /// CURSOR is the local analogue, and it loses data exactly the same way —
  /// advancing it past records we did not commit means the next drain asks from
  /// beyond them and they are never offered again. So the durable commit
  /// (`raw_archive` + `decoded_onehz` + the anchor, one transaction) happens
  /// HERE, before `confirm()`, and `confirm()` is what lets the adapter's
  /// cursor move at all. A commit that throws returns false, the adapter leaves
  /// the cursor where it was, and the batch is re-read next session — which
  /// costs a re-read and never a record.
  Future<void> _commitThenConfirm(OffloadCheckpoint cp) async {
    final ok = await _commit();
    if (!ok) {
      debugPrint('[oura] batch not committed; leaving the cursor where it is.');
      return;
    }
    await cp.confirm();
  }

  /// One transaction: the archive, the stamped rows, the anchor. Returns
  /// whether it landed.
  Future<bool> _commit() async {
    final deviceId = _deviceId;
    if (deviceId == null) return false;
    if (_pendingArchive.isEmpty && _pendingTemp.isEmpty) return true;
    // Taken out of the buffers BEFORE the await, so a retry cannot write them
    // twice under two different anchors.
    final archive = List<Map<String, Object?>>.from(_pendingArchive);
    final temps = List<(int, double)>.from(_pendingTemp);
    _pendingArchive.clear();
    _pendingTemp.clear();
    final anchor = _anchor;
    try {
      final db = await LocalDb.instance;
      await db.transaction((txn) async {
        final b = txn.batch();
        for (final row in archive) {
          // IGNORE on the `hex` primary key. The ring re-delivers freely — a
          // re-read of the same range is idempotent by design — and two frames
          // with identical bytes ARE the same record: the envelope decisecond
          // is inside the bytes, so genuinely distinct records cannot collide.
          b.insert('raw_archive', row,
              conflictAlgorithm: ConflictAlgorithm.ignore);
        }
        for (final (sec, tempC) in temps) {
          b.insert(
            'decoded_onehz',
            {
              'device_id': deviceId,
              'ts_ms': sec * 1000,
              'rec_ts': sec,
              // ponytail: `counter` is NOT NULL and is a WHOOP flash-record
              // number this ring does not have. 0 for every row is a constant,
              // not a measurement, and nothing reads the column except
              // `ORDER BY rec_ts, counter`. Make it nullable when db.dart is
              // next open — `hrs_link.dart` carries the same note.
              'counter': 0,
              // ABSOLUTE degrees Celsius, so `skin_temp_c` and never
              // `skin_temp_raw`, which is a relative ADC count on the bands
              // that have one. `hr` and the accelerometer columns are omitted
              // entirely: this ring's beat intervals and motion are bit-packed
              // and undecoded, and absent is NULL, never 0.
              'skin_temp_c': tempC,
              'device_family': kOura.id,
              'source': kOura.id,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        if (anchor != null) {
          // In the SAME transaction as the rows it stamped. An origin that
          // survived a commit its own rows did not would stamp the next session
          // against something nothing on disk agrees with.
          await LocalDb.setCursor(_anchorItem(deviceId), anchor, txn: txn);
        }
        await b.commit(noResult: true);
      });
      return true;
    } catch (e) {
      debugPrint('[oura] commit failed, ${archive.length} frame(s) and '
          '${temps.length} reading(s) not banked: $e');
      return false;
    }
  }

  /// Commit whatever a session ended holding.
  ///
  /// Reachable when a drain ends on the link dropping rather than on a batch
  /// summary: the frames arrived, so they are ours to bank, and the adapter's
  /// cursor never moved past them — so the worst case is that the next session
  /// re-reads them.
  Future<void> _flushPending() async {
    if (_pendingArchive.isEmpty && _pendingTemp.isEmpty) return;
    await _commit();
  }

  Future<void> _persistCursor(int ds) async {
    final deviceId = _deviceId;
    if (deviceId == null) return;
    // NOT MONOTONIC, and it must not be. 0 arrives here when the ring reports
    // data remaining and answers this bookmark with nothing — a bookmark past
    // the end, which only ever gets there by going BACKWARDS. A guard that
    // refused to lower it would turn the one recoverable case into the
    // permanent stall it exists to fix.
    await LocalDb.setCursor(_cursorItem(deviceId), '$ds');
  }

  Future<void> _loadAnchor(String deviceId) async {
    _anchor = await LocalDb.getCursor(_anchorItem(deviceId));
  }

  /// The stored origin as a pair, or null when there is not a usable one.
  /// A malformed value is treated as no origin: the session then abstains
  /// until the ring hands it a measured one, which is the safe direction.
  static (int, int)? _parseAnchor(String? raw) {
    final parts = raw?.split(',') ?? const [];
    if (parts.length != 2) return null;
    final ds = int.tryParse(parts[0]);
    final unix = int.tryParse(parts[1]);
    return (ds == null || unix == null) ? null : (ds, unix);
  }

  static Future<List<int>?> _readKey(String deviceId) async {
    try {
      final hex = await _secure.read(
        key: _keyItem(deviceId),
        iOptions: _kApple,
        mOptions: _kMacos,
      );
      return hex == null ? null : _unhex(hex);
    } catch (e) {
      // A locked keychain and a wedged keystore both land here. Distinct from
      // "no key": there is nothing for the user to redo, and the next unlocked
      // run reads it fine.
      debugPrint('[oura] the keychain was unavailable: $e');
      return null;
    }
  }

  /// Replay a scripted ring through the REAL [OuraAdapter] and the real write
  /// path. The only way in: the entry point is a BLE notification and
  /// `flutter_blue_plus` has no simulator path.
  ///
  /// [reply] answers each write the way the ring would, exactly as
  /// `oura_adapter_test.dart` scripts it — a replay link records writes but
  /// cannot react to them.
  @visibleForTesting
  Future<ReplayBandLink> ingestForTest(
    String deviceId,
    List<int> key,
    List<List<int>> Function(int writeIndex, List<int> value) reply, {
    int Function()? nowSeconds,
    Duration timeouts = const Duration(milliseconds: 50),
  }) async {
    _now = nowSeconds ?? _now;
    _deviceId = deviceId;
    await _loadAnchor(deviceId);
    final cursor = await LocalDb.getCursorInt(_cursorItem(deviceId)) ?? 0;
    final link = ReplayBandLink();
    _startRun(
      link,
      OuraAdapter(
        key: key,
        startCursorDs: cursor,
        anchor: _parseAnchor(_anchor),
        nowSeconds: _now,
        replyTimeout: timeouts,
        confirmTimeout: timeouts,
      ),
    );
    var served = 0;
    for (var spin = 0; spin < 800 && !(_runDone?.isCompleted ?? true); spin++) {
      await Future<void>.delayed(Duration.zero);
      while (served < link.writes.length) {
        for (final f in reply(served, link.writes[served].$2)) {
          link.feed(kOuraNotifyChar, f, atSec: _now());
        }
        served++;
      }
    }
    await link.close();
    await _runDone?.future.timeout(
      const Duration(seconds: 2),
      onTimeout: () {},
    );
    await _runSub?.cancel();
    _runSub = null;
    _runDone = null;
    await _flushPending();
    await _cursorWrites;
    _pendingArchive.clear();
    _pendingTemp.clear();
    _anchor = null;
    _deviceId = null;
    return link;
  }
}

/// Pair [device] as this phone's Oura ring. Null on success, or a sentence the
/// user can act on.
///
/// FACTORY RESET IS A PRECONDITION, NOT A CONSEQUENCE. The ring holds exactly
/// one 16-byte key and will only accept a new one while it is factory reset —
/// so a ring currently onboarded to its own vendor app cannot be paired here at
/// all until the owner resets it, and resetting is what removes it from that
/// app. There is no state in which both work. Say that BEFORE the user commits;
/// this function is the point of no return, not the warning.
///
/// THE KEY IS OURS AND NEVER LEAVES THE PHONE. It is generated here by
/// `Random.secure()`, there is no vendor server anywhere in the handshake and
/// no account is needed. Losing it costs another factory reset, nothing more.
///
/// THE ORDER IS INSTALL, THEN PROVE. The key install is unauthenticated — it
/// has to be, since it is what creates the credential — so it goes out first,
/// before any nonce request. The authentication round trip after it is not
/// required by the protocol; it is here because "the ring acknowledged the
/// write" and "the ring will now let us in" are different claims, and a pairing
/// that only checks the first hands the user a device row that can never sync.
///
/// STILL HARDWARE-UNVERIFIED, like everything else on this path (R6).
Future<String?> pairOuraRing(BluetoothDevice device) async {
  final rnd = Random.secure();
  final key = List<int>.generate(16, (_) => rnd.nextInt(256));
  final deviceId =
      'oura-${_hex(List<int>.generate(4, (_) => rnd.nextInt(256)))}';
  GattBandLink? link;
  try {
    await device.connect(timeout: const Duration(seconds: 20));
    final services = await device.discoverServices();
    link = GattBandLink(
      entry: kOura,
      services: services,
      onLog: (m) => debugPrint('[oura pair] $m'),
    );
    final missing = link.missingCharacteristics(kOura.requiredCharacteristics);
    if (missing.isNotEmpty) {
      return 'That device does not expose the ring service this app speaks.';
    }

    // Install, then prove — over the real wire builders and nothing else.
    //
    // ONE subscription and a growing list, rather than a `firstWhere` per
    // reply: `BandLink.notify` is single-subscription, so the second
    // `firstWhere` would throw "already listened to" AFTER the first reply had
    // been consumed — a pairing that fails on a ring that answered correctly.
    // ponytail: a 20 ms poll over the list is the smallest correct thing here.
    // The alternative is a second copy of `oura.dart`'s private `_Inbox`, for
    // three replies, once, during pairing.
    final inbox = <OuraFrame>[];
    final sub = link.notify(kOuraNotifyChar).listen((rec) {
      final f = parseFrame(rec.$2);
      if (f != null) inbox.add(f);
    });
    var read = 0;
    Future<OuraFrame?> waitFor(bool Function(OuraFrame) matches) async {
      final elapsed = Stopwatch()..start();
      while (elapsed.elapsed < const Duration(seconds: 10)) {
        while (read < inbox.length) {
          final f = inbox[read++];
          if (matches(f)) return f;
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      return null;
    }

    try {
      // THE KEY IS STORED BEFORE IT IS SENT, and the order is deliberate. A
      // crash between the write and the store leaves the ring holding a key
      // this phone does not have — unrecoverable except by another factory
      // reset, which is the one cost in this flow the user cannot undo. A
      // stored key with no ring behind it costs nothing: `sync()` never looks
      // at it, because there is no `device` row pointing to it yet.
      await _secure.write(
        key: _keyItem(deviceId),
        value: _hex(key),
        iOptions: _kApple,
        mOptions: _kMacos,
      );
      if (!await link.write(kOuraCommandChar, ouraCmdSetAuthKey(key))) {
        return 'The ring would not accept a command. Try again with it on '
            'the charger and next to the phone.';
      }
      final installed = await waitFor((f) => ouraSetAuthKeyResult(f) != null);
      // SILENCE IS A REFUSAL, NOT CONSENT. A ring that already holds a key is
      // the case that matters here and it does not necessarily answer at all —
      // and carrying on to mint a `device` row on the strength of a quiet ring
      // is how a user spends a factory reset and ends up with nothing working.
      if (installed == null || ouraSetAuthKeyResult(installed) != 0) {
        return _kResetFirst;
      }
      if (!await link.write(kOuraCommandChar, ouraCmdAuthNonce())) {
        return 'The ring would not accept a command. Try again with it on '
            'the charger and next to the phone.';
      }
      final challenge = await waitFor((f) => ouraAuthNonce(f) != null);
      if (challenge == null) {
        return 'The ring stopped answering part-way through pairing. Put it on '
            'the charger, keep it next to the phone, and try again.';
      }
      final answer = ouraAuthResponse(key, ouraAuthNonce(challenge)!);
      if (!await link.write(kOuraCommandChar, ouraCmdAuthenticate(answer))) {
        return 'The ring would not accept the pairing answer.';
      }
      final replyFrame = await waitFor((f) => ouraAuthResult(f) != null);
      if (replyFrame == null) {
        return 'The ring stopped answering part-way through pairing. Put it on '
            'the charger, keep it next to the phone, and try again.';
      }
      // THE CODES CARRY DIFFERENT REMEDIES, so they are not collapsed into one
      // sentence. `factoryReset` here means the install did not actually take
      // even though it was acknowledged — retrying is worth a try and does not
      // cost another reset. Everything else means the ring belongs to something
      // else, and only a reset frees it.
      final result = ouraAuthResult(replyFrame);
      if (result == kOuraAuthFactoryReset) {
        return 'The ring took the key but is still waiting for one, which '
            'should not happen. Try pairing again.';
      }
      if (result != 0) {
        return _kResetFirst;
      }
    } finally {
      await sub.cancel();
    }

    // The `device` row LAST, because it is what makes the ring reachable: a row
    // that exists is a ring `sync()` will try to drain, so it is only written
    // once the key is stored AND the ring has proved it accepts it.
    await LocalDb.upsertDevice(
      id: deviceId,
      adapterId: kOura.id,
      remoteId: device.remoteId.str,
      label: device.platformName.isEmpty ? kOura.label : device.platformName,
      // `tier` is left unset on purpose. It means MEASUREMENT QUALITY and it is
      // what decides precedence between two sources — and this ring supplies no
      // signal at all today (`OuraAdapter.signals` is `const {}`), so there is
      // no quality to rank. NULL is a refusal, not a default.
    );
    return null;
  } catch (e) {
    debugPrint('[oura pair] failed: $e');
    return 'Could not connect to that ring.';
  } finally {
    link?.close();
    try {
      await device.disconnect();
    } catch (_) {/* already gone */}
  }
}
