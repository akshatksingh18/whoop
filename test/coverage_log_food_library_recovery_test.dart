// Explicit historical meal entry points, using authored SQLite rows. These do
// not choose or alter the general Log-food action's time-based meal default.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/nutrition_store.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/screens/food_diary.dart';
import 'package:whoop_companion/ui2/screens/food_picker.dart'
    show DragList, MealReviewSheet;
import 'package:whoop_companion/ui2/ui2.dart';
import 'coverage_body_history_actions_test.dart' show flush;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

Finder action(String label) =>
    find.byWidgetPredicate((w) => w is Pressable && w.semanticLabel == label);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('log-food-library-recovery');
  });
  setUp(() async {
    await resetCoverageStore();
    db = await LocalDb.instance;
    for (final (key, category) in [
      ('a', 'Fruit'),
      ('b', 'Grain'),
      ('c', 'Fruit'),
    ]) {
      await NutritionDb.putFoodDef(
        db,
        myFoodDef(
          key: key,
          label: 'Authored food $key',
          refGrams: 100,
          kcal: 100,
          category: category,
        ),
      );
      await MyFoods.putMeal(
        db,
        MealTemplate(
          key: key,
          label: 'Authored meal $key',
          meal: 'breakfast',
          items: [(key, 50)],
        ),
      );
    }
    await MyFoods.reorderFoods(db, ['a', 'b', 'c']);
    await MyFoods.reorderMeals(db, ['a', 'b', 'c']);
  });
  tearDownAll(LocalDb.close);
  Future<void> open(WidgetTester t) async {
    final app = AppState.forTesting()..user = {};
    addTearDown(app.dispose);
    await localizedPage(
      t,
      const LogFoodScreen(date: '2021-04-06', meal: 'lunch'),
      app: app,
    );
    await flush(t);
  }

  Future<void> tap(WidgetTester t, Finder f) async {
    await reveal(t, f);
    await t.tap(f);
    await flush(t);
  }

  testWidgets(
    'unavailable saved food reads disclose failure and recover on Retry',
    (t) async {
      await db.execute('ALTER TABLE food_def RENAME TO authored_held_food_def');
      try {
        await open(t);
        expect(find.text('Foods could not load'), findsOneWidget);
        expect(find.text('Authored food a'), findsNothing);
      } finally {
        await t.runAsync(
          () => db.execute(
            'ALTER TABLE authored_held_food_def RENAME TO food_def',
          ),
        );
      }
      await tap(t, find.text('Retry'));
      expect(find.text('Foods could not load'), findsNothing);
      expect((await readPage(t)).join(' '), contains('Authored food a'));
      expect(await t.runAsync(() => MyFoods.all(db)), hasLength(3));
      expect(
        await t.runAsync(() => NutritionDb.entriesForDay(db, '2021-04-06')),
        isEmpty,
      );
    },
  );

  testWidgets(
    'category filtering opens the selected food with its explicit historical meal',
    (t) async {
      await open(t);
      await tap(t, action('Show Fruit'));
      var text = (await readPage(t)).join(' ');
      expect(text, contains('Authored food a'));
      expect(text, isNot(contains('Authored food b')));
      await tap(t, action('Log Authored food a'));
      final sheet = t.widget<FoodDetailSheet>(find.byType(FoodDetailSheet));
      expect(sheet.def['key'], 'a');
      expect(sheet.date, '2021-04-06');
      expect(sheet.meal, 'lunch');
      Navigator.of(t.element(find.byType(FoodDetailSheet))).pop();
      await flush(t);
      await tap(t, action('Show All'));
      text = (await readPage(t)).join(' ');
      expect(text, contains('Authored food b'));
      expect(
        await t.runAsync(() => NutritionDb.entriesForDay(db, '2021-04-06')),
        isEmpty,
      );
    },
  );

  testWidgets(
    'a refused last-portion read leaves the food available for retry',
    (t) async {
      await open(t);
      await t.runAsync(
        () => db.execute(
          'ALTER TABLE food_entry RENAME TO authored_held_food_entry',
        ),
      );
      try {
        await tap(t, action('Log Authored food a'));
        expect(find.byType(FoodDetailSheet), findsNothing);
        expect(
          find.text('Could not finish. Please try again.'),
          findsOneWidget,
        );
      } finally {
        await t.runAsync(
          () => db.execute(
            'ALTER TABLE authored_held_food_entry RENAME TO food_entry',
          ),
        );
      }
      await tap(t, action('Log Authored food a'));
      expect(find.byType(FoodDetailSheet), findsOneWidget);
      expect(
        t.widget<FoodDetailSheet>(find.byType(FoodDetailSheet)).meal,
        'lunch',
      );
      Navigator.of(t.element(find.byType(FoodDetailSheet))).pop();
      await flush(t);
      expect(
        await t.runAsync(() => NutritionDb.entriesForDay(db, '2021-04-06')),
        isEmpty,
      );
    },
  );

  for (final meals in [false, true]) {
    testWidgets(
      'log picker ${meals ? 'meal' : 'food'} reorder refusal retains every position and retries',
      (t) async {
        await open(t);
        if (meals) await tap(t, find.text('My meals'));
        final table = meals ? 'meal_template' : 'food_def';
        Future<List<String>> order() async => [
          for (final row in await db.query(table, orderBy: 'pos ASC'))
            row['key'] as String,
        ];
        await t.runAsync(
          () => db.execute(
            "CREATE TRIGGER authored_picker_refusal BEFORE UPDATE OF pos ON $table WHEN NEW.key='b' BEGIN SELECT RAISE(ABORT,'authored position refusal'); END",
          ),
        );
        try {
          t.widget<DragList>(find.byType(DragList)).onReorder(0, 3);
          await flush(t);
          expect(
            find.text('The new order was not saved. Please try again.'),
            findsOneWidget,
          );
          expect(await t.runAsync(order), ['a', 'b', 'c']);
        } finally {
          await t.runAsync(
            () => db.execute('DROP TRIGGER authored_picker_refusal'),
          );
        }
        t.widget<DragList>(find.byType(DragList)).onReorder(0, 3);
        await flush(t);
        expect(await t.runAsync(order), ['b', 'c', 'a']);
        expect(
          await t.runAsync(() => NutritionDb.entriesForDay(db, '2021-04-06')),
          isEmpty,
        );
      },
    );
  }

  testWidgets(
    'a unit changed after meal review refuses the entire plate and can retry',
    (t) async {
      await MyFoods.putMeal(
        db,
        MealTemplate(
          key: 'a',
          label: 'Authored meal a',
          meal: 'breakfast',
          items: const [('b', 25), ('a', 50)],
        ),
      );
      final original = (await NutritionDb.foodDef(db, 'a'))!;
      await open(t);
      await tap(t, find.text('My meals'));
      await tap(t, action('Log Authored meal a'));
      expect(find.byType(MealReviewSheet), findsOneWidget);
      await t.runAsync(
        () => NutritionDb.putFoodDef(db, {...original, 'unit': 'ml'}),
      );
      await tap(t, find.text('Log'));
      expect(
        find.text(
          'The unit of Authored food a changed. Edit this saved meal before logging it.',
        ),
        findsOneWidget,
      );
      expect(
        await t.runAsync(() => NutritionDb.entriesForDay(db, '2021-04-06')),
        isEmpty,
      );
      expect(await t.runAsync(() => MyFoods.meals(db)), hasLength(3));
      await t.runAsync(() => NutritionDb.putFoodDef(db, original));
      await tap(t, action('Log Authored meal a'));
      await tap(t, find.text('Log'));
      final entries = (await t.runAsync(
        () => NutritionDb.entriesForDay(db, '2021-04-06'),
      ))!;
      expect(entries, hasLength(2));
      expect(entries.every((e) => e.meal == 'lunch'), true);
      expect(entries.map((e) => e.foodKey).toSet(), {'a', 'b'});
    },
  );

  testWidgets(
    'a food removed after review produces an honest no-foods result',
    (t) async {
      await open(t);
      await tap(t, find.text('My meals'));
      await tap(t, action('Log Authored meal a'));
      expect(find.byType(MealReviewSheet), findsOneWidget);
      await t.runAsync(() => MyFoods.deleteFood(db, 'a'));
      await tap(t, find.text('Log'));
      expect(
        find.text(
          'No foods remain in Authored meal a. Edit the saved meal first.',
        ),
        findsOneWidget,
      );
      expect(
        await t.runAsync(() => NutritionDb.entriesForDay(db, '2021-04-06')),
        isEmpty,
      );
      expect(await t.runAsync(() => MyFoods.meals(db)), hasLength(3));
    },
  );
}
