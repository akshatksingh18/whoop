// Existing Food history navigation re-reads the viewed day after a correction.
// No meal selection rules, cutoffs or calorie methods are changed.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/data/nutrition_store.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/screens/food_diary.dart';
import 'package:whoop_companion/ui2/screens/nutrition_screen.dart';
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';
import 'coverage_nutrition_root_test.dart' show io;

void main() {
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('food-day-return');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  for (final historical in [false, true]) {
    testWidgets(
      'Food card opens and refreshes its exact date historical=$historical',
      (t) async {
        final day = historical ? '2021-04-06' : todayLabel();
        final eatenAt = localDayStartSec(day)! + 60;
        final app = AppState.forTesting()
          ..user = {
            'age': 30,
            'weight_kg': 70,
            'height_cm': 170,
            'sex': 'f',
            'kcal_target': 2000,
          };
        app.repo = LocalRepositoryImpl(getProfileMap: () => app.user);
        addTearDown(app.dispose);
        final db = await t.runAsync(() => LocalDb.instance);
        Future<void> put(double kcal) => NutritionDb.put(
          db!,
          FoodEntry(
            id: 'authored-viewed-day',
            date: day,
            meal: 'breakfast',
            label: 'Authored breakfast',
            kcal: kcal,
            atTs: eatenAt,
          ),
        );
        await t.runAsync(() => put(100));
        var returned = 0;
        await localizedPage(
          t,
          Scaffold(
            body: SingleChildScrollView(
              child: NutritionDayView(date: day, onChanged: () => returned++),
            ),
          ),
          app: app,
          settle: false,
        );
        await io(t);
        final card = find.byType(CalorieCard);
        expect(t.widget<CalorieCard>(card).eaten, 100);
        final dynamic action = t.widget<CalorieCard>(card).onTap;
        final pending = action() as Future<void>;
        var navigationFinished = false;
        pending.then((_) => navigationFinished = true);
        await io(t);
        expect(t.widget<DayFoodPage>(find.byType(DayFoodPage)).date, day);
        expect(returned, 0);
        await t.runAsync(() => put(200));
        Navigator.of(t.element(find.byType(DayFoodPage))).pop();
        await io(t);
        expect(navigationFinished, true);
        expect(find.byType(DayFoodPage), findsNothing);
        expect(returned, 1);
        expect(t.widget<CalorieCard>(card).eaten, 200);
        final entries = (await t.runAsync(
          () => NutritionDb.entriesForDay(db!, day),
        ))!;
        expect(entries, hasLength(1));
        expect(entries.single.meal, 'breakfast');
        expect(entries.single.atTs, eatenAt);
        if (historical) {
          expect(
            await t.runAsync(
              () => NutritionDb.entriesForDay(db!, todayLabel()),
            ),
            isEmpty,
          );
        }
      },
    );
  }
}
