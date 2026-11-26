// Housekeeping a full derive runs after its last day: superseded generations
// of the recomputable per-day intermediates are pruned and the count logged.
// Also the one guard that keeps an optional day feature's failure from
// costing the day. Real engine and SQLite; the one record is a synthetic second.
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/derivation_engine.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/models.dart';

import '../support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('derive-housekeeping'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  test('a derive prunes superseded intermediates and says how many', () async {
    final db = await LocalDb.instance;
    // Three generations of an unrelated day in both tables: the oldest goes.
    for (final table in const [
      'sleep_session_candidates',
      'wake_day_features',
    ]) {
      for (final v in const [1, 2, 3]) {
        await db.insert(table, {
          'day_id': '2020-01-01',
          'algo_version': v,
          'payload_json': '{}',
          'computed_at': 0,
        });
      }
    }
    final ts = localDayStartSec('2021-04-06')! + 12 * 3600;
    await LocalDb.insertRecord(
      RawRecord(
        counter: 1,
        packetType: 47,
        hex: 'authored-housekeeping',
        capturedAt: ts * 1000,
        recTs: ts,
      ),
      Sample(tsEpoch: ts, counter: 1, hr: 60, ax: 0, ay: 0, az: 1),
    );
    final logs = <String>[];
    await DerivationEngine(log: logs.add).run(const Profile(), force: true);
    expect(
      logs,
      contains('[derive] pruned 2 superseded intermediate rows'),
      reason: logs.join('\n'),
    );
    final left = await db.rawQuery(
      "SELECT algo_version FROM wake_day_features WHERE day_id = '2020-01-01' "
      'ORDER BY algo_version',
    );
    expect(left.map((r) => r['algo_version']), [2, 3]);
  });

  test('opening a store drops the retired rollup-input row', () async {
    await LocalDb.putBaseline('crossday_input', '{"days":[]}');
    await LocalDb.putBaseline('crossday_status', '{"kind":"ready"}');
    await LocalDb.close();
    expect(await LocalDb.baseline('crossday_input'), isNull);
    expect(
      (await LocalDb.baseline('crossday_status'))!['payload_json'],
      '{"kind":"ready"}',
    );
  });

  test('a failing optional feature answers its fallback and is named', () {
    final printed = <String>[];
    final original = debugPrint;
    debugPrint = (message, {wrapWidth}) => printed.add(message ?? '');
    try {
      expect(DerivationEngine.bestEffort('naps', () => 1, () => 0), 1);
      expect(
        DerivationEngine.bestEffort<int>(
          'naps',
          () => throw StateError('authored feature failure'),
          () => 0,
        ),
        0,
      );
    } finally {
      debugPrint = original;
    }
    expect(printed, [
      '[derive] naps FAILED/skipped: Bad state: authored feature failure',
    ]);
  });
}
