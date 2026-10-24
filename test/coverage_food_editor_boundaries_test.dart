// Label editing at the input/storage boundary; all values are synthetic.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/nutrition_store.dart';
import 'package:openstrap_edge/state/prefs.dart';
import 'package:openstrap_edge/ui2/screens/food_picker.dart';
import 'package:openstrap_edge/ui2/screens/journal_compose.dart'
    show OsTextField;
import 'package:openstrap_edge/ui2/ui2.dart';
import 'support/audit_visual.dart' show loadAuditFonts;

Finder field(String label) => find.descendant(
  of: find.byWidgetPredicate((w) => w is OsTextField && w.label == label),
  matching: find.byType(TextField),
);
Finder action(String label) =>
    find.byWidgetPredicate((w) => w is Pressable && w.semanticLabel == label);
Future<void> flush(WidgetTester t, {bool Function()? ready}) async {
  for (var i = 0; i < 200; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await t.pump(const Duration(milliseconds: 30));
    if (i >= 18 && (ready?.call() ?? true)) break;
  }
  await t.pumpAndSettle();
  expect(t.takeException(), isNull);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  Map<String, Object?>? saved;
  setUpAll(() async {
    await loadAuditFonts();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final root = (await Directory(
      'build/coverage-remainder/food-editor',
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
  });
  tearDown(() async {
    await db.execute('DROP TRIGGER IF EXISTS synthetic_food_def_refusal');
  });
  tearDownAll(LocalDb.close);
  Future<void> open(WidgetTester t, {Map<String, Object?>? existing}) async {
    t.view.physicalSize = const Size(430, 1800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(
          body: Builder(
            builder: (c) => TextButton(
              onPressed: () async {
                saved = await FoodEditor.show(c, existing: existing);
              },
              child: const Text('Open editor'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('Open editor'));
    await flush(t);
  }

  Future<void> submit(WidgetTester t) async {
    await t.ensureVisible(find.text('Save').last);
    await t.tap(find.text('Save').last);
    await flush(t, ready: () => find.text('Saving…').evaluate().isEmpty);
  }

  for (final (label, invalid) in [
    ('Amount', 'bad'),
    ('Calories (kcal)', '-1'),
    ('Protein (g)', '-1'),
    ('Carbs (g)', '-1'),
    ('Fat (g)', '-1'),
    ('Fibre (g)', '-1'),
  ]) {
    testWidgets(
      'rejects invalid $label without writing a food or clearing the draft',
      (t) async {
        await open(t);
        await t.enterText(field('Description'), 'Synthetic food');
        await t.enterText(field(label), invalid);
        await submit(t);
        expect(
          find.textContaining('enter a non-negative number'),
          findsOneWidget,
        );
        expect(saved, isNull);
        expect(await t.runAsync(() => db.query('food_def')), isEmpty);
        expect(
          t.widget<TextField>(field('Description')).controller!.text,
          'Synthetic food',
        );
        await t.pumpWidget(const SizedBox());
        await flush(t);
      },
    );
  }
  for (final invalid in ['0', '-5']) {
    testWidgets('count serving weight $invalid cannot produce a conversion', (
      t,
    ) async {
      await open(t);
      await t.enterText(field('Description'), 'Synthetic pieces');
      await t.tap(action('Unit link'));
      await t.pump();
      await t.enterText(field('Weight (g)'), invalid);
      await submit(t);
      expect(
        find.textContaining('Enter what the serving weighs'),
        findsOneWidget,
      );
      expect(saved, isNull);
      expect(await t.runAsync(() => db.query('food_def')), isEmpty);
      await t.pumpWidget(const SizedBox());
      await flush(t);
    });
  }
  testWidgets(
    'a count label keeps its optional weight and missing macros distinct from zero',
    (t) async {
      await open(t);
      await t.enterText(field('Description'), 'Synthetic pieces');
      await t.tap(action('Unit link'));
      await t.pump();
      await t.enterText(field('Amount'), '6');
      await t.enterText(field('Weight (g)'), '85');
      await t.enterText(field('Calories (kcal)'), '180');
      await t.enterText(field('Protein (g)'), '12');
      await submit(t);
      expect(saved, isNotNull);
      expect(saved!['unit'], 'link');
      expect(saved!['kcal_100'], closeTo(3000, .001));
      expect(saved!['protein_g_100'], closeTo(200, .001));
      expect(saved!['fibre_g_100'], isNull);
      expect(foodMeasures(saved!).single.amount, closeTo(6 / 85, .000001));
      final row = (await t.runAsync(
        () => NutritionDb.foodDef(db, saved!['key'] as String),
      ))!;
      expect(row['kcal_100'], saved!['kcal_100']);
    },
  );
  testWidgets(
    'unshown serving units and barcode provenance survive a real edit/save',
    (t) async {
      final old = <String, Object?>{
        ...myFoodDef(
          key: 'synthetic-label',
          label: 'Synthetic labelled food',
          refGrams: 100,
          unit: 'g',
          kcal: 200,
          protein: 10,
          measures: [(label: 'link', amount: 50), (label: 'cup', amount: 150)],
          measureCounts: {'cup': 2},
        ),
        'source': 'barcode',
        'brand': 'Synthetic brand',
        'sodium_mg_100': 100.0,
      };
      await t.runAsync(() => NutritionDb.putFoodDef(db, old));
      await open(t, existing: old);
      await t.enterText(field('Description'), 'Synthetic renamed food');
      await submit(t);
      expect(saved!['source'], 'barcode');
      expect(saved!['brand'], 'Synthetic brand');
      expect(saved!['unit'], 'link');
      expect(saved!['sodium_mg_100'], 5000);
      expect(
        foodMeasures(saved!).map((m) => m.label),
        containsAll(['g', 'cup']),
      );
      expect(measureCounts(saved!)['cup'], 2);
      expect(nutrientsFor(saved!, 1).kcal, 100);
    },
  );
  testWidgets(
    'a refused food write retains the draft and a deliberate retry writes once',
    (t) async {
      await open(t);
      await t.enterText(field('Description'), 'Synthetic retry food');
      await t.enterText(field('Calories (kcal)'), '150');
      await t.runAsync(
        () => db.execute(
          "CREATE TRIGGER synthetic_food_def_refusal BEFORE INSERT ON food_def BEGIN SELECT RAISE(ABORT, 'synthetic refusal'); END",
        ),
      );
      await submit(t);
      expect(find.textContaining('Your values are still here'), findsOneWidget);
      expect(saved, isNull);
      await t.runAsync(
        () => db.execute('DROP TRIGGER synthetic_food_def_refusal'),
      );
      await submit(t);
      expect(saved!['label'], 'Synthetic retry food');
      expect(await t.runAsync(() => db.query('food_def')), hasLength(1));
    },
  );
}
