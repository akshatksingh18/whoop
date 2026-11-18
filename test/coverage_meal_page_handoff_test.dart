// Existing meal-page menus/date navigation over authored SQLite history.
// These explicit meal choices do not implement the parked general meal default.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/nutrition_store.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/screens/food_diary.dart';
import 'package:whoop_companion/ui2/screens/food_picker.dart';
import 'package:whoop_companion/ui2/screens/journal_compose.dart'
    show WhoopTextField;
import 'package:whoop_companion/ui2/ui2.dart';

import 'coverage_food_calendar_recovery_test.dart' show flush;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

const day = '2021-04-06';
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FoodEntry original;
  late AppState app;
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('meal-page-handoff');
  });
  setUp(() async {
    await resetCoverageStore();
    app = AppState.forTesting()..user = {};
    final db = await LocalDb.instance;
    final def = myFoodDef(
      key: 'authored-oats',
      label: 'Authored oats',
      refGrams: 100,
      kcal: 200,
      protein: 10,
    );
    await NutritionDb.putFoodDef(db, def);
    final at = DayClock.onDate(day, 8, 10).millisecondsSinceEpoch ~/ 1000;
    original = FoodEntry(
      id: 'authored-portion',
      date: day,
      meal: 'breakfast',
      label: 'Authored oats',
      foodKey: 'authored-oats',
      quantity: 50,
      unit: 'g',
      conv: conversionSnapshot(def),
      kcal: 100,
      proteinG: 5,
      group: 'Bowl',
      atTs: at,
      loggedAt: at + 60,
    );
    await NutritionDb.put(db, original);
    await NutritionDb.put(
      db,
      const FoodEntry(
        id: 'authored-side',
        date: day,
        meal: 'breakfast',
        label: 'Authored side',
        group: 'Plate',
      ),
    );
  });
  tearDown(() async {
    final db = await LocalDb.instance;
    await db.execute('DROP TRIGGER IF EXISTS authored_meal_refusal');
    app.dispose();
  });
  tearDownAll(LocalDb.close);

  Future<void> open(WidgetTester t, {Widget? child}) async {
    await localizedPage(
      t,
      child ?? const MealPage(date: day, meal: 'breakfast'),
      app: app,
      push: true,
    );
    await flush(t);
  }

  Future<void> tap(WidgetTester t, Finder f) async {
    await reveal(t, f);
    await t.tap(f);
    await flush(t);
  }

  Future<void> menu(WidgetTester t) => tap(t, find.text('Authored oats').first);
  Future<List<FoodEntry>> rows(WidgetTester t, [String date = day]) async =>
      (await t.runAsync(
        () async => NutritionDb.entriesForDay(await LocalDb.instance, date),
      ))!;
  Future<FoodEntry> portion(WidgetTester t) async =>
      (await rows(t)).singleWhere((e) => e.id == original.id);
  Future<void> button(WidgetTester t, String label) async {
    final f = find.byWidgetPredicate((w) => w is BigButton && w.label == label);
    await reveal(t, f);
    await invokeControl(t, t.widget<BigButton>(f).onTap);
    await flush(t);
  }

  void provenance(FoodEntry e) {
    expect(e.id, original.id);
    expect(e.date, original.date);
    expect(e.meal, original.meal);
    expect(e.atTs, original.atTs);
    expect(e.loggedAt, original.loggedAt);
    expect(e.unit, original.unit);
  }

  for (final invalid in ['', '0', 'bad']) {
    testWidgets(
      'an invalid detail amount "$invalid" retains the portion for correction',
      (t) async {
        final db = await LocalDb.instance;
        final def = (await NutritionDb.foodDef(db, 'authored-oats'))!;
        await open(
          t,
          child: FoodDetailSheet(
            def: def,
            date: day,
            meal: 'breakfast',
            grams: 50,
          ),
        );
        final amount = find.descendant(
          of: find.byWidgetPredicate(
            (w) => w is WhoopTextField && w.label == 'Amount (g)',
          ),
          matching: find.byType(TextField),
        );
        await reveal(t, amount);
        await t.enterText(amount, invalid);
        await button(t, 'Log');
        expect(find.text('Enter an amount greater than zero.'), findsOneWidget);
        expect(find.byType(FoodDetailSheet), findsOneWidget);
        expect(await rows(t), hasLength(2));
        provenance(await portion(t));
        await reveal(t, amount);
        await t.enterText(amount, '75');
        await button(t, 'Log');
        final added = (await rows(
          t,
        )).singleWhere((e) => e.id != original.id && e.id != 'authored-side');
        expect(added.quantity, 75);
        expect(added.kcal, 150);
        expect(added.meal, 'breakfast');
        expect(added.date, day);
        expect(added.loggedAt, isNotNull);
        expect((await portion(t)).kcal, original.kcal);
      },
    );
  }

  for (final refused in [false, true]) {
    testWidgets(
      'Quick add delete footer cancels, ${refused ? 'refuses and retries, ' : ''}then closes with recoverable history',
      (t) async {
        final db = await LocalDb.instance;
        // An older diary portion whose saved definition is no longer available
        // uses the shipped Quick add editor, above its actual meal scaffold.
        await db.delete(
          'food_def',
          where: 'key=?',
          whereArgs: ['authored-oats'],
        );
        await open(
          t,
          child: Scaffold(
            body: SingleChildScrollView(
              child: MealCard(
                date: day,
                meal: original.meal,
                entries: await rows(t),
                onChanged: () {},
              ),
            ),
          ),
        );
        await tap(t, find.text('Authored oats'));
        expect(find.byType(QuickAddSheet), findsOneWidget);
        await tap(t, find.text('Delete entry'));
        await tap(t, find.text('Keep it'));
        expect(find.byType(QuickAddSheet), findsOneWidget);
        provenance(await portion(t));
        if (refused) {
          await db.execute(
            "CREATE TRIGGER authored_meal_refusal BEFORE DELETE ON food_entry BEGIN SELECT RAISE(ABORT,'authored footer refusal'); END",
          );
        }
        Future<void> remove() async {
          await tap(t, find.text('Delete entry'));
          await tap(t, find.text('Delete').last);
        }

        await remove();
        if (refused) {
          expect(find.byType(QuickAddSheet), findsOneWidget);
          expect(
            find.text('Food was not deleted. Please try again.'),
            findsOneWidget,
          );
          provenance(await portion(t));
          await db.execute('DROP TRIGGER authored_meal_refusal');
          await remove();
        }
        expect(find.byType(QuickAddSheet), findsNothing);
        expect((await rows(t)).single.id, 'authored-side');
        await tap(t, find.text('Undo'));
        final restored = await portion(t);
        provenance(restored);
        expect(restored.conv, original.conv);
        expect(restored.quantity, original.quantity);
        expect(restored.kcal, original.kcal);
        expect(restored.proteinG, original.proteinG);
        expect(restored.group, original.group);
      },
    );
  }

  testWidgets(
    'Quick add heading-only correction preserves the saved portion and timestamps',
    (t) async {
      await open(
        t,
        child: QuickAddSheet(
          date: day,
          meal: original.meal,
          from: original,
          editing: true,
        ),
      );
      await tap(t, find.text('Meal heading'));
      await tap(t, find.text('Plate').last);
      await button(t, 'Save changes');
      final saved = await portion(t);
      provenance(saved);
      expect(saved.group, 'Plate');
      expect(saved.foodKey, original.foodKey);
      expect(saved.conv, original.conv);
      expect(saved.quantity, original.quantity);
      expect(saved.kcal, original.kcal);
      expect(saved.proteinG, original.proteinG);
      expect(
        (await rows(t)).singleWhere((e) => e.id == 'authored-side').kcal,
        isNull,
      );
    },
  );

  for (final save in [false, true]) {
    testWidgets(
      'detail editor ${save ? 'updates future logs' : 'cancels'} without rewriting the recorded portion',
      (t) async {
        final db = await LocalDb.instance;
        final def = (await NutritionDb.foodDef(db, 'authored-oats'))!;
        await open(
          t,
          child: FoodDetailSheet(
            def: def,
            date: day,
            meal: 'breakfast',
            grams: 50,
          ),
        );
        await tap(t, find.text('Edit saved food'));
        expect(find.byType(FoodEditor), findsOneWidget);
        if (save) {
          Finder field(String label) => find.descendant(
            of: find.byWidgetPredicate(
              (w) => w is WhoopTextField && w.label == label,
            ),
            matching: find.byType(TextField),
          );
          await t.enterText(field('Description'), 'Authored updated oats');
          await reveal(t, field('Calories (kcal)'));
          await t.enterText(field('Calories (kcal)'), '240');
          await button(t, 'Save');
        } else {
          Navigator.of(t.element(find.byType(FoodEditor))).pop();
          await flush(t);
        }
        expect(find.byType(FoodDetailSheet), findsOneWidget);
        expect(await rows(t), hasLength(2));
        final previous = await portion(t);
        provenance(previous);
        expect(previous.label, original.label);
        expect(previous.kcal, original.kcal);
        expect(previous.conv, original.conv);
        final current = (await t.runAsync(
          () => NutritionDb.foodDef(db, 'authored-oats'),
        ))!;
        expect(
          current['label'],
          save ? 'Authored updated oats' : 'Authored oats',
        );
        await button(t, 'Log');
        final added = (await rows(
          t,
        )).singleWhere((e) => e.id != original.id && e.id != 'authored-side');
        expect(added.foodKey, original.foodKey);
        expect(added.quantity, 50);
        expect(added.kcal, save ? 120 : 100);
        expect(added.label, save ? 'Authored updated oats' : original.label);
        expect(added.loggedAt, isNotNull);
        expect((await portion(t)).kcal, original.kcal);
      },
    );
  }

  testWidgets(
    'meal amount menu edits only the chosen portion and retains recorded provenance',
    (t) async {
      await open(t);
      await menu(t);
      await tap(t, find.text('Change amount'));
      expect(find.byType(GramsSheet), findsOneWidget);
      await t.enterText(find.byType(TextField).first, '75');
      await button(t, 'Save');
      final saved = await portion(t);
      provenance(saved);
      expect(saved.quantity, 75);
      expect(saved.kcal, 150);
      expect(saved.proteinG, 7.5);
      expect(saved.group, 'Bowl');
      expect(
        (await rows(t)).singleWhere((e) => e.id == 'authored-side').kcal,
        isNull,
      );
      expect(find.byType(GramsSheet), findsNothing);
    },
  );

  testWidgets(
    'a refused meal heading change remains visible and the same entry can retry',
    (t) async {
      final db = await LocalDb.instance;
      await open(t);
      await db.execute(
        "CREATE TRIGGER authored_meal_refusal BEFORE INSERT ON food_entry WHEN NEW.id='authored-portion' BEGIN SELECT RAISE(ABORT,'authored heading refusal'); END",
      );
      Future<void> change() async {
        await menu(t);
        await tap(t, find.text('Put under a sub-heading'));
        await tap(t, find.text('Plate').last);
      }

      await change();
      expect(
        find.text('Could not change this entry. Please try again.'),
        findsOneWidget,
      );
      expect((await portion(t)).group, 'Bowl');
      await db.execute('DROP TRIGGER authored_meal_refusal');
      await change();
      final saved = await portion(t);
      provenance(saved);
      expect(saved.group, 'Plate');
      expect(saved.kcal, original.kcal);
      expect(saved.quantity, original.quantity);
    },
  );

  for (final refused in [false, true]) {
    testWidgets(
      'meal delete menu cancels, ${refused ? 'refuses then retries, ' : ''}and restores with Undo',
      (t) async {
        final db = await LocalDb.instance;
        await open(t);
        await menu(t);
        await tap(t, find.text('Delete').last);
        await tap(t, find.text('Keep it'));
        expect(await rows(t), hasLength(2));
        if (refused) {
          await db.execute(
            "CREATE TRIGGER authored_meal_refusal BEFORE DELETE ON food_entry BEGIN SELECT RAISE(ABORT,'authored deletion refusal'); END",
          );
        }
        Future<void> remove() async {
          await menu(t);
          await tap(t, find.text('Delete').last);
          await tap(t, find.text('Delete').last);
        }

        await remove();
        if (refused) {
          expect(
            find.text('Food was not deleted. Please try again.'),
            findsOneWidget,
          );
          expect(await rows(t), hasLength(2));
          provenance(await portion(t));
          await db.execute('DROP TRIGGER authored_meal_refusal');
          await remove();
        }
        expect((await rows(t)).single.id, 'authored-side');
        expect(find.text('Authored oats'), findsNothing);
        await tap(t, find.text('Undo'));
        final restored = await portion(t);
        provenance(restored);
        expect(restored.quantity, original.quantity);
        expect(restored.kcal, original.kcal);
        expect(restored.proteinG, original.proteinG);
        expect(restored.group, original.group);
        expect(find.text('Authored oats'), findsOneWidget);
      },
    );
  }

  testWidgets(
    'a meal date change carries the viewed date and explicit meal into Log food',
    (t) async {
      await open(t);
      await tap(
        t,
        find.byWidgetPredicate(
          (w) => w is Pressable && w.semanticLabel == 'Previous day',
        ),
      );
      expect(t.widget<DayHeader>(find.byType(DayHeader)).date, '2021-04-05');
      expect(find.text('Authored oats'), findsNothing);
      await tap(
        t,
        find.byWidgetPredicate((w) => w is BigButton && w.label == 'Add food'),
      );
      final log = t.widget<LogFoodScreen>(find.byType(LogFoodScreen));
      expect(log.date, '2021-04-05');
      expect(log.meal, 'breakfast');
      await tap(
        t,
        find.byWidgetPredicate(
          (w) => w is Pressable && w.semanticLabel == 'Log Authored oats',
        ),
      );
      final detail = t.widget<FoodDetailSheet>(find.byType(FoodDetailSheet));
      expect(detail.date, '2021-04-05');
      expect(detail.meal, 'breakfast');
      Navigator.of(t.element(find.byType(FoodDetailSheet))).pop();
      await flush(t);
      Navigator.of(t.element(find.byType(LogFoodScreen))).pop();
      await flush(t);
      expect(t.widget<DayHeader>(find.byType(DayHeader)).date, '2021-04-05');
      expect(await rows(t, '2021-04-05'), isEmpty);
      provenance(await portion(t));
    },
  );

  for (final entry in ['page', 'card']) {
    testWidgets(
      '$entry meal menu saves the available portion without deleting unknown history',
      (t) async {
        var reloads = 0;
        final db = await LocalDb.instance;
        await open(
          t,
          child: entry == 'card'
              ? Scaffold(
                  body: SingleChildScrollView(
                    child: MealCard(
                      date: day,
                      meal: 'breakfast',
                      entries: await rows(t),
                      onChanged: () => reloads++,
                    ),
                  ),
                )
              : null,
        );
        if (entry == 'card') {
          await tap(t, find.byTooltip('Breakfast options'));
        } else {
          // This callback awaits a modal choice, so open it with a real gesture.
          final f = find.byWidgetPredicate(
            (w) => w is BigButton && w.label == 'Copy, or save as a meal',
          );
          await tap(t, f);
        }
        await tap(t, find.text('Save meal').last);
        await t.enterText(
          find.byType(TextField).last,
          'Authored saved breakfast',
        );
        await tap(t, find.text('Save').last);
        final saved = (await t.runAsync(() => MyFoods.meals(db)))!.single;
        expect(saved.label, 'Authored saved breakfast');
        expect(saved.meal, 'breakfast');
        expect(saved.items, [('authored-oats', 50.0)]);
        expect(await rows(t), hasLength(2));
        provenance(await portion(t));
        expect(
          (await rows(t)).singleWhere((e) => e.id == 'authored-side').kcal,
          isNull,
        );
        if (entry == 'card') expect(reloads, 1);
      },
    );
  }
}
