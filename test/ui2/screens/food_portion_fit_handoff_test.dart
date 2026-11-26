// Real portion input/fit/cancel handoff;historical rows remain unchanged.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/nutrition_store.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/screens/food_picker.dart';
import 'package:whoop_companion/ui2/screens/food_left.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import '../../support/audit_visual.dart' show loadAuditFonts;
import '../../support/coverage_store.dart';
import '../../support/localized_coverage.dart';

void main() {
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('food-portion-fit', fresh: true);
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  for (final floor in [false, true]) {
    for (final scale in [1.0, 3.1]) {
      testWidgets(
        'historical portion fit floor=$floor at ${scale}x converts the real unit and cancelled review preserves history',
        (t) async {
          final db = await LocalDb.instance;
          final def = myFoodDef(
            key: 'authored-fit',
            label: 'Authored portion',
            refGrams: 100,
            kcal: 100,
            protein: 10,
            measures: const [(label: 'piece', amount: 24.8)],
          );
          await NutritionDb.putFoodDef(db, def);
          await NutritionDb.put(
            db,
            const FoodEntry(
              id: 'authored-eaten',
              date: '2021-04-06',
              meal: 'lunch',
              label: 'Authored eaten',
              kcal: 100,
              proteinG: 5,
            ),
          );
          if (floor) {
            await NutritionDb.put(
              db,
              const FoodEntry(
                id: 'authored-unknown',
                date: '2021-04-06',
                meal: 'lunch',
                label: 'Authored unknown',
              ),
            );
          }
          final rows = await db.query('food_entry'),
              foods = await db.query('food_def');
          final app = AppState.forTesting()
            ..user = {'kcal_target': 200, 'protein_target': 100};
          addTearDown(app.dispose);
          Portion? result;
          await localizedPage(
            t,
            Builder(
              builder: (c) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    result = await GramsSheet.show(
                      c,
                      def,
                      initial: 1.5,
                      initialUnit: 'piece',
                      date: '2021-04-06',
                      action: 'Use portion',
                    );
                  },
                  child: const Text('Review portion'),
                ),
              ),
            ),
            app: app,
            scale: scale,
          );
          Future<void> flush() async {
            await t.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 70)),
            );
            await t.pumpAndSettle();
            expect(t.takeException(), isNull);
          }

          Future<void> tap(Finder f) async {
            await reveal(t, f);
            await t.tap(f);
            await flush();
          }

          await tap(find.text('Review portion'));
          expect(find.byType(GramsSheet), findsOneWidget);
          final grams = find.byWidgetPredicate(
            (w) => w is Pressable && w.semanticLabel == 'Amount in g',
          );
          await tap(grams);
          final sheet = find.byType(GramsSheet);
          final field = find.descendant(
            of: sheet,
            matching: find.byType(TextField),
          );
          expect(t.widget<TextField>(field).controller!.text, '37');
          final chip = find.byType(FitChip);
          expect(chip, findsOneWidget);
          expect(t.widget<FitChip>(chip).atMost, floor);
          expect(t.widget<FitChip>(chip).label, '100 g');
          await tap(chip);
          expect(t.widget<TextField>(field).controller!.text, '100');
          expect(
            t.widget<LeftAfterCard>(find.byType(LeftAfterCard)).date,
            '2021-04-06',
          );
          expect(await t.runAsync(() => db.query('food_entry')), rows);
          Navigator.of(t.element(sheet)).pop();
          await flush();
          expect(result, isNull);
          expect(find.byType(GramsSheet), findsNothing);
          expect(await t.runAsync(() => db.query('food_entry')), rows);
          expect(await t.runAsync(() => db.query('food_def')), foods);
          expect(app.user, {'kcal_target': 200, 'protein_target': 100});
        },
      );
    }
  }
}
