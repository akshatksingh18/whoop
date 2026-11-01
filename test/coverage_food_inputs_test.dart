// Synthetic serving/diary drafts through real rendered controls and SQLite.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/nutrition_store.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/screens/food_diary.dart';
import 'package:whoop_companion/ui2/screens/food_picker.dart';
import 'package:whoop_companion/ui2/screens/journal_compose.dart';
import 'package:whoop_companion/ui2/screens/nutrition_screen.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

Finder field(String label) => find.descendant(
  of: find.byWidgetPredicate((w) => w is WhoopTextField && w.label == label),
  matching: find.byType(TextField),
);
Future<void> enter(WidgetTester t, String label, String value) async {
  await reveal(t, field(label));
  await t.enterText(field(label), value);
  await t.pump();
}

Future<void> button(WidgetTester t, String label) async {
  final f = find.byWidgetPredicate((w) => w is BigButton && w.label == label);
  await reveal(t, f);
  await invokeControl(t, t.widget<BigButton>(f).onTap);
}

class TargetsApp extends AppState {
  TargetsApp() : super.forTesting() {
    user = {'kcal_target': 2000, 'protein_target': 100};
  }
  final writes = <Map<String, dynamic>>[];
  bool refused = false;
  @override
  Future<Map<String, dynamic>> updateProfile(
    Map<String, dynamic> fields,
  ) async {
    writes.add(Map.of(fields));
    if (refused) throw StateError('synthetic target refusal');
    user = {...?user, ...fields};
    return user!;
  }
}

