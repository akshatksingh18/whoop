// The visible Journal Back action abandons the draft for the correct saved day.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/journal_fields.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/state/units_controller.dart';
import 'package:whoop_companion/ui2/screens/journal_compose.dart';
import 'package:whoop_companion/ui2/ui2.dart';

import '../ui2/screens/body_history_actions_test.dart' show flush;
import '../support/audit_visual.dart' show loadAuditFonts;
import '../support/store_fixtures.dart';
import '../support/coverage_store.dart';
import '../support/localized_coverage.dart';

void main() {
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('journal-back-preservation');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'Journal Back at ${scale}x leaves both saved civil dates unchanged',
      (t) async {
        const day = '2021-04-06';
        const next = '2021-04-07';
        final app = AppState.forTesting()
          ..repo = LocalRepositoryImpl(getProfileMap: () => {});
        final units = UnitsController.seed(UnitSystem.metric);
        addTearDown(app.dispose);
        addTearDown(units.dispose);
        final db = (await t.runAsync(() async {
          await JournalStore.put(day, '["travel"]', 'Authored saved note');
          await JournalStore.put(next, '["sick"]', 'Authored next-day note');
          await seedJournalMetrics(day, {
            'weight_kg': const JournalMetricValue(71),
          });
          return LocalDb.instance;
        }))!;
        final prior = await t.runAsync(
          () => db.query('journal', orderBy: 'date'),
        );
        await localizedPage(
          t,
          const JournalCompose(date: day),
          app: app,
          units: units,
          push: true,
        );
        await flush(t);
        expect(find.text(day), findsOneWidget);
        final note = find.byWidgetPredicate(
          (w) => w is TextField && w.controller?.text == 'Authored saved note',
        );
        await reveal(t, note);
        await t.enterText(note, 'Authored unsaved change');
        final back = find.byWidgetPredicate(
          (w) => w is Pressable && w.semanticLabel == 'Back',
        );
        await reveal(t, back);
        await t.tap(back);
        await flush(t);

        expect(find.byType(JournalCompose), findsNothing);
        expect(find.text('Closed test page'), findsOneWidget);
        expect(
          await t.runAsync(() => db.query('journal', orderBy: 'date')),
          prior,
        );
        final weights = (await t.runAsync(
          () => JournalStore.metricsForDay(day),
        ))!;
        expect(weights['weight_kg']?.value, 71);
        expect(
          await t.runAsync(() => JournalStore.metricsForDay(next)),
          isEmpty,
        );
      },
    );
  }
}
