// One-shot backfill of stored strain onto the recalibrated 0–21 scale.
//
// Raw 1 Hz substrate is pruned `rawRetentionDays` (3) behind the data edge, so
// history CANNOT be re-derived from raw — the engine logs "no substrate (raw
// pruned) — kept" and keeps the old row. It does not need raw: strain is a pure
// function of (TRIMP, wake minutes, sex), and `metric_series` already stores
// `trimp`, `worn_min` and `tst_min` for every derived day. This rebuilds the
// headline from those, so trends, v_daily/coach SQL and the day detail agree
// instead of showing a scale discontinuity at the fix date.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:openstrap_edge/compute/derivation_engine.dart' show kAlgoVersion;
import 'package:openstrap_edge/compute/strain_backfill.dart';
import 'package:openstrap_edge/data/db.dart';

/// Seed a derived day the way the engine would have before the rescale.
Future<void> seedDay(
  String day, {
  required double? trimp,
  required double? strain,
  required double wornMin,
  required double tstMin,
  bool finalized = true,
  int algoVersion = 62,
}) async {
  await LocalDb.putDayResult(
    dayId: day,
    algoVersion: algoVersion,
    payloadJson: jsonEncode({
      'date': day,
      'scalars': {
        'trimp': trimp,
        'strain': strain,
        'worn_min': wornMin,
        'tst_min': tstMin,
      },
      'series': {
        'hr_curve': [
          {'t': 1, 'v': 70},
        ],
        'strain_curve': [
          {'t': 1, 'v': strain},
        ],
      },
    }),
    windowJson: '{}',
    finalized: finalized,
    series: {
      'trimp': trimp,
      'strain': strain,
      'worn_min': wornMin,
      'tst_min': tstMin,
    },
  );
}

Future<double?> seriesValue(String key, String day) async {
  final rows = await LocalDb.metricSeries(key);
  for (final r in rows) {
    if (r['date'] == day) return (r['value'] as num?)?.toDouble();
  }
  return null;
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.dbName = 'openstrap_strain_backfill_test.db';
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  tearDownAll(() async {
    await LocalDb.close();
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  group('rescaledStrain — pure recompute from stored scalars', () {
    test('rebuilds the headline from TRIMP and the wake window', () {
      // Real bundle 2026-07-09: TRIMP 177.8, worn 827, TST 216 → wake 611.
      // Old scale put this at 12.79; the rescale reads ~9.0.
      final s = rescaledStrain(
        trimp: 177.80394321843846,
        wornMin: 827,
        tstMin: 216,
        female: false,
      );
      expect(s, isNotNull);
      expect(s!, closeTo(9.03, 0.05));
    });

    test('a short-wear inactive day rescales to zero', () {
      // Real bundle 2026-07-10: 23 steps, worn 486, TST 351 → wake 135.
      expect(
        rescaledStrain(trimp: 23.416868457643158, wornMin: 486, tstMin: 351,
            female: false),
        0.0,
      );
    });

    test('abstains rather than guessing when an input is missing', () {
      // No TRIMP → nothing to rescale from. Must leave the day alone, not zero it.
      expect(
        rescaledStrain(trimp: null, wornMin: 827, tstMin: 216, female: false),
        isNull,
      );
      expect(
        rescaledStrain(trimp: 177.8, wornMin: null, tstMin: 216, female: false),
        isNull,
      );
      // Wear entirely inside sleep leaves no wake window to price.
      expect(
        rescaledStrain(trimp: 177.8, wornMin: 200, tstMin: 240, female: false),
        isNull,
      );
    });

    test('sex changes the baseline, matching how the TRIMP was scored', () {
      final male = rescaledStrain(
          trimp: 300, wornMin: 900, tstMin: 0, female: false)!;
      final female = rescaledStrain(
          trimp: 300, wornMin: 900, tstMin: 0, female: true)!;
      // The female quiet-waking allowance is larger (0.86·e^0.334 vs
      // 0.64·e^0.384), so the same TRIMP nets less strain.
      expect(female, lessThan(male));
    });
  });

  group('backfillStrainScale — the stored history', () {
    test('rescales a raw-pruned historical day in series AND bundle', () async {
      await seedDay('2026-07-09',
          trimp: 177.80394321843846, strain: 12.790964777435558,
          wornMin: 827, tstMin: 216);
      // Data edge, well inside the retention window — must be left for the
      // engine to re-derive from raw rather than patched here.
      await seedDay('2026-07-20',
          trimp: 200, strain: 13.0, wornMin: 900, tstMin: 400,
          finalized: false);

      final r = await backfillStrainScale(female: false);
      expect(r.seriesDays, 1);
      expect(r.bundleDays, 1);

      // The trend series now carries the rescaled value.
      expect(await seriesValue('strain', '2026-07-09'), closeTo(9.03, 0.05));
      // …and so does the bundle the day-detail screen reads.
      final row = await LocalDb.dayResult('2026-07-09');
      expect((row!['algo_version'] as num).toInt(), kAlgoVersion);
      final scalars = (jsonDecode(row['payload_json'] as String)
          as Map)['scalars'] as Map;
      expect((scalars['strain'] as num).toDouble(), closeTo(9.03, 0.05));
      // TRIMP is the input, not the output — it must survive untouched.
      expect((scalars['trimp'] as num).toDouble(),
          closeTo(177.80394321843846, 1e-9));
    });

    test('leaves days inside the raw-retention window for a real re-derive',
        () async {
      // Patching these would write a row AT kAlgoVersion, and the derive gate
      // matches algo_version EXACTLY — the engine would then skip the day and
      // a partial patch would stand in for a full re-derivation.
      expect(await seriesValue('strain', '2026-07-20'), closeTo(13.0, 1e-9));
      final row = await LocalDb.dayResult('2026-07-20');
      expect((row!['algo_version'] as num).toInt(), 62);
    });

    test('drops the stale intraday curve rather than contradicting the headline',
        () async {
      // `series.strain_curve` is cumulative strain, one point per wake minute,
      // and its last point IS the old headline (12.79 for 2026-07-09). It was
      // built from per-sample HR that no longer exists, so it cannot be
      // rescaled — and a curve ending at 12.79 under a headline of 9.03 is
      // worse than no curve. The UI already renders a missing curve honestly.
      final row = await LocalDb.dayResult('2026-07-09');
      final payload = jsonDecode(row!['payload_json'] as String) as Map;
      final series = payload['series'] as Map?;
      expect(series?['strain_curve'], isNull);
      // Everything else in the block survives.
      expect(series?['hr_curve'], isNotNull);
    });

    test('is idempotent — a second run rewrites nothing', () async {
      final again = await backfillStrainScale(female: false);
      expect(again.seriesDays, 0);
      expect(again.bundleDays, 0);
      expect(await seriesValue('strain', '2026-07-09'), closeTo(9.03, 0.05));
    });

    test('a day with no stored TRIMP is skipped, not zeroed', () async {
      await LocalDb.putComputeFreshness(kStrainRescaleKey, '{}');
      await seedDay('2026-06-01',
          trimp: null, strain: 11.5, wornMin: 800, tstMin: 200);

      final r = await backfillStrainScale(female: false, force: true);
      expect(r.skipped, greaterThanOrEqualTo(1));
      // Left exactly as it was — an un-rescalable day must not become 0.
      expect(await seriesValue('strain', '2026-06-01'), closeTo(11.5, 1e-9));
    });
  });
}
