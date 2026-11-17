// Real coordinator entry points and SQLite transactions; authored history only.
// Storage optimization must not suppress an empty/successful derive or lose retry input.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/derivation_engine.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/compute/strain_backfill.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/series_codec.dart';

import 'day_result_reencode_test.dart' show seedLegacy, bundleFor;
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const day = '2021-04-06';
  final noon = localDayStartSec(day)! + 12 * 3600;
  setUpAll(() => coverageStore('coordinator-housekeeping'));
  setUp(resetCoverageStore);
  tearDown(() async {
    await (await LocalDb.instance).execute(
      'DROP TRIGGER IF EXISTS authored_housekeeping_refusal',
    );
  });
  tearDownAll(LocalDb.close);

  Future<int> enter(DerivationEngine engine, String mode) => switch (mode) {
    'rescan' => engine.rescanRecent(const Profile()),
    _ => engine.run(const Profile()),
  };

  for (final mode in ['ordinary', 'rescan']) {
    for (final refuse in [false, true]) {
      test(
        '$mode no-raw exit retains and losslessly converts old history; refusal=$refuse',
        () async {
          final db = await LocalDb.instance;
          await seedLegacy(db, day, noon);
          final before = (await db.query('day_result')).single;
          final logs = <String>[];
          final engine = DerivationEngine(background: true, log: logs.add);
          if (refuse) {
            await db.execute(
              "CREATE TRIGGER authored_housekeeping_refusal BEFORE UPDATE OF payload_json ON day_result "
              "BEGIN SELECT RAISE(ABORT,'authored housekeeping refusal'); END",
            );
          }

          expect(await enter(engine, mode), 0);
          expect(engine.running, false);
          if (refuse) {
            expect(
              logs.any(
                (s) =>
                    s.contains('storage housekeeping skipped:') &&
                    s.contains('authored housekeeping refusal'),
              ),
              true,
            );
            expect((await db.query('day_result')).single, before);
            expect(
              await LocalDb.computeFreshness(LocalDb.kReencodeCursorKey),
              isNull,
            );
            await db.execute('DROP TRIGGER authored_housekeeping_refusal');
            expect(await enter(engine, mode), 0);
          }
          final after = (await db.query('day_result')).single;
          expect(
            SeriesCodec.decodePayloadJson(after['payload_json']),
            bundleFor(noon),
          );
          expect(
            SeriesCodec.needsReencode(after['payload_json'] as String),
            false,
          );
          expect(
            {...after}..remove('payload_json'),
            {...before}..remove('payload_json'),
          );
          expect(
            logs.where((s) => s.contains('re-encoded 1 legacy day bundles')),
            hasLength(1),
          );
          final banked = await db.query('day_result');
          expect(await enter(engine, mode), 0);
          expect(await db.query('day_result'), banked);
          expect(engine.running, false);
        },
      );
    }
  }

  test(
    'an unreadable rescan baseline preserves the old signature and retries on the same engine',
    () async {
      await LocalDb.setCursor('baseline_sig', 'authored-pending-signature');
      final db = await LocalDb.instance;
      final cursor = await db.query('sync_cursor');
      final baseline = await db.query('baselines');
      final logs = <String>[];
      final engine = DerivationEngine(background: true, log: logs.add);
      await db.execute(
        'ALTER TABLE baselines RENAME TO authored_held_baselines',
      );
      try {
        expect(await engine.rescanRecent(const Profile()), 0);
        expect(
          logs.any(
            (s) => s.contains('rescan ERROR:') && s.contains('baselines'),
          ),
          true,
        );
        expect(await db.query('authored_held_baselines'), baseline);
        expect(await db.query('sync_cursor'), cursor);
        expect(engine.running, false);
      } finally {
        await db.execute(
          'ALTER TABLE authored_held_baselines RENAME TO baselines',
        );
      }
      expect(await engine.rescanRecent(const Profile()), 0);
      expect(
        logs.lastWhere((s) => s.contains('rescan:')),
        '[derive] rescan: no decoded data',
      );
      expect(await db.query('sync_cursor'), cursor);
      expect(engine.running, false);
    },
  );

  test(
    'ordinary no-raw exit applies the existing one-shot historical strain repair only once',
    () async {
      final db = await LocalDb.instance;
      const older = '2021-03-01', edge = '2021-04-06';
      final original = {
        'scalars': {'strain': 12.0, 'rhr': 55.0},
        'series': {
          'strain_curve': [
            for (var i = 0; i < 30; i++)
              {'t': localDayStartSec(older)! + 12 * 3600 + i * 60, 'v': 12.0},
          ],
        },
      };
      await db.insert('day_result', {
        'day_id': older,
        'algo_version': 47,
        'payload_json': jsonEncode(original),
        'window_json': '{"authored":"retain"}',
        'computed_at': 1,
        'finalized': 1,
        'skipped': 0,
        'partial': 0,
        'rhr': 55.0,
      });
      await LocalDb.putMetricSeriesValue(older, 'strain', 12);
      await LocalDb.putMetricSeriesValue(older, 'trimp', 80);
      await LocalDb.putMetricSeriesValue(edge, 'strain', 5);
      final expected = rescaledStrain(
        trimp: 80,
        wakeMinutes: 30,
        female: true,
      )!;
      final logs = <String>[];
      final engine = DerivationEngine(background: true, log: logs.add);
      expect(await engine.run(const Profile(sex: 'f')), 0);
      expect(
        logs.any((s) => s.contains('strain rescale: 1 day(s) rebuilt')),
        true,
      );
      final banked = (await LocalDb.dayResult(older))!;
      final payload = SeriesCodec.decodePayloadJson(banked['payload_json'])!;
      expect((payload['scalars'] as Map)['strain'], expected);
      expect((payload['scalars'] as Map)['rhr'], 55);
      expect((payload['series'] as Map).containsKey('strain_curve'), false);
      expect(banked['window_json'], '{"authored":"retain"}');
      expect(banked['finalized'], 1);
      expect(
        (await LocalDb.metricSeries(
          'strain',
        )).singleWhere((r) => r['date'] == older)['value'],
        expected,
      );
      final rows = await db.query('day_result');
      final series = await db.query('metric_series');
      expect(await engine.run(const Profile(sex: 'f')), 0);
      expect(await db.query('day_result'), rows);
      expect(await db.query('metric_series'), series);
      expect(
        logs.where((s) => s.contains('strain rescale: 1 day(s) rebuilt')),
        hasLength(1),
      );
    },
  );
}
