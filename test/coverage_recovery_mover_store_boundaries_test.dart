// Authored day-level observations exercise the real measured-only reader.
// Associations keep both sample counts; no calorie/recovery method is changed.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/derivation_engine.dart'
    show kAlgoVersion;
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/nutrition_store.dart';
import 'package:whoop_companion/data/recovery_movers.dart';
import 'coverage_localized_progress_test.dart' show ago;
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('recovery-mover-store-boundaries'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  Future<void> imported(String day) => LocalDb.putDayResult(
    dayId: day,
    algoVersion: kAlgoVersion,
    payloadJson: jsonEncode({'source': 'whoop_export', 'imported': true}),
    windowJson: '{}',
    finalized: true,
  );
  test(
    'unknown mover outcome refuses rather than inventing a direction',
    () async {
      expect(await loadRecoveryMovers('not-an-outcome'), isEmpty);
    },
  );
  test(
    'nine measured mornings plus an imported one cannot reach the ten-morning floor',
    () async {
      for (var i = 1; i <= 10; i++) {
        await LocalDb.putMetricSeriesValue(ago(i), 'rhr', 50 + i.toDouble());
      }
      await imported(ago(10));
      expect(await LocalDb.metricSeries('rhr'), hasLength(10));
      expect(
        await LocalDb.metricSeries('rhr', measuredOnly: true),
        hasLength(9),
      );
      expect(await loadRecoveryMovers('rhr'), isEmpty);
    },
  );
  test(
    'mover counts exclude imported outcomes and metric exposures while retaining unknown mornings',
    () async {
      for (var i = 0; i < 11; i++) {
        final morning = ago(2 * i + 1), prior = ago(2 * i + 2);
        final high = i < 6;
        await LocalDb.putMetricSeriesValue(morning, 'rhr', high ? 60 : 50);
        await LocalDb.putMetricSeriesValue(prior, 'steps', high ? 12000 : 6000);
        await LocalDb.putMetricSeriesValue(prior, 'strain', high ? 15 : 7);
        await LocalDb.putMetricSeriesValue(prior, 'worn_min', 960);
      }
      // The first morning has an imported previous day's exposure: unknown,
      // neither "with" nor "without". Its measured RHR remains in the store.
      await imported(ago(2));
      await LocalDb.putMetricSeriesValue(ago(25), 'rhr', 100);
      await LocalDb.putMetricSeriesValue(ago(26), 'steps', 12000);
      await imported(ago(25));
      await LocalDb.putMetricSeriesValue(ago(150), 'rhr', 100);
      await LocalDb.putMetricSeriesValue(ago(151), 'steps', 12000);
      final rows = await loadRecoveryMovers('rhr');
      for (final tag in ['10,000+ steps', 'Strain 14 or more']) {
        final row = rows.singleWhere((r) => r['tag'] == tag);
        expect(row['n_with'], 5);
        expect(row['n_without'], 5);
        expect(row['delta'], 10);
        expect(row['unit'], 'bpm');
        expect(row['helped'], false);
      }
      expect(
        (await LocalDb.metricSeries('rhr')).length,
        13,
        reason: 'Filtering a comparison must not delete historical evidence',
      );
    },
  );
  test(
    'unmarked food proves over or hit but cannot manufacture the opposite comparison group',
    () async {
      final db = await LocalDb.instance;
      for (var i = 0; i < 10; i++) {
        final morning = ago(2 * i + 1), prior = ago(2 * i + 2);
        final high = i < 5;
        await LocalDb.putMetricSeriesValue(morning, 'rhr', high ? 60 : 50);
        await NutritionDb.put(
          db,
          FoodEntry(
            id: 'authored-$i',
            date: prior,
            meal: 'dinner',
            label: 'Authored meal',
            kcal: high ? 2300 : 1000,
            proteinG: high ? 120 : 50,
            atTs:
                DateTime.parse(prior)
                    .add(Duration(hours: high ? 22 : 21, minutes: 15))
                    .millisecondsSinceEpoch ~/
                1000,
          ),
        );
      }
      final rows = await loadRecoveryMovers(
        'rhr',
        profile: {'kcal_target': 2000, 'protein_target': 100},
      );
      final tags = rows.map((r) => r['tag']).toSet();
      expect(tags, isNot(contains('Ate over your calorie goal')));
      expect(tags, isNot(contains('Hit your protein goal')));
      final late = rows.singleWhere((r) => r['tag'] == 'Ate after 22:00');
      expect(late['n_with'], 5);
      expect(late['n_without'], 5);
      expect(late['delta'], 10);
      expect(await NutritionDb.dayMarks(db, ago(30)), isEmpty);
      expect(await db.query('food_entry'), hasLength(10));
    },
  );
}
