// Whole-plate logging keeps uncertainty and an atomic historical meal write.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/nutrition_store.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/screens/food_diary.dart';
import 'package:whoop_companion/ui2/screens/food_picker.dart';
import 'package:whoop_companion/ui2/screens/food_group_picker.dart';
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

  Future<void> openDetail(
    WidgetTester t,
    Map<String, Object?> def, {
    double grams = 50,
    String? unit,
    String group = '',
  }) async {
    final app = AppState.forTesting()..user = {};
    addTearDown(app.dispose);
    await localizedPage(
      t,
      FoodDetailSheet(
        def: def,
        date: '2021-04-06',
        meal: 'lunch',
        grams: grams,
        unit: unit,
        group: group,
      ),
      app: app,
      push: true,
    );
    await flush(t);
  }

  Future<void> tap(WidgetTester t, Finder finder) async {
    await reveal(t, finder);
    await t.tap(finder);
    await flush(t);
  }

  Future<void> logPlate(WidgetTester t, String label) async {
    final f = find.byWidgetPredicate((w) => w is BigButton && w.label == label);
    await reveal(t, f);
    await invokeControl(t, t.widget<BigButton>(f).onTap);
    await flush(t);
  }

  testWidgets(
    'unavailable companions warn without blocking the chosen historical food',
    (t) async {
      final def = await seed(), db = await LocalDb.instance;
      await db.execute(
        'ALTER TABLE food_def RENAME TO synthetic_held_companion_defs',
      );
      try {
        await openDetail(t, def);
        expect(
          find.text(
            'Companion foods could not load. You can still log this food.',
          ),
          findsOneWidget,
        );
        expect(find.text('Often eaten with'), findsNothing);
      } finally {
        await t.runAsync(
          () => db.execute(
            'ALTER TABLE synthetic_held_companion_defs RENAME TO food_def',
          ),
        );
      }
      await logPlate(t, 'Log');
      final rows = (await t.runAsync(
        () => NutritionDb.entriesForDay(db, '2021-04-06'),
      ))!;
      expect(rows, hasLength(1));
      expect(rows.single.foodKey, 'synthetic-main');
      expect(rows.single.quantity, 50);
      expect(rows.single.kcal, 100);
      expect(rows.single.meal, 'lunch');
      expect(rows.single.loggedAt, isNotNull);
    },
  );

  testWidgets(
    'detail keeps a chosen unit, manual meal, heading and eaten time on its historical day',
    (t) async {
      await seed();
      final db = await LocalDb.instance;
      final def = myFoodDef(
        key: 'synthetic-main',
        label: 'Synthetic main',
        refGrams: 100,
        kcal: 200,
        measures: [(label: 'cup', amount: 100.0)],
      );
      await NutritionDb.putFoodDef(db, def);
      await openDetail(
        t,
        def,
        grams: 2,
        unit: 'cup',
        group: 'Original heading',
      );
      final dinner = find.byWidgetPredicate(
        (w) => w is Pressable && w.semanticLabel == 'Dinner',
      );
      await tap(t, dinner);
      expect(t.widget<MealGroupPicker>(find.byType(MealGroupPicker)).group, '');
      await tap(t, find.text('Meal heading'));
      await tap(t, find.text('Create a heading'));
      await t.enterText(find.byType(TextField).last, '  Authored dinner  ');
      await tap(t, find.text('Save').last);
      expect(
        t.widget<MealGroupPicker>(find.byType(MealGroupPicker)).group,
        'Authored dinner',
      );
      final time = find.byWidgetPredicate(
        (w) =>
            w is Pressable && (w.semanticLabel?.startsWith('Time ') ?? false),
      );
      await tap(t, time);
      expect(find.byType(TimePickerDialog), findsOneWidget);
      Navigator.of(
        t.element(find.byType(TimePickerDialog)),
      ).pop(const TimeOfDay(hour: 18, minute: 25));
      await flush(t);
      await logPlate(t, 'Log');
      final saved = (await t.runAsync(
        () => NutritionDb.entriesForDay(db, '2021-04-06'),
      ))!.single;
      expect(saved.meal, 'dinner');
      expect(saved.group, 'Authored dinner');
      expect(saved.unit, 'cup');
      expect(saved.quantity, 2);
      expect(saved.kcal, 400);
      expect(
        saved.atTs,
        DayClock.onDate('2021-04-06', 18, 25).millisecondsSinceEpoch ~/ 1000,
      );
      expect(saved.loggedAt, isNot(saved.atTs));
      expect(
        (await t.runAsync(() => NutritionDb.entriesForDay(db, todayLabel())))!,
        isEmpty,
      );
    },
  );

  testWidgets(
    'multiple companions retain unknown nutrients and use the label portion for a retired historical unit',
    (t) async {
      final def = await seed(), db = await LocalDb.instance;
      final extra = myFoodDef(
        key: 'synthetic-third',
        label: 'Synthetic third',
        refGrams: 100,
        kcal: 360,
        protein: 20,
      );
      await NutritionDb.putFoodDef(db, extra);
      for (var i = 1; i <= 3; i++) {
        await db.update(
          'food_entry',
          {'unit': 'retired spoon'},
          where: 'id=?',
          whereArgs: ['synthetic-other-$i'],
        );
        await NutritionDb.put(
          db,
          FoodEntry(
            id: 'synthetic-third-$i',
            date: '2021-04-0$i',
            meal: 'lunch',
            label: 'Synthetic third',
            foodKey: 'synthetic-third',
            quantity: 30,
            unit: 'g',
          ),
        );
      }
      await openDetail(t, def);
      for (final label in ['Synthetic companion', 'Synthetic third']) {
        await tap(
          t,
          find.byWidgetPredicate(
            (w) => w is Pressable && w.semanticLabel == 'Also log $label',
          ),
        );
      }
      await logPlate(t, 'Log 3 foods');
      final rows = (await t.runAsync(
        () => NutritionDb.entriesForDay(db, '2021-04-06'),
      ))!;
      expect(rows, hasLength(3));
      final missing = rows.singleWhere((e) => e.foodKey == 'synthetic-other');
      expect(missing.quantity, 100);
      expect(missing.kcal, isNull);
      expect(missing.proteinG, isNull);
      final known = rows.singleWhere((e) => e.foodKey == 'synthetic-third');
      expect(known.quantity, 30);
      expect(known.kcal, closeTo(108, 1e-8));
      expect(rows.every((e) => e.meal == 'lunch' && e.loggedAt != null), true);
      expect(
        await t.runAsync(
          () => db.query(
            'food_entry',
            where: 'unit=?',
            whereArgs: ['retired spoon'],
          ),
        ),
        hasLength(3),
      );
    },
  );

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
