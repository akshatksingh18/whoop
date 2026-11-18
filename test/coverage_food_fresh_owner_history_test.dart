// Reopening the actual Food root preserves its saved diary and actions.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/data/nutrition_store.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/state/units_controller.dart';
import 'package:whoop_companion/ui2/screens/nutrition_screen.dart';
import 'coverage_nutrition_root_test.dart' show io;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('food-fresh-owner', fresh: true);
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  for (final scale in [1.0, 3.1]) {
    testWidgets(
      'fresh Food owners retain saved food and navigation at ${scale}x',
      (t) async {
        final app = AppState.forTesting()
          ..user = {
            'age': 30,
            'sex': 'f',
            'height_cm': 170.0,
            'weight_kg': 70.0,
            'kcal_target': 2000,
          };
        app.repo = LocalRepositoryImpl(getProfileMap: () => app.user);
        final units = UnitsController.withUnits();
        addTearDown(app.dispose);
        addTearDown(units.dispose);
        final day = todayLabel();
        final db = (await t.runAsync(() => LocalDb.instance))!;
        await t.runAsync(
          () => NutritionDb.put(
            db,
            FoodEntry(
              id: 'authored-retained',
              date: day,
              meal: 'dinner',
              label: 'Authored retained meal',
              kcal: 345,
              atTs: localDayStartSec(day)! + 17 * 3600,
            ),
          ),
        );
        final rows = (await t.runAsync(() => db.query('food_entry')))!;
        final before = NutritionScreen.debugLoads;
        for (var owner = 0; owner < 2; owner++) {
          await localizedPage(
            t,
            Scaffold(
              body: NutritionScreen(key: ValueKey('food-$scale-$owner')),
            ),
            app: app,
            units: units,
            scale: scale,
            settle: false,
          );
          await io(t);
          expect(NutritionScreen.debugLoads, greaterThan(before + owner));
          final page = await readPage(t);
          expect(
            page.any((text) => text.startsWith('Add to ')),
            true,
            reason:
                'The existing meal-specific logging action remains reachable',
          );
          expect(page.join(' '), contains('Authored retained meal'));
          expect((await t.runAsync(() => db.query('food_entry')))!, rows);
          expect(app.isPaired, false);
          await t.pumpWidget(const SizedBox());
          await t.pumpAndSettle();
        }
      },
    );
  }
}
