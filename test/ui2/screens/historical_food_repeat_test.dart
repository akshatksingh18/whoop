// Exercise the historical Food page's real add and repeat actions.
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' show Database;
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/nutrition_store.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/screens/food_diary.dart';
import 'package:whoop_companion/ui2/screens/nutrition_screen.dart';
import 'package:whoop_companion/ui2/ui2.dart';

import 'nutrition_root_test.dart' show io;
import '../../support/audit_visual.dart' show loadAuditFonts;
import '../../support/coverage_store.dart';
import '../../support/localized_coverage.dart';

const originalDate = '2021-04-05';
const viewedDate = '2021-04-06';
const label = 'Authored oat portion';
const key = 'synthetic-oats';

void main() {
  late AppState app;
  late Database db;
  late int changes;
  late List<Map<String, Object?>> before;
  final lunch = Clock.fixed(DateTime(2021, 4, 9, 12));

  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('historical-food-repeat');
  });
  setUp(() async {
    await resetCoverageStore();
    app = AppState.forTesting();
    changes = 0;
    db = await LocalDb.instance;
    final chosen = myFoodDef(
      key: key,
      label: label,
      refGrams: 100,
      unit: 'g',
      kcal: 160,
    );
    await NutritionDb.putFoodDef(db, chosen);
    await NutritionDb.put(
      db,
      entryFromFood(
        chosen,
        75,
        id: 'authored-oat-original',
        date: originalDate,
        meal: 'breakfast',
        amount: 75,
        unit: 'g',
      ),
    );
    final second = myFoodDef(
      key: 'synthetic-apple',
      label: 'Authored second food',
      refGrams: 100,
      unit: 'g',
      kcal: 80,
    );
    await NutritionDb.putFoodDef(db, second);
    await NutritionDb.put(
      db,
      entryFromFood(
        second,
        90,
        id: 'authored-apple-original',
        date: originalDate,
        meal: 'dinner',
        amount: 90,
        unit: 'g',
      ),
    );
    before = await db.query('food_entry', orderBy: 'id');
  });
  tearDown(() async {
    app.dispose();
    await db.execute('DROP TRIGGER IF EXISTS authored_repeat_refusal');
  });
  tearDownAll(LocalDb.close);

  Future<void> open(WidgetTester t, double scale) async {
    await localizedPage(
      t,
      Scaffold(
        body: SingleChildScrollView(
          child: NutritionDayView(date: viewedDate, onChanged: () => changes++),
        ),
      ),
      app: app,
      scale: scale,
      settle: false,
    );
    await io(t);
  }

  Finder repeat(double scale) => scale > 1.3
      ? find.text('$label · 75 g')
      : find.byWidgetPredicate(
          (w) => w is Pressable && w.semanticLabel == 'Log $label again, 75 g',
        );

  Future<void> tap(WidgetTester t, Finder finder) async {
    await reveal(t, finder);
    await t.tap(finder);
    await io(t);
  }

  for (final scale in [1.0, 3.1]) {
    testWidgets(
      'Log again keeps date and portion and undoes one entry at scale $scale',
      (t) => withClock(lunch, () async {
        await open(t, scale);
        await tap(t, repeat(scale));
        expect(find.text('$label added to Lunch'), findsOneWidget);
        final rows = (await t.runAsync(
          () => db.query(
            'food_entry',
            where: 'date = ?',
            whereArgs: [viewedDate],
          ),
        ))!;
        final added = rows.single;
        expect(added, containsPair('meal', 'lunch'));
        expect(added, containsPair('food_key', key));
        expect(added, containsPair('quantity', 75));
        expect(added, containsPair('unit', 'g'));
        expect(added, containsPair('kcal', 120));
        expect(added, containsPair('source', 'repeat'));
        expect(
          DateTime.fromMillisecondsSinceEpoch((added['at_ts'] as int) * 1000),
          DateTime(2021, 4, 6, 13),
        );
        expect(added['logged_at'] as int, greaterThan(added['at_ts'] as int));
        expect(changes, 1);
        await tap(t, find.text('Undo'));
        expect(changes, 2);
        expect(
          await t.runAsync(() => db.query('food_entry', orderBy: 'id')),
          before,
        );
      }),
    );
  }

  testWidgets(
    'refused Log again keeps both original records and offers no Undo',
    (t) => withClock(lunch, () async {
      await db.execute('''
        CREATE TRIGGER authored_repeat_refusal BEFORE INSERT ON food_entry
        BEGIN SELECT RAISE(ABORT, 'authored insert refusal'); END
      ''');
      await open(t, 3.1);
      await tap(t, repeat(3.1));
      expect(find.text('$label was not added. Try again.'), findsOneWidget);
      expect(find.text('Undo'), findsNothing);
      expect(changes, 0);
      expect(
        await t.runAsync(() => db.query('food_entry', orderBy: 'id')),
        before,
      );
    }),
  );

  testWidgets(
    'historical calorie card passes its displayed meal and date to Log food',
    (t) => withClock(lunch, () async {
      await open(t, 1.0);
      await tap(t, find.text('Add to Lunch'));
      final page = find.byType(LogFoodScreen);
      final editor = t.widget<LogFoodScreen>(page);
      expect(editor.date, viewedDate);
      expect(editor.meal, 'lunch');
      Navigator.of(t.element(page)).pop();
      await io(t);
      expect(find.text('Add to Lunch'), findsOneWidget);
      expect(
        await t.runAsync(() => db.query('food_entry', orderBy: 'id')),
        before,
      );
    }),
  );
}
