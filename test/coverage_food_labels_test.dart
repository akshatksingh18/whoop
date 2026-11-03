// Actual Food -> Foods -> Labels dialogs against synthetic persistent data.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/nutrition_store.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/state/prefs.dart';
import 'package:whoop_companion/ui2/screens/nutrition_screen.dart';
import 'package:whoop_companion/ui2/screens/food_diary.dart' show askText;
import 'package:whoop_companion/ui2/ui2.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/audit_visual.dart' show loadAuditFonts;

Finder action(String text) =>
    find.byWidgetPredicate((w) => w is Pressable && w.semanticLabel == text);

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 15; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await t.pump(const Duration(milliseconds: 30));
  }
  await t.pumpAndSettle();
  expect(t.takeException(), isNull);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late AppState app;
  late List<Map<String, Object?>> diary;
  setUpAll(() async {
    await loadAuditFonts();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    final root = (await Directory(
      'build/coverage-remainder/food-labels',
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
    app = AppState.forTesting()..user = {'kcal_target': 2200};
    for (final (key, label, category) in [
      ('one', 'Synthetic oats', 'Breakfast'),
      ('two', 'Synthetic toast', 'Breakfast'),
      ('three', 'Synthetic rice', 'Lunch'),
      ('four', 'Synthetic fruit', ''),
    ]) {
      await NutritionDb.putFoodDef(
        db,
        myFoodDef(
          key: key,
          label: label,
          refGrams: 100,
          kcal: 80,
          category: category,
        ),
      );
    }
    await NutritionDb.put(
      db,
      const FoodEntry(
        id: 'synthetic-historical-entry',
        date: '2026-01-02',
        meal: 'breakfast',
        label: 'Synthetic oats',
        foodKey: 'one',
        quantity: 100,
        kcal: 80,
        proteinG: 4,
        confirmed: true,
      ),
    );
    diary = await db.query('food_entry');
  });
  tearDown(() async {
    await db.execute('DROP TRIGGER IF EXISTS refuse_synthetic_label');
    app.dispose();
  });
  tearDownAll(LocalDb.close);

  testWidgets(
    'other text prompts still require input unless explicitly optional',
    (t) async {
      String? answer;
      await t.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light),
          home: Scaffold(
            body: Builder(
              builder: (c) => TextButton(
                onPressed: () async =>
                    answer = await askText(c, 'Save meal', 'Name', ''),
                child: const Text('Open prompt'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('Open prompt'));
      await settle(t);
      await t.tap(find.text('Save').last);
      await settle(t);
      expect(find.text('Enter Name.'), findsOneWidget);
      expect(answer, isNull);
      await t.enterText(find.byType(TextField).last, '  Synthetic meal  ');
      await t.tap(find.text('Save').last);
      await settle(t);
      expect(answer, 'Synthetic meal');
    },
  );

  Future<void> open(WidgetTester t, {double scale = 1}) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    addTearDown(() async {
      await t.pumpWidget(const SizedBox());
      await settle(t);
    });
    await t.pumpWidget(
      ChangeNotifierProvider.value(
        value: app,
        child: MaterialApp(
          theme: buildTheme(Brightness.light),
          builder: (c, child) => MediaQuery(
            data: MediaQuery.of(
              c,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: const Scaffold(body: NutritionScreen()),
        ),
      ),
    );
    await settle(t);
    await t.ensureVisible(find.text('Foods'));
    await t.pumpAndSettle();
    await t.tap(find.text('Foods'));
    await settle(t);
  }

  Future<void> manage(WidgetTester t) async {
    await t.ensureVisible(action('Manage labels'));
    await t.pumpAndSettle();
    await t.tap(action('Manage labels'));
    await settle(t);
    expect(find.byTooltip('Rename Breakfast'), findsOneWidget);
  }

  Future<void> rename(WidgetTester t, String target) async {
    await manage(t);
    await t.ensureVisible(find.byTooltip('Rename Breakfast'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Rename Breakfast'));
    await settle(t);
    expect(find.text('Rename Breakfast'), findsOneWidget);
    await t.enterText(find.byType(TextField).last, target);
    await t.ensureVisible(find.text('Save').last);
    await t.pumpAndSettle();
    await t.tap(find.text('Save').last);
    await settle(t);
  }

  Future<Map<String, Object?>> categories(WidgetTester t) async => {
    for (final row in (await t.runAsync(() => db.query('food_def')))!)
      row['key'] as String: row['category'],
  };

  Future<void> unchangedDiary(WidgetTester t) async {
    expect(await t.runAsync(() => db.query('food_entry')), diary);
    expect(await t.runAsync(() => db.query('food_def')), hasLength(4));
  }

  for (final target in ['Morning', 'lUnCh', '']) {
    testWidgets(
      'renaming Breakfast to ${target.isEmpty ? 'empty' : target} preserves foods and diary',
      (t) async {
        await open(t);
        await rename(t, target);
        expect(find.text('Rename Breakfast'), findsNothing);
        final now = await categories(t);
        expect(now['one'], target == 'lUnCh' ? 'Lunch' : target);
        expect(now['two'], now['one']);
        expect(now['three'], 'Lunch');
        expect(now['four'], '');
        await unchangedDiary(t);
      },
    );
  }

  for (final confirm in [false, true]) {
    testWidgets(
      'label bin ${confirm ? 'removes the category' : 'can cancel'} without deleting foods',
      (t) async {
        await open(t);
        await manage(t);
        await t.tap(find.byTooltip('Remove Breakfast'));
        await settle(t);
        expect(find.text('Remove "Breakfast"?'), findsOneWidget);
        await t.tap(find.text(confirm ? 'Remove' : 'Keep it').last);
        await settle(t);
        expect((await categories(t))['one'], confirm ? '' : 'Breakfast');
        await unchangedDiary(t);
      },
    );
  }

  testWidgets(
    'cancel the rename prompt keeps both categories and allows reopening',
    (t) async {
      await open(t);
      await manage(t);
      await t.tap(find.byTooltip('Rename Breakfast'));
      await settle(t);
      await t.enterText(find.byType(TextField).last, 'Discarded draft');
      Navigator.of(t.element(find.byType(TextField).last)).pop();
      await settle(t);
      expect((await categories(t))['one'], 'Breakfast');
      await manage(t);
      await t.tap(find.byTooltip('Rename Breakfast'));
      await settle(t);
      expect(
        t.widget<TextField>(find.byType(TextField).last).controller!.text,
        'Breakfast',
      );
    },
  );

  testWidgets(
    'label length validation preserves input, then a valid rename retries',
    (t) async {
      await open(t);
      await rename(t, 'x' * 31);
      expect(find.text('Use 30 characters or fewer.'), findsOneWidget);
      expect((await categories(t))['one'], 'Breakfast');
      await t.enterText(find.byType(TextField).last, 'Morning');
      await t.tap(find.text('Save').last);
      await settle(t);
      expect((await categories(t))['one'], 'Morning');
    },
  );

  testWidgets('refused rename rolls back all foods and the library can retry', (
    t,
  ) async {
    await db.execute(
      "CREATE TRIGGER refuse_synthetic_label BEFORE UPDATE ON food_def WHEN NEW.key='two' BEGIN SELECT RAISE(ABORT,'synthetic label refusal'); END",
    );
    await open(t);
    await rename(t, 'Morning');
    expect(
      find.text('Could not change your saved food. Please try again.'),
      findsOneWidget,
    );
    expect((await categories(t))['one'], 'Breakfast');
    expect((await categories(t))['two'], 'Breakfast');
    await t.runAsync(() => db.execute('DROP TRIGGER refuse_synthetic_label'));
    await rename(t, 'Morning');
    expect((await categories(t))['one'], 'Morning');
    await unchangedDiary(t);
  });

  for (final scale in [2.0, 3.1]) {
    testWidgets(
      'label picker and rename actions remain reachable at ${scale}x',
      (t) async {
        await open(t, scale: scale);
        await rename(t, 'Morning');
        expect((await categories(t))['one'], 'Morning');
        expect(t.takeException(), isNull);
      },
    );
  }
}
