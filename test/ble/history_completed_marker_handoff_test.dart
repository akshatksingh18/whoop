// Real packets after a complete durable drain;no private-state/latch mutation.
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/ble/ble_engine.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_protocol/whoop_protocol.dart' as p;
import 'durable_boundary_test.dart'
    show historyStart, historyEnd, historyComplete, record, until;
import '../support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(
    () => coverageStore('history-completed-marker-handoff', fresh: true),
  );
  setUp(() async {
    await resetCoverageStore();
    BleEngine.resetBandClaimForTest();
  });
  tearDownAll(LocalDb.close);
  for (final (band, announced) in [
    (p.BandProfile.gen4, 0),
    (p.BandProfile.gen4, 1),
    (p.BandProfile.gen5, 0),
    (p.BandProfile.gen5, 1),
  ]) {
    for (final completeFirst in [false, true]) {
      test(
        '${band.type.name} completed drain preserves cursor across late markers completeFirst=$completeFirst count=$announced',
        () async {
          final logs = <String>[], writes = <List<int>>[];
          late BleEngine engine;
          engine = BleEngine(
            onRecord: (_, _) async {},
            onState: (_) {},
            log: logs.add,
          );
          engine.debugInstallFakeLink(
            band: band,
            onCommit: (raw, samples, token, {archives, deviceFamily}) =>
                SyncLedgerStore.commitBatch(
                  raw,
                  samples,
                  trimToken: token,
                  archives: archives,
                  deviceFamily: deviceFamily,
                ),
            onWrite: (frame) async {
              final inner = p.parseFrame(frame, profile: band)!.inner;
              writes.add(List.of(inner));
              if (inner[2] == p.Cmd.getClock) {
                scheduleMicrotask(
                  () => engine.debugAbsorbDecoded(
                    p.Decoded('cmd_response', {
                      'opcode': p.Cmd.getClock,
                      'req_seq': inner[1],
                      'cmd_status': 1,
                      'clock_epoch':
                          DateTime.now().millisecondsSinceEpoch ~/ 1000,
                    }),
                  ),
                );
              }
              return true;
            },
          );
          void rx(Uint8List inner) =>
              engine.debugReceiveFrame(p.Frame(inner, true, true));
          try {
            // Authored observations at the actual live edge. Current policy
            // still follows a productive round with another request.
            final stamp = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 1;
            final sample = record(band);
            ByteData.sublistView(sample).setUint32(7, stamp, Endian.little);
            final end = historyEnd();
            ByteData.sublistView(end).setUint32(3, stamp, Endian.little);
            rx(historyStart());
            rx(sample);
            rx(end);
            await until(
              () => writes.any((w) => w[2] == p.Cmd.historicalDataResult),
            );
            rx(historyComplete());
            await until(
              () => writes.any((w) => w[2] == p.Cmd.sendHistoricalData),
            );
            // Follow the real continuation rather than forcing the engine
            // inactive: the next declared burst is genuinely empty.
            rx(historyStart());
            rx(historyComplete());
            await until(
              () =>
                  !engine.offloadActive &&
                  logs.any(
                    (s) => s.contains('HistoryComplete — backlog drained'),
                  ),
            );
            final db = await LocalDb.instance;
            final legacySamples = await db.query('samples', orderBy: 'rowid');
            final decoded = await db.query('decoded_onehz', orderBy: 'ts_ms');
            final archived = await db.query('raw_archive', orderBy: 'rowid');
            final cursor = await CursorStore.read('strap_trim');
            expect(cursor, '8172635445362718');
            expect(decoded, hasLength(1));
            final acknowledgements = writes
                .where((w) => w[2] == p.Cmd.historicalDataResult)
                .length;
            expect(acknowledgements, 1);
            final late = Uint8List.fromList(end)..[20] ^= 1;
            ByteData.sublistView(late).setUint32(9, announced, Endian.little);
            final priorAckLedger = await LocalDb.syncLedgerEntry(
              'batch:8172635445362718',
            );
            final markers = completeFirst
                ? [historyComplete(), late]
                : [late, historyComplete()];
            for (final marker in markers) {
              final old = logs.length;
              rx(marker);
              await until(
                () => logs.skip(old).any((s) => s.contains('[SYNC] META')),
              );
              // A durable SQLite read also waits for any commit queued ahead of
              // it,then the short queue settle lets diagnostic writes finish.
              await db.query('sync_ledger');
              await Future<void>.delayed(const Duration(milliseconds: 30));
            }
            expect(await CursorStore.read('strap_trim'), cursor);
            expect(await db.query('samples', orderBy: 'rowid'), legacySamples);
            expect(await db.query('decoded_onehz', orderBy: 'ts_ms'), decoded);
            expect(await db.query('raw_archive', orderBy: 'rowid'), archived);
            expect(
              writes.where((w) => w[2] == p.Cmd.historicalDataResult),
              hasLength(acknowledgements),
            );
            expect(writes.any((w) => p.dangerousCmds.contains(w[2])), false);
            expect(engine.offloadActive, false);
            expect(engine.pendingCommandCount, 0);
            expect(
              await LocalDb.syncLedgerEntry('batch:8172635445362719'),
              isNull,
            );
            expect(
              await LocalDb.syncLedgerEntry('batch:8172635445362718'),
              priorAckLedger,
            );
          } catch (error) {
            fail(
              '$error\nAuthored engine trace:\n${logs.join('\n')}\nWrites:$writes\nSnapshot:${engine.offloadSnapshot}',
            );
          } finally {
            await engine.disconnect();
          }
        },
      );
    }
  }
}
