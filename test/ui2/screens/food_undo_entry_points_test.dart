// Every shipped deletion caller restores the actual row,not a rebuilt FoodEntry.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/data/nutrition_store.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/screens/food_diary.dart';
import 'package:whoop_companion/ui2/screens/food_picker.dart';
import 'package:whoop_companion/ui2/screens/nutrition_screen.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'food_calendar_recovery_test.dart' show flush;
import '../../support/audit_visual.dart' show loadAuditFonts;
import '../../support/coverage_store.dart';
import '../../support/localized_coverage.dart';

const day = '2021-04-06';
const target = 'authored-undo-entry';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState app;
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('food-undo-entry-points');
  });
  setUp(() async {
    await resetCoverageStore();
    app = AppState.forTesting()
      ..user = {}
      ..repo = LocalRepositoryImpl(getProfileMap: () => {});
  });
  tearDown(() => app.dispose());
  tearDownAll(LocalDb.close);

  Future<FoodEntry> seed(String route) async {
    final db = await LocalDb.instance;
    final def = myFoodDef(
      key: 'authored-undo-definition',
      label: 'Authored definition',
      refGrams: 100,
      kcal: 900,
    );
    await NutritionDb.putFoodDef(db, def);
    final entry = FoodEntry(
      id: target,
      date: day,
      meal: 'breakfast',
      label: 'Authored portion',
      foodKey: def['key'] as String,
      quantity: route == 'zero-legacy' ? 2 : 37.5,
      unit: route == 'zero-legacy' ? 'retired scoop' : 'g',
      conv: route == 'zero-legacy' ? '' : conversionSnapshot(def),
      kcal: 10,
      proteinG: 0,
      carbsG: null,
      atTs: 1617696900,
      loggedAt: 1617807700,
      source: FoodSource.barcode,
      confirmed: true,
      note: 'Authored preserved note',
    );
    await NutritionDb.put(db, entry);
    for (final (id, date) in [
      ('authored-last', day),
      ('authored-other-date', '2021-04-07'),
    ]) {
      await NutritionDb.put(
        db,
        FoodEntry(
          id: id,
          date: date,
          meal: 'breakfast',
          label: id,
          kcal: null,
          proteinG: 0,
        ),
      );
    }
    await NutritionDb.arrangeEntries(db, const [], [target, 'authored-last']);
    await db.update(
      'food_entry',
      {'created_at': 1234, 'updated_at': 5678},
      where: 'id=?',
      whereArgs: [target],
    );
    return entry;
  }

  Future<List<Map<String, Object?>>> rows(WidgetTester t) async =>
      (await t.runAsync(
        () async => (await LocalDb.instance).query('food_entry', orderBy: 'id'),
      ))!;

  Future<void> confirm(WidgetTester t) async {
    await flush(t);
    expect(find.text('Delete Authored portion?'), findsOneWidget);
    await t.tap(find.text('Delete').last);
    await flush(t);
  }

  for (final scale in [1.0, 3.1]) {
    for (final route in [
      'card',
      'meal-swipe',
      'meal-menu',
      'zero-snapshot',
      'zero-legacy',
      'quick-add',
    ]) {
      testWidgets(
        '$route Undo retains every historical column and saved order at ${scale}x',
        (t) async {
          final entry = await seed(route);
          Widget page;
          if (route == 'card') {
            page = const Scaffold(
              body: SingleChildScrollView(child: NutritionDayView(date: day)),
            );
          } else if (route.startsWith('meal')) {
            page = const MealPage(date: day, meal: 'breakfast');
          } else {
            page = Scaffold(
              body: Builder(
                builder: (c) => TextButton(
                  onPressed: () async {
                    if (route == 'quick-add') {
                      await QuickAddSheet.show(
                        c,
                        date: day,
                        meal: 'breakfast',
                        from: entry,
                        editing: true,
                      );
                    } else {
                      await editDiaryEntry(c, entry);
                    }
                  },
                  child: const Text('Edit original entry'),
                ),
              ),
            );
          }
          await localizedPage(t, page, app: app, scale: scale);
          await flush(t);
          final before = await rows(t);
          final db = await LocalDb.instance;
          final defs = await db.query('food_def');
          final otherCounts = await db.query(
            'food_day_count',
            where: 'date != ?',
            whereArgs: [day],
          );
          if (route == 'card' || route == 'meal-swipe') {
            final row = find.byKey(
              ValueKey(route == 'card' ? 'card-$target' : target),
            );
            await reveal(t, row);
            await t.drag(row, const Offset(-380, 0));
            await confirm(t);
          } else if (route == 'meal-menu') {
            final row = find.byWidgetPredicate(
              (w) =>
                  w is Pressable &&
                  w.semanticLabel == 'Authored portion, 10 kcal',
            );
            await reveal(t, row);
            await t.tap(row);
            await flush(t);
            await reveal(t, find.text('Delete'));
            await t.tap(find.text('Delete'));
            await confirm(t);
          } else {
            await t.tap(find.text('Edit original entry'));
            await flush(t);
            if (route == 'quick-add') {
              await reveal(t, find.text('Delete entry'));
              await t.tap(find.text('Delete entry'));
              await confirm(t);
              expect(find.byType(QuickAddSheet), findsNothing);
            } else {
              expect(find.byType(GramsSheet), findsOneWidget);
              await t.enterText(find.byType(TextField).first, '0');
              await t.pumpAndSettle();
              final remove = find.byWidgetPredicate(
                (w) => w is BigButton && w.label == 'Remove',
              );
              await reveal(t, remove);
              await invokeControl(t, t.widget<BigButton>(remove).onTap);
              await flush(t);
              expect(find.byType(GramsSheet), findsNothing);
            }
          }
          expect(
            await rows(t),
            before.where((r) => r['id'] != target).toList(),
          );
          expect(find.text('Deleted Authored portion'), findsOneWidget);
          await t.tap(find.text('Undo'));
          await flush(t);
          expect(await rows(t), before);
          expect(await db.query('food_def'), defs);
          expect(
            await db.query(
              'food_day_count',
              where: 'date != ?',
              whereArgs: [day],
            ),
            otherCounts,
          );
          expect(
            (await t.runAsync(
              () => NutritionDb.entriesForDay(db, day),
            ))!.map((e) => e.id),
            [target, 'authored-last'],
          );
          if (route == 'card') {
            final card = t.widget<MealCard>(
              find.byWidgetPredicate(
                (w) => w is MealCard && w.meal == 'breakfast',
              ),
            );
            expect(card.entries.map((e) => e.id), [target, 'authored-last']);
          }
          expect(t.takeException(), isNull);
        },
        timeout: const Timeout(Duration(seconds: 30)),
      );
    }
  }
  for (final outcome in ['missing', 'replacement', 'newer-edit']) {
    testWidgets(
      'stale card $outcome cannot restore stale data or overwrite a replacement',
      (t) async {
        await seed('card');
        await localizedPage(
          t,
          const Scaffold(
            body: SingleChildScrollView(child: NutritionDayView(date: day)),
          ),
          app: app,
        );
        await flush(t);
        final db = await LocalDb.instance;
        final row = find.byKey(const ValueKey('card-$target'));
        final pending = t.widget<SwipeDelete>(row).onDelete();
        await flush(t);
        if (outcome == 'missing') {
          await db.delete('food_entry', where: 'id=?', whereArgs: [target]);
        } else if (outcome == 'newer-edit') {
          await db.update(
            'food_entry',
            {'note': 'Authored concurrent edit', 'pos': 8},
            where: 'id=?',
            whereArgs: [target],
          );
        }
        final actualBeforeDelete = await rows(t);
        await t.tap(find.text('Delete').last);
        await flush(t);
        await t.runAsync(() => pending);
        await flush(t);
        if (outcome == 'missing') {
          expect(
            find.text('Food was not deleted. Please try again.'),
            findsOneWidget,
          );
          expect(find.text('Undo'), findsNothing);
          expect(await rows(t), actualBeforeDelete);
          return;
        }
        if (outcome == 'replacement') {
          await NutritionDb.put(
            db,
            const FoodEntry(
              id: target,
              date: '2021-04-08',
              meal: 'dinner',
              label: 'Authored new owner',
              kcal: 99,
            ),
          );
        }
        final held = await rows(t);
        await t.tap(find.text('Undo'));
        await flush(t);
        if (outcome == 'replacement') {
          expect(await rows(t), held);
          expect(
            find.text('Could not restore this entry. Please try again.'),
            findsOneWidget,
          );
        } else {
          expect(await rows(t), actualBeforeDelete);
        }
        expect(t.takeException(), isNull);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  }
}
