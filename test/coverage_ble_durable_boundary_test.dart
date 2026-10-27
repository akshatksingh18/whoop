// Real frame routing, decode, SQLite transaction and ACK ordering. Only GATT
// delivery is substituted. Every record/token/profile in this file is synthetic.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/ble/ble_engine.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/state/prefs.dart';
import 'package:whoop_protocol/whoop_protocol.dart' as proto;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _ts = 1760000000;
const _token = [0x81, 0x72, 0x63, 0x54, 0x45, 0x36, 0x27, 0x18];
const _tokenHex = '8172635445362718';

Uint8List historyStart() => Uint8List.fromList([
  proto.PacketType.metadata,
  1,
  proto.SyncMeta.historyStart,
]);

Uint8List historyEnd({int count = 1}) {
  final inner = Uint8List(24);
  inner[0] = proto.PacketType.metadata;
  inner[1] = 2;
  inner[2] = proto.SyncMeta.historyEnd;
  ByteData.sublistView(inner)
    ..setUint32(3, _ts, Endian.little)
    ..setUint32(9, count, Endian.little);
  inner.setRange(13, 21, _token);
  return inner;
}

Uint8List record(proto.BandProfile band, {bool unknown = false}) {
  final gen5 = band == proto.BandProfile.gen5;
  final inner = Uint8List(gen5 ? proto.kGen5V18InnerLen : 89);
  inner[0] = proto.PacketType.historicalData;
  inner[1] = unknown ? 99 : (gen5 ? 18 : 24);
  inner[2] = 0x80;
  final data = ByteData.sublistView(inner)
    ..setUint32(3, 41, Endian.little)
    ..setUint32(7, _ts, Endian.little);
  if (gen5) {
    inner[14] = 64;
    data
      ..setFloat32(33, 0.5, Endian.little)
      ..setFloat32(45, 1.0, Endian.little);
  }
  return inner;
}

Future<void> until(bool Function() done) async {
  for (var i = 0; i < 200 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(done(), true, reason: 'Synthetic queued frame processing must settle');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    final dir = (await Directory(
      'build/coverage-remainder/ble-durable',
    ).create(recursive: true)).absolute;
    LocalDb.dbName = '${dir.path}/synthetic.sqlite';
    await LocalDb.close();
    await databaseFactory.deleteDatabase(LocalDb.dbName);
    db = await LocalDb.instance;
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.ensureLoaded();
    await LocalDb.wipeAll();
  });
  tearDown(() async {
    await db.execute('DROP TRIGGER IF EXISTS refuse_synthetic_cursor');
    await db.execute('DROP TRIGGER IF EXISTS refuse_synthetic_archive');
  });
  tearDownAll(LocalDb.close);

  for (final band in [proto.BandProfile.gen4, proto.BandProfile.gen5]) {
    final name = band == proto.BandProfile.gen4 ? 'gen4' : 'gen5';
    for (final mode in [
      'decoded',
      'archive',
      'cursor failure',
      'archive failure',
    ]) {
      test(
        '$name $mode cannot ACK before the matching durable transaction',
        () async {
          final archive = mode.contains('archive');
          final fail = mode.contains('failure');
          if (fail) {
            await db.execute(
              mode == 'cursor failure'
                  ? "CREATE TRIGGER refuse_synthetic_cursor BEFORE INSERT ON sync_cursor WHEN NEW.name='rec_ts_hw' BEGIN SELECT RAISE(ABORT,'synthetic cursor failure'); END"
                  : "CREATE TRIGGER refuse_synthetic_archive BEFORE INSERT ON raw_archive BEGIN SELECT RAISE(ABORT,'synthetic archive failure'); END",
            );
          }
          final logs = <String>[];
          final writes = <List<int>>[];
          var committed = false;
          final engine = BleEngine(
            onRecord: (_, _) async {},
            onState: (_) {},
            log: logs.add,
          );
          engine.debugInstallFakeLink(
            band: band,
            onCommit: (raws, samples, token, {archives, deviceFamily}) async {
              expect(writes, isEmpty);
              expect(token, _tokenHex);
              await LocalDb.commitSyncBatch(
                raws,
                samples,
                trimToken: token,
                archives: archives,
                deviceFamily: deviceFamily,
              );
              committed = true;
            },
            onWrite: (frame) async {
              final inner = proto.parseFrame(frame, profile: band)!.inner;
              if (inner[2] == proto.Cmd.historicalDataResult) {
                expect(committed, true);
                expect(await LocalDb.getCursor('strap_trim'), _tokenHex);
                final decoded = await db.query('decoded_onehz');
                final archived = await db.query('raw_archive');
                expect(archive ? archived : decoded, hasLength(1));
                expect(archive ? decoded : archived, isEmpty);
                writes.add(inner.sublist(3));
              }
              return true;
            },
          );
          try {
            for (final inner in [
              historyStart(),
              record(band, unknown: archive),
              historyEnd(),
            ]) {
              engine.debugReceiveFrame(proto.Frame(inner, true, true));
            }
            await until(
              () => fail
                  ? logs.any((s) => s.contains('DURABLE COMMIT FAILED'))
                  : writes.isNotEmpty,
            );
            if (fail) {
              await until(() => !engine.isConnected);
              expect(writes, isEmpty);
              expect(committed, false);
              expect(await LocalDb.getCursor('strap_trim'), isNull);
              expect(await LocalDb.getCursorInt('rec_ts_hw'), isNull);
              expect(await db.query('decoded_onehz'), isEmpty);
              expect(await db.query('raw_archive'), isEmpty);
              expect(
                (await LocalDb.syncLedgerEntry('batch:$_tokenHex'))!['status'],
                'commit_failed',
              );
            } else {
              expect(writes.single, [1, ..._token]);
              expect(await LocalDb.getCursorInt('counter_hw'), archive ? 0 : 41);
              expect(await LocalDb.getCursorInt('rec_ts_hw'), archive ? 0 : _ts);
              if (archive) {
                expect((await db.query('raw_archive')).single['counter'], 41);
              }
            }
          } finally {
            await engine.disconnect();
          }
        },
      );
    }

    test(
      '$name a held real commit survives link loss without ACKing its old token',
      () async {
        final reached = Completer<void>(), release = Completer<void>();
        final writes = <int>[];
        final engine = BleEngine(onRecord: (_, _) async {}, onState: (_) {});
        var committed = false;
        engine.debugInstallFakeLink(
          band: band,
          onCommit: (raws, samples, token, {archives, deviceFamily}) async {
            reached.complete();
            await release.future;
            await LocalDb.commitSyncBatch(
              raws,
              samples,
              trimToken: token,
              archives: archives,
              deviceFamily: deviceFamily,
            );
            committed = true;
          },
          onWrite: (frame) async {
            writes.add(proto.parseFrame(frame, profile: band)!.inner[2]);
            return true;
          },
        );
        for (final inner in [historyStart(), record(band), historyEnd()]) {
          engine.debugReceiveFrame(proto.Frame(inner, true, true));
        }
        await reached.future;
        await engine.disconnect();
        release.complete();
        await until(() => committed);
        // Queue continuations have had a turn, not just the SQL callback.
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(writes, isEmpty);
        expect(await db.query('decoded_onehz'), hasLength(1));
        expect(await LocalDb.getCursor('strap_trim'), _tokenHex);
      },
    );
  }
}
