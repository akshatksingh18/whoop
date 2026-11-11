// Real coordinator, VM ports/worker lifecycle and SQLite. Fault entry points
// substitute a worker's reported error, uncaught VM error or premature exit.
// This does not simulate OOM or certify native process delivery.
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/derivation_engine.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/models.dart';

import 'support/coverage_store.dart';

void _reportedFailure(SendPort main) {
  final port = ReceivePort();
  main.send(port.sendPort);
  port.listen((message) {
    if (message is Map && message['type'] == 'finish') {
      main.send({
        'type': 'error',
        'error': 'authored reported prepare failure',
      });
      port.close();
    }
  });
}

void _crashedWorker(SendPort main) =>
    throw StateError('authored uncaught prepare failure');
void _exitedWorker(SendPort main) => Isolate.exit();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('prepare-worker-failure-recovery'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  const day = '2021-04-06';

  for (final mode in ['ordinary', 'rescan']) {
    for (final failure in ['reported', 'crashed', 'exited']) {
      test(
        '$mode $failure worker releases its lock, preserves banked data and permits real-worker retry',
        () async {
          final ts = localDayStartSec(day)! + 12 * 3600;
          await LocalDb.insertRecord(
            RawRecord(
              counter: 1,
              packetType: 47,
              hex: 'authored-worker-recovery',
              capturedAt: ts * 1000,
              recTs: ts,
            ),
            Sample(tsEpoch: ts, counter: 1, hr: 60, ax: 0, ay: 0, az: 1),
          );
          await LocalDb.putDayResult(
            dayId: day,
            algoVersion: kAlgoVersion,
            payloadJson:
                '{"scalars":{"rhr":55},"authored":"banked worker recovery"}',
            windowJson: '{"authored":"retain this window"}',
            rhr: 55,
            series: {'rhr': 55},
          );
          final db = await LocalDb.instance;
          final banked = await db.query('day_result');
          final raw = await db.query('decoded_onehz');
          final beats = await db.query('decoded_rr');
          final series = await db.query('metric_series');
          final signature = await LocalDb.getCursor('baseline_sig');
          final logs = <String>[];
          final engine = DerivationEngine(
            background: true,
            log: logs.add,
            prepareWorkerEntry: switch (failure) {
              'reported' => _reportedFailure,
              'crashed' => _crashedWorker,
              _ => _exitedWorker,
            },
          );
          Future<int> run(DerivationEngine owner) => mode == 'rescan'
              ? owner.rescanRecent(const Profile())
              : owner.run(const Profile(), force: true);
          expect(await run(engine), 0);
          final expected = switch (failure) {
            'reported' =>
              'prepare worker error: authored reported prepare failure',
            'crashed' => 'prepare worker crashed:',
            _ => 'prepare worker exited without a result',
          };
          expect(
            logs.any((s) => s.contains(expected)),
            true,
            reason: logs.join('\n'),
          );
          expect(engine.running, false);
          expect(await db.query('day_result'), banked);
          expect(await db.query('metric_series'), series);
          expect(await db.query('decoded_onehz'), raw);
          expect(await db.query('decoded_rr'), beats);
          expect(await LocalDb.getCursor('baseline_sig'), signature);
          final retry = DerivationEngine(background: true);
          expect(await run(retry), 1);
          expect(retry.running, false);
          expect(await db.query('decoded_onehz'), raw);
          expect(await db.query('decoded_rr'), beats);
          expect((await LocalDb.dayResult(day))!['rhr'], 55);
          expect(
            (await LocalDb.dayResult(day))!['window_json'],
            '{"authored":"retain this window"}',
          );
        },
      );
    }
  }
}
