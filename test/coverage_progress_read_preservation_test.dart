// Public Progress loader over real stored food/sessions and genuine SQL refusal.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/data/nutrition_store.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/screens/progress_screen.dart';
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('progress-read-preservation');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  for (final table in ['food_entry', 'food_day_mark', 'sessions']) {
    for (final retained in [false, true]) {
      testWidgets(
        '$table refusal retains previous=$retained and permits actual reader retry',
        (t) async {
          final db = await LocalDb.instance;
          const day = '2021-04-06';
          await NutritionDb.put(
            db,
            const FoodEntry(
              id: 'authored-food',
              date: day,
              meal: 'lunch',
              label: 'Authored food',
              kcal: 300,
              proteinG: 12,
              quantity: 100,
              atTs: 1617724800,
            ),
          );
          await NutritionDb.setDayMark(db, day, 'complete');
          await LocalDb.putSession({
            'id': 'authored-session',
            'type': 'yoga',
            'start_ts': 1617724800,
            'end_ts': 1617726600,
            'status': 'done',
            'created_at': 1,
          });
          final rows = await db.query(table);
          final app = AppState.forTesting()
            ..repo = LocalRepositoryImpl(getProfileMap: () => {});
          addTearDown(app.dispose);
          late BuildContext context;
          await localizedPage(
            t,
            Builder(
              builder: (c) {
                context = c;
                return const Scaffold(body: Text('Existing Progress reader'));
              },
            ),
            app: app,
          );
          final original = (await t.runAsync(
            () => ProgressData.load(context),
          ))!;
          expect(original.food.single.kcal, 300);
          expect(original.sessions.single.type, 'yoga');
          await db.execute(
            'ALTER TABLE $table RENAME TO authored_hidden_progress',
          );
          ProgressData broken;
          try {
            broken = (await t.runAsync(
              () => ProgressData.load(
                context,
                previous: retained ? original : null,
              ),
            ))!;
            expect(
              broken.readErrors,
              contains(table == 'sessions' ? 'Workouts' : 'Food'),
            );
            if (table == 'sessions') {
              expect(broken.sessions, retained ? original.sessions : isEmpty);
              expect(broken.food, original.food);
            } else {
              if (retained) {
                expect(broken.food, original.food);
              } else if (table == 'food_entry') {
                expect(broken.food, isEmpty);
              } else {
                // Entries were read successfully; only the complete-day mark
                // is unavailable. Retain measured intake without claiming a
                // complete/countable day.
                expect(broken.food.single.date, day);
                expect(broken.food.single.kcal, 300);
                expect(broken.food.single.protein, 12);
                expect(broken.food.single.counts, false);
              }
              expect(broken.sessions, original.sessions);
            }
            expect(await db.query('authored_hidden_progress'), rows);
          } finally {
            await db.execute(
              'ALTER TABLE authored_hidden_progress RENAME TO $table',
            );
          }
          final retry = (await t.runAsync(
            () => ProgressData.load(context, previous: broken),
          ))!;
          expect(retry.readErrors, isEmpty);
          expect(retry.food, original.food);
          expect(retry.sessions, original.sessions);
          expect(await db.query(table), rows);
          expect(await db.query('decoded_onehz'), isEmpty);
          expect(await db.query('day_result'), isEmpty);
        },
      );
    }
  }
}
