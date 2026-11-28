import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/strain_backfill.dart';
import 'package:whoop_companion/data/db.dart';

import '../support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('strain-backfill-preservation'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  test(
    'historical strain stays intact when a retained day cannot be read',
    () async {
      const withoutBundle = '2021-04-04';
      const malformed = '2021-04-05';
      const missingScalars = '2021-04-06';
      const recent = '2021-04-20';
      await DayResultStore.put(
        dayId: withoutBundle,
        algoVersion: 62,
        payloadJson: '{}',
        windowJson: '{}',
        series: const {'trimp': 110, 'strain': 8},
      );
      final db = await LocalDb.instance;
      expect(
        await db.delete(
          'day_result',
          where: 'day_id = ?',
          whereArgs: [withoutBundle],
        ),
        1,
      );
      final curve = [
        for (var minute = 0; minute < 50; minute++) {'t': minute * 60, 'v': 8},
      ];
      for (final day in [malformed, missingScalars, recent]) {
        await DayResultStore.put(
          dayId: day,
          algoVersion: 62,
          payloadJson: jsonEncode({
            if (day != missingScalars) 'scalars': {'strain': 8},
            'series': {'strain_curve': curve},
          }),
          windowJson: '{}',
          series: const {'trimp': 110, 'strain': 8},
        );
      }
      // An older restored database can carry text that never passed the current encoder.
      expect(
        await db.update(
          'day_result',
          {'payload_json': '{'},
          where: 'day_id = ?',
          whereArgs: [malformed],
        ),
        1,
      );
      final savedDays = await db.query('day_result', orderBy: 'day_id');
      final savedSeries = await db.query('metric_series', orderBy: 'key, date');
      expect(savedSeries, hasLength(8));

      final result = await backfillStrainScale(female: false);
      expect(result.skipped, 3);
      expect(result.seriesDays, 0);
      expect(result.bundleDays, 0);
      expect(result.didWork, isFalse);
      expect(await db.query('day_result', orderBy: 'day_id'), savedDays);
      expect(
        await db.query('metric_series', orderBy: 'key, date'),
        savedSeries,
      );
      final marker = await ComputeFreshnessStore.read(kStrainRescaleKey);
      expect(marker, isNotNull);

      final repeat = await backfillStrainScale(female: false);
      expect(repeat.skipped, 0);
      expect(repeat.didWork, isFalse);
      expect(await ComputeFreshnessStore.read(kStrainRescaleKey), marker);
      expect(await db.query('day_result', orderBy: 'day_id'), savedDays);
      expect(
        await db.query('metric_series', orderBy: 'key, date'),
        savedSeries,
      );
    },
  );
}
