// Build 75: shared ranges, food order/measures/sub-headings, meal times,
// Live Activity status and the trimmed day breakdown.

import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/nutrition_store.dart';
import 'package:openstrap_edge/live/live_activity.dart';
import 'package:openstrap_edge/compute/profile.dart';
import 'package:openstrap_edge/gps/run_history.dart' show isRunType;
import 'package:openstrap_edge/ui2/screens/day_timeline.dart';
import 'package:openstrap_edge/ui2/screens/food_picker.dart';
import 'package:openstrap_edge/ui2/screens/metric_detail.dart';
import 'package:openstrap_edge/ui2/theme.dart';
import 'package:openstrap_edge/ui2/grammar.dart' show InputSheet;
import 'package:openstrap_edge/ui2/screens/nutrition_screen.dart' show CalorieCard;

FoodEntry _entry(String id, String food, {String group = '', int at = 0}) =>
    FoodEntry(
      id: id,
      date: '2026-10-06',
      meal: 'breakfast',
      label: food,
      foodKey: 'my:$food',
      quantity: 1,
      unit: 'serving',
      atTs: at,
      group: group,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('shared ranges and links', () {
    test('Trends and every metric share Today · 7 · 30 · 3 months', () {
      expect(kRangeDays, [1, 7, 30, 90]);
      expect(kRangeLabels, ['Today', '7 days', '30 days', '3 months']);
    });

    test('a dated link opens the shortest range holding that day', () {
      String ago(int d) {
        final n = DateTime.now();
        final x = DateTime(n.year, n.month, n.day - d);
        return '${x.year}-${x.month.toString().padLeft(2, '0')}-'
            '${x.day.toString().padLeft(2, '0')}';
      }

      expect(MetricDetail.at('hrv', ago(0)).range, 0);
      expect(MetricDetail.at('hrv', ago(0)).day, isNull);
      expect(MetricDetail.at('hrv', ago(3)).range, 1);
      expect(MetricDetail.at('hrv', ago(3)).day, ago(3));
      expect(MetricDetail.at('hrv', ago(20)).range, 2);
      expect(MetricDetail.at('hrv', ago(60)).range, 3);
      expect(MetricDetail.at('hrv', ago(200)).range, 3);
      expect(MetricDetail.at('hrv', null).range, 0);
    });

    test('the 7-day average needs enough measured days and fills no gap', () {
      final r = rollingMean([1, null, 3, 5, null, 7], 3, minCount: 2);
      expect(r, [null, null, 2, 4, 4, 6]);
      expect(rollingMean(const [], 7), isEmpty);
    });
  });

  group('meal times', () {
    final now = DateTime(2026, 10, 6, 10, 11);
    test('dinner logged in the morning gets its usual hour, not 10:11', () {
      expect(
        foodEntryTime('2026-10-06', 'dinner', now: now),
        DateTime(2026, 10, 6, 19),
      );
    });
    test('the meal under way, and snacks, use the clock', () {
      expect(foodEntryTime('2026-10-06', 'breakfast', now: now), now);
      expect(foodEntryTime('2026-10-06', 'snack', now: now), now);
      final late = DateTime(2026, 10, 6, 20, 30);
      expect(foodEntryTime('2026-10-06', 'dinner', now: late), late);
      expect(
        foodEntryTime('2026-10-06', 'lunch', now: late),
        DateTime(2026, 10, 6, 13),
      );
    });
    test('a past day keeps the usual hour', () {
      expect(
        foodEntryTime('2026-10-01', 'lunch', now: now),
        DateTime(2026, 10, 1, 13),
      );
    });
  });

  group('measures and sub-headings in rows', () {
    test('named measures round-trip; damaged or blank ones read as none', () {
      final def = myFoodDef(
        key: 'my:whey',
        label: 'Whey',
        refGrams: 29,
        kcal: 120,
        protein: 24,
        measures: [(label: 'scoop', amount: 29)],
      );
      expect(foodMeasures(def), [(label: 'scoop', amount: 29.0)]);
      expect(foodMeasures({'measures_json': 'nope'}), isEmpty);
      expect(foodMeasures({'measures_json': ''}), isEmpty);
      expect(
        myFoodDef(key: 'k', label: 'x', refGrams: 1).containsKey(
          'measures_json',
        ),
        isFalse,
        reason: 'an edit without measures keeps the saved ones',
      );
    });

    test('a saved meal keeps each item sub-heading; old rows have none', () {
      const m = MealTemplate(
        key: 'meal:1',
        label: 'Breakfast',
        meal: 'breakfast',
        items: [('my:eggs', 3), ('my:oats', 50)],
        groups: ['Eggs and Sausage', 'Oatmeal'],
      );
      final back = MealTemplate.fromRow(m.toRow(0));
      expect(back.groups, ['Eggs and Sausage', 'Oatmeal']);
      expect(back.hasGroups, isTrue);
      final old = MealTemplate.fromRow({
        'key': 'k',
        'label': 'Old',
        'meal': 'lunch',
        'items_json': '[{"food":"my:oats","g":50}]',
      });
      expect(old.groupAt(0), '');
      expect(old.hasGroups, isFalse);
    });
  });

  group('food order, meals and entries in the database', () {
    late Database db;
    setUpAll(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      LocalDb.dbName = 'build75-regressions.db';
      await databaseFactory.deleteDatabase(
        path.join(await databaseFactory.getDatabasesPath(), LocalDb.dbName),
      );
      db = await LocalDb.instance;
    });
    setUp(() async {
      for (final t in ['food_entry', 'food_def', 'meal_template']) {
        await db.delete(t);
      }
    });
    tearDownAll(() async {
      await LocalDb.close();
      await databaseFactory.deleteDatabase(
        path.join(await databaseFactory.getDatabasesPath(), LocalDb.dbName),
      );
    });

    Map<String, Object?> food(String name) => myFoodDef(
      key: 'my:$name',
      label: name,
      refGrams: 1,
      unit: 'serving',
      kcal: 70,
    );

    test('a new food goes to the top; edits keep place and measures', () async {
      await NutritionDb.putFoodDef(db, food('a'));
      await NutritionDb.putFoodDef(db, {
        ...food('b'),
        'measures_json': encodeMeasures([(label: 'egg', amount: 1)]),
      });
      List<String> names(List<Map<String, Object?>> rows) => [
        for (final r in rows) r['label'] as String,
      ];
      expect(names(await MyFoods.all(db)), ['b', 'a']);
      await MyFoods.reorderFoods(db, ['my:a', 'my:b']);
      expect(names(await MyFoods.all(db)), ['a', 'b']);
      // Editing b without measures keeps its place and its measure.
      await NutritionDb.putFoodDef(db, food('b'));
      final all = await MyFoods.all(db);
      expect(names(all), ['a', 'b']);
      expect(foodMeasures(all.last), [(label: 'egg', amount: 1.0)]);
    });

    test('saved meals keep a dragged order across edits', () async {
      MealTemplate meal(String k) => MealTemplate(
        key: k,
        label: k,
        meal: 'breakfast',
        items: const [('my:a', 1)],
      );
      await MyFoods.putMeal(db, meal('x'));
      await MyFoods.putMeal(db, meal('y'));
      expect([for (final m in await MyFoods.meals(db)) m.key], ['y', 'x']);
      await MyFoods.reorderMeals(db, ['x', 'y']);
      await MyFoods.putMeal(db, meal('y'));
      expect([for (final m in await MyFoods.meals(db)) m.key], ['x', 'y']);
    });

    test(
      'saving and logging a meal keeps sub-headings; review amounts apply',
      () async {
        for (final n in ['eggs', 'sausage', 'oats']) {
          await NutritionDb.putFoodDef(db, food(n));
        }
        final saved = await MyFoods.saveMeal(
          db,
          label: 'Big breakfast',
          meal: 'breakfast',
          entries: [
            _entry('1', 'eggs', group: 'Eggs and Sausage'),
            _entry('2', 'sausage', group: 'Eggs and Sausage'),
            _entry('3', 'oats', group: 'Oatmeal'),
          ],
        );
        expect(saved.saved, 3);
        final m = (await MyFoods.meals(db)).single;
        expect(m.groups, ['Eggs and Sausage', 'Eggs and Sausage', 'Oatmeal']);
        final n = await MyFoods.logMeal(
          db,
          m,
          '2026-10-07',
          'breakfast',
          amounts: [4, null, 1],
        );
        expect(n, 2, reason: 'the unticked sausage is left out');
        final es = await NutritionDb.entriesForDay(db, '2026-10-07');
        expect({for (final e in es) e.label: e.group}, {
          'eggs': 'Eggs and Sausage',
          'oats': 'Oatmeal',
        });
        expect(es.firstWhere((e) => e.label == 'eggs').quantity, 4);
        expect(es.firstWhere((e) => e.label == 'eggs').kcal, 280);
      },
    );

    test('an old saved meal without sub-headings still files under its name',
        () async {
      await NutritionDb.putFoodDef(db, food('oats'));
      final old = MealTemplate.fromRow({
        'key': 'old',
        'label': 'Usual',
        'meal': 'breakfast',
        'items_json': '[{"food":"my:oats","g":1,"unit":"serving"}]',
      });
      await MyFoods.logMeal(db, old, '2026-10-07', 'breakfast');
      final es = await NutritionDb.entriesForDay(db, '2026-10-07');
      expect(es.single.group, 'Usual');
    });

    test('a dragged entry order survives later edits of an entry', () async {
      for (final (i, id) in ['p', 'q', 'r'].indexed) {
        await NutritionDb.put(db, _entry(id, id, at: i));
      }
      await NutritionDb.reorderEntries(db, ['r', 'p', 'q']);
      final es = await NutritionDb.entriesForDay(db, '2026-10-06');
      expect([for (final e in es) e.id], ['r', 'p', 'q']);
      await NutritionDb.put(db, es.firstWhere((e) => e.id == 'p').atQuantity(2));
      final again = await NutritionDb.entriesForDay(db, '2026-10-06');
      expect([for (final e in again) e.id], ['r', 'p', 'q']);
    });
  });

  test('the first open seeds positions from the order shown until now',
      () async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await createNutritionTables(db);
    // Back to the build-74 shape: no position column yet.
    await db.execute('ALTER TABLE food_def DROP COLUMN pos');
    await db.execute('ALTER TABLE meal_template DROP COLUMN pos');
    for (final k in ['never', 'old', 'recent']) {
      await db.insert('food_def', {'key': k, 'label': k, 'created_at': 0});
    }
    for (final (k, t) in [('old', 1), ('recent', 2)]) {
      await db.insert('food_entry', {
        'id': k,
        'date': '2026-10-01',
        'meal': 'lunch',
        'food_key': k,
        'label': k,
        'created_at': t,
        'updated_at': t,
      });
    }
    for (final k in ['b', 'a']) {
      await db.insert('meal_template', {
        'key': k,
        'label': k,
        'meal': 'lunch',
        'items_json': '[]',
        'created_at': 0,
      });
    }
    await createNutritionTables(db);
    expect(
      [for (final r in await db.query('food_def', orderBy: 'pos')) r['key']],
      ['recent', 'old', 'never'],
      reason: 'most recently eaten first, exactly as the list showed before',
    );
    expect([for (final m in await MyFoods.meals(db)) m.key], ['a', 'b']);
    await db.close();
  });

  group('build 76 food fixes', () {
    test('stored numbers come back to an edit field without float noise', () {
      expect(editableNumber(20.000000000000004), '20');
      expect(editableNumber(10.000000000000002), '10');
      expect(editableNumber(6.5), '6.5');
      expect(editableNumber(0.125), '0.125');
      expect(editableNumber(null), '');
      // The round trip that produced it: 20 g on a 29 g label.
      final def = myFoodDef(key: 'k', label: 'Whey', refGrams: 29, protein: 20);
      final back = (def['protein_g_100'] as double) * 29 / 100;
      expect(editableNumber(back), '20');
    });

    test('a measure typed with its count reads as one measure', () {
      Map<String, Object?> d(String l, double a) => {
        'measures_json': encodeMeasures([(label: l, amount: a)]),
      };
      expect(foodMeasures(d('1 scoop', 29)), [(label: 'scoop', amount: 29.0)]);
      expect(foodMeasures(d('2 scoops', 58)), [(label: 'scoop', amount: 29.0)]);
      expect(foodMeasures(d('scoop', 29)), [(label: 'scoop', amount: 29.0)]);
    });

    testWidgets('an item can be dragged under another sub-heading', (t) async {
      List<(String, String)>? got;
      final items = ['a', 'b', 'c'];
      final groups = {'a': 'Oatmeal', 'b': 'Oatmeal', 'c': ''};
      await t.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: Scaffold(
            body: SingleChildScrollView(
              child: GroupedDragList<String>(
                items: items,
                groupOf: (i) => groups[i]!,
                headerBuilder: (c, g, _) =>
                    SizedBox(height: 30, child: Text('H:$g')),
                itemBuilder: (c, i) =>
                    SizedBox(key: ValueKey(i), height: 50, child: Text(i)),
                onChanged: (x) => got = x,
              ),
            ),
          ),
        ),
      );
      expect(find.text('H:Oatmeal'), findsOneWidget);
      expect(find.text('H:'), findsOneWidget, reason: 'No sub-heading target');
      final g = await t.startGesture(t.getCenter(find.text('c')));
      await t.pump(kLongPressTimeout + const Duration(milliseconds: 100));
      await g.moveBy(const Offset(0, -110));
      await t.pump(const Duration(milliseconds: 300));
      await g.up();
      await t.pumpAndSettle();
      expect(got, isNotNull);
      expect({for (final (grp, i) in got!) i: grp}['c'], 'Oatmeal');
    });

    testWidgets('an empty No sub-heading is not shown outside a drag', (
      t,
    ) async {
      await t.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: Scaffold(
            body: SingleChildScrollView(
              child: GroupedDragList<String>(
                items: const ['a', 'b'],
                groupOf: (i) => 'Oatmeal',
                headerBuilder: (c, g, _) =>
                    SizedBox(height: 30, child: Text('H:$g')),
                itemBuilder: (c, i) =>
                    SizedBox(key: ValueKey(i), height: 50, child: Text(i)),
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      expect(find.text('H:Oatmeal'), findsOneWidget);
      expect(find.text('H:'), findsNothing);
    });

    testWidgets('pulling a sheet past its top closes it', (t) async {
      await t.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: Builder(
            builder: (c) => Scaffold(
              body: TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: c,
                  isScrollControlled: true,
                  builder: (_) => InputSheet(
                    children: [
                      const Text('Edit food'),
                      for (var i = 0; i < 30; i++)
                        SizedBox(height: 60, child: Text('row $i')),
                    ],
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      expect(find.text('Edit food'), findsOneWidget);
      // From the middle of the content, well past the top.
      await t.drag(find.text('row 3'), const Offset(0, 300));
      await t.pumpAndSettle();
      expect(find.text('Edit food'), findsNothing);
    });

    testWidgets('the calorie card reads eaten / goal and what is left', (
      t,
    ) async {
      await t.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: const Scaffold(body: CalorieCard(eaten: 1475, goal: 2202)),
        ),
      );
      expect(find.text('1,475'), findsOneWidget);
      expect(find.text('kcal / 2,202'), findsOneWidget);
      expect(find.text('727'), findsOneWidget);
      expect(find.text('left'), findsOneWidget);
    });
  });

  group('build 78', () {
    final sausage = {
      'key': 'my:sausage',
      'label': 'Chicken sausage',
      'serving_g': 71.0,
      'unit': 'g',
      'kcal_100': 110 * 100 / 71,
      'measures_json': encodeMeasures([(label: 'Link', amount: 71)]),
    };
    final perLink = {
      'key': 'my:link',
      'label': 'Sausage per link',
      'serving_g': 1.0,
      'unit': 'link',
      'kcal_100': 110 * 100.0,
      'measures_json': encodeMeasures([(label: 'g', amount: 1 / 71)]),
    };

    test('a food converts both ways between its units', () {
      expect(foodUnitNames(sausage), ['g', 'Link']);
      expect(toBase(sausage, 3, 'link'), 213, reason: 'case-insensitive');
      expect(toBase(perLink, 142, 'g'), closeTo(2, 1e-9));
      expect(toBase(sausage, 1, 'cup'), isNull);
      expect(portionWithWeight(3, 'Link', sausage), '3 Links · 213 g');
      expect(portionWithWeight(2, 'link', perLink), '2 links · 142 g');
      expect(portionWithWeight(150, 'g', sausage), '150 g');
      final e = entryFromFood(
        sausage,
        toBase(sausage, 3, 'Link')!,
        id: 'x',
        date: '2026-10-06',
        meal: 'breakfast',
        amount: 3,
        unit: 'Link',
      );
      expect(e.quantity, 3);
      expect(e.unit, 'Link');
      expect(e.kcal, closeTo(330, 1e-9));
    });

    testWidgets('switching unit converts the amount and scales the same', (
      t,
    ) async {
      final unit = ValueNotifier<String>('g');
      final amount = TextEditingController(text: '142');
      await t.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: Scaffold(
            body: AmountInput(controller: amount, def: sausage, unit: unit),
          ),
        ),
      );
      expect(find.text('142 g = 2 Links'), findsOneWidget);
      await t.tap(find.text('Link'));
      await t.pump();
      expect(unit.value, 'Link');
      expect(amount.text, '2');
      await t.tap(find.bySemanticsLabel('More'));
      await t.pump();
      expect(amount.text, '3', reason: 'one link per tap');
      expect(find.text('3 Links = 213 g'), findsOneWidget);
    });

    test('other workouts take the lower of net HR and net activity', () {
      const p = Profile(ageYears: 23, weightKg: 80.5, heightCm: 186.69, sex: 'm');
      // 24 min of weight training at mean HR 130: MET net (3.5 − 1).
      final byMet = 2.5 * 80.5 * 24 / 60;
      final kcal = otherWorkoutActiveKcal(
        p: p,
        minutes: 24,
        meanHr: 130,
        met: conservativeMet('weight_training', 6.0),
      )!;
      expect(conservativeMet('weight_training', 6.0), 3.5);
      expect(kcal, lessThanOrEqualTo(byMet + 1e-9));
      expect(
        otherWorkoutActiveKcal(p: p, minutes: 24, met: 3.5),
        closeTo(byMet, 1e-9),
      );
      expect(otherWorkoutActiveKcal(p: p, minutes: 0, met: 5), isNull);
      expect(otherWorkoutActiveKcal(p: const Profile(), minutes: 20), isNull);
    });

    test('treadmill and track work are running', () {
      for (final t in ['treadmill', 'track_intervals', 'sprinting', 'running']) {
        expect(isRunType(t), isTrue, reason: t);
      }
      expect(isRunType('weight_training'), isFalse);
      expect(liveActivityEligible('treadmill'), isTrue);
    });

    testWidgets('one long-press drags into the hidden No sub-heading', (
      t,
    ) async {
      List<(String, String)>? got;
      await t.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: Scaffold(
            body: SingleChildScrollView(
              child: GroupedDragList<String>(
                items: const ['a', 'b'],
                groupOf: (i) => 'Oatmeal',
                headerBuilder: (c, g, _) =>
                    SizedBox(height: 30, child: Text('H:$g')),
                itemBuilder: (c, i) =>
                    SizedBox(key: ValueKey(i), height: 50, child: Text(i)),
                onChanged: (x) => got = x,
              ),
            ),
          ),
        ),
      );
      expect(find.text('H:'), findsNothing);
      final g = await t.startGesture(t.getCenter(find.text('a')));
      await t.pump(kLongPressTimeout + const Duration(milliseconds: 100));
      await t.pump();
      expect(find.text('H:'), findsOneWidget, reason: 'shown on the same hold');
      await g.moveBy(const Offset(0, 140));
      await t.pump(const Duration(milliseconds: 300));
      await g.up();
      await t.pumpAndSettle();
      expect(got, isNotNull, reason: 'the first hold dragged');
      expect({for (final (grp, i) in got!) i: grp}['a'], '');
      expect(find.text('H:'), findsNothing, reason: 'hidden again after');
    });
  });

  group('amount control', () {
    Future<void> pump(WidgetTester t, Map<String, Object?> def) =>
        t.pumpWidget(
          MaterialApp(
            theme: buildTheme(Brightness.dark),
            home: Scaffold(
              body: AmountInput(
                controller: TextEditingController(text: '1'),
                def: def,
              ),
            ),
          ),
        );

    testWidgets('a counted food offers 1 to 4, each labelled once', (t) async {
      await pump(t, {'serving_g': 1, 'unit': 'serving'});
      expect(find.text('1 serving'), findsOneWidget);
      expect(find.text('4 servings'), findsOneWidget);
      expect(find.textContaining('serving · '), findsNothing);
      await t.tap(find.bySemanticsLabel('More'));
      await t.pump();
      expect(find.text('2'), findsOneWidget);
      await t.tap(find.text('4 servings'));
      await t.pump();
      expect(find.text('4'), findsOneWidget);
    });

    testWidgets('a weighed food offers its measure with grams', (t) async {
      await pump(t, {
        'serving_g': 29,
        'unit': 'g',
        'measures_json': encodeMeasures([(label: 'scoop', amount: 29)]),
      });
      expect(find.text('1 scoop · 29 g'), findsOneWidget);
      expect(find.text('2 scoops · 58 g'), findsOneWidget);
      await t.tap(find.bySemanticsLabel('More'));
      await t.pump();
      expect(find.text('2'), findsOneWidget, reason: 'a tap steps by one gram');
      // Holding keeps stepping, faster the longer it is held.
      final hold = await t.startGesture(
        t.getCenter(find.bySemanticsLabel('More')),
      );
      await t.pump(const Duration(milliseconds: 600));
      for (var i = 0; i < 20; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      await hold.up();
      await t.pump();
      final held = double.parse(
        t.widget<EditableText>(find.byType(EditableText)).controller.text,
      );
      expect(held, greaterThan(15));
      final after = held;
      await t.pump(const Duration(seconds: 1));
      expect(
        t.widget<EditableText>(find.byType(EditableText)).controller.text,
        editableNumber(after),
        reason: 'releasing stops it',
      );
    });
  });

  group('Live Activity', () {
    test('running and walking only, treadmill included', () {
      expect(liveActivityEligible('walking'), isTrue);
      expect(liveActivityEligible('running'), isTrue);
      expect(liveActivityEligible('treadmill'), isTrue);
      expect(liveActivityEligible('weight_training'), isFalse);
      expect(liveActivityEligible('other'), isFalse);
    });

    test('the bridge reason is kept, and a refusal is not active', () async {
      const channel = MethodChannel('openstrap/live_activity');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'update') {
              return {
                'ok': false,
                'reason': 'Live Activities are off for WHOOP in iOS Settings',
              };
            }
            if (call.method == 'status') {
              return {'enabled': false, 'extensionOk': true};
            }
            return true;
          });
      await LiveActivity.update(
        id: 'walk',
        type: 'walking',
        elapsed: 5,
        paused: false,
        distanceKm: null,
        hr: null,
      );
      expect(LiveActivity.isActive, isFalse);
      expect(LiveActivity.lastReason, contains('off for WHOOP'));
      expect((await LiveActivity.status())['enabled'], isFalse);
      await LiveActivity.end();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
  });

  test('the day breakdown can leave band events out', () {
    final timeline = {
      'events': [
        {'event_id': 7, 'ts': 1000},
      ],
    };
    expect(
      dayMoments(timeline: timeline, bandEvents: false),
      isEmpty,
    );
  });
}
