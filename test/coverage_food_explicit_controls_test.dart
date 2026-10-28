// Explicit meal/date/time controls; no change to the parked default-meal policy.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/data/nutrition_store.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/screens/food_diary.dart';
import 'package:whoop_companion/ui2/screens/food_picker.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'coverage_food_history_test.dart' show field, flush;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

Finder action(String s) =>
    find.byWidgetPredicate((w) => w is Pressable && w.semanticLabel == s);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState app;
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('food-explicit-controls');
  });
  setUp(() async {
    await resetCoverageStore();
    app = AppState.forTesting()
      ..repo = LocalRepositoryImpl(getProfileMap: () => {})
      ..user = {};
  });
  tearDown(() => app.dispose());
  tearDownAll(LocalDb.close);
  Future<void> tap(WidgetTester t, Finder f) async {
    await reveal(t, f);
    await t.tap(f);
    await flush(t);
  }

  Future<void> save(WidgetTester t) async {
    final f = find.byWidgetPredicate((w) => w is BigButton && w.label == 'Add');
    await reveal(t, f);
    await invokeControl(t, t.widget<BigButton>(f).onTap);
    await flush(t);
  }

  testWidgets(
    'manual meal choice remains authoritative through Quick add and reopening',
    (t) async {
      await localizedPage(
        t,
        const LogFoodScreen(date: '2021-04-06', meal: 'lunch'),
        app: app,
        push: true,
      );
      await flush(t);
      await tap(t, action('Log to Lunch'));
      await tap(t, find.text('Dinner').last);
      expect(action('Log to Dinner'), findsOneWidget);
      await tap(t, find.text('Quick add'));
      expect(
        t.widget<QuickAddSheet>(find.byType(QuickAddSheet)).meal,
        'dinner',
      );
      await t.enterText(field('Name'), 'Synthetic explicit dinner');
      await t.enterText(field('Calories (kcal)'), '120');
      await save(t);
      expect(action('Log to Dinner'), findsOneWidget);
      await tap(t, find.text('Quick add'));
      expect(
        t.widget<QuickAddSheet>(find.byType(QuickAddSheet)).meal,
        'dinner',
      );
      final entries = (await t.runAsync(
        () async =>
            NutritionDb.entriesForDay(await LocalDb.instance, '2021-04-06'),
      ))!;
      expect(entries.single.meal, 'dinner');
      expect(entries.single.label, 'Synthetic explicit dinner');
      expect(entries.single.kcal, 120);
      expect(entries.single.loggedAt, isNotNull);
    },
  );
  for (final changeTime in [false, true]) {
    testWidgets(
      'editing historical Quick add ${changeTime ? 'changes eaten time' : 'keeps an explicitly reselected eaten time'} without changing logging provenance',
      (t) async {
        final db = await LocalDb.instance;
        final at =
            DayClock.onDate('2021-04-06', 12, 15).millisecondsSinceEpoch ~/
            1000;
        final e = FoodEntry(
          id: 'synthetic-edit',
          date: '2021-04-06',
          meal: 'lunch',
          label: 'Synthetic edit',
          atTs: at,
          loggedAt: 1617715000,
          kcal: 120,
          group: 'Original',
        );
        await NutritionDb.put(db, e);
        await localizedPage(
          t,
          QuickAddSheet(date: e.date, meal: e.meal, from: e, editing: true),
          app: app,
          push: true,
        );
        await flush(t);
        await tap(t, action('Dinner'));
        final time = find.byWidgetPredicate(
          (w) =>
              w is Pressable && (w.semanticLabel?.startsWith('Time ') ?? false),
        );
        await tap(t, time);
        Navigator.of(
          t.element(find.byType(TimePickerDialog)),
        ).pop(TimeOfDay(hour: changeTime ? 18 : 12, minute: 15));
        await flush(t);
        final button = find.byWidgetPredicate(
          (w) => w is BigButton && w.label == 'Save changes',
        );
        await reveal(t, button);
        await invokeControl(t, t.widget<BigButton>(button).onTap);
        final saved = (await t.runAsync(
          () => NutritionDb.entriesForDay(db, e.date),
        ))!.single;
        expect(saved.meal, 'dinner');
        expect(saved.group, '');
        expect(
          saved.atTs,
          changeTime
              ? DayClock.onDate(e.date, 18, 15).millisecondsSinceEpoch ~/ 1000
              : e.atTs,
        );
        expect(saved.loggedAt, e.loggedAt);
        expect(saved.id, e.id);
        expect(saved.kcal, e.kcal);
      },
    );
  }
  testWidgets(
    'explicit meal entry links preserve a historical day and refresh after return',
    (t) async {
      var reloads = 0;
      await localizedPage(
        t,
        Scaffold(
          body: MealCard(
            date: '2021-04-06',
            meal: 'breakfast',
            entries: const [],
            onChanged: () => reloads++,
          ),
        ),
        app: app,
      );
      await tap(t, action('Open Breakfast'));
      final meal = t.widget<MealPage>(find.byType(MealPage));
      expect(meal.date, '2021-04-06');
      expect(meal.meal, 'breakfast');
      await tap(t, action('Back').first);
      expect(reloads, 1);
      await tap(t, find.byTooltip('Log Breakfast'));
      final log = t.widget<LogFoodScreen>(find.byType(LogFoodScreen));
      expect(log.date, '2021-04-06');
      expect(log.meal, 'breakfast');
      await tap(t, action('Back'));
      expect(reloads, 2);
    },
  );
  testWidgets(
    'creating a food from an explicit meal can cancel without creating a diary item',
    (t) async {
      await localizedPage(
        t,
        const LogFoodScreen(date: '2021-04-06', meal: 'snack'),
        app: app,
        push: true,
      );
      await flush(t);
      await tap(t, find.text('Create a food'));
      expect(find.byType(FoodEditor), findsOneWidget);
      Navigator.of(t.element(find.byType(FoodEditor))).pop();
      await flush(t);
      expect(find.byType(LogFoodScreen), findsOneWidget);
      expect(t.widget<LogFoodScreen>(find.byType(LogFoodScreen)).meal, 'snack');
      expect(
        (await t.runAsync(
          () async =>
              NutritionDb.entriesForDay(await LocalDb.instance, '2021-04-06'),
        ))!,
        isEmpty,
      );
    },
  );
}
