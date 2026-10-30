// Authored Food-root refresh/calendar/target navigation. No meal-default change.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/nutrition_store.dart';
import 'package:whoop_companion/ui2/screens/food_calendar.dart';
import 'package:whoop_companion/ui2/screens/food_diary.dart' show dayTitle;
import 'package:whoop_companion/ui2/screens/nutrition_screen.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'coverage_food_inputs_test.dart' show TargetsApp, enter, button;
import 'coverage_nutrition_root_test.dart' show io, ago;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

Finder control(String label) =>
    find.byWidgetPredicate((w) => w is Pressable && w.semanticLabel == label);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TargetsApp app;
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('food-root-entrypoints');
  });
  setUp(() async {
    await resetCoverageStore();
    app = TargetsApp()
      ..user = {
        'age': 30,
        'sex': 'f',
        'height_cm': 170,
        'weight_kg': 70,
        'kcal_target': 2000,
        'protein_target': 100,
      };
    await NutritionDb.put(
      await LocalDb.instance,
      FoodEntry(
        id: 'authored-root',
        date: todayLabel(),
        meal: 'lunch',
        label: 'Authored original meal',
        kcal: 400,
      ),
    );
  });
  tearDown(() => app.dispose());
  tearDownAll(LocalDb.close);

  Future<void> open(WidgetTester t) async {
    await localizedPage(
      t,
      const Scaffold(body: NutritionScreen()),
      app: app,
      settle: false,
    );
    await io(t);
  }

  Future<List<Map<String, Object?>>> food(WidgetTester t) async =>
      (await t.runAsync(
        () async => (await LocalDb.instance).query('food_entry', orderBy: 'id'),
      ))!;

  testWidgets(
    'COV-48 Food root refresh rereads silently changed local evidence',
    (t) async {
      await open(t);
      final oldKey = t
          .widget<NutritionDayView>(find.byType(NutritionDayView))
          .key;
      final loads = NutritionScreen.debugLoads;
      final db = await LocalDb.instance;
      // Deliberately no revision publication: the visible pull action must read.
      await t.runAsync(
        () => db.update(
          'food_entry',
          {'label': 'Authored refreshed meal'},
          where: 'id = ?',
          whereArgs: ['authored-root'],
        ),
      );
      final expected = await food(t);
      final refresh = t
          .state<RefreshIndicatorState>(find.byType(RefreshIndicator))
          .show();
      await io(t);
      await refresh;
      await io(t);
      expect(NutritionScreen.debugLoads, greaterThan(loads));
      final view = t.widget<NutritionDayView>(find.byType(NutritionDayView));
      expect(view.date, todayLabel());
      expect(view.key, isNot(oldKey));
      await reveal(t, find.text('Authored refreshed meal'));
      expect(find.text('Authored refreshed meal'), findsOneWidget);
      expect(find.text('Authored original meal'), findsNothing);
      expect(await food(t), expected);
      expect(app.writes, isEmpty);
    },
  );

  testWidgets(
    'COV-48 Food root calendar returns the chosen historical date and cancellation keeps it',
    (t) async {
      await open(t);
      final original = await food(t);
      Future<void> calendar() async {
        await t.tap(
          find.byWidgetPredicate(
            (w) =>
                w is Pressable &&
                (w.semanticLabel?.endsWith('. Choose a day') ?? false),
          ),
        );
        await io(t);
        expect(find.byType(FoodCalendar), findsOneWidget);
      }

      await calendar();
      final target = ago(1);
      if (target.substring(0, 7) != todayLabel().substring(0, 7)) {
        await t.tap(find.byTooltip('Previous month'));
        await io(t);
      }
      await t.tap(
        find.descendant(
          of: find.byType(FoodCalendar),
          matching: find.byWidgetPredicate(
            (w) =>
                w is Pressable &&
                  w.semanticLabel == dayTitle(target),
          ),
        ),
      );
      await io(t);
      expect(
        t.widget<NutritionDayView>(find.byType(NutritionDayView)).date,
        target,
      );
      expect(find.text('Back to today'), findsOneWidget);
      await calendar();
      await t.binding.handlePopRoute();
      await io(t);
      expect(find.byType(FoodCalendar), findsNothing);
      expect(
        t.widget<NutritionDayView>(find.byType(NutritionDayView)).date,
        target,
      );
      expect(await food(t), original);
      expect(app.writes, isEmpty);
    },
  );

  for (final save in [false, true]) {
    testWidgets(
      'COV-48 Food root goals ${save ? 'save reloads the explicit target' : 'cancel keeps profile and selected day'}',
      (t) async {
        await open(t);
        final original = await food(t);
        final user = Map<String, dynamic>.of(app.user!);
        final swipe = t.widget<Swipe>(
          find.byWidgetPredicate((w) => w is Swipe && w.label == 'Day'),
        );
        swipe.onPrevious!();
        await io(t);
        final day = ago(1);
        await t.tap(control('Goals'));
        await io(t);
        expect(find.text('Daily targets'), findsOneWidget);
        if (save) {
          await enter(t, 'Calories (kcal)', '2100.5');
          await button(t, 'Save');
        } else {
          await t.binding.handlePopRoute();
        }
        await io(t);
        expect(find.text('Daily targets'), findsNothing);
        final view = t.widget<NutritionDayView>(find.byType(NutritionDayView));
        expect(view.date, day);
        expect(
          t.widget<CalorieCard>(find.byType(CalorieCard)).goal,
          save ? 2100.5 : 2000,
        );
        if (save) {
          expect(app.writes, hasLength(1));
          expect(app.writes.single['kcal_target'], 2100.5);
          expect(app.user!['protein_target'], user['protein_target']);
        } else {
          expect(app.writes, isEmpty);
          expect(app.user, user);
        }
        expect(await food(t), original);
      },
    );
  }
}