void main() {
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('food-inputs');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  for (final mode in ['negative', 'unreadable', 'clear', 'zero', 'refused']) {
    testWidgets(
      'COV-44 nutrition targets keep explicit typed values and retry drafts $mode',
      (t) async {
        final app = TargetsApp()..refused = mode == 'refused';
        addTearDown(app.dispose);
        bool? saved;
        await localizedPage(
          t,
          Scaffold(
            body: Builder(
              builder: (c) => FilledButton(
                onPressed: () async {
                  saved = await editNutritionGoals(c);
                },
                child: const Text('Open targets'),
              ),
            ),
          ),
          app: app,
        );
        await t.tap(find.text('Open targets'));
        await t.pumpAndSettle();
        await enter(t, 'Calories (kcal)', switch (mode) {
          'negative' => '-1',
          'unreadable' => 'abc',
          'clear' => '',
          'zero' => '0',
          _ => '2100.5',
        });
        await button(t, 'Save');
        if (['negative', 'unreadable'].contains(mode)) {
          expect(app.writes, isEmpty);
          expect(
            find.textContaining('enter a non-negative number'),
            findsOneWidget,
          );
          expect(saved, isNull);
        } else {
          if (mode == 'refused') {
            expect(
              find.textContaining('Your values are still here'),
              findsOneWidget,
            );
            expect(
              t.widget<TextField>(field('Calories (kcal)')).controller!.text,
              '2100.5',
            );
            expect(saved, isNull);
            app.refused = false;
            await button(t, 'Save');
          }
          expect(saved, true);
          expect(
            app.writes.last['kcal_target'],
            mode == 'clear'
                ? isNull
                : mode == 'zero'
                ? 0
                : 2100.5,
          );
          expect(app.writes.last['protein_target'], 100);
        }
      },
    );
  }
  for (final mode in [
    'blank',
    'zero',
    'negative',
    'unreadable',
    'weight-zero',
    'named-food',
    'unnamed-food',
    'known-macros',
    'legacy-edit',
  ]) {
    testWidgets('COV-44 quick-add explicit historical lunch draft $mode', (
      t,
    ) async {
      const date = '2021-04-06';
      const original = FoodEntry(
        id: 'synthetic-entry',
        date: date,
        meal: 'lunch',
        label: 'Synthetic retained',
        quantity: 50,
        unit: 'g',
        proteinG: 0,
        sugarG: 2,
        sodiumMg: 3,
        note: 'Synthetic note',
        loggedAt: 1617796800,
      );
      final editing = mode == 'legacy-edit';
      final db = await LocalDb.instance;
      if (editing) await NutritionDb.put(db, original);
      await localizedPage(
        t,
        QuickAddSheet(
          date: date,
          meal: 'lunch',
          from: editing ? original : null,
          editing: editing,
        ),
        push: true,
      );
      if (!['blank', 'legacy-edit'].contains(mode))
        await enter(
          t,
          'Calories (kcal)',
          mode == 'negative'
              ? '-1'
              : mode == 'unreadable'
              ? 'nope'
              : mode == 'zero'
              ? '0'
              : '200',
        );
      if (mode == 'weight-zero') await enter(t, 'Weight (g)', '0');
      if (mode.endsWith('food')) {
        final f = find.byWidgetPredicate(
          (w) => w is Pressable && w.semanticLabel == 'Save to My foods',
        );
        await reveal(t, f);
        await t.tap(f);
        await t.pumpAndSettle();
        if (mode == 'named-food') await enter(t, 'Name', ' Synthetic serving ');
      }
      if (mode == 'known-macros') {
        await enter(t, 'Protein (g)', '0');
        await enter(t, 'Weight (g)', '250');
      }
      await button(t, editing ? 'Save changes' : 'Add');
      final entries = await NutritionDb.entriesForDay(db, date);
      if ([
        'blank',
        'negative',
        'unreadable',
        'weight-zero',
        'unnamed-food',
      ].contains(mode)) {
        expect(entries, isEmpty);
        expect(find.byType(QuickAddSheet), findsOneWidget);
        expect(
          find.textContaining(
            mode == 'blank'
                ? 'Enter calories'
                : mode == 'weight-zero'
                ? 'above zero'
                : mode == 'unnamed-food'
                ? 'Name it'
                : 'non-negative',
          ),
          findsWidgets,
        );
      } else {
        expect(entries, hasLength(1));
        final e = entries.single;
        expect(e.date, date);
        expect(e.meal, 'lunch');
        expect(
          e.kcal,
          editing
              ? isNull
              : mode == 'zero'
              ? 0
              : 200,
        );
        if (editing) {
          expect(e.id, original.id);
          expect(e.loggedAt, original.loggedAt);
          expect(e.atTs, isNull);
          expect(e.sugarG, 2);
          expect(e.sodiumMg, 3);
          expect(e.note, original.note);
        }
        if (mode == 'known-macros') {
          expect(e.proteinG, 0);
          expect(e.carbsG, isNull);
          expect(e.quantity, 250);
        }
        if (mode == 'named-food') {
          expect(e.label, 'Synthetic serving');
          expect(e.foodKey, isNotNull);
          expect(await MyFoods.all(db), hasLength(1));
        }
      }
    });
  }
  for (final mode in [
    'new',
    'count',
    'scanned',
    'kept-units',
    'invalid',
    'missing-description',
    'zero-serving',
    'bad-serving-weight',
  ]) {
    testWidgets(
      'COV-44 food editor keeps serving and missing nutrients $mode',
      (t) async {
        final existing = mode == 'scanned'
            ? <String, Object?>{
                'key': 'my:synthetic',
                'label': 'Synthetic pack',
                'unit': 'g',
                'serving_g': 85.0,
                'serving_label': '6 pieces (85 g)',
                'kcal_100': 200.0,
                'protein_g_100': 0.0,
                'sodium_mg_100': 10.0,
                'source': 'barcode',
              }
            : mode == 'kept-units'
            ? myFoodDef(
                key: 'my:synthetic',
                label: 'Synthetic count',
                unit: 'g',
                refGrams: 100,
                kcal: 200,
                protein: 0,
                measures: [
                  (label: 'link', amount: 50),
                  (label: 'cup', amount: 120),
                ],
                measureCounts: {'link': 2, 'cup': 1},
              )
            : null;
        await localizedPage(
          t,
          FoodEditor(existing: existing, reviewBarcode: mode == 'scanned'),
          push: true,
        );
        if (existing == null && mode != 'missing-description')
          await enter(t, 'Description', 'Synthetic food');
        if (mode == 'count' || mode == 'bad-serving-weight') {
          final f = find.byWidgetPredicate(
            (w) => w is Pressable && w.semanticLabel == 'Unit link',
          );
          await reveal(t, f);
          await t.tap(f);
          await t.pumpAndSettle();
          await enter(t, 'Weight (g)', mode == 'count' ? '50' : '0');
        }
        if (existing == null)
          await enter(t, 'Calories (kcal)', mode == 'invalid' ? 'bad' : '200');
        if (mode == 'zero-serving') await enter(t, 'Amount', '0');
        await button(t, mode == 'scanned' ? 'Save to My foods' : 'Save');
        final defs = await MyFoods.all(await LocalDb.instance);
        if ([
          'invalid',
          'missing-description',
          'zero-serving',
          'bad-serving-weight',
        ].contains(mode)) {
          expect(defs, isEmpty);
          expect(find.byType(FoodEditor), findsOneWidget);
          expect(
            find.textContaining(
              mode == 'invalid'
                  ? 'non-negative'
                  : mode == 'bad-serving-weight'
                  ? 'serving weighs'
                  : 'serving size',
            ),
            findsWidgets,
          );
        } else {
          expect(defs, hasLength(1));
          final d = defs.single;
          expect(d['kcal_100'], isNotNull);
          expect(d['carbs_g_100'], isNull);
          if (mode == 'count') {
            expect(foodUnit(d), 'link');
            expect(foodMeasures(d).single.label, 'g');
            expect(foodMeasures(d).single.amount, closeTo(.02, .0001));
          }
          if (mode == 'scanned') {
            expect(d['source'], 'barcode');
            expect(d['sodium_mg_100'], closeTo(10 * 85 / 6, .001));
            expect(foodUnit(d), 'piece');
          }
          if (mode == 'kept-units') {
            expect(foodMeasures(d).map((m) => m.label), contains('cup'));
            expect(d['protein_g_100'], 0);
          }
        }
      },
    );
  }
}
