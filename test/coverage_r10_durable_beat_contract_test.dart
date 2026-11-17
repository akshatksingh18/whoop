// Authored R10 packets through the real engine, SQLite transaction and trim ACK.
// Only the GATT transport is substituted; nothing is sent to physical hardware.
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' show Database;
import 'package:whoop_companion/ble/ble_engine.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_protocol/whoop_protocol.dart' as p;
import 'coverage_ble_durable_boundary_test.dart'
    show historyStart, historyEnd, until;
import 'support/coverage_store.dart';

const ts = 1760000000;
const tokenHex = '8172635445362718';
const token = [0x81, 0x72, 0x63, 0x54, 0x45, 0x36, 0x27, 0x18];

Uint8List authoredR10(int count) {
  final b = Uint8List(1920);
  b[0] = p.PacketType.historicalData;
  b[1] = 10;
  b[2] = 0x80;
  final v = ByteData.sublistView(b)
    ..setUint32(3, 41, Endian.little)
    ..setUint32(7, ts, Endian.little);
  b[17] = 60;
  b[18] = count;
  for (var i = 0; i < 8; i++) {
    v.setInt16(19 + 2 * i, 800 + i, Endian.little);
  }
  return b;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late BleEngine engine;
  late List<String> logs;
  late List<List<int>> writes;
  late int expected;
  late bool refuseAck;
  setUpAll(() => coverageStore('r10-durable-contract'));
  setUp(() async {
    await resetCoverageStore();
    db = await LocalDb.instance;
    logs = [];
    writes = [];
    expected = 8;
    refuseAck = false;
    engine = BleEngine(
      onRecord: (_, _) async {},
      onState: (_) {},
      log: logs.add,
    );
  });
  tearDown(() async {
    await db.execute('DROP TRIGGER IF EXISTS authored_r10_refusal');
    await engine.disconnect();
  });
  tearDownAll(LocalDb.close);

  Future<List<Map<String, Object?>>> beats() => db.query(
    'decoded_rr',
    where: 'device_id = ?',
    whereArgs: [LocalDb.kPrimaryDeviceId],
    orderBy: 'beat_index',
  );
  void install() => engine.debugInstallFakeLink(
    band: p.BandProfile.gen4,
    onCommit: (raws, samples, trim, {archives, deviceFamily}) async {
      expect(samples, hasLength(1));
      expect(samples.single!.rrIntervalsMs, [
        for (var i = 0; i < expected; i++) 800 + i,
      ]);
      expect([
        samples.single!.ax,
        samples.single!.ay,
        samples.single!.az,
      ], everyElement(isNull));
      await LocalDb.commitSyncBatch(
        raws,
        samples,
        trimToken: trim,
        archives: archives,
        deviceFamily: deviceFamily,
      );
    },
    onWrite: (frame) async {
      final inner = p.parseFrame(frame)!.inner;
      if (inner[2] == p.Cmd.historicalDataResult) {
        expect(inner.sublist(3), [1, ...token]);
        final stored = await beats();
        expect(stored.map((r) => r['rr_ms']), [
          for (var i = 0; i < expected; i++) 800 + i,
        ]);
        expect(stored.map((r) => r['beat_index']), [
          for (var i = 0; i < expected; i++) i,
        ]);
        expect(
          stored.every((r) => r['rec_ts'] == ts && r['rr_ts_ms'] == ts * 1000),
          true,
        );
        expect(
          await db.query(
            'decoded_onehz',
            where: 'device_id = ?',
            whereArgs: [LocalDb.kPrimaryDeviceId],
          ),
          isEmpty,
        );
        expect(await LocalDb.getCursor('strap_trim'), tokenHex);
        writes.add(List.of(inner.sublist(3)));
        return !refuseAck;
      }
      return true;
    },
  );
  void burst(int count) {
    for (final inner in [historyStart(), authoredR10(count), historyEnd()]) {
      engine.debugReceiveFrame(p.Frame(inner, true, true));
    }
  }

  Future<void> acked() async {
    for (var i = 0; i < 1200; i++) {
      if ((await LocalDb.syncLedgerEntry('batch:$tokenHex'))?['status'] ==
          'acked') {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    fail('Expected durable ACK ledger: ${logs.join('\n')}');
  }

  for (final count in [0, 1, 4, 5, 8, 9]) {
    test(
      'COV-48 R10 declared $count commits its accepted beats before the exact ACK and reopens',
      () async {
        expected = count <= 8 ? count : 0;
        install();
        burst(count);
        await acked();
        expect(writes, isNotEmpty);
        final before = await beats();
        expect(before, hasLength(expected));
        final header = await db.query('samples');
        expect(header, hasLength(1));
        expect(header.single['hr'], 60);
        expect(await db.query('raw_archive'), isEmpty);
        await engine.disconnect();
        await LocalDb.close();
        db = await LocalDb.instance;
        expect(await beats(), before);
        expect(await LocalDb.getCursor('strap_trim'), tokenHex);
        expect(
          (await LocalDb.syncLedgerEntry('batch:$tokenHex'))!['status'],
          'acked',
        );
      },
    );
  }
  for (final kind in ['beat insert', 'cursor insert', 'ACK delivery']) {
    test(
      'COV-48 R10 $kind refusal preserves evidence and retries all eight without duplicates',
      () async {
        if (kind != 'ACK delivery') {
          await db.execute(
            kind == 'beat insert'
                ? "CREATE TRIGGER authored_r10_refusal BEFORE INSERT ON decoded_rr BEGIN SELECT RAISE(ABORT,'authored R10 beat refusal'); END"
                : "CREATE TRIGGER authored_r10_refusal BEFORE INSERT ON sync_cursor WHEN NEW.name='rec_ts_hw' BEGIN SELECT RAISE(ABORT,'authored R10 cursor refusal'); END",
          );
        } else {
          refuseAck = true;
        }
        install();
        burst(8);
        if (refuseAck) {
          var ended = false;
          for (var i = 0; i < 1200; i++) {
            if ((await LocalDb.syncLedgerEntry('batch:$tokenHex'))?['status'] ==
                    'ack_failed' &&
                !engine.offloadActive) {
              ended = true;
              break;
            }
            await Future<void>.delayed(const Duration(milliseconds: 5));
          }
          expect(ended, true, reason: logs.join('\n'));
          expect(await beats(), hasLength(8));
          expect(writes, isNotEmpty);
          expect(
            (await LocalDb.syncLedgerEntry('batch:$tokenHex'))!['status'],
            'ack_failed',
          );
        } else {
          await until(
            () => logs.any((s) => s.contains('DURABLE COMMIT FAILED')),
            attempts: 1200,
          );
          expect(writes, isEmpty);
          expect(await beats(), isEmpty);
          expect(await db.query('samples'), isEmpty);
          expect(await LocalDb.getCursor('strap_trim'), isNull);
        }
        await db.execute('DROP TRIGGER IF EXISTS authored_r10_refusal');
        await engine.disconnect();
        refuseAck = false;
        writes.clear();
        install();
        burst(8);
        await acked();
        expect(await beats(), hasLength(8));
        expect(writes, isNotEmpty);
        expect((await db.query('samples')), hasLength(1));
      },
    );
  }
  test(
    'COV-48 R10 replay preserves foreign device beats and reopens without duplicate primary beats',
    () async {
      await LocalDb.upsertDevice(
        id: 'authored-foreign-device',
        adapterId: 'gen4',
      );
      await db.insert('decoded_rr', {
        'device_id': 'authored-foreign-device',
        'ts_ms': ts * 1000,
        'rec_ts': ts,
        'rr_ts_ms': ts * 1000,
        'beat_ts_ms': ts * 1000,
        'beat_index': 0,
        'rr_ms': 850,
        'device_family': 'gen4',
      });
      final foreign = await db.query(
        'decoded_rr',
        where: 'device_id = ?',
        whereArgs: ['authored-foreign-device'],
      );
      for (var attempt = 0; attempt < 2; attempt++) {
        install();
        burst(8);
        await acked();
        expect(await beats(), hasLength(8));
        expect(
          await db.query(
            'decoded_rr',
            where: 'device_id = ?',
            whereArgs: ['authored-foreign-device'],
          ),
          foreign,
        );
        await engine.disconnect();
      }
      await LocalDb.close();
      db = await LocalDb.instance;
      expect(await beats(), hasLength(8));
      expect(
        await db.query(
          'decoded_rr',
          where: 'device_id = ?',
          whereArgs: ['authored-foreign-device'],
        ),
        foreign,
      );
      expect(await LocalDb.getCursor('strap_trim'), tokenHex);
    },
  );
}
