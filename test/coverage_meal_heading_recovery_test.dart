// A heading is a draft destination, not permission to rewrite food or its day.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/nutrition_store.dart';
import 'package:whoop_companion/ui2/screens/food_group_picker.dart';
import 'package:whoop_companion/ui2/screens/food_picker.dart' show PickRow;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('meal-heading-recovery', fresh: true);
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  Future<void> flush(WidgetTester t) async {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  }

  for (final scale in [1.0, 3.1]) {
    for (final action in ['existing', 'none', 'cancel', 'retry']) {
      testWidgets(
        'historical heading $action at $scale retains meal/date/provenance and all food',
        (t) async {
          final db = (await t.runAsync(() async {
            final db = await LocalDb.instance;
            for (final x in [
              ('alpha', '2021-04-06', 'lunch', 'Alpha'),
              ('zulu', '2021-04-06', 'lunch', 'Zulu'),
              ('dinner', '2021-04-06', 'dinner', 'Other meal'),
              ('history', '2021-04-05', 'lunch', 'Other day'),
            ]) {
              await NutritionDb.put(
                db,
                FoodEntry(
                  id: x.$1,
                  date: x.$2,
                  meal: x.$3,
                  group: x.$4,
                  label: 'Authored ${x.$1}',
                  kcal: 100,
                  quantity: 1,
                  unit: 'serving',
                  atTs: 1617700000,
                  loggedAt: 1617800000,
                  confirmed: true,
                ),
              );
            }
            await NutritionDb.freezeCounting(db, goalKnown: true);
            return db;
          }))!;
          final before = (await t.runAsync(
            () => db.query('food_entry', orderBy: 'id'),
          ))!;
          var heading = 'Current draft';
          final changes = <String>[];
          await localizedPage(
            t,
            Scaffold(
              body: StatefulBuilder(
                builder: (c, setState) => MealGroupPicker(
                  date: '2021-04-06',
                  meal: 'lunch',
                  group: heading,
                  onChanged: (value) => setState(() {
                    heading = value;
                    changes.add(value);
                  }),
                ),
              ),
            ),
            scale: scale,
          );
          final row = find.widgetWithText(PickRow, 'Meal heading');
          if (action == 'retry') {
            await t.runAsync(
              () => db.execute(
                'ALTER TABLE food_entry RENAME TO authored_retained_food_entry',
              ),
            );
            try {
              await t.tap(row);
              await flush(t);
              expect(
                find.text('Meal headings could not load. Please retry.'),
                findsOneWidget,
              );
              expect(changes, isEmpty);
              expect(heading, 'Current draft');
              expect(
                await t.runAsync(
                  () => db.query('authored_retained_food_entry', orderBy: 'id'),
                ),
                before,
              );
            } finally {
              await t.runAsync(
                () => db.execute(
                  'ALTER TABLE authored_retained_food_entry RENAME TO food_entry',
                ),
              );
            }
            ScaffoldMessenger.of(t.element(row)).hideCurrentSnackBar();
            await flush(t);
          }
          await t.tap(row);
          await flush(t);
          expect(find.text('Other day'), findsNothing);
          expect(find.text('Other meal'), findsNothing);
          expect(find.text('Alpha'), findsOneWidget);
          expect(find.text('Zulu'), findsOneWidget);
          expect(find.text('Current draft'), findsWidgets);
          if (action == 'cancel') {
            Navigator.of(t.element(find.text('No heading'))).pop();
            await flush(t);
            expect(changes, isEmpty);
            expect(heading, 'Current draft');
            await t.tap(row);
            await flush(t);
          }
          final selected = action == 'none' || action == 'cancel'
              ? ''
              : 'Alpha';
          await t.tap(
            find.widgetWithText(
              PickRow,
              selected.isEmpty ? 'No heading' : selected,
            ),
          );
          await flush(t);
          expect(heading, selected);
          expect(changes, [selected]);
          expect(find.text('Create a heading'), findsNothing);
          await t.tap(row);
          await flush(t);
          expect(find.text('Alpha'), findsOneWidget);
          Navigator.of(t.element(find.text('No heading'))).pop();
          await flush(t);
          expect(changes, [selected]);
          expect(
            await t.runAsync(() => db.query('food_entry', orderBy: 'id')),
            before,
          );
          expect(await t.runAsync(() => db.query('sessions')), isEmpty);
          expect(await t.runAsync(() => db.query('day_result')), isEmpty);
        },
      );
    }
  }
}
