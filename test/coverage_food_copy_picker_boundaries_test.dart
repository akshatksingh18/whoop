// Explicit historical copy choices, not the parked general Log-food default.
// Counts must distinguish a failed read, an empty meal and unknown energy.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/nutrition_store.dart';
import 'package:whoop_companion/ui2/screens/food_diary.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'coverage_food_calendar_recovery_test.dart' show control, flush;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  ({String date, String meal})? chosen;
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('food-copy-picker-boundaries');
  });
  setUp(() async {
    await resetCoverageStore();
    chosen = null;
    final db = await LocalDb.instance;
    for (final (id, day, meal, kcal) in [
      ('authored-breakfast', '2021-04-06', 'breakfast', 400.0),
      ('authored-unknown', '2021-04-06', 'lunch', null),
      ('authored-dinner', '2021-04-07', 'dinner', 500.0),
    ]) {
      await NutritionDb.put(
        db,
        FoodEntry(id: id, date: day, meal: meal, label: id, kcal: kcal),
      );
    }
  });
  tearDownAll(LocalDb.close);
  Finder button() => find.byWidgetPredicate(
    (w) => w is BigButton && w.label == 'Use authored meal',
  );
  Future<void> open(WidgetTester t, {bool count = true}) async {
    await localizedPage(
      t,
      Builder(
        builder: (c) => TextButton(
          onPressed: () async {
            chosen = await pickDayMeal(
              c,
              title: 'Use authored meal',
              date: '2021-04-06',
              meal: 'breakfast',
              showCount: count,
            );
          },
          child: const Text('Open authored picker'),
        ),
      ),
    );
    await t.tap(find.text('Open authored picker'));
    await flush(t);
  }

  testWidgets(
    'source picker rereads historical days and preserves explicit meals and unknown energy',
    (t) async {
      await open(t);
      expect(find.textContaining('1 item · 400 kcal'), findsOneWidget);
      await t.tap(control('Lunch'));
      await flush(t);
      expect(find.textContaining('Calories not tracked'), findsOneWidget);
      expect(find.textContaining('0 kcal'), findsNothing);
      expect(t.widget<BigButton>(button()).onTap, isNotNull);
      await t.tap(control('Next day'));
      await flush(t);
      expect(find.text('Nothing in Lunch that day'), findsOneWidget);
      expect(t.widget<BigButton>(button()).onTap, isNull);
      await t.tap(control('Dinner'));
      await flush(t);
      expect(find.textContaining('1 item · 500 kcal'), findsOneWidget);
      await t.tap(button());
      await flush(t);
      expect(chosen, (date: '2021-04-07', meal: 'dinner'));
      expect(await (await LocalDb.instance).query('food_entry'), hasLength(3));
    },
  );
  testWidgets(
    'failed source read blocks selection until Retry reads the retained entries',
    (t) async {
      final db = await LocalDb.instance;
      await db.execute(
        'ALTER TABLE food_entry RENAME TO synthetic_picker_retained_food',
      );
      var hidden = true;
      try {
        await open(t);
        expect(find.text('Food could not load'), findsOneWidget);
        expect(find.text('Nothing in Breakfast that day'), findsNothing);
        expect(t.widget<BigButton>(button()).onTap, isNull);
        await t.runAsync(
          () => db.execute(
            'ALTER TABLE synthetic_picker_retained_food RENAME TO food_entry',
          ),
        );
        hidden = false;
        await invokeControl(
          t,
          t.widget<StatusCard>(find.byType(StatusCard)).onFix,
        );
        await flush(t);
        expect(find.text('Food could not load'), findsNothing);
        expect(find.textContaining('1 item · 400 kcal'), findsOneWidget);
        await t.tap(button());
        await flush(t);
        expect(chosen, (date: '2021-04-06', meal: 'breakfast'));
        expect(await db.query('food_entry'), hasLength(3));
      } finally {
        if (hidden) {
          await db.execute(
            'ALTER TABLE synthetic_picker_retained_food RENAME TO food_entry',
          );
        }
      }
    },
  );
  testWidgets(
    'destination picker accepts an empty explicit historical meal without reading source counts',
    (t) async {
      await open(t, count: false);
      await t.tap(control('Snacks'));
      await t.tap(control('Next day'));
      await flush(t);
      expect(find.byType(StatusCard), findsNothing);
      expect(find.textContaining('Nothing in'), findsNothing);
      expect(t.widget<BigButton>(button()).onTap, isNotNull);
      await t.tap(button());
      await flush(t);
      expect(chosen, (date: '2021-04-07', meal: 'snack'));
      expect(await (await LocalDb.instance).query('food_entry'), hasLength(3));
    },
  );
}
