// Existing saved-food/meal editors; explicit authored data, no meal-default repair.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/nutrition_store.dart';
import 'package:whoop_companion/ui2/screens/food_picker.dart';
import 'package:whoop_companion/ui2/screens/journal_compose.dart'
    show WhoopTextField;
import 'package:whoop_companion/ui2/ui2.dart';
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('food-editor-recovery');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  Future<Map<String, Object?>> food() async {
    final f = myFoodDef(
      key: 'my:authored',
      label: 'Authored oats',
      refGrams: 100,
      kcal: 200,
      protein: 0,
      category: 'Fruit',
    );
    await NutritionDb.putFoodDef(await LocalDb.instance, f);
    return f;
  }

  Future<void> open(
    WidgetTester t,
    Future<void> Function(BuildContext) show,
  ) async {
    await localizedPage(
      t,
      Builder(
        builder: (c) => Scaffold(
          body: TextButton(
            onPressed: () => show(c),
            child: const Text('Existing library editor'),
          ),
        ),
      ),
    );
    await t.tap(find.text('Existing library editor'));
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await t.pumpAndSettle();
  }

  Future<void> tap(WidgetTester t, Finder f) async {
    await t.ensureVisible(f);
    await t.tap(f);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  }

  Future<void> save(WidgetTester t) async {
    final f = find.widgetWithText(BigButton, 'Save');
    await t.ensureVisible(f);
    await invokeControl(t, t.widget<BigButton>(f).onTap);
  }

  Finder label(String value) =>
      find.byWidgetPredicate((w) => w is Pressable && w.semanticLabel == value);

  testWidgets(
    'selecting then clearing a saved-food label preserves nutrition and no food log',
    (t) async {
      final original = await t.runAsync(food);
      await open(t, (c) async {
        await FoodEditor.show(c, existing: original);
      });
      await tap(t, label('Label Fruit, selected'));
      expect(label('Label Fruit'), findsOneWidget);
      await tap(t, label('Label Fruit'));
      expect(label('Label Fruit, selected'), findsOneWidget);
      await tap(t, label('Label Fruit, selected'));
      await save(t);
      expect(find.byType(FoodEditor), findsNothing);
      final stored = (await t.runAsync(
        () async => MyFoods.all(await LocalDb.instance),
      ))!;
      expect(stored.single['category'], '');
      expect(stored.single['kcal_100'], original!['kcal_100']);
      expect(stored.single['protein_g_100'], 0);
      expect(
        await t.runAsync(
          () async => (await LocalDb.instance).query('food_entry'),
        ),
        isEmpty,
      );
    },
  );

  testWidgets(
    'failed saved-food read blocks meal Save, then Retry preserves the exact meal',
    (t) async {
      await t.runAsync(food);
      const meal = MealTemplate(
        key: 'authored-meal',
        label: 'Authored lunch',
        meal: 'lunch',
        items: [('my:authored', 50)],
        units: {'my:authored': 'g'},
      );
      final db = await LocalDb.instance;
      await t.runAsync(() => MyFoods.putMeal(db, meal));
      final before = await t.runAsync(() => db.query('meal_template'));
      await t.runAsync(
        () =>
            db.execute('ALTER TABLE food_def RENAME TO authored_held_food_def'),
      );
      try {
        await open(t, (c) async {
          await MealEditor.show(c, existing: meal);
        });
        expect(find.text('Foods could not load'), findsOneWidget);
        await save(t);
        expect(
          find.text('Load your saved foods before saving this meal.'),
          findsOneWidget,
        );
        expect(await t.runAsync(() => db.query('meal_template')), before);
      } finally {
        await t.runAsync(
          () => db.execute(
            'ALTER TABLE authored_held_food_def RENAME TO food_def',
          ),
        );
      }
      await tap(t, find.text('Retry'));
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await t.pumpAndSettle();
      expect(find.text('Foods could not load'), findsNothing);
      await save(t);
      final stored = (await t.runAsync(() => MyFoods.meals(db)))!.single;
      expect(stored.key, meal.key);
      expect(stored.label, meal.label);
      expect(stored.meal, meal.meal);
      expect(stored.items, meal.items);
      expect(stored.units, meal.units);
      expect(await t.runAsync(() => db.query('food_entry')), isEmpty);
    },
  );

  testWidgets(
    'empty meal picker gives the existing library action without inventing foods',
    (t) async {
      await open(t, (c) async {
        await MealEditor.show(c);
      });
      await tap(t, find.widgetWithText(BigButton, 'Add a food'));
      expect(find.text('Add foods first, under Food › Foods.'), findsOneWidget);
      await tap(t, find.widgetWithText(BigButton, 'Done'));
      expect(find.byType(MealEditor), findsOneWidget);
      expect(
        await t.runAsync(() async => MyFoods.meals(await LocalDb.instance)),
        isEmpty,
      );
    },
  );

  testWidgets(
    'new sub-heading returns trimmed text only after nonblank input',
    (t) async {
      String? result;
      await open(t, (c) async {
        result = await pickFoodGroup(c, [], '');
      });
      await tap(t, find.widgetWithText(BigButton, 'Use this name'));
      expect(result, isNull);
      expect(find.text('Sub-heading'), findsOneWidget);
      final input = find.descendant(
        of: find.byType(WhoopTextField),
        matching: find.byType(TextField),
      );
      await t.enterText(input, '  Authored side  ');
      await tap(t, find.widgetWithText(BigButton, 'Use this name'));
      expect(result, 'Authored side');
      expect(find.text('Existing library editor'), findsOneWidget);
    },
  );
}
