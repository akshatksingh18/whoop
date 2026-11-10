// Real weekly reader,SQLite and the existing clock seam;no hand-made WeekNumbers.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/data/nutrition_store.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/screens/week_card.dart';
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('week-food-absence-clock');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  for (final scale in [1.0, 3.1]) {
    for (final kind in [
      'today',
      'yesterday',
      'today marked complete',
      'Monday prior Sunday',
      'Monday current only',
      'empty Wednesday',
    ]) {
      testWidgets(
        'COV-68 $kind at ${scale}x keeps unfinished-food meaning independent of the real weekday',
        (t) async {
          final monday = kind.startsWith('Monday');
          final now = monday
              ? DateTime(2021, 4, 26, 12)
              : DateTime(2021, 4, 21, 12);
          final db = await LocalDb.instance;
          if (kind != 'empty Wednesday') {
            final date = switch (kind) {
              'yesterday' => '2021-04-20',
              'Monday prior Sunday' => '2021-04-25',
              'Monday current only' => '2021-04-26',
              _ => '2021-04-21',
            };
            await t.runAsync(
              () => NutritionDb.put(
                db,
                FoodEntry(
                  id: 'authored-unfinished',
                  date: date,
                  meal: 'lunch',
                  label: 'Authored unfinished meal',
                  kcal: 400,
                  proteinG: 20,
                ),
              ),
            );
            if (kind == 'today marked complete') {
              await t.runAsync(
                () => NutritionDb.setDayMark(db, date, 'complete'),
              );
            }
          }
          final before = await t.runAsync(() => db.query('food_entry'));
          final app = AppState.forTesting()
            ..repo = LocalRepositoryImpl(getProfileMap: () => {});
          addTearDown(app.dispose);
          final prior = WeekCard.debugLoads;
          await localizedPage(
            t,
            Scaffold(
              body: SingleChildScrollView(child: WeekCard(clock: () => now)),
            ),
            app: app,
            scale: scale,
            settle: false,
          );
          for (var i = 0; i < 150 && WeekCard.debugLoads <= prior; i++) {
            await t.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)),
            );
            await t.pump(const Duration(milliseconds: 20));
          }
          expect(WeekCard.debugLoads, greaterThan(prior));
          await t.pumpAndSettle();
          final text = (await readPage(t)).join(' ');
          const explanation =
              'Food summary awaits a completed day. Today and incomplete logs are excluded.';
          final excludes =
              kind != 'Monday current only' &&
              kind != 'empty Wednesday' &&
              kind != 'today marked complete';
          expect(
            text,
            excludes ? contains(explanation) : isNot(contains(explanation)),
          );
          expect(text, contains(monday ? 'Last week' : 'This week'));
          if (kind == 'today marked complete') {
            expect(text, contains('LOGGED PROTEIN'));
            expect(text, contains('20 g'));
          }
          expect(text, isNot(contains('BUDGET DEFICIT')));
          expect(text, isNot(contains('BUDGET SURPLUS')));
          expect(await t.runAsync(() => db.query('food_entry')), before);
          expect(await t.runAsync(() => db.query('day_result')), isEmpty);
          expect(await t.runAsync(() => db.query('metric_series')), isEmpty);
          expect(t.takeException(), isNull);
        },
      );
    }
  }
}
