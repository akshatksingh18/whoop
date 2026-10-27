// Build 90 (Akshat's option B): "After this, today" on the food screen he logs
// from, and "Fit what's left". Synthetic foods and goals only.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/nutrition_store.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/screens/food_diary.dart';
import 'package:whoop_companion/ui2/screens/food_left.dart';
import 'package:whoop_companion/ui2/screens/food_picker.dart';
import 'package:whoop_companion/ui2/theme.dart';

const _lentils = <String, Object?>{
  'key': 'my:lentils',
  'label': 'Red lentils, cooked',
  'serving_g': 100.0,
  'unit': 'g',
  'kcal_100': 116.0,
  'protein_g_100': 9.0,
  'carbs_g_100': 20.0,
  'fat_g_100': 0.4,
  'fibre_g_100': 7.9,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('maths', () {
    const eaten = NutrientTotal(1717, 3, 0);
    test('left after this, over, and at most', () {
      expect(leftAfter(2000, eaten, 232)!.value, 51);
      expect(leftAfter(2000, eaten, 400)!.value, -117);
      expect(leftAfter(2000, const NutrientTotal(1717, 3, 1), 232)!.atMost, isTrue);
      expect(leftAfter(null, eaten, 232), isNull, reason: 'no goal, no card');
      expect(leftAfter(2000, eaten, null), isNull, reason: 'unknown food');
      expect(leftAfter(2000, const NutrientTotal(null, 0, 0), 300)!.value, 1700,
          reason: 'an empty day has eaten nothing');
    });

    test('fit rounds down, whole grams or half units, never over', () {
      // 283 kcal left at 1.16 kcal/g → 243 g (281.9 kcal).
      expect(fitAmount(goal: 2000, eaten: eaten, kcalPerUnit: 1.16, unit: 'g'), 243);
      // 150 kcal a link → 1.5 links.
      expect(fitAmount(goal: 2000, eaten: eaten, kcalPerUnit: 150, unit: 'link'), 1.5);
      // Ticked companions come off first.
      expect(
        fitAmount(goal: 2000, eaten: eaten, kcalPerUnit: 1.16, unit: 'g', otherKcal: 61),
        191,
      );
      expect(fitAmount(goal: 1700, eaten: eaten, kcalPerUnit: 1.16, unit: 'g'), isNull,
          reason: 'nothing left');
      expect(fitAmount(goal: 2000, eaten: eaten, kcalPerUnit: null, unit: 'g'), isNull);
      expect(fitAmount(goal: 2000, eaten: eaten, kcalPerUnit: 600, unit: 'link'), isNull,
          reason: 'not even half a unit fits');
    });
  });

  group('screens', () {
    final today = todayLabel();
    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      LocalDb.dbName = 'build90_food_left_test.db';
      await databaseFactory.deleteDatabase(
        path.join(await databaseFactory.getDatabasesPath(), LocalDb.dbName),
      );
      final db = await LocalDb.instance;
      for (final (id, kcal, protein) in const [
        ('a', 1200.0, 60.0),
        ('b', 517.0, 36.0),
      ]) {
        await NutritionDb.put(
          db,
          FoodEntry(
            id: id,
            date: today,
            meal: 'breakfast',
            label: id,
            kcal: kcal,
            proteinG: protein,
          ),
        );
      }
    });
    tearDownAll(() async {
      await LocalDb.close();
      await databaseFactory.deleteDatabase(
        path.join(await databaseFactory.getDatabasesPath(), LocalDb.dbName),
      );
    });

    Widget app(Widget child) {
      final state = AppState.forTesting()
        ..user = {'kcal_target': 2000, 'protein_target': 140};
      return ChangeNotifierProvider<AppState>.value(
        value: state,
        child: MaterialApp(
          theme: buildTheme(Brightness.light),
          home: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      );
    }

    Future<void> settle(WidgetTester t) async {
      for (var i = 0; i < 10; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await t.pump();
      }
    }

    testWidgets('the food screen shows what is left and fits it in one tap', (t) async {
      t.view.physicalSize = const Size(390 * 3, 1400 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(app(FoodDetailSheet(
        def: _lentils,
        date: today,
        meal: 'lunch',
        grams: 200,
      )));
      await settle(t);
      // 2000 − 1717 − 232 = 51.
      expect(find.text('51 kcal left'), findsOneWidget);
      expect(find.text('Protein: 26 g left of 140'), findsOneWidget);
      expect(find.text('LEFT AFTER'), findsOneWidget);
      expect(find.text('% of your daily goal'), findsNothing);
      await t.tap(find.textContaining("Fit what's left · 243 g"));
      await settle(t);
      expect(find.text('1 kcal left'), findsOneWidget, reason: '243 g is 281.9 kcal');
      // More than is left reads as over, not as a negative "left".
      await t.enterText(find.byType(TextField).first, '400');
      await settle(t);
      expect(find.text('Over by 181 kcal'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('editing an entry counts it once', (t) async {
      await t.pumpWidget(app(const GramsSheet(
        def: _lentils,
        initial: 100,
        date: '1999-01-01',
      )));
      await settle(t);
      // An empty day: 2000 − 116.
      expect(find.text('1,884 kcal left'), findsOneWidget);
      await t.pumpWidget(app(GramsSheet(
        key: const ValueKey('edit-b'),
        def: _lentils,
        initial: 100,
        date: today,
        excludeId: 'b',
      )));
      await settle(t);
      // Entry b (517) is the one being edited: 2000 − 1200 − 116.
      expect(find.text('684 kcal left'), findsOneWidget);
    });

    testWidgets('no goal, no card', (t) async {
      final state = AppState.forTesting()..user = const {};
      await t.pumpWidget(ChangeNotifierProvider<AppState>.value(
        value: state,
        child: MaterialApp(
          theme: buildTheme(Brightness.light),
          home: Scaffold(
            body: GramsSheet(def: _lentils, initial: 100, date: today),
          ),
        ),
      ));
      await settle(t);
      expect(find.textContaining('kcal left'), findsNothing);
      expect(find.textContaining("Fit what's left"), findsNothing);
    });
  });
}
