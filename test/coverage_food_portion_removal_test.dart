// Existing historical-entry edits: zero removes only after the real store
// accepts deletion, and Undo restores the recorded portion/provenance.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/nutrition_store.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/screens/food_diary.dart';
import 'package:whoop_companion/ui2/screens/food_picker.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'coverage_food_calendar_recovery_test.dart' show flush;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('food-portion-removal');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  Future<FoodEntry> seed(bool legacy) async {
    final db = await LocalDb.instance;
    final def = myFoodDef(
      key: 'synthetic-food',
      label: 'Synthetic food',
      refGrams: 100,
      kcal: 900,
    );
    await NutritionDb.putFoodDef(db, def);
    final e = FoodEntry(
      id: 'synthetic-old-portion',
      date: '2021-04-06',
      meal: 'dinner',
      label: 'Synthetic recorded portion',
      foodKey: 'synthetic-food',
      quantity: legacy ? 2 : 100,
      unit: legacy ? 'retired scoop' : 'g',
      conv: legacy ? '' : conversionSnapshot(def),
      kcal: 200,
      proteinG: null,
      atTs: 1617735600,
      loggedAt: 1617736600,
      group: 'Authored plate',
    );
    await NutritionDb.put(db, e);
    return e;
  }

  Future<void> host(
    WidgetTester t,
    FoodEntry e,
    ValueChanged<bool> result, {
    bool remove = false,
  }) async {
    final app = AppState.forTesting()..user = {};
    addTearDown(app.dispose);
    await localizedPage(
      t,
      Scaffold(
        body: Builder(
          builder: (c) => TextButton(
            onPressed: () async {
              result(
                await (remove ? deleteDiaryEntry(c, e) : editDiaryEntry(c, e)),
              );
            },
            child: const Text('Edit authored entry'),
          ),
        ),
      ),
      app: app,
    );
    await t.tap(find.text('Edit authored entry'));
    await flush(t);
  }

  Future<void> remove(WidgetTester t) async {
    final f = find.byWidgetPredicate(
      (w) => w is BigButton && w.label == 'Remove',
    );
    await reveal(t, f);
    await invokeControl(t, t.widget<BigButton>(f).onTap);
    await flush(t);
  }

  Future<List<FoodEntry>?> rows(WidgetTester t) => t.runAsync(
    () async => NutritionDb.entriesForDay(await LocalDb.instance, '2021-04-06'),
  );

  for (final legacy in [false, true]) {
    for (final refused in [false, true]) {
      testWidgets(
        '${legacy ? 'retired-unit' : 'snapshot'} zero portion ${refused ? 'retains and retries refused deletion' : 'removes and restores with Undo'}',
        (t) async {
          final e = await seed(legacy), db = await LocalDb.instance;
          bool? result;
          await host(t, e, (v) => result = v);
          expect(find.byType(GramsSheet), findsOneWidget);
          await t.enterText(find.byType(TextField).first, '0');
          await t.pumpAndSettle();
          expect(
            find.text('An amount of 0 removes this entry from the day.'),
            findsOneWidget,
          );
          if (refused) {
            await db.execute(
              "CREATE TRIGGER synthetic_portion_delete BEFORE DELETE ON food_entry BEGIN SELECT RAISE(ABORT,'synthetic portion refusal'); END",
            );
          }
          try {
            await remove(t);
            if (refused) {
              expect(result, isNull);
              expect(find.byType(GramsSheet), findsOneWidget);
              expect(
                find.text(
                  'Could not save this portion. Your values are here; try again.',
                ),
                findsOneWidget,
              );
              expect((await rows(t))!.single.kcal, 200);
              expect(
                t
                    .widget<TextField>(find.byType(TextField).first)
                    .controller!
                    .text,
                '0',
              );
              await db.execute('DROP TRIGGER synthetic_portion_delete');
              await remove(t);
            }
            expect(result, true);
            expect(find.byType(GramsSheet), findsNothing);
            expect(await rows(t), isEmpty);
            await t.tap(find.text('Undo'));
            await flush(t);
            final restored = (await rows(t))!.single;
            expect(restored.id, e.id);
            expect(restored.quantity, e.quantity);
            expect(restored.unit, e.unit);
            expect(restored.kcal, 200);
            expect(restored.proteinG, isNull);
            expect(restored.atTs, e.atTs);
            expect(restored.loggedAt, e.loggedAt);
            expect(restored.meal, 'dinner');
            expect(restored.group, 'Authored plate');
          } finally {
            await db.execute('DROP TRIGGER IF EXISTS synthetic_portion_delete');
          }
        },
      );
    }
  }
  testWidgets(
    'a refused food-definition read releases the edit latch so the same historical entry can reopen',
    (t) async {
      final e = await seed(false), db = await LocalDb.instance;
      await db.execute(
        'ALTER TABLE food_def RENAME TO synthetic_hidden_food_def',
      );
      var hidden = true;
      bool? result;
      try {
        await host(t, e, (v) => result = v);
        expect(result, false);
        expect(
          find.text('Could not change this entry. Please try again.'),
          findsOneWidget,
        );
        expect((await rows(t))!.single.id, e.id);
        await db.execute(
          'ALTER TABLE synthetic_hidden_food_def RENAME TO food_def',
        );
        hidden = false;
        result = null;
        await t.tap(find.text('Edit authored entry'));
        await flush(t);
        expect(find.byType(GramsSheet), findsOneWidget);
        Navigator.of(t.element(find.byType(GramsSheet))).pop();
        await flush(t);
        expect(result, false);
        expect((await rows(t))!.single.loggedAt, e.loggedAt);
      } finally {
        if (hidden) {
          await db.execute(
            'ALTER TABLE synthetic_hidden_food_def RENAME TO food_def',
          );
        }
      }
    },
  );
  testWidgets(
    'confirmed quantity deletion names the recorded portion and cancel leaves the dated entry intact',
    (t) async {
      final e = await seed(false);
      bool? result;
      await host(t, e, (v) => result = v, remove: true);
      expect(find.textContaining('(100 g)'), findsOneWidget);
      await t.tap(find.text('Keep it'));
      await flush(t);
      expect(result, false);
      expect((await rows(t))!.single.id, e.id);
      expect((await rows(t))!.single.meal, 'dinner');
    },
  );
}
