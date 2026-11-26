// Actual Foods-tab routes, real saved definitions and unchanged diary provenance.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/nutrition_store.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/screens/food_picker.dart';
import 'package:whoop_companion/ui2/screens/nutrition_screen.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'nutrition_root_test.dart' show FoodRepo, io;
import 'saved_meal_editor_test.dart' show action, field;
import '../../support/audit_visual.dart' show loadAuditFonts;
import '../../support/coverage_store.dart';
import '../../support/localized_coverage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState app;
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('food-library-editor-routes', fresh: true);
  });
  setUp(() async {
    await resetCoverageStore();
    app = AppState.forTesting()..repo = FoodRepo();
    final db = await LocalDb.instance;
    await NutritionDb.putFoodDef(
      db,
      myFoodDef(
        key: 'my:authored-route-food',
        label: 'Authored route food',
        refGrams: 100,
        unit: 'g',
        kcal: 200,
        protein: 0,
      ),
    );
    await MyFoods.putMeal(
      db,
      const MealTemplate(
        key: 'meal:authored-route-meal',
        label: 'Authored route meal',
        meal: 'dinner',
        items: [('my:authored-route-food', 50)],
        units: {'my:authored-route-food': 'g'},
        groups: ['Authored heading'],
      ),
    );
    await NutritionDb.put(
      db,
      const FoodEntry(
        id: 'authored-retained-diary',
        date: '2021-04-06',
        meal: 'lunch',
        label: 'Original diary label',
        foodKey: 'my:authored-route-food',
        quantity: 50,
        unit: 'g',
        kcal: 100,
        proteinG: 0,
        atTs: 1617700000,
        loggedAt: 1617800000,
      ),
    );
  });
  tearDown(() => app.dispose());
  tearDownAll(LocalDb.close);

  Future<void> press(WidgetTester t, Finder f) async {
    await reveal(t, f);
    await t.tap(f);
    await io(t);
  }

  Future<void> open(WidgetTester t) async {
    await localizedPage(
      t,
      const Scaffold(body: NutritionScreen()),
      app: app,
      settle: false,
    );
    await io(t);
    await press(t, find.text('Foods'));
  }

  for (final meal in [false, true]) {
    for (final route in ['new', 'cancel edit', 'rename']) {
      testWidgets(
        'Foods-tab ${meal ? 'meal' : 'food'} $route preserves the original diary and unrelated library',
        (t) async {
          final db = (await t.runAsync(() => LocalDb.instance))!;
          final beforeFood = (await t.runAsync(() => db.query('food_def')))!;
          final beforeMeal = (await t.runAsync(
            () => db.query('meal_template'),
          ))!;
          final beforeDiary = await t.runAsync(() => db.query('food_entry'));
          await open(t);
          if (route == 'new') {
            // These are the two distinct section actions on the real Foods tab.
            final button = meal
                ? find.descendant(
                    of: find.byWidgetPredicate(
                      (w) => w is Section && w.title == 'Saved meals',
                    ),
                    matching: find.text('New'),
                  )
                : action('Create a food');
            await press(t, button);
          } else {
            await press(
              t,
              find.text(meal ? 'Authored route meal' : 'Authored route food'),
            );
          }
          expect(
            meal ? find.byType(MealEditor) : find.byType(FoodEditor),
            findsOneWidget,
          );
          final input = field(meal ? 'Name' : 'Description');
          expect(
            t.widget<TextField>(input).controller!.text,
            route == 'new'
                ? ''
                : meal
                ? 'Authored route meal'
                : 'Authored route food',
          );
          await t.enterText(input, 'Authored changed name');
          if (route == 'rename') {
            await press(t, find.widgetWithText(BigButton, 'Save'));
          } else {
            await press(t, action('Close'));
            expect(find.text('Discard changes?'), findsOneWidget);
            await press(t, find.text('Discard'));
          }
          expect(find.byType(MealEditor), findsNothing);
          expect(find.byType(FoodEditor), findsNothing);
          expect(await t.runAsync(() => db.query('food_entry')), beforeDiary);
          final afterFood = (await t.runAsync(() => db.query('food_def')))!;
          final afterMeal = (await t.runAsync(
            () => db.query('meal_template'),
          ))!;
          // Renaming may update the definition's timestamp, never the food log.
          Map<String, Object?> stable(Map<String, Object?> row) =>
              {...row}..remove('created_at');
          if (route == 'rename' && !meal) {
            expect(stable(afterFood.single), {
              ...stable(beforeFood.single),
              'label': 'Authored changed name',
            });
          } else {
            expect(afterFood, beforeFood);
          }
          if (route == 'rename' && meal) {
            expect(stable(afterMeal.single), {
              ...stable(beforeMeal.single),
              'label': 'Authored changed name',
            });
          } else {
            expect(afterMeal, beforeMeal);
          }
          final page = (await readPage(t)).join(' ');
          expect(
            page,
            contains(
              route == 'rename' ? 'Authored changed name' : 'Authored route',
            ),
          );
          expect(page, contains('Saved meals'));
          expect(page, contains('My foods'));
          expect(t.takeException(), isNull);
        },
      );
    }
  }
}
