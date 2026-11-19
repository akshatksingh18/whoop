// Promoted original regression:actual historical row and saved drag position.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/data/nutrition_store.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/screens/food_diary.dart';
import 'package:whoop_companion/ui2/screens/food_picker.dart';
import 'package:whoop_companion/ui2/screens/nutrition_screen.dart';
import 'coverage_food_calendar_recovery_test.dart' show flush;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('food-undo-position-negative');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  testWidgets(
    'Undo preserves the actual dragged position of a historical Food card entry',
    (t) async {
      final db = await LocalDb.instance;
      for (final (i, id) in ['first', 'target', 'last'].indexed) {
        await NutritionDb.put(
          db,
          FoodEntry(
            id: id,
            date: '2021-04-06',
            meal: 'breakfast',
            label: 'Authored $id',
            kcal: id == 'last' ? null : 10,
            proteinG: 0,
            atTs: 1617696900 + i,
            loggedAt: 1617807700 + i,
          ),
        );
      }
      await NutritionDb.reorderEntries(db, ['target', 'last', 'first']);
      final app = AppState.forTesting()
        ..user = {}
        ..repo = LocalRepositoryImpl(getProfileMap: () => {});
      addTearDown(app.dispose);
      await localizedPage(
        t,
        const Scaffold(
          body: SingleChildScrollView(
            child: NutritionDayView(date: '2021-04-06'),
          ),
        ),
        app: app,
      );
      await flush(t);
      final before = await db.query('food_entry', orderBy: 'id');
      final card = find.byKey(const ValueKey('card-target'));
      final pending = t.widget<SwipeDelete>(card).onDelete();
      await flush(t);
      await t.tap(find.text('Delete').last);
      await flush(t);
      await t.runAsync(() => pending);
      await t.tap(find.text('Undo'));
      await flush(t);
      final after = await db.query('food_entry', orderBy: 'id');
      final b = before.singleWhere((r) => r['id'] == 'target'),
          a = after.singleWhere((r) => r['id'] == 'target');
      final meal = t.widget<MealCard>(
        find.byWidgetPredicate((w) => w is MealCard && w.meal == 'breakfast'),
      );
      expect(a, b);
      expect(after, before);
      expect(meal.entries.map((e) => e.id), ['target', 'last', 'first']);
      expect(a['at_ts'], b['at_ts']);
      expect(a['logged_at'], b['logged_at']);
      expect(a['kcal'], b['kcal']);
      expect(a['protein_g'], 0);
      expect(
        a['pos'],
        b['pos'],
        reason:
            'Undo must retain the order saved through the real reorder action',
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
