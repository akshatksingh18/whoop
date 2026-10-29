// Meal component mutations, rollback and Undo through authored SQLite inputs.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/nutrition_store.dart';
import 'package:whoop_companion/ui2/screens/food_diary.dart';
import 'package:whoop_companion/ui2/screens/food_picker.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('meal-mutation-boundaries');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  const date = '2021-04-06';
  const entry = FoodEntry(
    id: 'synthetic-entry',
    date: date,
    meal: 'lunch',
    label: 'Synthetic oats',
    foodKey: 'synthetic-food',
    quantity: 50,
    unit: 'g',
    kcal: 100,
    proteinG: 5,
    group: 'Synthetic bowl',
  );
  const other = FoodEntry(
    id: 'synthetic-other',
    date: date,
    meal: 'lunch',
    label: 'Synthetic unknown',
    group: 'Synthetic plate',
  );
  Future<void> seed() async {
    final db = await LocalDb.instance;
    await NutritionDb.putFoodDef(
      db,
      myFoodDef(
        key: 'synthetic-food',
        label: entry.label,
        refGrams: 100,
        kcal: 200,
        protein: 10,
      ),
    );
    await NutritionDb.put(db, entry);
    await NutritionDb.put(db, other);
  }

  Future<void> flush(WidgetTester t) async {
    for (var i = 0; i < 8; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 15)),
      );
      await t.pump(const Duration(milliseconds: 30));
    }
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  }

  for (final refusal in [false, true]) {
    testWidgets(
      'COV-47 meal arrangement ${refusal ? 'rolls back' : 'persists'} whole groups and order',
      (t) async {
        await seed();
        final db = await LocalDb.instance;
        await localizedPage(t, const MealPage(date: date, meal: 'lunch'));
        expect(find.textContaining('minimum'), findsOneWidget);
        if (refusal)
          await db.execute(
            "CREATE TRIGGER synthetic_arrange_refusal BEFORE UPDATE ON food_entry BEGIN SELECT RAISE(ABORT,'synthetic arrange refusal'); END",
          );
        final list = t.widget<GroupedDragList<FoodEntry>>(
          find.byType(GroupedDragList<FoodEntry>),
        );
        list.onChanged([
          ('Synthetic plate', other),
          ('Synthetic plate', entry),
        ]);
        await flush(t);
        final stored = (await t.runAsync(
          () => NutritionDb.entriesForDay(db, date),
        ))!;
        expect(
          stored.firstWhere((e) => e.id == entry.id).group,
          refusal ? entry.group : 'Synthetic plate',
        );
        expect(stored.firstWhere((e) => e.id == entry.id).kcal, 100);
        if (refusal) {
          expect(
            find.text('The change was not saved. Please try again.'),
            findsOneWidget,
          );
          await db.execute('DROP TRIGGER synthetic_arrange_refusal');
          t
              .widget<GroupedDragList<FoodEntry>>(
                find.byType(GroupedDragList<FoodEntry>),
              )
              .onChanged([
                ('Synthetic plate', other),
                ('Synthetic plate', entry),
              ]);
          await flush(t);
          expect(
            (await t.runAsync(
              () => NutritionDb.entriesForDay(db, date),
            ))!.firstWhere((e) => e.id == entry.id).group,
            'Synthetic plate',
          );
        }
      },
    );
  }
  for (final selection in ['No sub-heading', 'Synthetic plate']) {
    testWidgets('COV-47 meal item moves to $selection without repricing', (
      t,
    ) async {
      await seed();
      await localizedPage(t, const MealPage(date: date, meal: 'lunch'));
      final row = find.byWidgetPredicate(
        (w) => w is Pressable && w.semanticLabel == 'Synthetic oats, 100 kcal',
      );
      await t.tap(row);
      await flush(t);
      expect(find.text('Change amount'), findsOneWidget);
      await t.tap(find.text('Put under a sub-heading'));
      await flush(t);
      await t.tap(find.text(selection).last);
      await flush(t);
      final db = await LocalDb.instance;
      final saved = (await t.runAsync(
        () => NutritionDb.entriesForDay(db, date),
      ))!.firstWhere((e) => e.id == entry.id);
      expect(saved.group, selection == 'No sub-heading' ? '' : selection);
      expect(saved.quantity, 50);
      expect(saved.kcal, 100);
      expect(saved.date, date);
    });
  }
  for (final phase in ['delete', 'undo']) {
    testWidgets(
      'COV-47 refused $phase keeps the food row recoverable and visible',
      (t) async {
        await seed();
        final db = await LocalDb.instance;
        late BuildContext context;
        await localizedPage(
          t,
          Scaffold(
            body: Builder(
              builder: (c) {
                context = c;
                return const Text('Synthetic diary');
              },
            ),
          ),
        );
        if (phase == 'delete')
          await db.execute(
            "CREATE TRIGGER synthetic_delete_refusal BEFORE DELETE ON food_entry BEGIN SELECT RAISE(ABORT,'synthetic delete refusal'); END",
          );
        bool? removed;
        await t.runAsync(() async {
          removed = await deleteDiaryEntry(context, entry, confirm: false);
        });
        await t.pumpAndSettle();
        if (phase == 'delete') {
          expect(removed, false);
          expect(
            find.text('Food was not deleted. Please try again.'),
            findsOneWidget,
          );
          expect(
            (await t.runAsync(() => NutritionDb.entriesForDay(db, date)))!,
            hasLength(2),
          );
          await db.execute('DROP TRIGGER synthetic_delete_refusal');
        } else {
          expect(removed, true);
          expect(
            (await t.runAsync(() => NutritionDb.entriesForDay(db, date)))!,
            hasLength(1),
          );
          await db.execute(
            "CREATE TRIGGER synthetic_undo_refusal BEFORE INSERT ON food_entry BEGIN SELECT RAISE(ABORT,'synthetic undo refusal'); END",
          );
          final undo = t
              .widget<SnackBarAction>(find.byType(SnackBarAction))
              .onPressed;
          await invokeControl(t, undo);
          expect(
            find.text('Could not restore this entry. Please try again.'),
            findsOneWidget,
          );
          await db.execute('DROP TRIGGER synthetic_undo_refusal');
          await invokeControl(t, undo);
          final restored = (await t.runAsync(
            () => NutritionDb.entriesForDay(db, date),
          ))!.firstWhere((e) => e.id == entry.id);
          expect(restored.quantity, 50);
          expect(restored.group, entry.group);
          expect(restored.kcal, 100);
          expect(restored.date, date);
        }
      },
    );
  }
}
