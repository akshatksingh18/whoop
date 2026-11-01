// Real frame routing, decode, SQLite transaction and ACK ordering. Only GATT
// delivery is substituted. Every record/token/profile in this file is synthetic.
import 'dart:async';
import 'dart:convert';
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

Uint8List historyComplete() => Uint8List.fromList([
  proto.PacketType.metadata,
  3,
  proto.SyncMeta.historyComplete,
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

Future<void> until(bool Function() done, {int attempts = 200}) async {
  for (var i = 0; i < attempts && !done(); i++) {
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
    await db.execute('DROP TRIGGER IF EXISTS refuse_synthetic_tail');
  });
  tearDownAll(LocalDb.close);

  for (final band in [proto.BandProfile.gen4, proto.BandProfile.gen5]) {
    test(
      'COV-48 ${band.type.name} refused best-effort abort keeps durable ACK-failure evidence and retries',
      () async {
        final logs = <String>[], writes = <List<int>>[];
        var refusing = true;
        final engine = BleEngine(
          onRecord: (_, _) async {},
          onState: (_) {},
          log: logs.add,
        );
        void install() => engine.debugInstallFakeLink(
          band: band,
          onCommit: (raws, samples, token, {archives, deviceFamily}) =>
              LocalDb.commitSyncBatch(
                raws,
                samples,
                trimToken: token,
                archives: archives,
                deviceFamily: deviceFamily,
              ),
          onWrite: (frame) async {
            final inner = proto.parseFrame(frame, profile: band)!.inner;
            writes.add(List.of(inner));
            if (inner[2] == proto.Cmd.historicalDataResult) {
              expect(await db.query('decoded_onehz'), hasLength(1));
              expect(await LocalDb.getCursor('strap_trim'), _tokenHex);
              return !refusing;
            }
            if (inner[2] == proto.Cmd.abortHistoricalTransmits) {
              return !refusing;
            }
            return true;
          },
        );
        void rx(Uint8List inner) =>
            engine.debugReceiveFrame(proto.Frame(inner, true, true));
        final bytes = record(band);
        void burst() {
          rx(historyStart());
          rx(bytes);
          rx(historyEnd());
        }

        try {
          install();
          burst();
          await until(
            () =>
                logs.any(
                  (s) =>
                      s.contains('best-effort history abort') &&
                      s.contains('was not delivered'),
                ) &&
                !engine.offloadActive,
            attempts: 1200,
          );
          expect(
            writes.where((w) => w[2] == proto.Cmd.abortHistoricalTransmits),
            hasLength(1),
          );
          final row = (await LocalDb.syncLedgerEntry('batch:$_tokenHex'))!;
          expect(row['status'], 'ack_failed');
          expect(row['acked_at'], isNull);
          expect(jsonDecode(row['meta_json'] as String)['ack_failures'], 1);
          final saved = await db.query('decoded_onehz');
          expect(saved, hasLength(1));
          expect(await LocalDb.getCursor('strap_trim'), _tokenHex);
          final count = writes.length;
          for (final marker in [
            historyStart(),
            historyEnd(),
            historyComplete(),
          ]) {
            rx(marker);
          }
          await Future<void>.delayed(const Duration(milliseconds: 20));
          expect(writes, hasLength(count));
          expect(
            await engine.debugWriteRaw(
              proto.buildCommand(71, proto.Cmd.getBatteryLevel, const [
                0,
              ], band),
            ),
            true,
          );
          await engine.disconnect();
          refusing = false;
          writes.clear();
          install();
          burst();
          await until(
            () => writes.any((w) => w[2] == proto.Cmd.historicalDataResult),
            attempts: 1200,
          );
          await until(() => logs.any((s) => s.contains('ACK')), attempts: 1200);
          // Wait for the real post-write ledger update rather than only the
          // transport callback, which precedes publication.
          for (var i = 0; i < 1200; i++) {
            if ((await LocalDb.syncLedgerEntry(
                  'batch:$_tokenHex',
                ))!['status'] ==
                'acked') {
              break;
            }
            await Future<void>.delayed(const Duration(milliseconds: 5));
          }
          expect(
            (await LocalDb.syncLedgerEntry('batch:$_tokenHex'))!['status'],
            'acked',
          );
          expect(await db.query('decoded_onehz'), saved);
          expect(
            writes.where((w) => w[2] == proto.Cmd.historicalDataResult),
            hasLength(1),
          );
          expect(writes.single.sublist(3, 12), [1, ..._token]);
          expect(await LocalDb.getCursor('strap_trim'), _tokenHex);
        } finally {
          await engine.disconnect();
        }
      },
    );
  }
  for (final band in [proto.BandProfile.gen4, proto.BandProfile.gen5]) {
    final name = band == proto.BandProfile.gen4 ? 'gen4' : 'gen5';
    test(
      'COV-42 $name failed ACKs preserve one durable row through quarantine and recovery',
      () async {
        final writes = <List<int>>[];
        var refuseAck = true;
        var aborts = 0;
        final engine = BleEngine(onRecord: (_, _) async {}, onState: (_) {});
        void connect() => engine.debugInstallFakeLink(
          band: band,
          onCommit: (raws, samples, token, {archives, deviceFamily}) =>
              LocalDb.commitSyncBatch(
                raws,
                samples,
                trimToken: token,
                archives: archives,
                deviceFamily: deviceFamily,
              ),
          onWrite: (frame) async {
            final inner = proto.parseFrame(frame, profile: band)!.inner;
            writes.add(inner);
            if (inner[2] == proto.Cmd.abortHistoricalTransmits) aborts++;
            if (inner[2] == proto.Cmd.historicalDataResult) {
              expect(await db.query('decoded_onehz'), hasLength(1));
              expect(await LocalDb.getCursor('strap_trim'), _tokenHex);
              return !refuseAck;
            }
            return true;
          },
        );
        void burst() {
          for (final inner in [historyStart(), record(band), historyEnd()]) {
            engine.debugReceiveFrame(proto.Frame(inner, true, true));
          }
        }

        try {
          for (var failure = 1; failure <= 3; failure++) {
            connect();
            burst();
            await until(
              () => aborts == failure && !engine.offloadActive,
              attempts: 1000,
            );
            final row = (await LocalDb.syncLedgerEntry('batch:$_tokenHex'))!;
            expect(row['status'], 'ack_failed');
            expect(row['acked_at'], isNull);
            expect(
              jsonDecode(row['meta_json'] as String)['ack_failures'],
              failure,
            );
            // The fake link does not run the UI's READY transition. Probe the
            // actual write guard instead: the same link must still accept I/O.
            expect(
              await engine.debugWriteRaw(
                proto.buildCommand(71, proto.Cmd.getBatteryLevel, const [
                  0,
                ], band),
              ),
              isTrue,
              reason: 'terminal failure must not tear down the transport',
            );
            expect(await db.query('decoded_onehz'), hasLength(1));
            expect(engine.state.syncChunkQuarantined, failure == 3);
          }
          final evidence = await LocalDb.quarantinedSyncChunks();
          expect(evidence, hasLength(1));
          expect(evidence.single['reason'], 'persistent_ack_failure');
          expect(
            jsonDecode(evidence.single['payload_json'] as String)['token'],
            _tokenHex,
          );
          final failedWrites = writes
              .where((w) => w[2] == proto.Cmd.historicalDataResult)
              .toList();
          expect(failedWrites, hasLength(9));
          for (final inner in failedWrites) {
            expect(inner.sublist(3), [1, ..._token]);
          }

          refuseAck = false;
          connect();
          burst();
          await until(() => !engine.state.syncChunkQuarantined);
          await until(
            () =>
                writes
                    .where((w) => w[2] == proto.Cmd.historicalDataResult)
                    .length ==
                10,
          );
          // The per-token ledger is written after the transport succeeds.
          for (var i = 0; i < 200; i++) {
            if ((await LocalDb.syncLedgerEntry(
                  'batch:$_tokenHex',
                ))?['status'] ==
                'acked') {
              break;
            }
            await Future<void>.delayed(const Duration(milliseconds: 5));
          }
          expect(
            (await LocalDb.syncLedgerEntry('batch:$_tokenHex'))!['status'],
            'acked',
          );
          expect(
            await LocalDb.quarantinedSyncChunks(),
            evidence,
            reason: 'recovery must keep the diagnostic evidence',
          );
          expect(await db.query('decoded_onehz'), hasLength(1));
          expect(aborts, 3);
        } finally {
          await engine.disconnect();
        }
      },
    );

    test(
      'COV-42 $name only productive completion clears empty-sync warnings',
      () async {
        final logs = <String>[];
        final writes = <List<int>>[];
        final engine = BleEngine(
          onRecord: (_, _) async {},
          onState: (_) {},
          log: logs.add,
        );
        engine.debugInstallFakeLink(
          band: band,
          onCommit: (raws, samples, token, {archives, deviceFamily}) =>
              LocalDb.commitSyncBatch(
                raws,
                samples,
                trimToken: token,
                archives: archives,
                deviceFamily: deviceFamily,
              ),
          onWrite: (frame) async {
            writes.add(proto.parseFrame(frame, profile: band)!.inner);
            return true;
          },
        );
        void rx(Uint8List inner) =>
            engine.debugReceiveFrame(proto.Frame(inner, true, true));
        try {
          for (var completed = 1; completed <= 3; completed++) {
            rx(historyStart());
            rx(historyComplete());
            await until(
              () =>
                  logs
                          .where(
                            (s) =>
                                s.contains('HistoryComplete — backlog drained'),
                          )
                          .length ==
                      completed &&
                  !engine.offloadActive,
            );
            expect(engine.state.syncClockLost, completed == 3);
          }
          expect(writes, isEmpty, reason: 'COMPLETE has no trim ACK');
          expect(await db.query('decoded_onehz'), isEmpty);
          engine.state.strapNeedsReboot = true;
          rx(historyStart());
          rx(record(band));
          rx(historyEnd());
          await until(
            () => writes.any((w) => w[2] == proto.Cmd.historicalDataResult),
          );
          expect(
            engine.state.syncClockLost,
            isTrue,
            reason: 'the warnings clear at completed offload policy',
          );
          rx(historyComplete());
          await until(() => !engine.offloadActive);
          expect(engine.state.syncClockLost, isFalse);
          expect(engine.state.strapNeedsReboot, isFalse);
          expect(await db.query('decoded_onehz'), hasLength(1));
        } finally {
          await engine.disconnect();
        }
      },
    );

    test(
      'COV-42 $name a refused COMPLETE tail stays buffered and retries without a premature trim',
      () async {
        final logs = <String>[];
        final writes = <List<int>>[];
        await db.execute(
          "CREATE TRIGGER refuse_synthetic_tail BEFORE INSERT ON decoded_onehz BEGIN SELECT RAISE(ABORT,'synthetic tail refusal'); END",
        );
        final engine = BleEngine(
          onRecord: (_, _) async {},
          onState: (_) {},
          log: logs.add,
        );
        engine.debugInstallFakeLink(
          band: band,
          onCommit: (raws, samples, token, {archives, deviceFamily}) =>
              LocalDb.commitSyncBatch(
                raws,
                samples,
                trimToken: token,
                archives: archives,
                deviceFamily: deviceFamily,
              ),
          onWrite: (frame) async {
            writes.add(proto.parseFrame(frame, profile: band)!.inner);
            expect(await db.query('decoded_onehz'), hasLength(1));
            return true;
          },
        );
        void rx(Uint8List inner) =>
            engine.debugReceiveFrame(proto.Frame(inner, true, true));
        try {
          rx(historyStart());
          rx(record(band));
          rx(historyComplete());
          await until(
            () =>
                logs.any(
                  (s) => s.contains('HistoryComplete tail commit FAILED'),
                ) &&
                !engine.offloadActive,
          );
          expect(writes, isEmpty);
          expect(await db.query('decoded_onehz'), isEmpty);
          expect(await LocalDb.getCursor('strap_trim'), isNull);
          await db.execute('DROP TRIGGER refuse_synthetic_tail');
          // No new sensor frame: the failed tail itself must still be present.
          rx(historyStart());
          rx(historyEnd(count: 0));
          await until(() => writes.isNotEmpty);
          expect(writes.single.sublist(3), [1, ..._token]);
          expect(await db.query('decoded_onehz'), hasLength(1));
          expect(await LocalDb.getCursorInt('rec_ts_hw'), _ts);
          expect(await LocalDb.getCursor('strap_trim'), _tokenHex);
        } finally {
          await engine.disconnect();
        }
      },
    );

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
              expect(
                await LocalDb.getCursorInt('counter_hw'),
                archive ? 0 : 41,
              );
              expect(
                await LocalDb.getCursorInt('rec_ts_hw'),
                archive ? 0 : _ts,
              );
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

  for (final refuseResult in [false, true]) {
    test(
      'COV-42 gen5 short-count ${refuseResult ? 'failed result is terminal' : 'redelivery succeeds'} with durable SQL rows',
      () async {
        final writes = <List<int>>[];
        final band = proto.BandProfile.gen5;
        final engine = BleEngine(onRecord: (_, _) async {}, onState: (_) {});
        engine.debugInstallFakeLink(
          band: band,
          onCommit: (raws, samples, token, {archives, deviceFamily}) =>
              LocalDb.commitSyncBatch(
                raws,
                samples,
                trimToken: token,
                archives: archives,
                deviceFamily: deviceFamily,
              ),
          onWrite: (frame) async {
            final inner = proto.parseFrame(frame, profile: band)!.inner;
            writes.add(inner);
            expect(await db.query('decoded_onehz'), hasLength(1));
            if (inner[2] == proto.Cmd.historicalDataResult && inner[3] == 0) {
              expect(await LocalDb.getCursor('strap_trim'), isNull);
              return !refuseResult;
            }
            return true;
          },
        );
        void rx(Uint8List inner) =>
            engine.debugReceiveFrame(proto.Frame(inner, true, true));
        try {
          rx(historyStart());
          rx(record(band));
          rx(historyEnd(count: 3));
          await until(
            () => refuseResult
                ? writes.any(
                        (w) => w[2] == proto.Cmd.abortHistoricalTransmits,
                      ) &&
                      !engine.offloadActive
                : writes.isNotEmpty,
          );
          expect(writes.first.sublist(3, 5), [0, 0]);
          // The gen5 envelope pads this short failure body with zero bytes.
          expect(writes.first.sublist(5), everyElement(0));
          expect(await LocalDb.getCursor('strap_trim'), isNull);
          expect(await LocalDb.getCursorInt('rec_ts_hw'), _ts);
          expect(await db.query('decoded_onehz'), hasLength(1));
          if (refuseResult) {
            expect(
              (await LocalDb.syncLedgerEntry('batch:$_tokenHex'))!['status'],
              'aborted',
            );
            final sent = writes.length;
            for (final marker in [
              historyStart(),
              historyEnd(),
              historyComplete(),
            ]) {
              rx(marker);
            }
            await Future<void>.delayed(const Duration(milliseconds: 15));
            expect(
              writes,
              hasLength(sent),
              reason: 'stragglers cannot reopen a terminal task',
            );
            expect(
              await engine.debugWriteRaw(
                proto.buildCommand(71, proto.Cmd.getBatteryLevel, const [
                  0,
                ], band),
              ),
              isTrue,
            );
          } else {
            rx(historyStart());
            rx(record(band));
            rx(historyEnd());
            await until(() => writes.length == 2);
            expect(writes.last.sublist(3), [1, ..._token]);
            expect(await db.query('decoded_onehz'), hasLength(1));
            expect(await LocalDb.getCursor('strap_trim'), _tokenHex);
          }
        } finally {
          await engine.disconnect();
        }
      },
    );
  }
  for (final band in [proto.BandProfile.gen4, proto.BandProfile.gen5]) {
    test(
      'COV-48 ${band.type.name} replacement START replays the partial chunk once before ACK',
      () async {
        final logs = <String>[], commits = <List<int>>[], acks = <List<int>>[];
        final engine = BleEngine(
          onRecord: (_, _) async {},
          onState: (_) {},
          log: logs.add,
        );
        engine.debugInstallFakeLink(
          band: band,
          onCommit: (raws, samples, token, {archives, deviceFamily}) async {
            commits.add([for (final raw in raws) raw.counter]);
            await LocalDb.commitSyncBatch(
              raws,
              samples,
              trimToken: token,
              archives: archives,
              deviceFamily: deviceFamily,
            );
          },
          onWrite: (frame) async {
            final inner = proto.parseFrame(frame, profile: band)!.inner;
            if (inner[2] == proto.Cmd.historicalDataResult && inner[3] == 1) {
              expect(await db.query('decoded_onehz'), hasLength(2));
              expect(await LocalDb.getCursor('strap_trim'), _tokenHex);
              acks.add(List.of(inner));
            }
            return true;
          },
        );
        void rx(Uint8List inner) =>
            engine.debugReceiveFrame(proto.Frame(inner, true, true));
        final first = record(band);
        final second = record(band);
        ByteData.sublistView(second)
          ..setUint32(3, 42, Endian.little)
          ..setUint32(7, _ts + 1, Endian.little);
        try {
          rx(historyStart());
          rx(first);
          await until(() => engine.offloadSnapshot['buffered_records'] == 1);
          expect(commits, isEmpty);
          expect(acks, isEmpty);
          rx(historyStart());
          await until(
            () => logs.any(
              (l) => l.contains('HistoryStart received during active burst'),
            ),
          );
          expect(engine.offloadSnapshot['buffered_records'], 0);
          rx(first); // The new burst re-offers the earlier uncommitted bytes.
          rx(second);
          await until(() => engine.offloadSnapshot['buffered_records'] == 2);
          rx(historyEnd(count: 2));
          await until(() => acks.isNotEmpty, attempts: 1200);
          expect(commits, [
            [41, 42],
          ]);
          expect(acks, hasLength(1));
          expect(acks.single.sublist(3, 12), [1, ..._token]);
          final rows = await db.query('decoded_onehz', orderBy: 'counter');
          expect(rows.map((r) => r['counter']), [41, 42]);
          expect(rows.map((r) => r['rec_ts']), [_ts, _ts + 1]);
          expect(await LocalDb.getCursorInt('counter_hw'), 42);
          expect(await LocalDb.getCursorInt('rec_ts_hw'), _ts + 1);
        } finally {
          await engine.disconnect();
        }
      },
    );
  }
}
