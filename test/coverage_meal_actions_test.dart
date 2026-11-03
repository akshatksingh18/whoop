// Meal copy/save workflows use the actual sheets and synthetic SQLite entries.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/nutrition_store.dart';
import 'package:whoop_companion/state/prefs.dart';
import 'package:whoop_companion/ui2/screens/food_diary.dart';
import 'package:whoop_companion/ui2/screens/journal_compose.dart'
    show WhoopTextField;
import 'package:whoop_companion/ui2/ui2.dart';

Future<void> flush(WidgetTester t) async {
  for (var i = 0; i < 12; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await t.pump(const Duration(milliseconds: 40));
  }
  await t.pumpAndSettle();
  expect(t.takeException(), isNull);
}

Finder field(String label) => find.descendant(
  of: find.byWidgetPredicate((w) => w is WhoopTextField && w.label == label),
  matching: find.byType(TextField),
);
Finder press(String label) =>
    find.byWidgetPredicate((w) => w is Pressable && w.semanticLabel == label);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late String today, yesterday;
  late FoodEntry own, quick;
  var changes = 0;
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final root = await Directory(
      'build/coverage-expansion/meals',
    ).create(recursive: true);
    LocalDb.dbName = '${root.absolute.path}/synthetic.sqlite';
    await LocalDb.close();
    await databaseFactory.deleteDatabase(LocalDb.dbName);
    db = await LocalDb.instance;
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.ensureLoaded();
    await LocalDb.wipeAll();
    DayClock.install([], []);
    today = todayLabel();
    yesterday = shiftDay(today, -1);
    changes = 0;
    await NutritionDb.putFoodDef(db, {
      'key': 'synthetic-oats',
      'label': 'Synthetic oats',
      'unit': 'g',
      'kcal_100': 200.0,
      'protein_g_100': 10.0,
      'source': 'manual',
    });
    own = FoodEntry(
      id: 'own',
      date: yesterday,
      meal: 'breakfast',
      label: 'Synthetic oats',
      foodKey: 'synthetic-oats',
      quantity: 50,
      unit: 'g',
      kcal: 100,
      proteinG: 5,
      group: 'Synthetic bowl',
      atTs:
          DateTime.parse(
            yesterday,
          ).add(const Duration(hours: 8)).millisecondsSinceEpoch ~/
          1000,
    );
    quick = FoodEntry(
      id: 'quick',
      date: yesterday,
      meal: 'breakfast',
      label: 'Synthetic quick add',
      kcal: 50,
    );
    await NutritionDb.put(db, own);
    await NutritionDb.put(db, quick);
  });
  tearDown(() async {
    await db.execute('DROP TRIGGER IF EXISTS synthetic_food_refusal');
  });
  tearDownAll(LocalDb.close);
  Future<void> open(
    WidgetTester t, {
    String? date,
    List<FoodEntry>? entries,
  }) async {
    t.view.physicalSize = const Size(430, 1500);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(
          body: Builder(
            builder: (c) => TextButton(
              onPressed: () => mealMenu(
                c,
                date ?? today,
                'breakfast',
                entries ?? [own, quick],
                () => changes++,
              ),
              child: const Text('Meal options'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('Meal options'));
    await flush(t);
  }

  Future<void> done(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await flush(t);
  }

  Future<void> choose(WidgetTester t, String value) async {
    await t.ensureVisible(find.text(value).last);
    await t.tap(find.text(value).last);
    await flush(t);
  }

  testWidgets(
    'copy from previews the selected meal and writes new IDs on the viewed day',
    (t) async {
      await open(t, entries: []);
      await choose(t, 'Copy from');
      expect(find.textContaining('2 items'), findsWidgets);
      await choose(t, 'Copy from');
      final copied = (await t.runAsync(
        () => NutritionDb.entriesForDay(db, today),
      ))!;
      expect(copied, hasLength(2));
      expect(copied.map((e) => e.id), isNot(contains('own')));
      expect(copied.map((e) => e.kcal).reduce((a, b) => a! + b!), 150);
      expect(copied.every((e) => e.meal == 'breakfast'), isTrue);
      expect(
        copied.firstWhere((e) => e.foodKey != null).group,
        'Synthetic bowl',
      );
      expect(changes, 1);
      expect(find.text('Copied 2 items'), findsOneWidget);
      expect(
        (await t.runAsync(() => NutritionDb.entriesForDay(db, yesterday)))!,
        hasLength(2),
      );
      await done(t);
    },
  );
  testWidgets(
    'copy to changes the target meal without mutating source portions',
    (t) async {
      await open(t, date: yesterday);
      await choose(t, 'Copy to');
      await t.tap(press('Lunch'));
      await t.pump();
      await choose(t, 'Copy to');
      final copied = (await t.runAsync(
        () => NutritionDb.entriesForDay(db, today),
      ))!;
      expect(copied, hasLength(2));
      expect(copied.every((e) => e.meal == 'lunch'), isTrue);
      final source = (await t.runAsync(
        () => NutritionDb.entriesForDay(db, yesterday),
      ))!;
      expect(source.firstWhere((e) => e.id == 'own').quantity, 50);
      expect(changes, 1);
      expect(find.textContaining('Copied 2 items to Lunch'), findsOneWidget);
      await done(t);
    },
  );
  testWidgets(
    'an empty source meal explains the absence and disables copying',
    (t) async {
      await open(t);
      await choose(t, 'Copy from');
      await t.tap(press('Dinner'));
      await t.pump();
      expect(find.text('Nothing in Dinner that day'), findsOneWidget);
      expect(
        t
            .widget<BigButton>(
              find.byWidgetPredicate(
                (w) => w is BigButton && w.label == 'Copy from',
              ),
            )
            .onTap,
        isNull,
      );
      expect(
        (await t.runAsync(() => NutritionDb.entriesForDay(db, today)))!,
        isEmpty,
      );
      await done(t);
    },
  );
  testWidgets('refused copy rolls back all items and permits a clean retry', (
    t,
  ) async {
    await t.runAsync(
      () => db.execute(
        "CREATE TEMP TRIGGER synthetic_food_refusal BEFORE INSERT ON food_entry WHEN NEW.date = '$today' BEGIN SELECT RAISE(ABORT, 'synthetic food refusal'); END",
      ),
    );
    await open(t);
    await choose(t, 'Copy from');
    await choose(t, 'Copy from');
    expect(
      find.text('That did not complete. Please try again.'),
      findsOneWidget,
    );
    expect(
      (await t.runAsync(() => NutritionDb.entriesForDay(db, today)))!,
      isEmpty,
    );
    expect(changes, 0);
    await t.runAsync(() => db.execute('DROP TRIGGER synthetic_food_refusal'));
    await t.tap(find.text('Meal options'));
    await flush(t);
    await choose(t, 'Copy from');
    await choose(t, 'Copy from');
    expect(
      (await t.runAsync(() => NutritionDb.entriesForDay(db, today)))!,
      hasLength(2),
    );
    expect(changes, 1);
    await done(t);
  });
  testWidgets('save meal validates its name and discloses skipped quick adds', (
    t,
  ) async {
    await open(t, date: yesterday);
    await choose(t, 'Save meal');
    await t.enterText(field('Name'), ' ');
    await choose(t, 'Save');
    expect(find.text('Enter Name.'), findsOneWidget);
    expect((await t.runAsync(() => MyFoods.meals(db)))!, isEmpty);
    await t.enterText(field('Name'), ' Synthetic bowl ');
    await choose(t, 'Save');
    final meals = (await t.runAsync(() => MyFoods.meals(db)))!;
    expect(meals, hasLength(1));
    expect(meals.single.label, 'Synthetic bowl');
    expect(meals.single.items.single, ('synthetic-oats', 50.0));
    expect(find.textContaining('1 left out'), findsOneWidget);
    expect(changes, 1);
    await done(t);
  });
  testWidgets('quick adds alone do not create an empty saved meal', (t) async {
    await open(t, date: yesterday, entries: [quick]);
    await choose(t, 'Save meal');
    await choose(t, 'Save');
    expect((await t.runAsync(() => MyFoods.meals(db)))!, isEmpty);
    expect(
      find.text('Only your own foods can go in a saved meal'),
      findsOneWidget,
    );
    await done(t);
  });
  testWidgets('closing the menu writes nothing and does not publish a change', (
    t,
  ) async {
    await open(t);
    await t.tapAt(const Offset(5, 5));
    await flush(t);
    expect(changes, 0);
    expect(
      (await t.runAsync(() => NutritionDb.entriesForDay(db, today)))!,
      isEmpty,
    );
    await done(t);
  });
  testWidgets(
    'meal page displays partial totals and opens an editable entry without changing it',
    (t) async {
      t.view.physicalSize = const Size(430, 1600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light),
          home: MealPage(date: yesterday, meal: 'breakfast'),
        ),
      );
      await flush(t);
      expect(find.text('Synthetic oats'), findsOneWidget);
      await t.tap(find.text('Synthetic quick add'));
      await flush(t);
      expect(find.text('Edit entry'), findsOneWidget);
      await choose(t, 'Edit entry');
      expect(find.byType(QuickAddSheet), findsOneWidget);
      expect(
        (await t.runAsync(() => NutritionDb.entriesForDay(db, yesterday)))!,
        hasLength(2),
      );
      await done(t);
    },
  );
}
