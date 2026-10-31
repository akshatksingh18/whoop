// Saved compositions retain amounts, units and headings across real sheet edits.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/nutrition_store.dart';
import 'package:whoop_companion/ui2/screens/food_picker.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'coverage_saved_meal_editor_test.dart' show flush;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Object? result;
  late Map<String, Object?> food;
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('saved-meal-unit-contracts');
  });
  setUp(() async {
    await resetCoverageStore();
    result = null;
    food = myFoodDef(
      key: 'synthetic-food',
      label: 'Synthetic oats',
      refGrams: 100,
      kcal: 200,
      measures: [(label: 'cup', amount: 50.0)],
      category: 'Grains & bread',
    );
    await NutritionDb.putFoodDef(await LocalDb.instance, food);
  });
  tearDownAll(LocalDb.close);
  Future<void> open(
    WidgetTester t,
    Future<Object?> Function(BuildContext) show,
  ) async {
    await localizedPage(
      t,
      Scaffold(
        body: Builder(
          builder: (c) => TextButton(
            onPressed: () async {
              result = await show(c);
            },
            child: const Text('Open synthetic sheet'),
          ),
        ),
      ),
    );
    await t.tap(find.text('Open synthetic sheet'));
    await flush(t);
  }

  Future<void> tap(WidgetTester t, Finder f) async {
    await reveal(t, f);
    await t.tap(f);
    await flush(t);
  }

  for (final missingUnit in [false, true]) {
    testWidgets(
      'duplicate food units ${missingUnit ? 'remove unconvertible copies honestly' : 'convert every other copy without changing quantities'}',
      (t) async {
        final meal = MealTemplate(
          key: 'synthetic-meal',
          label: 'Synthetic duplicates',
          meal: 'lunch',
          items: [('synthetic-food', 1), ('synthetic-food', 2)],
          units: {'synthetic-food': missingUnit ? 'retired-unit' : 'cup'},
          groups: ['Bowl', 'Side'],
        );
        await MyFoods.putMeal(await LocalDb.instance, meal);
        await open(t, (c) => MealEditor.show(c, existing: meal));
        await tap(t, find.text('Synthetic oats').first);
        if (missingUnit)
          expect(
            find.textContaining('a unit this food no longer has'),
            findsOneWidget,
          );
        final input = t.widget<AmountInput>(find.byType(AmountInput));
        input.unit!.value = 'g';
        await t.enterText(find.byType(TextField).last, '100');
        await tap(t, find.text('Done').last);
        if (missingUnit)
          expect(
            find.textContaining('1 other Synthetic oats portion was'),
            findsOneWidget,
          );
        await tap(t, find.text('Save').last);
        expect(result, isTrue);
        final saved = (await t.runAsync(
          () async => MyFoods.meals(await LocalDb.instance),
        ))!.single;
        expect(saved.units['synthetic-food'], 'g');
        expect(
          saved.items.map((x) => x.$2).toList(),
          missingUnit ? [100.0] : [100.0, 100.0],
        );
        expect(saved.groups, missingUnit ? ['Bowl'] : ['Bowl', 'Side']);
      },
    );
  }
  testWidgets(
    'saved meal rearrangement and deletion keep heading/amount associations',
    (t) async {
      await NutritionDb.putFoodDef(
        await LocalDb.instance,
        myFoodDef(
          key: 'synthetic-rice',
          label: 'Synthetic rice',
          refGrams: 100,
          kcal: 150,
        ),
      );
      const meal = MealTemplate(
        key: 'synthetic-meal',
        label: 'Synthetic grouped',
        meal: 'lunch',
        items: [('synthetic-food', 50), ('synthetic-rice', 80)],
        groups: ['First', 'Second'],
        units: {'synthetic-food': 'g', 'synthetic-rice': 'g'},
      );
      await MyFoods.putMeal(await LocalDb.instance, meal);
      await open(t, (c) => MealEditor.show(c, existing: meal));
      final list = t.widget<GroupedDragList<int>>(
        find.byType(GroupedDragList<int>),
      );
      list.onChanged([('Reordered', 1), ('First', 0)]);
      await t.pumpAndSettle();
      final row = find.ancestor(
        of: find.text('Synthetic oats'),
        matching: find.byType(SwipeDelete),
      );
      await invokeControl(t, t.widget<SwipeDelete>(row).onDelete);
      await tap(t, find.text('Save').last);
      final saved = (await t.runAsync(
        () async => MyFoods.meals(await LocalDb.instance),
      ))!.single;
      expect(saved.items, [('synthetic-rice', 80.0)]);
      expect(saved.groups, ['Reordered']);
    },
  );
  testWidgets(
    'stored meal review loads current definitions, edits a portion and keeps selected rows',
    (t) async {
      const meal = MealTemplate(
        key: 'synthetic-meal',
        label: 'Synthetic review',
        meal: 'lunch',
        items: [('synthetic-food', 50), ('synthetic-food', 80)],
        units: {'synthetic-food': 'g'},
        groups: ['', 'Bowl'],
      );
      await open(t, (c) => MealReviewSheet.show(c, meal));
      expect(find.text('No sub-heading'), findsOneWidget);
      expect(find.text('Bowl'), findsOneWidget);
      await tap(t, find.text('Synthetic oats').first);
      await t.enterText(find.byType(TextField).last, '75');
      await tap(t, find.text('Done').last);
      await tap(t, find.text('Log').last);
      final reviewed = result as ({List<double?> amounts, List<String> units});
      expect(reviewed.amounts, [75.0, 80.0]);
      expect(reviewed.units, ['g', 'g']);
    },
  );
  for (final label in ['  Synthetic custom  ', 'grains & bread']) {
    testWidgets('new food label trims and reuses existing names $label', (
      t,
    ) async {
      await open(t, (c) => FoodEditor.show(c, existing: food));
      final add = find.byWidgetPredicate(
        (w) => w is Pressable && w.semanticLabel == 'New label',
      );
      await tap(t, add);
      await t.enterText(find.byType(TextField).last, '');
      await t.tap(find.text('Save').last);
      await t.pumpAndSettle();
      expect(find.text('Type a name.'), findsOneWidget);
      await t.enterText(find.byType(TextField).last, label);
      await t.tap(find.text('Save').last);
      await flush(t);
      await tap(t, find.text('Save').last);
      final saved = (await t.runAsync(
        () async =>
            NutritionDb.foodDef(await LocalDb.instance, 'synthetic-food'),
      ))!;
      expect(
        saved['category'],
        label.contains('Synthetic') ? 'Synthetic custom' : 'Grains & bread',
      );
    });
  }
}
