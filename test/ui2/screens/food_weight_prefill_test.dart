// Food history pre-fills from a saved weigh-in and preserves the daily owner.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/body_log.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/data/nutrition_store.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/state/units_controller.dart';
import 'package:whoop_companion/ui2/screens/nutrition_screen.dart';
import 'package:whoop_companion/ui2/ui2.dart';

import 'nutrition_root_test.dart' show ago, io;
import '../../support/audit_visual.dart' show loadAuditFonts;
import '../../support/coverage_store.dart';
import '../../support/localized_coverage.dart';

void main() {
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('food-weight-prefill');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  for (final firstExists in [false, true]) {
    testWidgets(
      'Food History uses earlier weigh-ins and keeps the first daily reading: $firstExists',
      (t) async {
        final app = AppState.forTesting()
          ..user = {
            'age': 38,
            'sex': 'f',
            'height_cm': 168.0,
            'weight_kg': 75.0,
          }
          ..repo = LocalRepositoryImpl(getProfileMap: () => {});
        final units = UnitsController.seed(UnitSystem.metric);
        addTearDown(app.dispose);
        addTearDown(units.dispose);
        final db = (await t.runAsync(() async {
          final db = await LocalDb.instance;
          await BodyLogDb.putWeight(ago(5), 72.0, 'kg', historyOnly: false);
          await BodyLogDb.putWeight(
            ago(firstExists ? 0 : 1),
            73.0,
            'kg',
            historyOnly: false,
          );
          await NutritionDb.put(
            db,
            FoodEntry(
              id: 'authored-complete-day',
              date: ago(4),
              meal: 'lunch',
              label: 'Authored closed day sample',
              kcal: 1800,
            ),
          );
          await NutritionDb.setDayMark(db, ago(4), 'complete');
          return db;
        }))!;
        final food = await t.runAsync(() => db.query('food_entry'));
        final earlier = await t.runAsync(() => BodyLogDb.readingsOn(ago(5)));
        await localizedPage(
          t,
          const Scaffold(body: NutritionScreen()),
          app: app,
          units: units,
          settle: false,
        );
        await io(t);
        await t.tap(find.text('History'));
        await io(t);
        expect(
          (await readPage(t)).join(' '),
          contains(
            firstExists ? '1/5 complete food days' : '1/4 complete food days',
          ),
        );

        final log = find.byWidgetPredicate(
          (w) => w is Pressable && w.semanticLabel == 'Log weight',
        );
        await reveal(t, log);
        await t.tap(log);
        await t.pumpAndSettle();
        final field = find.byType(TextField).last;
        expect(t.widget<TextField>(field).controller!.text, '73.0');
        await t.enterText(field, '74.2');
        await t.tap(find.text('Save').last);
        await io(t);
        final current = (await t.runAsync(() => BodyLogDb.readingsOn(ago(0))))!;
        expect(current.map((w) => w.kg), firstExists ? [73.0, 74.2] : [74.2]);
        expect(app.user!['weight_kg'], firstExists ? 73.0 : 74.2);
        expect(await t.runAsync(() => db.query('food_entry')), food);
        expect(await t.runAsync(() => BodyLogDb.readingsOn(ago(5))), earlier);
      },
    );
  }
}
