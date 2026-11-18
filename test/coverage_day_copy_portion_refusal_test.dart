// Real portion sheet/refusal/retry and transactional copy; authored food only.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/nutrition_store.dart';
import 'package:whoop_companion/ui2/screens/food_day_copy.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('day-copy-portion-refusal', fresh: true);
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  for (final knownEnergy in [true, false]) {
    testWidgets(
      'copy refuses overflowing ${knownEnergy ? 'energy' : 'quantity'} then accepts a reviewed half',
      (t) async {
        const from = '2021-04-06', to = '2021-04-07';
        final eaten =
            DateTime(2021, 4, 6, 12, 15).millisecondsSinceEpoch ~/ 1000;
        final original = FoodEntry(
          id: 'authored-copy-source',
          date: from,
          meal: 'lunch',
          label: 'Authored meal',
          quantity: knownEnergy ? 1 : 100,
          unit: 'g',
          kcal: knownEnergy ? 400 : null,
          proteinG: 20,
          atTs: eaten,
          loggedAt: 123,
          note: 'Authored provenance',
          group: 'Retain group',
        );
        final source = (await t.runAsync(() async {
          final db = await LocalDb.instance;
          await NutritionDb.put(db, original);
          return await db.query('food_entry');
        }))!;
        var calls = 0;
        await localizedPage(
          t,
          Builder(
            builder: (c) => Scaffold(
              body: TextButton(
                onPressed: () => reviewFoodDayCopy(
                  c,
                  from: from,
                  to: to,
                  entries: [original],
                  onLog: (reviewed) async {
                    calls++;
                    expect(
                      await NutritionDb.logDayCopy(
                        await LocalDb.instance,
                        date: to,
                        reviewed: reviewed,
                      ),
                      1,
                    );
                  },
                ),
                child: const Text('Review copy'),
              ),
            ),
          ),
        );
        await t.tap(find.text('Review copy'));
        await t.pumpAndSettle();
        Finder portion(String amount) => find.byWidgetPredicate(
          (w) =>
              w is Pressable &&
              w.semanticLabel == 'Portion of Authored meal, $amount×',
        );
        await t.tap(portion('1'));
        await t.pumpAndSettle();
        await t.enterText(find.byType(TextField), '1e308');
        await t.tap(find.text('Save'));
        await t.pumpAndSettle();
        expect(
          find.text('That portion is too large. Enter a smaller amount.'),
          findsOneWidget,
        );
        expect(portion('1'), findsOneWidget);
        expect(calls, 0);
        expect(
          await t.runAsync(
            () async => (await LocalDb.instance).query('food_entry'),
          ),
          source,
        );
        await t.tap(portion('1'));
        await t.pumpAndSettle();
        await t.enterText(find.byType(TextField), '0.5');
        await t.tap(find.text('Save'));
        await t.pumpAndSettle();
        expect(
          find.text('That portion is too large. Enter a smaller amount.'),
          findsNothing,
        );
        expect(portion('0.5'), findsOneWidget);
        expect(calls, 0);
        final commit = t.widget<BigButton>(
          find.byWidgetPredicate((w) => w is BigButton && w.onTap != null),
        );
        await invokeControl(t, commit.onTap);
        expect(calls, 1);
        await t.runAsync(() async {
          final db = await LocalDb.instance;
          expect(
            await db.query('food_entry', where: 'date = ?', whereArgs: [from]),
            source,
          );
          final copied = (await NutritionDb.entriesForDay(db, to)).single;
          expect(copied.id, isNot(original.id));
          expect(copied.quantity, knownEnergy ? .5 : 50);
          expect(copied.kcal, knownEnergy ? 200 : isNull);
          expect(copied.proteinG, 10);
          expect(copied.note, original.note);
          expect(copied.group, original.group);
          expect(copied.meal, original.meal);
          expect(
            copied.atTs,
            DateTime(2021, 4, 7, 12, 15).millisecondsSinceEpoch ~/ 1000,
          );
          expect(copied.loggedAt, isNot(original.loggedAt));
        });
        expect(find.text('Copy a day'), findsNothing);
        expect(t.takeException(), isNull);
      },
    );
  }
}
