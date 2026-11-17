// The actual Foods tab owns empty/search states and a removed selected label.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/nutrition_store.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/screens/nutrition_screen.dart';
import 'coverage_nutrition_root_test.dart' show FoodRepo, io;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState app;
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('food-library-empty-selection', fresh: true);
  });
  setUp(() async {
    await resetCoverageStore();
    app = AppState.forTesting()
      ..user = {
        'age': 30,
        'sex': 'f',
        'height_cm': 170.0,
        'weight_kg': 70.0,
        'kcal_target': 2000,
      }
      ..repo = FoodRepo();
    await NutritionDb.put(
      await LocalDb.instance,
      const FoodEntry(
        id: 'authored-retained-food',
        date: '2021-04-06',
        meal: 'lunch',
        label: 'Authored history',
        kcal: 100,
        atTs: 1617700000,
        loggedAt: 1617800000,
      ),
    );
  });
  tearDown(() => app.dispose());
  tearDownAll(LocalDb.close);
  Future<void> open(WidgetTester t, double scale) async {
    await localizedPage(
      t,
      const Scaffold(body: NutritionScreen()),
      app: app,
      scale: scale,
      settle: false,
    );
    await io(t);
    await t.ensureVisible(find.text('Foods'));
    await t.pumpAndSettle();
    await t.tap(find.text('Foods'));
    await io(t);
  }

  for (final scale in [1.0, 3.1]) {
    for (final search in [false, true]) {
      testWidgets(
        'empty Foods search=$search scale=$scale preserves diary provenance and actions',
        (t) async {
          final db = (await t.runAsync(() => LocalDb.instance))!;
          if (search) {
            // The real search control exists while the library contains food;
            // a query can yield no matches without deleting that saved food.
            await t.runAsync(
              () => NutritionDb.putFoodDef(
                db,
                myFoodDef(
                  key: 'my:authored-existing',
                  label: 'Authored existing',
                  refGrams: 100,
                  unit: 'g',
                  kcal: 100,
                ),
              ),
            );
          }
          final library = (await t.runAsync(() => MyFoods.all(db)))!;
          final saved = await t.runAsync(() => db.query('food_entry'));
          await open(t, scale);
          if (search) {
            await t.enterText(
              find.byType(TextField).first,
              'authored-no-match',
            );
            await io(t);
          }
          final text = (await readPage(t)).join(' ');
          expect(text, contains('My foods'));
          expect(
            text,
            contains(
              search
                  ? 'No matches'
                  : 'Add a food once from its label; log any amount after.',
            ),
          );
          expect(text, contains('New'));
          expect(text, contains('Saved meals'));
          expect(await t.runAsync(() => MyFoods.all(db)), library);
          expect(await t.runAsync(() => MyFoods.meals(db)), isEmpty);
          expect(await t.runAsync(() => db.query('food_entry')), saved);
          expect(await t.runAsync(() => db.query('sessions')), isEmpty);
        },
        timeout: const Timeout(Duration(seconds: 45)),
      );
    }
  }
  for (final merge in [false, true]) {
    testWidgets(
      'a selected library label ${merge ? 'merge' : 'removal'} returns to all foods without deleting them',
      (t) async {
        final db = (await t.runAsync(() async {
          final db = await LocalDb.instance;
          for (final name in ['alpha', 'beta']) {
            await NutritionDb.putFoodDef(
              db,
              myFoodDef(
                key: 'my:$name',
                label: 'Authored $name',
                refGrams: 100,
                unit: 'g',
                kcal: 100,
                category: name,
              ),
            );
          }
          return db;
        }))!;
        final before = (await t.runAsync(() => MyFoods.all(db)))!;
        await open(t, 1);
        await t.tap(find.text('alpha').first);
        await io(t);
        expect((await readPage(t)).join(' '), contains('Authored alpha'));
        expect(find.text('Authored beta'), findsNothing);
        await reveal(t, find.text('Manage labels'));
        await t.tap(find.text('Manage labels'));
        await t.pumpAndSettle();
        await t.tap(find.byTooltip(merge ? 'Rename alpha' : 'Remove alpha'));
        await t.pumpAndSettle();
        if (merge) {
          await t.enterText(find.byType(TextField).last, 'beta');
          await t.tap(find.text('Save').last);
        } else {
          await t.tap(find.text('Remove'));
        }
        await io(t);
        final text = (await readPage(t)).join(' ');
        expect(text, contains('Authored alpha'));
        expect(text, contains('Authored beta'));
        final after = (await t.runAsync(() => MyFoods.all(db)))!;
        expect(after, hasLength(2));
        for (final row in before) {
          final actual = after.singleWhere((r) => r['key'] == row['key']);
          for (final key in row.keys.where((k) => k != 'category')) {
            expect(actual[key], row[key], reason: key);
          }
        }
        expect(
          after.singleWhere((r) => r['key'] == 'my:alpha')['category'],
          merge ? 'beta' : '',
        );
        expect(
          (await t.runAsync(() => db.query('food_entry')))!.single['logged_at'],
          1617800000,
        );
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );
  }
}
