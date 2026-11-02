// Historical day quick-log and counting controls through real authored SQLite rows.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/nutrition_store.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/screens/nutrition_screen.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'coverage_nutrition_root_test.dart' show io;
import 'support/localized_coverage.dart';

void main() {
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('food-day-controls');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  const date = '2021-04-07';
  testWidgets(
    'COV-48 refused quick-log Undo leaves the exact entry and explains manual recovery',
    (t) async {
      final db = await LocalDb.instance;
      await NutritionDb.putFoodDef(
        db,
        myFoodDef(
          key: 'my:synthetic',
          label: 'Synthetic oats',
          refGrams: 100,
          unit: 'g',
          kcal: 200,
          protein: 0,
        ),
      );
      await NutritionDb.put(
        db,
        const FoodEntry(
          id: 'synthetic-prior',
          date: '2021-04-06',
          meal: 'lunch',
          label: 'Synthetic oats',
          foodKey: 'my:synthetic',
          quantity: 50,
          unit: 'g',
          kcal: 100,
          proteinG: 0,
          atTs: 1617714000,
          loggedAt: 1617715000,
        ),
      );
      final before = await db.query('food_entry', orderBy: 'id');
      final app = AppState.forTesting()..user = {'kcal_target': 2000};
      addTearDown(app.dispose);
      var changed = 0;
      await localizedPage(
        t,
        Scaffold(
          body: SingleChildScrollView(
            child: NutritionDayView(date: date, onChanged: () => changed++),
          ),
        ),
        app: app,
      );
      final chip = find.byWidgetPredicate(
        (w) =>
            w is Pressable &&
            w.semanticLabel?.startsWith('Log Synthetic oats again') == true,
      );
      await reveal(t, chip);
      await invokeControl(t, t.widget<Pressable>(chip).onTap);
      final saved = (await t.runAsync(
        () => db.query('food_entry', orderBy: 'id'),
      ))!;
      expect(saved, hasLength(2));
      expect(changed, 1);
      final logged = (await t.runAsync(
        () => NutritionDb.entriesForDay(db, date),
      ))!.single;
      expect(logged.quantity, 50);
      expect(logged.kcal, 100);
      expect(logged.proteinG, 0);
      expect(dayLabelAtSec(logged.atTs!), date);
      expect(dayLabelAtSec(logged.loggedAt!), todayLabel());
      await t.runAsync(
        () => db.execute(
          "CREATE TRIGGER authored_undo_refusal BEFORE DELETE ON food_entry BEGIN SELECT RAISE(ABORT,'authored Undo refusal'); END",
        ),
      );
      try {
        // Use the real button gesture: SnackBarAction also hides the old
        // notice. Calling only its user callback bypasses that framework step.
        await t.tap(find.byType(SnackBarAction));
        await io(t);
        expect(
          await t.runAsync(() => db.query('food_entry', orderBy: 'id')),
          saved,
        );
        expect(changed, 1);
        expect(
          find.text(
            'Could not undo: ${logged.label} is still logged. Delete it from the meal instead.',
          ),
          findsOneWidget,
        );
        expect(t.takeException(), isNull);
      } finally {
        await t.runAsync(
          () => db.execute('DROP TRIGGER authored_undo_refusal'),
        );
      }
      // A later explicit removal targets only the new row. The prior meal and
      // its original eaten/logged provenance remain byte-identical.
      await t.runAsync(() => NutritionDb.delete(db, logged.id));
      expect(
        await t.runAsync(() => db.query('food_entry', orderBy: 'id')),
        before,
      );
    },
    timeout: const Timeout(Duration(seconds: 25)),
  );
  for (final refused in [false, true]) {
    testWidgets(
      'COV-44 historical quick log and undo preserve quantity and provenance $refused',
      (t) async {
        final db = await LocalDb.instance;
        final def = myFoodDef(
          key: 'my:synthetic',
          label: 'Synthetic oats',
          refGrams: 100,
          unit: 'g',
          kcal: 200,
          protein: 0,
        );
        await NutritionDb.putFoodDef(db, def);
        await NutritionDb.put(
          db,
          FoodEntry(
            id: 'synthetic-prior',
            date: '2021-04-06',
            meal: 'lunch',
            label: 'Synthetic oats',
            foodKey: 'my:synthetic',
            quantity: 50,
            unit: 'g',
            kcal: 100,
            proteinG: 0,
          ),
        );
        final app = AppState.forTesting()..user = {'kcal_target': 2000};
        addTearDown(app.dispose);
        var changed = 0;
        await localizedPage(
          t,
          Scaffold(
            body: SingleChildScrollView(
              child: NutritionDayView(date: date, onChanged: () => changed++),
            ),
          ),
          app: app,
        );
        final chip = find.byWidgetPredicate(
          (w) =>
              w is Pressable &&
              w.semanticLabel?.startsWith('Log Synthetic oats again') == true,
        );
        await reveal(t, chip);
        if (refused)
          await t.runAsync(
            () => db.execute(
              "CREATE TRIGGER synthetic_quick_refusal BEFORE INSERT ON food_entry BEGIN SELECT RAISE(ABORT,'synthetic quick refusal'); END",
            ),
          );
        await invokeControl(t, t.widget<Pressable>(chip).onTap);
        if (refused) {
          expect(
            await t.runAsync(() => NutritionDb.entriesForDay(db, date)),
            isEmpty,
          );
          expect(find.textContaining('was not added'), findsOneWidget);
          await t.runAsync(
            () => db.execute('DROP TRIGGER synthetic_quick_refusal'),
          );
          await invokeControl(t, t.widget<Pressable>(chip).onTap);
        }
        final entries = (await t.runAsync(
          () => NutritionDb.entriesForDay(db, date),
        ))!;
        expect(entries, hasLength(1));
        final e = entries.single;
        expect(e.quantity, 50);
        expect(e.kcal, 100);
        expect(e.proteinG, 0);
        expect(e.date, date);
        expect(dayLabelAtSec(e.atTs!), date);
        expect(dayLabelAtSec(e.loggedAt!), todayLabel());
        expect(changed, 1);
        await invokeControl(
          t,
          t.widget<SnackBarAction>(find.byType(SnackBarAction)).onPressed,
        );
        expect(
          await t.runAsync(() => NutritionDb.entriesForDay(db, date)),
          isEmpty,
        );
        expect(changed, 2);
      },
      timeout: const Timeout(Duration(seconds: 25)),
    );
    testWidgets(
      'COV-44 historical day mark refuses atomically and undo restores automatic counting $refused',
      (t) async {
        final db = await LocalDb.instance;
        await NutritionDb.put(
          db,
          const FoodEntry(
            id: 'synthetic-dinner',
            date: date,
            meal: 'dinner',
            label: 'Synthetic plate',
            kcal: 1800,
          ),
        );
        final app = AppState.forTesting()..user = {'kcal_target': 2000};
        addTearDown(app.dispose);
        await localizedPage(
          t,
          const Scaffold(
            body: SingleChildScrollView(child: NutritionDayView(date: date)),
          ),
          app: app,
        );
        final action = find.byWidgetPredicate(
          (w) =>
              w is Pressable &&
              (w.semanticLabel == 'Count this day' ||
                  w.semanticLabel == 'Mark complete'),
        );
        await reveal(t, action);
        if (refused)
          await t.runAsync(
            () => db.execute(
              "CREATE TRIGGER synthetic_mark_refusal BEFORE INSERT ON food_day_mark BEGIN SELECT RAISE(ABORT,'synthetic mark refusal'); END",
            ),
          );
        await invokeControl(t, t.widget<Pressable>(action).onTap);
        if (refused) {
          expect(
            (await t.runAsync(() => NutritionDb.dayMarks(db, date)))![date],
            isNull,
          );
          expect(
            find.text('Day status could not be saved. Try again.'),
            findsOneWidget,
          );
          await t.runAsync(
            () => db.execute('DROP TRIGGER synthetic_mark_refusal'),
          );
          await invokeControl(t, t.widget<Pressable>(action).onTap);
        }
        expect(
          (await t.runAsync(() => NutritionDb.dayMarks(db, date)))![date],
          'complete',
        );
        final undo = find.byWidgetPredicate(
          (w) => w is Pressable && w.semanticLabel == 'Undo',
        );
        await reveal(t, undo);
        await invokeControl(t, t.widget<Pressable>(undo).onTap);
        expect(
          (await t.runAsync(() => NutritionDb.dayMarks(db, date)))![date],
          isNull,
        );
      },
      timeout: const Timeout(Duration(seconds: 25)),
    );
  }
}
