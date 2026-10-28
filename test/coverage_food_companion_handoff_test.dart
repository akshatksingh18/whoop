// Whole-plate logging keeps uncertainty and an atomic historical meal write.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/nutrition_store.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/screens/food_diary.dart';
import 'package:whoop_companion/ui2/screens/food_picker.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('food-companion-handoff');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  Future<void> flush(WidgetTester t) async {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  }

  Future<Map<String, Object?>> seed() async {
    final db = await LocalDb.instance;
    final main = myFoodDef(
      key: 'synthetic-main',
      label: 'Synthetic main',
      refGrams: 100,
      kcal: 200,
      protein: 10,
    );
    final other = myFoodDef(
      key: 'synthetic-other',
      label: 'Synthetic companion',
      refGrams: 100,
    );
    await NutritionDb.putFoodDef(db, main);
    await NutritionDb.putFoodDef(db, other);
    for (var i = 1; i <= 3; i++) {
      final date = '2021-04-0$i';
      for (final (id, quantity) in [
        ('synthetic-main', 100.0),
        ('synthetic-other', 50.0),
      ]) {
        await NutritionDb.put(
          db,
          FoodEntry(
            id: '$id-$i',
            date: date,
            meal: 'lunch',
            label: id,
            foodKey: id,
            quantity: quantity,
            unit: 'g',
          ),
        );
      }
    }
    return main;
  }

  for (final refusal in [false, true]) {
    testWidgets(
      'COV-47 companion plate ${refusal ? 'rolls back and retries' : 'commits'} without converting unknowns to zero',
      (t) async {
        final def = await seed(), db = await LocalDb.instance;
        final app = AppState.forTesting()
          ..user = {
            'kcal_target': 80,
            'protein_target': 5,
            'carbs_target': 20,
            'fat_target': 10,
            'fibre_target': 10,
          };
        addTearDown(app.dispose);
        await localizedPage(
          t,
          FoodDetailSheet(
            def: def,
            date: '2021-04-06',
            meal: 'lunch',
            grams: 50,
          ),
          app: app,
          push: true,
        );
        final companion = find.byWidgetPredicate(
          (w) =>
              w is Pressable &&
              w.semanticLabel == 'Also log Synthetic companion',
        );
        await reveal(t, companion);
        await t.tap(companion);
        await t.pumpAndSettle();
        await t.tap(companion);
        await t.pumpAndSettle();
        await t.tap(companion);
        await t.pumpAndSettle();
        expect((await readPage(t)).join(' '), contains('over ≥ 20'));
        if (refusal)
          await db.execute(
            "CREATE TRIGGER synthetic_plate_refusal BEFORE INSERT ON food_entry WHEN NEW.food_key='synthetic-other' AND NEW.date='2021-04-06' BEGIN SELECT RAISE(ABORT,'synthetic plate refusal'); END",
          );
        final log = find.byWidgetPredicate(
          (w) => w is BigButton && w.label == 'Log 2 foods',
        );
        await reveal(t, log);
        await invokeControl(t, t.widget<BigButton>(log).onTap);
        if (refusal) {
          expect(
            (await t.runAsync(
              () => NutritionDb.entriesForDay(db, '2021-04-06'),
            ))!,
            isEmpty,
          );
          expect(
            find.text('Could not save. Your portion is still here; try again.'),
            findsOneWidget,
          );
          await db.execute('DROP TRIGGER synthetic_plate_refusal');
          await invokeControl(t, t.widget<BigButton>(log).onTap);
        }
        final rows = (await t.runAsync(
          () => NutritionDb.entriesForDay(db, '2021-04-06'),
        ))!;
        expect(rows, hasLength(2));
        expect(rows.every((e) => e.meal == 'lunch'), true);
        expect(rows.firstWhere((e) => e.foodKey == 'synthetic-main').kcal, 100);
        final partner = rows.firstWhere((e) => e.foodKey == 'synthetic-other');
        expect(partner.quantity, 50);
        expect(partner.kcal, isNull);
        expect(partner.proteinG, isNull);
      },
    );
  }
  testWidgets(
    'COV-47 Log screen saved-meal handoff reviews before writing the explicit historical meal',
    (t) async {
      await seed();
      final db = await LocalDb.instance;
      final meal = MealTemplate(
        key: 'synthetic-meal',
        label: 'Synthetic saved meal',
        meal: 'breakfast',
        items: const [('synthetic-main', 50), ('synthetic-other', 25)],
      );
      await MyFoods.putMeal(db, meal);
      final app = AppState.forTesting()..user = {};
      addTearDown(app.dispose);
      await localizedPage(
        t,
        const LogFoodScreen(date: '2021-04-06', meal: 'dinner'),
        app: app,
      );
      await t.tap(find.text('My meals'));
      await t.pumpAndSettle();
      final plus = find.byWidgetPredicate(
        (w) => w is Pressable && w.semanticLabel == 'Log Synthetic saved meal',
      );
      await reveal(t, plus);
      await t.tap(plus);
      await flush(t);
      expect(find.byType(MealReviewSheet), findsOneWidget);
      expect(
        (await t.runAsync(() => NutritionDb.entriesForDay(db, '2021-04-06')))!,
        isEmpty,
      );
      final log = find.byWidgetPredicate(
        (w) => w is BigButton && w.label == 'Log',
      );
      await t.tap(log);
      await flush(t);
      final rows = (await t.runAsync(
        () => NutritionDb.entriesForDay(db, '2021-04-06'),
      ))!;
      expect(rows, hasLength(2));
      expect(rows.every((e) => e.meal == 'dinner'), true);
      expect(rows.map((e) => e.quantity).toSet(), {50.0, 25.0});
      expect(find.text('Added Synthetic saved meal · 2 items'), findsOneWidget);
    },
  );
}
