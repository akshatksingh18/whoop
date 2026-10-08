// Build 85: one lifting number everywhere (MET only, heart rate never prices
// it), day measures that never borrow yesterday, food categories that every
// food list shares, walks in km/h and the scannable design pieces.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:openstrap_edge/compute/day_upkeep.dart';
import 'package:openstrap_edge/compute/profile.dart';
import 'dart:convert';

import 'package:openstrap_edge/compute/derivation_engine.dart' show kAlgoVersion;
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/local_repository_impl.dart';
import 'package:openstrap_edge/data/nutrition_store.dart';
import 'package:openstrap_edge/ui2/activity/run_detail.dart' show speedKmh;
import 'package:openstrap_edge/ui2/grammar.dart';
import 'package:openstrap_edge/ui2/screens/food_picker.dart'
    show FoodCategoryFilter, foodsIn;
import 'package:openstrap_edge/ui2/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const me = Profile(ageYears: 23, weightKg: 80.5, heightCm: 186.69, sex: 'm');

  group('lifting: one MET-only number', () {
    test('60 active minutes of weight training is (3.5 − 1) × 80.5 × 1 h', () {
      expect(
        sessionActiveKcal(p: me, type: 'Weight training', minutes: 60),
        closeTo(201.25, 1e-9),
      );
      // 30 min, the setup preview's window.
      expect(
        sessionActiveKcal(p: me, type: 'weight_training', minutes: 30),
        closeTo(100.625, 1e-9),
      );
    });

    test('heart rate never moves a lift, low or high', () {
      for (final hr in [70.0, 85.0, 110.0, 150.0]) {
        expect(
          sessionActiveKcal(
            p: me,
            type: 'Weight training',
            minutes: 60,
            meanHr: hr,
            catalogueMet: 6.0,
          ),
          closeTo(201.25, 1e-9),
          reason: 'HR $hr',
        );
      }
    });

    test('the catalogue 6.0 MET is not used for a lift', () {
      // The old setup preview: 6 × 3.5 × 80 ÷ 200 × 30 = 252 gross.
      expect(
        sessionActiveKcal(
          p: const Profile(weightKg: 80),
          type: 'Weight training',
          minutes: 30,
          catalogueMet: 6.0,
        ),
        closeTo(100.0, 1e-9),
      );
    });

    test('other sessions keep the lower of heart rate and MET', () {
      final byMet = sessionActiveKcal(
        p: me,
        type: 'Cycling',
        minutes: 60,
        catalogueMet: 7.5,
      );
      final withLowHr = sessionActiveKcal(
        p: me,
        type: 'Cycling',
        minutes: 60,
        catalogueMet: 7.5,
        meanHr: 80,
      );
      expect(byMet, closeTo((7.5 - 1) * 80.5, 1e-9));
      expect(withLowHr!, lessThan(byMet!));
    });

    test('no weight or no time, no number', () {
      expect(
        sessionActiveKcal(p: const Profile(), type: 'Weight training', minutes: 60),
        isNull,
      );
      expect(sessionActiveKcal(p: me, type: 'Weight training', minutes: 0), isNull);
    });
  });

  group('distance chips', () {
    test('every source sentence has a short chip', () {
      expect(distanceTagOf('Recorded walking route'), 'Distance: GPS route');
      expect(distanceTagOf('Estimated from step length'), 'Distance: step length');
      expect(
        distanceTagOf('Phone motion-distance estimate'),
        'Distance: phone motion',
      );
      expect(
        distanceTagOf('Distance incomplete; add height for step-length estimate'),
        'Distance incomplete',
      );
    });
  });

  test('a walk reads in km/h: 10:17 /km is 5.8 km/h', () {
    expect(speedKmh(617), '5.8');
    expect(speedKmh(720), '5.0');
  });

  group('food categories', () {
    late Database db;
    setUpAll(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      LocalDb.dbName = 'build85.db';
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

    test('a category is stored, kept on a re-save without one, and cleared', () async {
      await NutritionDb.putFoodDef(
        db,
        myFoodDef(
          key: 'my:apple',
          label: 'Apple',
          refGrams: 182,
          kcal: 95,
          category: 'Fruits',
        ),
      );
      expect(foodCategory((await NutritionDb.foodDef(db, 'my:apple'))!), 'Fruits');
      // A write that does not mention the category (reorder, scan refresh)
      // keeps it, exactly as positions and measures are kept.
      await NutritionDb.putFoodDef(
        db,
        myFoodDef(key: 'my:apple', label: 'Apple', refGrams: 182, kcal: 95),
      );
      expect(foodCategory((await NutritionDb.foodDef(db, 'my:apple'))!), 'Fruits');
      // The editor sends '' to clear it.
      await NutritionDb.putFoodDef(
        db,
        myFoodDef(
          key: 'my:apple',
          label: 'Apple',
          refGrams: 182,
          kcal: 95,
          category: '',
        ),
      );
      expect(
        foodCategory((await NutritionDb.foodDef(db, 'my:apple'))!),
        kUncategorised,
      );
    });

    test('nutrition is untouched by a category', () async {
      await NutritionDb.putFoodDef(
        db,
        myFoodDef(
          key: 'my:whey',
          label: 'Whey',
          refGrams: 30,
          kcal: 120,
          protein: 24,
          category: 'Supplements',
        ),
      );
      final d = (await NutritionDb.foodDef(db, 'my:whey'))!;
      expect((d['kcal_100'] as num).toDouble(), closeTo(400, 1e-9));
      expect((d['protein_g_100'] as num).toDouble(), closeTo(80, 1e-9));
    });

    test('lists filter by the same field, in the fixed order', () {
      final foods = <Map<String, Object?>>[
        {'key': 'a', 'label': 'Oats', 'category': 'Grains & bread'},
        {'key': 'b', 'label': 'Banana', 'category': 'Fruits'},
        {'key': 'c', 'label': 'Mystery', 'category': ''},
        {'key': 'd', 'label': 'Apple', 'category': 'Fruits'},
      ];
      expect(foodCategoriesIn(foods), [
        'Fruits',
        'Grains & bread',
        kUncategorised,
      ]);
      expect([for (final f in foodsIn(foods, 'Fruits')) f['label']], [
        'Banana',
        'Apple',
      ]);
      expect(foodsIn(foods, null), hasLength(4));
      expect([for (final f in foodsIn(foods, kUncategorised)) f['key']], ['c']);
    });

    test('day measures never borrow another day for today', () async {
      final repo = LocalRepositoryImpl(getProfileMap: () => const {});
      final today = todayLabel();
      final y = DateTime.now().subtract(const Duration(days: 1));
      final yesterday = dayLabelOf(DateTime(y.year, y.month, y.day, 12));
      // Yesterday is fully calculated with 10.8 strain; today is not.
      await LocalDb.putDayResult(
        dayId: yesterday,
        algoVersion: kAlgoVersion,
        windowJson: '{}',
        payloadJson: jsonEncode({
          'scalars': {'strain': 10.8},
        }),
      );
      expect(await repo.getDayStrain(today), isEmpty);
      // Today's interim figure, the one the Today ring reads, is what shows.
      await LocalDb.putWakeDayFeatures(
        dayId: today,
        algoVersion: kAlgoVersion,
        payloadJson: jsonEncode({'day_id': today, 'strain': 0.4}),
      );
      final s = await repo.getDayStrain(today);
      expect(s['strain'], 0.4);
      expect(s['interim'], isTrue);
      expect((await repo.getDayStrain(yesterday))['strain'], 10.8);
    });

    testWidgets('the filter hides itself with one category', (t) async {
      await t.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: Scaffold(
            body: FoodCategoryFilter(
              foods: const [
                {'key': 'a', 'category': 'Fruits'},
              ],
              selected: null,
              onSelect: (_) {},
            ),
          ),
        ),
      );
      expect(find.text('All'), findsNothing);
    });
  });

  group('design pieces', () {
    Future<void> host(WidgetTester t, Widget w) => t.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(body: SingleChildScrollView(child: w)),
      ),
    );

    testWidgets('the updated stamp says when, or that nothing ran', (t) async {
      await host(
        t,
        UpdatedStamp(DateTime(2026, 10, 8, 7, 5), now: DateTime(2026, 10, 8, 9)),
      );
      expect(find.text('Updated 07:05'), findsOneWidget);
      await host(t, const UpdatedStamp(null));
      expect(find.text('Not calculated yet'), findsOneWidget);
    });

    testWidgets('the comparison names the gap in words', (t) async {
      await host(
        t,
        const CompareRow(
          leftLabel: 'Eaten',
          left: 2448,
          rightLabel: 'Budget',
          right: 2451.19,
          suffix: ' so far',
        ),
      );
      expect(find.text('2,448'), findsOneWidget);
      expect(find.text('2,451'), findsOneWidget);
      expect(find.text('Under so far'), findsOneWidget);
      expect(find.text('3 kcal'), findsOneWidget);
    });

    testWidgets('each method keeps its own breakdown', (t) async {
      await host(
        t,
        const CaloriePair(
          budget: 2451.19,
          acsm: 2500,
          note: '',
          budgetParts: [('Walking', 395.381)],
          acsmParts: [('Walking', 444.2)],
        ),
      );
      expect(find.text('Budget'), findsOneWidget);
      expect(find.text('ACSM'), findsOneWidget);
      expect(find.text('2,451 kcal'), findsOneWidget);
      expect(find.text('395'), findsOneWidget);
      expect(find.text('444'), findsOneWidget);
    });
  });
}
