// Real saved-meal review and SQLite;no meal-default or calorie-policy changes.
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
    await coverageStore('saved-meal-item-selection', fresh: true);
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

  Future<void> tap(WidgetTester t, Finder f) async {
    await reveal(t, f);
    await t.tap(f);
    await flush(t);
  }

  Finder toggle(String label) =>
      find.byWidgetPredicate((w) => w is Pressable && w.semanticLabel == label);
  Finder button(String label) =>
      find.byWidgetPredicate((w) => w is BigButton && w.label == label);
  for (final scale in [1.0, 3.1]) {
    for (final action in ['omit', 'reinclude', 'all-off-cancel']) {
      testWidgets(
        'saved meal $action at ${scale}x keeps historical ownership and uncertainty',
        (t) async {
          final db = await LocalDb.instance;
          await NutritionDb.putFoodDef(
            db,
            myFoodDef(
              key: 'known',
              label: 'Authored known',
              refGrams: 100,
              kcal: 200,
              protein: 10,
            ),
          );
          await NutritionDb.putFoodDef(
            db,
            myFoodDef(key: 'unknown', label: 'Authored unknown', refGrams: 100),
          );
          final meal = MealTemplate(
            key: 'retained-meal',
            label: 'Authored selection',
            meal: 'breakfast',
            items: const [('known', 50), ('unknown', 25), ('removed', 75)],
          );
          await MyFoods.putMeal(db, meal);
          final defs = await MyFoods.all(db);
          final app = AppState.forTesting()..user = {};
          addTearDown(app.dispose);
          await localizedPage(
            t,
            const LogFoodScreen(date: '2021-04-06', meal: 'dinner'),
            app: app,
            scale: scale,
          );
          await tap(t, find.text('My meals'));
          await tap(
            t,
            find.byWidgetPredicate(
              (w) =>
                  w is Pressable && w.semanticLabel == 'Log Authored selection',
            ),
          );
          expect(find.byType(MealReviewSheet), findsOneWidget);
          expect(find.text('Deleted food'), findsOneWidget);
          expect(t.widget<Pressable>(toggle('Include')).onTap, isNull);
          await tap(t, toggle('Leave out').at(1));
          if (action == 'reinclude') await tap(t, toggle('Include').first);
          if (action == 'all-off-cancel') {
            await tap(t, toggle('Leave out'));
            await reveal(t, button('Log'));
            expect(t.widget<BigButton>(button('Log')).onTap, isNull);
            expect(
              await t.runAsync(
                () => NutritionDb.entriesForDay(db, '2021-04-06'),
              ),
              isEmpty,
            );
            Navigator.of(t.element(find.byType(MealReviewSheet))).pop();
            await flush(t);
          } else {
            await reveal(t, button('Log'));
            await invokeControl(t, t.widget<BigButton>(button('Log')).onTap);
            await flush(t);
          }
          final rows = (await t.runAsync(
            () => NutritionDb.entriesForDay(db, '2021-04-06'),
          ))!;
          if (action == 'all-off-cancel') {
            expect(rows, isEmpty);
          } else {
            expect(rows, hasLength(action == 'omit' ? 1 : 2));
            expect(
              rows.every(
                (e) =>
                    e.date == '2021-04-06' &&
                    e.meal == 'dinner' &&
                    e.loggedAt != null,
              ),
              true,
            );
            final known = rows.singleWhere((e) => e.foodKey == 'known');
            expect(known.quantity, 50);
            expect(known.kcal, 100);
            expect(known.proteinG, 5);
            expect(rows.where((e) => e.foodKey == 'removed'), isEmpty);
            if (action == 'reinclude') {
              final unknown = rows.singleWhere((e) => e.foodKey == 'unknown');
              expect(unknown.quantity, 25);
              expect(unknown.kcal, isNull);
              expect(unknown.proteinG, isNull);
            }
          }
          final after = (await t.runAsync(() => MyFoods.meals(db)))!.single;
          expect(after.key, meal.key);
          expect(after.items, meal.items);
          expect(after.meal, 'breakfast');
          expect(after.label, meal.label);
          expect(await t.runAsync(() => MyFoods.all(db)), defs);
        },
      );
    }
  }
  for (final scale in [1.0, 3.1]) {
    testWidgets(
      'meal editor category filtering at ${scale}x is a reversible unsaved view',
      (t) async {
        final db = await LocalDb.instance;
        await NutritionDb.putFoodDef(
          db,
          myFoodDef(
            key: 'fruit',
            label: 'Authored fruit',
            category: 'Fruit',
            refGrams: 100,
            kcal: 50,
          ),
        );
        await NutritionDb.putFoodDef(
          db,
          myFoodDef(
            key: 'grain',
            label: 'Authored grain',
            category: 'Grain',
            refGrams: 100,
            kcal: 300,
          ),
        );
        const meal = MealTemplate(
          key: 'filter-meal',
          label: 'Authored unchanged meal',
          meal: 'lunch',
          items: [('fruit', 50)],
        );
        await MyFoods.putMeal(db, meal);
        final before = await db.query('meal_template'),
            defs = await MyFoods.all(db);
        final app = AppState.forTesting()..user = {};
        addTearDown(app.dispose);
        await localizedPage(
          t,
          const MealEditor(existing: meal),
          app: app,
          scale: scale,
          push: true,
        );
        await flush(t);
        await tap(t, button('Add a food'));
        await tap(t, toggle('Show Grain'));
        final filter = find.byType(FoodCategoryFilter);
        final picker = find
            .ancestor(of: filter, matching: find.byType(InputSheet))
            .first;
        Finder pickedFood(String text) => find.descendant(
          of: picker,
          matching: find.widgetWithText(PickRow, text),
        );
        expect(t.widget<FoodCategoryFilter>(filter).selected, 'Grain');
        expect(pickedFood('Authored grain'), findsOneWidget);
        expect(pickedFood('Authored fruit'), findsNothing);
        await tap(t, toggle('Show All'));
        expect(t.widget<FoodCategoryFilter>(filter).selected, isNull);
        expect(pickedFood('Authored fruit'), findsOneWidget);
        expect(pickedFood('Authored grain'), findsOneWidget);
        await tap(t, button('Done'));
        expect(find.byType(MealEditor), findsOneWidget);
        Navigator.of(t.element(find.byType(MealEditor))).pop();
        await flush(t);
        expect(await t.runAsync(() => db.query('meal_template')), before);
        expect(await t.runAsync(() => MyFoods.all(db)), defs);
        expect(await t.runAsync(() => db.query('food_entry')), isEmpty);
      },
    );
  }
}
