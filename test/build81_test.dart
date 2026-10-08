// Build 81: sleep in recovery, patterns from logged data, bedtime
// consistency, the Monday week line and Quick add's weight and save switch.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_analytics/onehz.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/nutrition_store.dart';
import 'package:openstrap_edge/data/recovery_movers.dart';
import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:openstrap_edge/ui2/screens/food_diary.dart' show QuickAddSheet;
import 'package:openstrap_edge/ui2/screens/food_picker.dart' show DragList;
import 'package:openstrap_edge/ui2/screens/journal_compose.dart'
    show OsTextField;
import 'package:openstrap_edge/ui2/screens/sleep_detail.dart'
    show bedtimeSpreadMin, bedtimeWord;
import 'package:openstrap_edge/ui2/screens/week_card.dart' show weekChange;
import 'package:openstrap_edge/ui2/theme.dart';

/// Sixteen nights spread around [centre] (deterministic).
List<double> _base(double centre, double spread) => [
  for (var i = 0; i < 16; i++) centre + ((i * 7) % 5 - 2) * spread / 2,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('recovery counts last night\'s sleep', () {
    final hrv = _base(4.2, 0.1); // ln(rmssd)
    final rhr = _base(55, 2);
    final tst = _base(420, 30); // usual about 7 h

    Readiness score(double tonight) => readinessComposite([
      hrvInput(4.4, hrv), // a good HRV night
      rhrInput(53, rhr),
      sleepInput(tonight, tst),
    ]).value!;

    test('a 5 h 30 min night pulls a strong heart-signal score down', () {
      final usual = score(420).score;
      final short = score(330).score;
      expect(short, lessThan(usual - 15), reason: 'usual $usual short $short');
    });

    test('a long night is rewarded at most one deviation', () {
      final long = readinessComposite([sleepInput(600, tst), hrvInput(4.2, hrv)]);
      final drivers = {for (final d in long.drivers!) d.label: d.contribution};
      // Sleep's oriented z is capped at +1, renormalised by its weight share.
      expect(drivers['sleep']!, lessThanOrEqualTo(0.20 / 0.55 + 1e-9));
    });

    test('weights are HRV > RHR > sleep > breathing > temperature', () {
      expect(hrvInput(1, const []).weight, 0.35);
      expect(rhrInput(1, const []).weight, 0.25);
      expect(sleepInput(1, const []).weight, 0.20);
      expect(respInput(1, const []).weight, 0.12);
      expect(tempInput(1, const [], settledFraction: 1).weight, 0.08);
      expect(wHrv + wRhr + wSleep + wResp + wTemp, closeTo(1, 1e-9));
    });

    test('no sleep last night drops the input instead of inventing one', () {
      final r = readinessComposite([
        hrvInput(4.4, hrv),
        rhrInput(53, rhr),
        sleepInput(null, tst),
      ]);
      expect(r.present, isTrue);
      expect(r.inputs_used, isNot(contains('sleep')));
    });
  });

  group('what moves your recovery', () {
    test('compares mornings with and without a tag, with counts', () {
      final outcome = <String, double>{};
      final tags = <String, Map<String, bool>>{};
      for (var i = 0; i < 12; i++) {
        final date = '2026-09-${(i + 1).toString().padLeft(2, '0')}';
        final late = i.isEven;
        outcome[date] = late ? 58 : 55; // resting HR higher after late meals
        tags[date] = {'Ate after 22:00': late};
      }
      final rows = moversFrom(outcomeKey: 'rhr', outcome: outcome, tags: tags);
      expect(rows, hasLength(1));
      expect(rows.single['delta'], closeTo(3, 1e-9));
      expect(rows.single['helped'], isFalse, reason: 'higher resting HR');
      expect(rows.single['n_with'], 6);
      expect(rows.single['n_without'], 6);
      expect(rows.single['unit'], 'bpm');
    });

    test('a tag needs five mornings on each side', () {
      final outcome = {for (var i = 0; i < 8; i++) '2026-09-0${i + 1}': 60.0};
      final tags = {
        for (var i = 0; i < 8; i++)
          '2026-09-0${i + 1}': {'Workout after 19:00': i < 3},
      };
      expect(
        moversFrom(outcomeKey: 'readiness', outcome: outcome, tags: tags),
        isEmpty,
      );
    });

    test('tags come from the day before, and unknown days count nowhere', () {
      final dinner = DateTime(2026, 9, 1, 22, 30).millisecondsSinceEpoch ~/ 1000;
      final lunch = DateTime(2026, 9, 2, 13).millisecondsSinceEpoch ~/ 1000;
      FoodEntry e(String date, int at, double kcal) => FoodEntry(
        id: '$date$at',
        date: date,
        meal: 'dinner',
        label: 'x',
        atTs: at,
        kcal: kcal,
        proteinG: 50,
      );
      final tags = moverTags(
        dates: ['2026-09-02', '2026-09-03', '2026-09-04'],
        food: {
          '2026-09-01': [e('2026-09-01', dinner, 2600)],
          '2026-09-02': [e('2026-09-02', lunch, 1500)],
        },
        sessions: [
          {
            'start_ts':
                DateTime(2026, 9, 2, 19, 30).millisecondsSinceEpoch ~/ 1000,
          },
        ],
        strain: {'2026-09-01': 15},
        steps: {'2026-09-02': 12000},
        onsetSec: {'2026-09-02': -2 * 3600, '2026-09-03': -5 * 3600},
        kcalTarget: 2200,
        proteinTarget: 140,
      );
      expect(tags['2026-09-02']!['Ate after 22:00'], isTrue);
      expect(tags['2026-09-02']!['Ate over your calorie goal'], isTrue);
      expect(tags['2026-09-02']!['Hit your protein goal'], isFalse);
      expect(tags['2026-09-02']!['Strain 14 or more'], isTrue);
      expect(tags['2026-09-02']!['Asleep after 01:00'], isTrue, reason: '02:00');
      expect(tags['2026-09-03']!['Ate after 22:00'], isFalse);
      expect(tags['2026-09-03']!['Workout after 19:00'], isTrue);
      expect(tags['2026-09-03']!['10,000+ steps'], isTrue);
      expect(tags['2026-09-03']!['Asleep after 01:00'], isFalse, reason: '23:00');
      // Nothing logged on 3 September: no food tags for the 4th at all.
      expect(tags['2026-09-04']!.containsKey('Ate after 22:00'), isFalse);
      expect(tags['2026-09-04']!.containsKey('Strain 14 or more'), isFalse);
    });
  });

  group('bedtime consistency and the week line', () {
    test('spread is the standard deviation, in plain words', () {
      expect(bedtimeSpreadMin([0, 10, -10, 5, -5, 0]), isNull, reason: '6');
      final steady = bedtimeSpreadMin([0, 10, -10, 5, -5, 0, 0])!;
      expect(steady, lessThan(10));
      expect(bedtimeWord(steady), 'Steady');
      expect(bedtimeWord(45), 'Varies');
      expect(bedtimeWord(90), 'Irregular');
    });

    test('a week average carries its change from the week before', () {
      expect(weekChange(64, 59, (v) => '${v.round()}'), '64 · +5');
      expect(weekChange(7.2, 8, (v) => v.toStringAsFixed(1)), '7.2 · −0.8');
      expect(weekChange(64, null, (v) => '${v.round()}'), '64');
    });
  });

  testWidgets('dragging a row to the top edge scrolls a long page', (t) async {
    t.view.physicalSize = const Size(390, 600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    var order = [for (var i = 0; i < 30; i++) 'Food $i'];
    final scroll = ScrollController();
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (c, set) => SingleChildScrollView(
              controller: scroll,
              child: DragList(
                length: order.length,
                itemBuilder: (c, i) => SizedBox(
                  key: ValueKey(order[i]),
                  height: 60,
                  child: Text(order[i]),
                ),
                onReorder: (from, to) => set(() {
                  final x = order.removeAt(from);
                  order.insert(to > from ? to - 1 : to, x);
                }),
              ),
            ),
          ),
        ),
      ),
    );
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await t.pump();
    final start = scroll.offset;
    final g = await t.startGesture(t.getCenter(find.text('Food 29')));
    await t.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    // Up to the top edge and hold there: the page itself scrolls.
    await g.moveTo(const Offset(195, 300));
    await t.pump(const Duration(milliseconds: 50));
    await g.moveTo(const Offset(195, 10));
    for (var i = 0; i < 60; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    expect(scroll.offset, lessThan(start - 600), reason: 'page scrolled up');
    await g.moveTo(const Offset(195, 12));
    await t.pump(const Duration(milliseconds: 100));
    await g.up();
    await t.pumpAndSettle();
    expect(
      order.indexOf('Food 29'),
      lessThan(20),
      reason: 'dropped far above where a single screen could reach',
    );
  });

  group('Quick add', () {
    late Database db;
    setUpAll(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      LocalDb.dbName = 'build81-quickadd.db';
      await databaseFactory.deleteDatabase(
        path.join(await databaseFactory.getDatabasesPath(), LocalDb.dbName),
      );
      db = await LocalDb.instance;
    });
    tearDownAll(() async {
      await LocalDb.close();
      await databaseFactory.deleteDatabase(
        path.join(await databaseFactory.getDatabasesPath(), LocalDb.dbName),
      );
    });

    Finder field(String label) => find.descendant(
      of: find.byWidgetPredicate((w) => w is OsTextField && w.label == label),
      matching: find.byType(TextField),
    );

    Future<void> open(WidgetTester t) async {
      t.view.physicalSize = const Size(390, 1400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: Builder(
            builder: (c) => TextButton(
              onPressed: () => Navigator.of(c).push(
                MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(
                    body: QuickAddSheet(date: '2026-10-07', meal: 'snack'),
                  ),
                ),
              ),
              child: const Text('go'),
            ),
          ),
        ),
      );
      await t.tap(find.text('go'));
      await t.pumpAndSettle();
    }

    Future<void> add(WidgetTester t) async {
      await t.ensureVisible(find.text('Add'));
      await t.pumpAndSettle();
      await t.tap(find.text('Add'));
      for (
        var i = 0;
        i < 100 && find.byType(QuickAddSheet).evaluate().isNotEmpty;
        i++
      ) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await t.pump(const Duration(milliseconds: 50));
      }
      expect(find.byType(QuickAddSheet), findsNothing, reason: 'saved');
    }

    testWidgets('every macro is on the sheet and the weight is kept', (
      t,
    ) async {
      await open(t);
      expect(find.text('Other macros (optional)'), findsNothing);
      for (final l in [
        'Protein (g)',
        'Carbs (g)',
        'Fat (g)',
        'Fibre (g)',
        'Weight (g)',
      ]) {
        expect(field(l), findsOneWidget, reason: l);
      }
      await t.enterText(field('Name'), 'Protein shake');
      await t.enterText(field('Calories (kcal)'), '220');
      await t.enterText(field('Protein (g)'), '40');
      await t.enterText(field('Weight (g)'), '250');
      await add(t);
      final rows = (await t.runAsync(
        () => db.query('food_entry', where: "label = 'Protein shake'"),
      ))!;
      expect(rows, hasLength(1));
      expect(rows.single['quantity'], 250);
      expect(rows.single['unit'], 'g');
      expect(rows.single['kcal'], 220, reason: 'the weight scales nothing');
      expect(rows.single['food_key'], isNull, reason: 'not saved as a food');
    });

    testWidgets('Save to My foods keeps it as a food at that weight', (
      t,
    ) async {
      await open(t);
      await t.enterText(field('Name'), 'Bar');
      await t.enterText(field('Calories (kcal)'), '200');
      await t.enterText(field('Protein (g)'), '20');
      await t.enterText(field('Weight (g)'), '60');
      await t.ensureVisible(find.text('Save to My foods'));
      await t.tap(find.text('Save to My foods'));
      await t.pump();
      await add(t);
      final defs = (await t.runAsync(
        () => db.query('food_def', where: "label = 'Bar'"),
      ))!;
      expect(defs, hasLength(1));
      final def = defs.single;
      expect(foodUnit(def), 'g');
      expect(nutrientsFor(def, 60).kcal, closeTo(200, 1e-9));
      final entry = (await t.runAsync(
        () => db.query('food_entry', where: "label = 'Bar'"),
      ))!.single;
      expect(entry['food_key'], def['key'], reason: 'linked to the new food');
    });

    testWidgets('saving to My foods needs a name', (t) async {
      await open(t);
      await t.enterText(field('Calories (kcal)'), '200');
      await t.ensureVisible(find.text('Save to My foods'));
      await t.tap(find.text('Save to My foods'));
      await t.pump();
      await t.ensureVisible(find.text('Add'));
      await t.tap(find.text('Add'));
      await t.pump();
      expect(find.text('Name it to save it to My foods.'), findsOneWidget);
    });
  });
}
