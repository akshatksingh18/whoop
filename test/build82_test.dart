// Build 82: drag lists scroll their page (build81_test), sheets ask before
// discarding typed values, Foods search, and the saved-meal flow (picker
// with search and multi-add, one unit per food, review → edit, kcal rows).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/nutrition_store.dart';
import 'package:openstrap_edge/ui2/grammar.dart' show Pressable;
import 'package:openstrap_edge/ui2/screens/food_diary.dart' show QuickAddSheet;
import 'package:openstrap_edge/ui2/screens/food_picker.dart';
import 'package:openstrap_edge/ui2/screens/journal_compose.dart'
    show OsTextField;
import 'package:openstrap_edge/ui2/theme.dart';

Finder _field(String label) => find.descendant(
  of: find.byWidgetPredicate((w) => w is OsTextField && w.label == label),
  matching: find.byType(TextField),
);

final _close = find.byWidgetPredicate(
  (w) => w is Pressable && w.semanticLabel == 'Close',
);

Future<void> _host(WidgetTester t, void Function(BuildContext) open) async {
  t.view.physicalSize = const Size(390, 1400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Scaffold(
        body: Builder(
          builder: (c) => TextButton(
            onPressed: () => open(c),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.text('Open'));
  await t.pumpAndSettle();
}

Future<void> _settle(WidgetTester t, [int frames = 40]) async {
  for (var i = 0; i < frames; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await t.pump(const Duration(milliseconds: 30));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;

  final eggs = myFoodDef(
    key: 'my:eggs',
    label: 'Eggs',
    refGrams: 1,
    unit: 'egg',
    kcal: 70,
    protein: 6,
    measures: [(label: 'g', amount: 1 / 50)],
  );
  final oats = myFoodDef(
    key: 'my:oats',
    label: 'Oats',
    refGrams: 40,
    kcal: 150,
    protein: 5,
  );

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.dbName = 'build82.db';
    await databaseFactory.deleteDatabase(
      path.join(await databaseFactory.getDatabasesPath(), LocalDb.dbName),
    );
    db = await LocalDb.instance;
    await NutritionDb.putFoodDef(db, eggs);
    await NutritionDb.putFoodDef(db, oats);
  });
  tearDownAll(() async {
    await LocalDb.close();
    await databaseFactory.deleteDatabase(
      path.join(await databaseFactory.getDatabasesPath(), LocalDb.dbName),
    );
  });

  group('a sheet asks before discarding what was typed', () {
    testWidgets('untouched closes at once', (t) async {
      await _host(
        t,
        (c) => QuickAddSheet.show(c, date: '2026-10-07', meal: 'snack'),
      );
      await t.tap(_close);
      await t.pumpAndSettle();
      expect(find.byType(QuickAddSheet), findsNothing);
      expect(find.text('Discard changes?'), findsNothing);
    });

    testWidgets('typed: Keep editing stays, Discard leaves', (t) async {
      await _host(
        t,
        (c) => QuickAddSheet.show(c, date: '2026-10-07', meal: 'snack'),
      );
      await t.enterText(_field('Calories (kcal)'), '300');
      await t.tap(_close);
      await t.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);
      await t.tap(find.text('Keep editing'));
      await t.pumpAndSettle();
      expect(find.byType(QuickAddSheet), findsOneWidget);
      expect(
        t.widget<TextField>(_field('Calories (kcal)')).controller!.text,
        '300',
      );
      // A pull down from the handle asks the same.
      await t.fling(find.text('Quick add'), const Offset(0, 300), 1200);
      await t.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);
      await t.tap(find.text('Discard'));
      await t.pumpAndSettle();
      expect(find.byType(QuickAddSheet), findsNothing);
    });
  });

  group('saved meals', () {
    test('summary and search helpers', () {
      final m = MealTemplate(
        key: 'meal:x',
        label: 'Breakfast',
        meal: 'breakfast',
        items: const [('my:eggs', 3), ('my:oats', 80)],
        units: const {'my:eggs': 'egg', 'my:oats': 'g'},
      );
      final defs = {'my:eggs': eggs, 'my:oats': oats};
      expect(mealSummary(m, defs), '510 kcal · 2 foods · Breakfast');
      expect(nameMatches('Chicken Sausage', 'sausage'), isTrue);
      expect(nameMatches(null, 'x'), isFalse);
    });

    test('saving a meal keeps one unit per food, converting later copies',
        () async {
      FoodEntry e(String id, double q, String unit) => FoodEntry(
        id: id,
        date: '2026-10-07',
        meal: 'breakfast',
        label: 'Eggs',
        foodKey: 'my:eggs',
        quantity: q,
        unit: unit,
      );
      final r = await MyFoods.saveMeal(
        db,
        label: 'Two ways',
        meal: 'breakfast',
        entries: [e('a', 2, 'egg'), e('b', 50, 'g')],
      );
      expect(r.saved, 2);
      final m = (await MyFoods.meals(db)).firstWhere(
        (m) => m.label == 'Two ways',
      );
      expect(m.units['my:eggs'], 'egg');
      expect(m.items[0].$2, 2);
      expect(m.items[1].$2, closeTo(1, 1e-9), reason: '50 g is one egg');
    });

    testWidgets('the picker searches, shows servings and adds several', (
      t,
    ) async {
      await _host(t, (c) => MealEditor.show(c));
      await _settle(t);
      await t.enterText(_field('Name'), 'Morning');
      await t.ensureVisible(find.text('Add a food'));
      await t.tap(find.text('Add a food'));
      await t.pumpAndSettle();
      expect(find.text('Add foods'), findsOneWidget);
      expect(find.textContaining('per 100'), findsNothing);
      expect(find.textContaining('1 egg: 70 kcal'), findsOneWidget);
      await t.enterText(_field('Search'), 'oat');
      await t.pump();
      expect(find.text('Eggs'), findsNothing);
      await t.tap(find.text('Oats'));
      await t.pumpAndSettle();
      await t.tap(find.text('Add').last);
      await t.pumpAndSettle();
      expect(find.textContaining('Added: Oats'), findsOneWidget);
      await t.enterText(_field('Search'), '');
      await t.pump();
      await t.tap(find.text('Eggs'));
      await t.pumpAndSettle();
      await t.tap(find.text('Add').last);
      await t.pumpAndSettle();
      expect(find.text('Done · 2 added'), findsOneWidget);
      await t.tap(find.text('Done · 2 added'));
      await t.pumpAndSettle();
      // Both landed in the meal; the editor is still open to save.
      expect(find.text('Oats'), findsOneWidget);
      expect(find.text('Eggs'), findsOneWidget);
    });

    testWidgets('the review links to editing the saved meal', (t) async {
      final m = MealTemplate(
        key: 'meal:review',
        label: 'Review me',
        meal: 'lunch',
        items: const [('my:eggs', 2)],
        units: const {'my:eggs': 'egg'},
        groups: const [''],
      );
      var edit = false;
      await _host(
        t,
        (c) => showModalBottomSheet<void>(
          context: c,
          isScrollControlled: true,
          builder: (_) => MealReviewSheet(
            meal: m,
            defs: {'my:eggs': eggs},
            onEdit: () => edit = true,
          ),
        ),
      );
      expect(find.text('Other'), findsNothing);
      await t.ensureVisible(find.text('Edit saved meal'));
      await t.tap(find.text('Edit saved meal'));
      await t.pumpAndSettle();
      expect(edit, isTrue);
      expect(find.byType(MealReviewSheet), findsNothing);
    });
  });
}
