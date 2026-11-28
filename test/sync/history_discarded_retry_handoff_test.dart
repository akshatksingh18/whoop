// Real idle watchdog,automatic retry,wire traffic and SQLite. Only the native
// transport and policy clock are controlled;no private latch is assigned.
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/ble/ble_engine.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/sync/sync_policy.dart';
import 'package:whoop_protocol/whoop_protocol.dart' as p;
import '../ble/durable_boundary_test.dart'
    show historyStart, historyEnd, record;
import 'history_watchdog_budget_test.dart' show driveHistory, historyIO;
import '../support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('history-discarded-retry-handoff', fresh: true));
  setUp(() async {
    await resetCoverageStore();
    BleEngine.resetBandClaimForTest();
  });
  tearDownAll(LocalDb.close);
  for (final band in [p.BandProfile.gen4, p.BandProfile.gen5]) {
    for (final lateRecord in [false, true]) {
      testWidgets(
        '${band.type.name} discarded burst survives real retry and pre-START lateRecord=$lateRecord',
        (t) async {
          var now = DateTime.now();
          final logs = <String>[], writes = <List<int>>[];
          late BleEngine engine;
          engine = BleEngine(
            onRecord: (_, _) async {},
            onState: (_) {},
            log: logs.add,
            policyNow: () => now,
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
          void rx(Uint8List b) =>
              engine.debugReceiveFrame(p.Frame(b, true, true));
          int count(int op) => writes.where((w) => w[2] == op).length;
          final original = record(band), later = record(band);
          final data = ByteData.sublistView(later);
          data.setUint32(3, 42, Endian.little);
          data.setUint32(
            7,
            data.getUint32(7, Endian.little) + 1,
            Endian.little,
          );
          try {
            expect(
              await driveHistory(t, engine.debugStartHistoricalRefresh()),
              true,
            );
            rx(historyStart());
            rx(original);
            await historyIO(
              t,
              () => engine.offloadSnapshot['buffered_records'] == 1,
            );
            now = now.add(const Duration(seconds: kBackfillIdleTimeoutSeconds));
            await t.pump(const Duration(seconds: kBackfillIdleTimeoutSeconds));
            await historyIO(t, () => !engine.offloadActive);
            expect(count(p.Cmd.abortHistoricalTransmits), 1);
            expect(
              await t.runAsync(() => CursorStore.read('strap_trim')),
              isNull,
            );
            now = now.add(
              const Duration(seconds: kHistoricalAbortRetryDelaySeconds),
            );
            await t.pump(
              const Duration(seconds: kHistoricalAbortRetryDelaySeconds),
            );
            await historyIO(
              t,
              () =>
                  count(p.Cmd.sendHistoricalData) == 2 && engine.offloadActive,
            );
            final mark = logs.length;
            if (lateRecord) rx(later);
            rx(historyEnd());
            await historyIO(
              t,
              () => logs
                  .skip(mark)
                  .any(
                    (s) => s.contains(
                      band.isGen5
                          ? 'before this task\'s first HISTORY_START'
                          : 'terminates a DISCARDED burst',
                    ),
                  ),
            );
            final db = await t.runAsync(() => LocalDb.instance);
            final before = (await t.runAsync(
              () => db!.query('decoded_onehz'),
            ))!;
            expect(before, hasLength(lateRecord && !band.isGen5 ? 1 : 0));
            expect(count(p.Cmd.historicalDataResult), 0);
            expect(
              await t.runAsync(() => CursorStore.read('strap_trim')),
              isNull,
            );
            expect(count(p.Cmd.abortHistoricalTransmits), 1);
            if (!band.isGen5) {
              expect(
                (await t.runAsync(
                  () => LocalDb.syncLedgerEntry('batch:8172635445362718'),
                ))!['status'],
                'trim_refused',
              );
            }
            // Actual fresh START lifts poison,then the band replays both rows.
            rx(historyStart());
            rx(original);
            rx(later);
            rx(historyEnd(count: 2));
            await historyIO(t, () => count(p.Cmd.historicalDataResult) == 1);
            final raw = (await t.runAsync(() => db!.query('decoded_onehz')))!;
            expect(raw, hasLength(2));
            expect(
              await t.runAsync(() => CursorStore.read('strap_trim')),
              '8172635445362718',
            );
            final ack = writes.singleWhere(
              (w) => w[2] == p.Cmd.historicalDataResult,
            );
            expect(ack.sublist(4), [
              0x81,
              0x72,
              0x63,
              0x54,
              0x45,
              0x36,
              0x27,
              0x18,
            ]);
            expect(writes.any((w) => p.dangerousCmds.contains(w[2])), false);
            expect(engine.offloadSnapshot['history_stuck'], false);
            expect(engine.pendingCommandCount, 0);
          } catch (error) {
            fail(
              '$error\nAuthored retry trace:\n${logs.join('\n')}\nSnapshot:${engine.offloadSnapshot}',
            );
          } finally {
            await driveHistory(t, engine.disconnect());
          }
        },
      );
    }
  }
}
