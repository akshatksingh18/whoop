// Real alternate row/editor entry points retain explicit meal,date and history.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/nutrition_store.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/screens/food_diary.dart';
import 'package:whoop_companion/ui2/screens/food_picker.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'food_calendar_recovery_test.dart' show flush;
import 'saved_meal_editor_test.dart' show field;
import '../../support/audit_visual.dart' show loadAuditFonts;
import '../../support/coverage_store.dart';
import '../../support/localized_coverage.dart';

const day = '2021-04-06';
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState app;
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('log-food-review-handoffs');
  });
  setUp(() async {
    await resetCoverageStore();
    app = AppState.forTesting()..user = {};
    final db = await LocalDb.instance;
    await NutritionDb.putFoodDef(
      db,
      myFoodDef(
        key: 'authored-food',
        label: 'Authored row food',
        refGrams: 100,
        kcal: 200,
        protein: 0,
      ),
    );
    await MyFoods.putMeal(
      db,
      const MealTemplate(
        key: 'authored-meal',
        label: 'Authored row meal',
        meal: 'breakfast',
        items: [('authored-food', 50)],
      ),
    );
    await NutritionDb.put(
      db,
      const FoodEntry(
        id: 'authored-original',
        date: '2021-04-07',
        meal: 'lunch',
        label: 'Authored original',
        foodKey: 'authored-food',
        quantity: 37.5,
        kcal: 75,
        proteinG: 0,
        atTs: 1617800000,
        loggedAt: 1617900000,
      ),
    );
  });
  tearDown(() => app.dispose());
  tearDownAll(LocalDb.close);
  Future<void> tap(WidgetTester t, Finder f) async {
    await reveal(t, f);
    await t.tap(f);
    await flush(t);
  }

  Finder big(String label) =>
      find.byWidgetPredicate((w) => w is BigButton && w.label == label);
  for (final scale in [1.0, 3.1]) {
    for (final route in ['meal-row', 'food-row', 'create-food']) {
      testWidgets(
        '$route opens a cancellable historical dinner review at ${scale}x',
        (t) async {
          final db = await LocalDb.instance;
          final before = await db.query('food_entry', orderBy: 'id');
          final definitions = await db.query('food_def', orderBy: 'key');
          final templates = await db.query('meal_template', orderBy: 'key');
          await localizedPage(
            t,
            const LogFoodScreen(date: day, meal: 'dinner'),
            app: app,
            scale: scale,
          );
          await flush(t);
          if (route == 'meal-row') {
            await tap(t, find.text('My meals'));
            await tap(t, find.text('Authored row meal'));
            expect(find.byType(MealReviewSheet), findsOneWidget);
            Navigator.of(t.element(find.byType(MealReviewSheet))).pop();
            await flush(t);
            expect(await db.query('food_entry', orderBy: 'id'), before);
            // Reopening through + is the same review,not a stale or already logged meal.
            final plus = find.byWidgetPredicate(
              (w) =>
                  w is Pressable && w.semanticLabel == 'Log Authored row meal',
            );
            await tap(t, plus);
            await reveal(t, big('Log'));
            await invokeControl(t, t.widget<BigButton>(big('Log')).onTap);
            await flush(t);
            final saved = (await t.runAsync(
              () => NutritionDb.entriesForDay(db, day),
            ))!.single;
            expect(saved.meal, 'dinner');
            expect(saved.date, day);
            expect(saved.quantity, 50);
            expect(saved.kcal, 100);
            expect(saved.proteinG, 0);
            expect(saved.loggedAt, isNotNull);
            expect(saved.atTs, isNot(saved.loggedAt));
          } else {
            if (route == 'create-food') {
              await tap(t, find.text('Create a food'));
              expect(find.byType(FoodEditor), findsOneWidget);
              await t.enterText(
                field('Description'),
                'Authored newly created food',
              );
              await t.enterText(field('Calories (kcal)'), '0');
              await reveal(t, big('Save'));
              await invokeControl(t, t.widget<BigButton>(big('Save')).onTap);
              await flush(t);
              expect(find.byType(FoodEditor), findsNothing);
            } else {
              await tap(t, find.text('Authored row food'));
            }
            expect(find.byType(FoodDetailSheet), findsOneWidget);
            final detail = t.widget<FoodDetailSheet>(
              find.byType(FoodDetailSheet),
            );
            expect(detail.meal, 'dinner');
            expect(detail.date, day);
            if (route == 'food-row') {
              expect(detail.grams, 37.5);
              expect(detail.def['key'], 'authored-food');
            } else {
              expect(detail.def['label'], 'Authored newly created food');
              expect(detail.def['kcal_100'], 0);
              expect(detail.def['protein_g_100'], isNull);
            }
            expect(await db.query('food_entry', orderBy: 'id'), before);
            Navigator.of(t.element(find.byType(FoodDetailSheet))).pop();
            await flush(t);
            expect(find.byType(LogFoodScreen), findsOneWidget);
            expect(
              t.widget<LogFoodScreen>(find.byType(LogFoodScreen)).meal,
              'dinner',
            );
            expect(
              t.widget<LogFoodScreen>(find.byType(LogFoodScreen)).date,
              day,
            );
            expect(await db.query('food_entry', orderBy: 'id'), before);
          }
          expect(
            await db.query(
              'food_entry',
              where: 'date != ?',
              whereArgs: [day],
              orderBy: 'id',
            ),
            before,
          );
          expect(await db.query('meal_template', orderBy: 'key'), templates);
          final afterDefs = await db.query('food_def', orderBy: 'key');
          expect(
            afterDefs.where((r) => r['key'] == 'authored-food').toList(),
            definitions,
          );
          expect(afterDefs.length, route == 'create-food' ? 2 : 1);
          expect(t.takeException(), isNull);
        },
        timeout: const Timeout(Duration(seconds: 30)),
      );
    }
  }
}
