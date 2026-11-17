// Saved-meal composition and review through real sheets/SQLite, synthetic only.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/nutrition_store.dart';
import 'package:whoop_companion/state/prefs.dart';
import 'package:whoop_companion/ui2/screens/food_picker.dart';
import 'package:whoop_companion/ui2/screens/journal_compose.dart'
    show WhoopTextField;
import 'package:whoop_companion/ui2/ui2.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'support/audit_visual.dart' show loadAuditFonts;

Finder field(String name) => find.descendant(
  of: find.byWidgetPredicate((w) => w is WhoopTextField && w.label == name),
  matching: find.byType(TextField),
);
Finder action(String name) =>
    find.byWidgetPredicate((w) => w is Pressable && w.semanticLabel == name);
Future<void> flush(WidgetTester t) async {
  for (var i = 0; i < 15; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await t.pump(const Duration(milliseconds: 30));
  }
  await t.pumpAndSettle();
  expect(t.takeException(), isNull);
}

Future<void> tap(WidgetTester t, Finder target) async {
  // Let the field's deferred focus/scroll request finish before scrolling
  // elsewhere, as it would while the person finishes typing.
  await flush(t);
  await t.ensureVisible(target);
  await t.pumpAndSettle();
  await t.tap(target);
  await flush(t);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  bool? saved;
  setUpAll(() async {
    await loadAuditFonts();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    final root = (await Directory(
      'build/coverage-remainder/saved-meals',
    ).create(recursive: true)).absolute;
    LocalDb.dbName = '${root.path}/synthetic.sqlite';
    await LocalDb.close();
    await databaseFactory.deleteDatabase(LocalDb.dbName);
    db = await LocalDb.instance;
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.ensureLoaded();
    await LocalDb.wipeAll();
    saved = null;
    for (final (key, name, category) in [
      ('one', 'Synthetic oats', 'Breakfast'),
      ('two', 'Synthetic rice', 'Lunch'),
    ]) {
      await NutritionDb.putFoodDef(
        db,
        myFoodDef(
          key: key,
          label: name,
          category: category,
          refGrams: 100,
          kcal: 200,
          protein: 10,
        ),
      );
    }
  });
  tearDown(() => db.execute('DROP TRIGGER IF EXISTS refuse_synthetic_meal'));
  tearDownAll(LocalDb.close);

  Future<void> open(
    WidgetTester t, {
    MealTemplate? existing,
    double scale = 1,
  }) async {
    t.view.physicalSize = const Size(390, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        builder: (c, w) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
          child: w!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (c) => TextButton(
              onPressed: () async =>
                  saved = await MealEditor.show(c, existing: existing),
              child: const Text('Open editor'),
            ),
          ),
        ),
      ),
    );
    await tap(t, find.text('Open editor'));
    addTearDown(() async {
      await t.pumpWidget(const SizedBox());
      await flush(t);
    });
  }

  Future<List<MealTemplate>> meals(WidgetTester t) async =>
      (await t.runAsync(() => MyFoods.meals(db)))!;
  Future<void> addOats(WidgetTester t) async {
    await tap(t, find.text('Add a food'));
    await tap(t, find.text('Synthetic oats'));
    // GramsSheet must commit the portion explicitly before the picker adds it.
    await tap(t, find.text('Add').last);
    await tap(t, find.text('Done · 1 added'));
  }

  testWidgets(
    'name and at least one item are both required, then the same draft saves',
    (t) async {
      await open(t);
      await tap(t, find.text('Save').last);
      expect(
        find.text('Enter a name and add at least one food.'),
        findsOneWidget,
      );
      await t.enterText(field('Name'), '  Synthetic breakfast  ');
      await tap(t, find.text('Save').last);
      expect(await meals(t), isEmpty);
      await addOats(t);
      await tap(t, action('Lunch'));
      await tap(t, find.text('Save').last);
      expect(saved, isTrue);
      final m = (await meals(t)).single;
      expect(m.label, 'Synthetic breakfast');
      expect(m.meal, 'lunch');
      expect(m.items, [('one', 100.0)]);
      expect(m.units, {'one': 'g'});
      expect(
        await t.runAsync(() => db.query('food_entry')),
        isEmpty,
        reason: 'Saving a template is not logging food',
      );
    },
  );

  testWidgets('food picker search never adds hidden foods', (t) async {
    await open(t);
    await t.enterText(field('Name'), 'Synthetic filter');
    await tap(t, find.text('Add a food'));
    await t.enterText(field('Search'), 'not present');
    await t.pumpAndSettle();
    expect(find.text('No matches'), findsOneWidget);
    await t.enterText(field('Search'), 'rice');
    await t.pumpAndSettle();
    expect(find.text('Synthetic oats'), findsNothing);
    await tap(t, find.text('Synthetic rice'));
    await tap(t, find.text('Add').last);
    await tap(t, find.text('Done · 1 added'));
    await tap(t, find.text('Save').last);
    expect((await meals(t)).single.items, [('two', 100.0)]);
  });

  testWidgets('refused template write retains the edited draft and can retry', (
    t,
  ) async {
    await db.execute(
      "CREATE TRIGGER refuse_synthetic_meal BEFORE INSERT ON meal_template BEGIN SELECT RAISE(ABORT,'synthetic refusal'); END",
    );
    await open(t);
    await t.enterText(field('Name'), 'Synthetic retry');
    await addOats(t);
    await tap(t, find.text('Save').last);
    expect(
      find.text('Could not save. Your meal is still here; try again.'),
      findsOneWidget,
    );
    expect(
      t.widget<TextField>(field('Name')).controller!.text,
      'Synthetic retry',
    );
    expect(await meals(t), isEmpty);
    await t.runAsync(() => db.execute('DROP TRIGGER refuse_synthetic_meal'));
    await tap(t, find.text('Save').last);
    expect((await meals(t)).single.items, [('one', 100.0)]);
    expect(saved, isTrue);
  });

  testWidgets(
    'editing a portion and heading reorders grouped items without losing the other food',
    (t) async {
      const old = MealTemplate(
        key: 'existing',
        label: 'Synthetic grouped',
        meal: 'breakfast',
        items: [('one', 50), ('two', 100)],
        units: {'one': 'g', 'two': 'g'},
        groups: ['', 'Bowl'],
      );
      await MyFoods.putMeal(db, old);
      await open(t, existing: old);
      await tap(t, find.text('Synthetic oats'));
      await t.enterText(find.byType(TextField).last, '75');
      await tap(t, find.text('Sub-heading').last);
      await tap(t, find.text('Bowl').last);
      await tap(t, find.text('Done').last);
      await tap(t, find.text('Save').last);
      final m = (await meals(t)).single;
      expect(m.key, 'existing');
      expect(m.items.toSet(), {('one', 75.0), ('two', 100.0)});
      expect(m.groups, ['Bowl', 'Bowl']);
      expect(m.units, {'one': 'g', 'two': 'g'});
    },
  );

  testWidgets(
    'a deleted library food stays disclosed in the editor, not silently priced as zero',
    (t) async {
      const old = MealTemplate(
        key: 'existing',
        label: 'Synthetic retained',
        meal: 'breakfast',
        items: [('gone', 25), ('one', 50)],
      );
      await MyFoods.putMeal(db, old);
      await open(t, existing: old);
      expect(find.text('Deleted food'), findsOneWidget);
      expect(find.textContaining('At least'), findsOneWidget);
      await tap(t, find.text('Save').last);
      expect((await meals(t)).single.items, old.items);
    },
  );

  for (final scale in [2.0, 3.1]) {
    testWidgets('existing template can be renamed and saved at ${scale}x', (
      t,
    ) async {
      const old = MealTemplate(
        key: 'existing',
        label: 'Synthetic old',
        meal: 'breakfast',
        items: [('one', 50)],
      );
      await MyFoods.putMeal(db, old);
      await open(t, existing: old, scale: scale);
      await t.enterText(field('Name'), 'Synthetic new');
      await tap(t, find.text('Save').last);
      expect((await meals(t)).single.label, 'Synthetic new');
      expect(saved, isTrue);
    });
  }
}
