// Actual saved-report and derived-day readers through the rendered day link.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/derivation_engine.dart'
    show kAlgoVersion;
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/notify/notification_report.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/theme/theme_controller.dart';
import 'package:whoop_companion/ui2/screens/day_timeline.dart';
import 'package:whoop_companion/ui2/screens/metric_detail.dart' show DayNav;
import 'package:whoop_companion/ui2/screens/what_changed.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import '../support/audit_visual.dart' show loadAuditFonts;
import '../support/coverage_store.dart';
import '../support/localized_coverage.dart';

void main() {
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('finding-day-route-handoff');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  for (final scale in [1.0, 3.1]) {
    for (final historical in [false, true]) {
      testWidgets(
        'finding day link keeps viewed/report dates separate history=$historical $scale',
        (t) async {
          const original = '2021-04-07', prior = '2021-04-06';
          for (final day in [prior, original]) {
            await LocalDb.putDayResult(
              dayId: day,
              algoVersion: kAlgoVersion,
              payloadJson: jsonEncode({'date': day}),
              windowJson: '{}',
            );
          }
          final id = await NotificationReport.save(
            'Authored retained finding',
            'Original wording remains retained.',
            original,
          );
          final app = AppState.forTesting()
            ..repo = LocalRepositoryImpl(getProfileMap: () => {});
          addTearDown(app.dispose);
          final theme = ThemeController.seed(
            AppThemeChoice.light,
            Brightness.light,
          );
          addTearDown(theme.dispose);
          final db = await LocalDb.instance;
          final days = await db.query('day_result', orderBy: 'day_id');
          final report = await NotificationReport.read(id);
          await localizedPage(
            t,
            WhatChangedScreen(day: original, reportId: id),
            app: app,
            themeController: theme,
            scale: scale,
          );
          final state = t.state(find.byType(WhatChangedScreen));
          if (historical) {
            t.widget<DayNav>(find.byType(DayNav)).onDay(prior);
            await t.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 100)),
            );
            await t.pumpAndSettle();
          }
          final shown = historical ? prior : original;
          expect(t.widget<DayNav>(find.byType(DayNav)).day, shown);
          final link = find.text('What happened that day');
          await reveal(t, link);
          await t.ensureVisible(link);
          await t.tap(link);
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await t.pumpAndSettle();
          expect(find.byType(DayTimelineScreen), findsOneWidget);
          expect(
            t.widget<DayTimelineScreen>(find.byType(DayTimelineScreen)).day,
            shown,
          );
          expect(t.widget<DayNav>(find.byType(DayNav)).day, shown);
          expect(find.text('This day could not load'), findsNothing);
          await t.tap(
            find
                .byWidgetPredicate(
                  (w) => w is Pressable && w.semanticLabel == 'Back',
                )
                .first,
          );
          await t.pumpAndSettle();
          expect(find.byType(DayTimelineScreen), findsNothing);
          expect(t.state(find.byType(WhatChangedScreen)), same(state));
          await reveal(t, find.byType(DayNav));
          expect(t.widget<DayNav>(find.byType(DayNav)).day, shown);
          expect(
            t
                .widget<WhatChangedScreen>(find.byType(WhatChangedScreen))
                .reportId,
            id,
          );
          expect(await t.runAsync(() => NotificationReport.read(id)), report);
          expect(
            await t.runAsync(() => db.query('day_result', orderBy: 'day_id')),
            days,
          );
          expect(t.takeException(), isNull);
        },
      );
    }
  }
}
