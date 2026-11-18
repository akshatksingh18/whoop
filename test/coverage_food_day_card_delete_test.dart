// Shipped day-view -> meal-card -> confirm/delete/Undo, with real SQLite refusals.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/data/nutrition_store.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/screens/food_picker.dart';
import 'package:whoop_companion/ui2/screens/nutrition_screen.dart';
import 'coverage_food_calendar_recovery_test.dart' show flush;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

const day = '2021-04-06';
const id = 'authored-card-entry';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState app;
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('food-day-card-delete');
  });
  setUp(() async {
    await resetCoverageStore();
    app = AppState.forTesting()
      ..user = {}
      ..repo = LocalRepositoryImpl(getProfileMap: () => {});
    final db = await LocalDb.instance;
    final def = myFoodDef(
      key: 'authored-card-definition',
      label: 'Authored saved food',
      refGrams: 100,
      kcal: 900,
    );
    await NutritionDb.putFoodDef(db, def);
    await NutritionDb.put(
      db,
      FoodEntry(
        id: id,
        date: day,
        meal: 'breakfast',
        label: 'Authored card portion',
        foodKey: def['key'] as String,
        quantity: 37.5,
        unit: 'g',
        conv: conversionSnapshot(def),
        kcal: 150,
        proteinG: 0,
        carbsG: 12.5,
        fibreG: null,
        atTs: 1617696900,
        loggedAt: 1617807700,
        source: FoodSource.barcode,
        confirmed: true,
        note: 'Authored original note',
        group: 'Authored plate',
      ),
    );
    for (final (entryId, date, meal, kcal) in [
      ('authored-unknown', day, 'breakfast', null),
      ('authored-other-meal', day, 'dinner', 0.0),
      ('authored-other-day', '2021-04-07', 'breakfast', 75.0),
    ]) {
      await NutritionDb.put(
        db,
        FoodEntry(
          id: entryId,
          date: date,
          meal: meal,
          label: entryId,
          kcal: kcal,
          loggedAt: 1617807800,
        ),
      );
    }
  });
  tearDown(() async {
    app.dispose();
    final db = await LocalDb.instance;
    for (final name in ['authored_card_delete', 'authored_card_undo']) {
      await db.execute('DROP TRIGGER IF EXISTS $name');
    }
  });
  tearDownAll(LocalDb.close);

  Future<List<Map<String, Object?>>> rows(WidgetTester t) async =>
      (await t.runAsync(
        () async => (await LocalDb.instance).query('food_entry', orderBy: 'id'),
      ))!;

  Map<String, Object?> semanticRow(Map<String, Object?> row) =>
      Map<String, Object?>.of(row)
        ..remove('created_at')
        ..remove('updated_at');

  for (final scale in [1.0, 3.1]) {
    for (final refusal in ['none', 'delete', 'undo']) {
      testWidgets(
        'Food day card $refusal preserves cancel, historical ownership and Undo at ${scale}x',
        (t) async {
          var reloads = 0;
          await localizedPage(
            t,
            Scaffold(
              body: SingleChildScrollView(
                child: NutritionDayView(date: day, onChanged: () => reloads++),
              ),
            ),
            app: app,
            scale: scale,
          );
          await flush(t);
          final before = await rows(t);
          final db = await LocalDb.instance;
          final defs = await db.query('food_def');
          final siblingCounts = await db.query(
            'food_day_count',
            where: 'date != ?',
            whereArgs: [day],
          );
          final card = find.byKey(const ValueKey('card-$id'));
          expect(card, findsOneWidget);
          await reveal(t, card);

          // Exercise the real gesture at both text scales, then cancel it.
          await t.drag(card, const Offset(-380, 0));
          await flush(t);
          expect(find.text('Delete Authored card portion?'), findsOneWidget);
          await t.tap(find.text('Keep it'));
          await flush(t);
          expect(await rows(t), before);
          expect(reloads, 0);
          expect(card, findsOneWidget);

          Future<void> confirmDelete() async {
            // The same rendered callback; the gesture binding was checked above.
            final pending = t.widget<SwipeDelete>(card).onDelete();
            await flush(t);
            expect(find.text('Delete Authored card portion?'), findsOneWidget);
            await t.tap(find.text('Delete').last);
            await flush(t);
            await t.runAsync(() => pending);
            await flush(t);
          }

          if (refusal == 'delete') {
            await db.execute(
              "CREATE TRIGGER authored_card_delete BEFORE DELETE ON food_entry WHEN OLD.id='$id' BEGIN SELECT RAISE(ABORT,'authored delete refusal'); END",
            );
            await confirmDelete();
            expect(await rows(t), before);
            expect(card, findsOneWidget);
            expect(reloads, greaterThan(0));
            expect(
              find.text('Food was not deleted. Please try again.'),
              findsOneWidget,
            );
            await db.execute('DROP TRIGGER authored_card_delete');
          }
          await confirmDelete();
          expect(card, findsNothing);
          expect(
            await rows(t),
            before.where((row) => row['id'] != id).toList(),
          );
          expect(find.text('Deleted Authored card portion'), findsOneWidget);
          final deletedReloads = reloads;
          if (refusal == 'undo') {
            await db.execute(
              "CREATE TRIGGER authored_card_undo BEFORE INSERT ON food_entry WHEN NEW.id='$id' BEGIN SELECT RAISE(ABORT,'authored Undo refusal'); END",
            );
          }
          await t.tap(find.text('Undo'));
          await flush(t);
          final after = await rows(t);
          if (refusal == 'undo') {
            expect(after, before.where((row) => row['id'] != id).toList());
            expect(card, findsNothing);
            expect(reloads, deletedReloads);
            expect(
              find.text('Could not restore this entry. Please try again.'),
              findsOneWidget,
            );
          } else {
            expect(
              after.map(semanticRow).toList(),
              before.map(semanticRow).toList(),
            );
            expect(card, findsOneWidget);
            expect(reloads, greaterThan(deletedReloads));
          }
          expect(await db.query('food_def'), defs);
          expect(
            await db.query(
              'food_day_count',
              where: 'date != ?',
              whereArgs: [day],
            ),
            siblingCounts,
          );
          expect(
            t.widget<NutritionDayView>(find.byType(NutritionDayView)).date,
            day,
          );
          expect(t.takeException(), isNull);
        },
      );
    }
  }
}
