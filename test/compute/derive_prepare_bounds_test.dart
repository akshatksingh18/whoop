// The two bounds on one day's substrate prepare: a worker that never answers
// hits the per-day timeout, and a day past the row budget is refused before
// its pages reach the worker. Real coordinator, VM ports and SQLite; the rows
// are synthetic seconds, not a recording.
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/derivation_engine.dart';
import 'package:whoop_companion/compute/derive_prepare.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/models.dart';

import '../support/coverage_store.dart';

/// Takes every message and answers none of them.
void _silentWorker(SendPort main) {
  final port = ReceivePort();
  main.send(port.sendPort);
  port.listen((_) {});
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('derive-prepare-bounds'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  const day = '2021-04-06';

  test(
    'a prepare worker that never answers times out and releases the engine',
    () async {
      final ts = localDayStartSec(day)! + 12 * 3600;
      await LocalDb.insertRecord(
        RawRecord(
          counter: 1,
          packetType: 47,
          hex: 'authored-silent-worker',
          capturedAt: ts * 1000,
          recTs: ts,
        ),
        Sample(tsEpoch: ts, counter: 1, hr: 60, ax: 0, ay: 0, az: 1),
      );
      final logs = <String>[];
      final engine = DerivationEngine(
        log: logs.add,
        prepareWorkerEntry: _silentWorker,
      );
      expect(await engine.run(const Profile(), force: true), 0);
      expect(
        logs.any((l) => l.contains('substrate prepare for $day timed out')),
        true,
        reason: logs.join('\n'),
      );
      expect(engine.running, false);
      // A retryable skip marker, never a finalized day.
      final row = (await LocalDb.dayResult(day))!;
      expect(row['payload_json'], '{"skipped":true,"reason":"timeout"}');
      expect(row['finalized'], 0);
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );

  test(
    'a page the worker cannot read is reported and the worker exits',
    () async {
      final inbox = ReceivePort();
      final exited = ReceivePort();
      await Isolate.spawn(
        derivationPrepareWorker,
        inbox.sendPort,
        onExit: exited.sendPort,
      );
      final replies = inbox.asBroadcastStream();
      final worker = await replies.first as SendPort;
      worker.send({'type': 'page', 'frames': 'authored-not-a-list'});
      final reply = await replies.first as Map;
      expect(reply['type'], 'error');
      expect(reply['error'], contains("is not a subtype of type 'List"));
      // Closing its only port lets the isolate finish.
      await exited.first.timeout(const Duration(seconds: 30));
      inbox.close();
      exited.close();
    },
  );

  test(
    'a day past the row budget is refused, not prepared',
    () async {
      final start = localDayStartSec(day)!;
      final db = await LocalDb.instance;
      // Six band ids sharing the day's seconds: 500,001 rows, one past the
      // budget, inside one local day.
      await db.execute(
        'WITH RECURSIVE n(i) AS (SELECT 0 UNION ALL SELECT i + 1 FROM n '
        'WHERE i < 500000) '
        'INSERT INTO decoded_onehz (device_id, ts_ms, rec_ts, counter, hr, '
        'ax, ay, az) SELECT \'authored-\' || (i % 6), (? + i / 6) * 1000, '
        '? + i / 6, i, 60, 0, 0, 1 FROM n',
        [start, start],
      );
      final logs = <String>[];
      final engine = DerivationEngine(log: logs.add);
      expect(await engine.run(const Profile(), force: true), 0);
      expect(
        logs.any((l) => l.contains('day_prepare_budget_exceeded day=$day')),
        true,
        reason: logs.join('\n'),
      );
      expect(engine.running, false);
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
