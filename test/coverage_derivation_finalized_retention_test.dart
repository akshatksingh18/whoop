// Ordinary scheduler modes over finalized authored days; no staging workers.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/derivation_engine.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('finalized-retention'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  for (final heavy in [false, true]) {
    test(
      'COV-48 finalized history skips workers and applies existing input retention in heavy=$heavy',
      () async {
        const days = ['2021-04-01', '2021-04-05', '2021-04-06'];
        final db = await LocalDb.instance;
        for (var i = 0; i < days.length; i++) {
          final ts = localDayStartSec(days[i])! + 12 * 3600;
          await LocalDb.putDayResult(
            dayId: days[i],
            algoVersion: kAlgoVersion,
            payloadJson: jsonEncode({
              'date': days[i],
              'scalars': {'rhr': 56 + i},
            }),
            windowJson: '{}',
            finalized: true,
            rhr: 56.0 + i,
            series: {'rhr': 56.0 + i},
          );
          await db.insert('decoded_onehz', {
            'device_id': '',
            'ts_ms': ts * 1000,
            'rec_ts': ts,
            'counter': i + 1,
            'hr': 56 + i,
            'device_family': 'gen4',
          });
        }
        final saved = await db.query('day_result', orderBy: 'day_id');
        final scalars = await db.query('metric_series', orderBy: 'date');
        final raw = await db.query('decoded_onehz', orderBy: 'rec_ts');
        final logs = <String>[];
        final completed = <String>[];
        final engine = DerivationEngine(background: true, log: logs.add);
        expect(
          await engine.run(
            const Profile(),
            heavy: heavy,
            onDayDone: (day, _, _) => completed.add(day),
          ),
          0,
        );
        expect(completed, isEmpty);
        expect(engine.running, false);
        expect(engine.snapshot()['scope_reason'], 'latest-finalized-check');
        expect(engine.snapshot()['scope_days'], 1);
        expect(engine.snapshot()['todo_days'], 0);
        expect(engine.snapshot()['raw_rows'], 0);
        expect(
          logs.any(
            (l) => l.endsWith('derive: all days finalized — nothing to do'),
          ),
          true,
        );
        expect(await db.query('day_result', orderBy: 'day_id'), saved);
        expect(await db.query('metric_series', orderBy: 'date'), scalars);
        expect(
          await db.query('decoded_onehz', orderBy: 'rec_ts'),
          raw.skip(1).toList(),
        );
        expect(await engine.run(const Profile(), heavy: heavy), 0);
        expect(await db.query('day_result', orderBy: 'day_id'), saved);
        expect(
          await db.query('decoded_onehz', orderBy: 'rec_ts'),
          raw.skip(1).toList(),
        );
      },
    );
  }
}
