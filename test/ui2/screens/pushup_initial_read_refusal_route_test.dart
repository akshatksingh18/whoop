// The embedded Pushups entry remains usable before its first SQLite read.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/pushups.dart';
import 'package:whoop_companion/ui2/screens/pushups_screen.dart';
import 'package:whoop_companion/ui2/screens/today_plan.dart';

import 'nutrition_root_test.dart' show io;
import '../../support/audit_visual.dart' show loadAuditFonts;
import '../../support/coverage_store.dart';
import '../../support/localized_coverage.dart';

void main() {
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('pushup-initial-read-refusal-route');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  testWidgets(
    'embedded Pushups opens and retries empty or paused days after a refused read',
    (t) async {
      // Startup reconciliation keeps a shared queue for the owning widget clock.
      for (final paused in [false, true]) {
        await t.pumpWidget(const SizedBox());
        await io(t);
        await t.runAsync(resetCoverageStore);
        final db = (await t.runAsync(() => LocalDb.instance))!;
        final before = await t.runAsync(() async {
          if (paused) {
            final now = DateTime.now();
            await PushupDb.save(
              PushupSession(
                id: 'authored-paused-pushups',
                day: todayLabel(now),
                started: now,
                interval: 40,
              ),
            );
          }
          return db.query('pushup_session');
        });
        var withheld = false;
        try {
          await t.runAsync(
            () => db.execute(
              'ALTER TABLE pushup_session RENAME TO authored_held_pushup_session',
            ),
          );
          withheld = true;
          await localizedPage(
            t,
            const Scaffold(
              body: TodayPushupRow(embedded: true, showWhenEmpty: true),
            ),
            settle: false,
          );
          await io(t);
          final row = find.byType(PlanRow);
          expect(t.widget<PlanRow>(row).sub, 'Open day and reminders');
          await t.tap(find.text('Open day and reminders'));
          await io(t);
          expect(find.byType(PushupsScreen), findsOneWidget);
          expect(find.text('Pushups could not load'), findsOneWidget);
          expect(find.text('Your saved days are intact.'), findsOneWidget);
          expect(
            await t.runAsync(() => db.query('authored_held_pushup_session')),
            before,
          );

          await t.runAsync(
            () => db.execute(
              'ALTER TABLE authored_held_pushup_session RENAME TO pushup_session',
            ),
          );
          withheld = false;
          final retry = find.text('Retry');
          await reveal(t, retry);
          await t.tap(retry);
          await io(t);
          expect(find.text('Pushups could not load'), findsNothing);
          expect(find.text(paused ? 'Resume' : 'Start my day'), findsOneWidget);
          expect(await t.runAsync(() => db.query('pushup_session')), before);
        } finally {
          if (withheld) {
            await t.runAsync(
              () => db.execute(
                'ALTER TABLE authored_held_pushup_session RENAME TO pushup_session',
              ),
            );
          }
        }
      }
    },
  );
}
