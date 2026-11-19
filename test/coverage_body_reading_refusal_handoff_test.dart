// Real historical reading deletion, SQLite rollback, retry and edited draft.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/body_log.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/screens/progress_screen.dart';
import 'package:whoop_companion/ui2/screens/journal_compose.dart'
    show WhoopTextField;
import 'package:whoop_companion/ui2/ui2.dart';
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

Finder get _weight => find.descendant(
  of: find.byWidgetPredicate(
    (w) => w is WhoopTextField && w.label == 'Weight (kg)',
  ),
  matching: find.byType(TextField),
);

void main() {
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('body-reading-refusal-handoff');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  for (final scale in [1.0, 3.1]) {
    for (final draft in [false, true]) {
      testWidgets(
        'historical reading refusal preserves rows and retries $scale draft=$draft',
        (t) async {
          const day = '2021-04-06', other = '2021-04-07';
          await BodyLogDb.putWeight(day, 70, 'kg', at: DateTime(2021, 4, 6, 8));
          await BodyLogDb.putWeight(day, 71, 'kg', at: DateTime(2021, 4, 6, 9));
          await BodyLogDb.putWeight(other, 72, 'kg');
          final db = await LocalDb.instance;
          final before = await db.query('body_weight_reading', orderBy: 'id');
          final daily = await db.query('body_weight', orderBy: 'date');
          final app = AppState.forTesting()..user = {'weight_kg': 80.0};
          addTearDown(app.dispose);
          addTearDown(
            () => db.execute('DROP TRIGGER IF EXISTS authored_reading_refusal'),
          );
          await localizedPage(
            t,
            const BodyEntryScreen(unit: 'kg', date: day),
            app: app,
            scale: scale,
          );
          if (draft) await t.enterText(_weight, '73.25');
          await t.runAsync(
            () => db.execute(
              "CREATE TRIGGER authored_reading_refusal BEFORE DELETE ON body_weight_reading BEGIN SELECT RAISE(ABORT,'authored refusal'); END",
            ),
          );

          Future<void> removeFirst() async {
            final action = find.byWidgetPredicate(
              (w) =>
                  w is Pressable &&
                  (w.semanticLabel?.contains("the day's weight. Delete") ??
                      false),
            );
            expect(action, findsOneWidget);
            Future<void>? pending;
            await t.runAsync(() async {
              pending = Future<void>.sync(t.widget<Pressable>(action).onTap!);
              await Future<void>.delayed(const Duration(milliseconds: 20));
            });
            await t.pumpAndSettle();
            expect(find.text('Delete this reading?'), findsOneWidget);
            expect(
              find.textContaining("The next reading becomes the day's weight."),
              findsOneWidget,
            );
            await t.tap(find.text('Delete').last);
            await t.runAsync(() => pending!);
            await t.pumpAndSettle();
            expect(t.takeException(), isNull);
          }

          await removeFirst();
          expect(find.text('That reading was not deleted.'), findsOneWidget);
          expect(
            await t.runAsync(
              () => db.query('body_weight_reading', orderBy: 'id'),
            ),
            before,
          );
          expect(
            await t.runAsync(() => db.query('body_weight', orderBy: 'date')),
            daily,
          );
          expect(
            t.widget<TextField>(_weight).controller!.text,
            draft ? '73.25' : '70',
          );
          expect(app.user!['weight_kg'], 80);

          await t.runAsync(
            () => db.execute('DROP TRIGGER authored_reading_refusal'),
          );
          await removeFirst();
          final remaining = (await t.runAsync(
            () => BodyLogDb.readingsOn(day),
          ))!;
          expect(remaining, hasLength(1));
          expect(remaining.single.kg, 71);
          expect(
            remaining.single.atTs,
            DateTime(2021, 4, 6, 9).millisecondsSinceEpoch ~/ 1000,
          );
          expect(remaining.single.historyOnly, true);
          expect((await t.runAsync(() => BodyLogDb.weightOn(day)))!.kg, 71);
          expect((await t.runAsync(() => BodyLogDb.weightOn(other)))!.kg, 72);
          expect(
            t.widget<TextField>(_weight).controller!.text,
            draft ? '73.25' : '71',
          );
          expect(app.user!['weight_kg'], 80);
        },
      );
    }
  }
}
