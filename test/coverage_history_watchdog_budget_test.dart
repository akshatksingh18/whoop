// Actual history frames/watchdogs/retry policy and SQLite; radio only substituted.
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/ble/ble_engine.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/sync/sync_policy.dart';
import 'package:whoop_protocol/whoop_protocol.dart' as p;
import 'coverage_ble_durable_boundary_test.dart' show historyStart, record;
import 'support/coverage_store.dart';

Future<void> historyIO(WidgetTester t, bool Function() ready) async {
  for (var i = 0; i < 500 && !ready(); i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await t.pump(const Duration(milliseconds: 5));
  }
  expect(ready(), true, reason: 'Actual history operation must settle');
}

Future<T> driveHistory<T>(WidgetTester t, Future<T> work) async {
  var done = false;
  T? result;
  Object? error;
  work.then(
    (v) {
      result = v;
      done = true;
    },
    onError: (Object e) {
      error = e;
      done = true;
    },
  );
  await historyIO(t, () => done);
  if (error != null) throw error!;
  return result as T;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('history-watchdog-budget', fresh: true));
  setUp(() async {
    await resetCoverageStore();
    BleEngine.resetBandClaimForTest();
  });
  tearDownAll(LocalDb.close);
  for (final band in [p.BandProfile.gen4, p.BandProfile.gen5]) {
    for (final refuseFinalAbort in [false, true]) {
      testWidgets(
        '${band.type.name} four silent tasks exhaust the real three-retry budget; final refusal=$refuseFinalAbort',
        (t) async {
          var now = DateTime.now();
          final logs = <String>[], writes = <Uint8List>[];
          var aborts = 0;
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
                LocalDb.commitSyncBatch(
                  raw,
                  samples,
                  trimToken: token,
                  archives: archives,
                  deviceFamily: deviceFamily,
                ),
            onWrite: (frame) async {
              final inner = p.parseFrame(frame, profile: band)!.inner;
              writes.add(Uint8List.fromList(inner));
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
              if (inner[2] == p.Cmd.abortHistoricalTransmits) {
                aborts++;
                if (refuseFinalAbort && aborts == 4) return false;
              }
              return true;
            },
          );
          int count(int op) => writes.where((b) => b[2] == op).length;
          try {
            expect(
              await driveHistory(t, engine.debugStartHistoricalRefresh()),
              true,
            );
            for (var task = 0; task < 4; task++) {
              expect(engine.offloadActive, true);
              engine.debugReceiveFrame(p.Frame(historyStart(), true, true));
              engine.debugReceiveFrame(p.Frame(record(band), true, true));
              await historyIO(
                t,
                () => (engine.offloadSnapshot['buffered_records'] as int) > 0,
              );
              now = now.add(
                const Duration(seconds: kBackfillIdleTimeoutSeconds),
              );
              await t.pump(
                const Duration(seconds: kBackfillIdleTimeoutSeconds),
              );
              await historyIO(t, () => !engine.offloadActive);
              expect(
                count(p.Cmd.historicalDataResult),
                0,
                reason: 'An abandoned chunk must never trim the band',
              );
              expect(
                await t.runAsync(() => LocalDb.getCursor('strap_trim')),
                isNull,
              );
              if (task < 3) {
                now = now.add(
                  const Duration(seconds: kHistoricalAbortRetryDelaySeconds),
                );
                await t.pump(
                  const Duration(seconds: kHistoricalAbortRetryDelaySeconds),
                );
                await historyIO(
                  t,
                  () =>
                      count(p.Cmd.sendHistoricalData) == task + 2 &&
                      engine.offloadActive,
                );
              }
            }
            expect(count(p.Cmd.sendHistoricalData), 4);
            expect(aborts, 4);
            expect(
              logs.any((s) => s.contains('already retried 3 times')),
              true,
            );
            final sent = writes.length;
            now = now.add(const Duration(minutes: 2));
            await t.pump(const Duration(minutes: 2));
            await historyIO(t, () => !engine.offloadActive);
            expect(
              writes.length,
              sent,
              reason: 'Exhaustion must leave no hidden retry timer',
            );
            expect(engine.pendingCommandCount, 0);
            expect(
              await t.runAsync(
                () async => (await LocalDb.instance).query('decoded_onehz'),
              ),
              isEmpty,
            );
            expect(writes.any((b) => p.dangerousCmds.contains(b[2])), false);
          } finally {
            await driveHistory(t, engine.disconnect());
          }
        },
      );
    }
  }
}
