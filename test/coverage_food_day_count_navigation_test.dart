// Real profile hydration/counting policy, historical Food actions and Back ownership.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/nutrition_store.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/screens/food_diary.dart';
import 'package:whoop_companion/ui2/screens/nutrition_screen.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'coverage_nutrition_root_test.dart' show FoodRepo, io;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

const day = '2021-04-06';
Finder action(String label) =>
    find.byWidgetPredicate((w) => w is Pressable && w.semanticLabel == label);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState app;
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('food-day-count-navigation', fresh: true);
  });
  setUp(() async {
    await resetCoverageStore();
    app = AppState.forTesting()..repo = FoodRepo();
    // Use the real profile command to establish the shared counting goal.
    await app.updateProfile({'kcal_target': 2000});
    await NutritionDb.put(
      await LocalDb.instance,
      const FoodEntry(
        id: 'authored-counted-dinner',
        date: day,
        meal: 'dinner',
        label: 'Authored retained dinner',
        kcal: 1800,
        proteinG: 0,
        atTs: 1617742800,
        loggedAt: 1617829200,
      ),
    );
  });
  tearDown(() => app.dispose());
  tearDownAll(LocalDb.close);
  Future<void> open(WidgetTester t, double scale) async {
    await localizedPage(
      t,
      const Scaffold(
        body: SingleChildScrollView(child: NutritionDayView(date: day)),
      ),
      app: app,
      scale: scale,
      settle: false,
    );
    await io(t);
  }

  Future<void> press(WidgetTester t, Finder f) async {
    await reveal(t, f);
    await t.tap(f);
    await io(t);
  }

  for (final scale in [1.0, 3.1]) {
    for (final refused in [false, true]) {
      testWidgets(
        'automatic counted day Missing food/Undo refusal=$refused scale=$scale keeps the frozen goal and diary',
        (t) async {
          final db = (await t.runAsync(() => LocalDb.instance))!;
          await open(t, scale);
          final diary = await t.runAsync(() => db.query('food_entry'));
          final basis = (await t.runAsync(() => db.query('food_day_count')))!;
          expect(basis.single['calorie_goal'], 2000);
          expect(basis.single['basis'], 'automatic');
          expect(basis.single['counted'], 1);
          expect(
            (await readPage(t)).join(' '),
            contains('Counted automatically'),
          );
          if (refused) {
            await t.runAsync(
              () => db.execute(
                "CREATE TRIGGER authored_missing_food_refusal BEFORE INSERT ON food_day_mark BEGIN SELECT RAISE(ABORT,'authored missing-food refusal'); END",
              ),
            );
            try {
              await press(t, action('Missing food'));
              expect(
                find.text('Day status could not be saved. Try again.'),
                findsOneWidget,
              );
              expect(await t.runAsync(() => db.query('food_day_count')), basis);
              expect(
                await t.runAsync(() => db.query('food_day_mark')),
                isEmpty,
              );
            } finally {
              await t.runAsync(
                () => db.execute('DROP TRIGGER authored_missing_food_refusal'),
              );
            }
          }
          await press(t, action('Missing food'));
          expect(
            (await t.runAsync(() => NutritionDb.dayMarks(db, day)))![day],
            'incomplete',
          );
          expect(
            (await readPage(t)).join(' '),
            contains('Marked as missing food'),
          );
          final missing = (await t.runAsync(() => db.query('food_day_count')))!;
          expect(missing.single['calorie_goal'], 2000);
          expect(missing.single['frozen_at'], basis.single['frozen_at']);
          expect(missing.single['counted'], 0);
          await press(t, action('Undo'));
          expect(
            (await t.runAsync(() => NutritionDb.dayMarks(db, day)))![day],
            isNull,
          );
          expect(
            (await readPage(t)).join(' '),
            contains('Counted automatically'),
          );
          final restored = (await t.runAsync(
            () => db.query('food_day_count'),
          ))!;
          expect(restored.single['calorie_goal'], 2000);
          expect(restored.single['frozen_at'], basis.single['frozen_at']);
          expect(restored.single['basis'], 'automatic');
          expect(restored.single['counted'], 1);
          expect(await t.runAsync(() => db.query('food_entry')), diary);
          expect(app.user!['kcal_target'], 2000);
        },
      );
    }
    testWidgets(
      'historical calorie-card and Food progress links return to the same day scale=$scale',
      (t) async {
        final db = (await t.runAsync(() => LocalDb.instance))!;
        await open(t, scale);
        final diary = await t.runAsync(() => db.query('food_entry'));
        await press(t, action('View food for the day'));
        expect(find.byType(DayFoodPage), findsOneWidget);
        expect(t.widget<DayFoodPage>(find.byType(DayFoodPage)).date, day);
        expect(
          (await readPage(t)).join(' '),
          contains('Authored retained dinner'),
        );
        Navigator.of(t.element(find.byType(DayFoodPage))).pop();
        await io(t);
        expect(
          t.widget<NutritionDayView>(find.byType(NutritionDayView)).date,
          day,
        );
        await press(t, find.text('Food progress'));
        expect(
          (await readPage(t)).join(' '),
          contains('Food, training and recovery'),
        );
        final route = find.text('Food, training and recovery').first;
        Navigator.of(t.element(route)).pop();
        await io(t);
        expect(
          t.widget<NutritionDayView>(find.byType(NutritionDayView)).date,
          day,
        );
        expect(
          (await readPage(t)).join(' '),
          contains('Counted automatically'),
        );
        expect(await t.runAsync(() => db.query('food_entry')), diary);
        expect(app.user!['kcal_target'], 2000);
        expect(t.takeException(), isNull);
      },
    );
  }
}
