// Actual persisted food/morning reader: completeness cannot invent nutrients.
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/nutrition_store.dart';
import 'package:whoop_companion/data/recovery_movers.dart';
import 'coverage_localized_progress_test.dart' show ago;
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('complete-food-mover-groups', fresh: true));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  for (final outcome in ['rhr', 'readiness']) {
    for (final state in ['complete', 'unknown-energy', 'incomplete']) {
      test(
        '$outcome food comparison keeps $state evidence and sample floors',
        () async {
          final db = await LocalDb.instance;
          for (var i = 0; i < 10; i++) {
            final morning = ago(2 * i + 1), prior = ago(2 * i + 2);
            final over = i < 5;
            await LocalDb.putMetricSeriesValue(
              morning,
              outcome,
              over ? 60 : 50,
            );
            await NutritionDb.put(
              db,
              FoodEntry(
                id: 'authored-group-$i',
                date: prior,
                meal: 'dinner',
                label: 'Authored complete-day intake',
                kcal: !over && i == 9 && state == 'unknown-energy'
                    ? null
                    : over
                    ? 2300
                    : 1000,
                proteinG: over ? 120 : 50,
              ),
            );
            await NutritionDb.setDayMark(
              db,
              prior,
              state == 'incomplete' && !over && i == 9
                  ? 'incomplete'
                  : 'complete',
            );
          }
          final foods = await db.query('food_entry');
          final marks = await db.query('food_day_mark');
          final metrics = await db.query('metric_series');
          final rows = await loadRecoveryMovers(
            outcome,
            profile: {'kcal_target': 2000, 'protein_target': 100},
          );
          final energy = rows.where(
            (r) => r['tag'] == 'Ate over your calorie goal',
          );
          if (state == 'complete') {
            expect(energy, hasLength(1));
            expect(energy.single['n_with'], 5);
            expect(energy.single['n_without'], 5);
            expect(energy.single['delta'], 10);
            expect(energy.single['helped'], outcome == 'readiness');
          } else {
            expect(
              energy,
              isEmpty,
              reason:
                  'Only four known not-over mornings cannot meet the five-morning floor',
            );
          }
          final protein = rows.where(
            (r) => r['tag'] == 'Hit your protein goal',
          );
          expect(
            protein.length,
            state == 'incomplete' ? 0 : 1,
            reason: 'Unknown energy must not erase independently known protein',
          );
          if (protein.isNotEmpty) {
            expect(protein.single['n_with'], 5);
            expect(protein.single['n_without'], 5);
            expect(protein.single['delta'], 10);
          }
          expect(await db.query('food_entry'), foods);
          expect(await db.query('food_day_mark'), marks);
          expect(await db.query('metric_series'), metrics);
        },
      );
    }
  }
}
