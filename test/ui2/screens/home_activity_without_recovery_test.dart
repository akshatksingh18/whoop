// Today can report observed waking activity while the night remains absent.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/derivation_engine.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/state/units_controller.dart';
import 'package:whoop_companion/theme/theme_controller.dart';
import 'package:whoop_companion/ui2/screens/home_screen.dart';
import 'package:whoop_companion/ui2/screens/readiness_detail.dart';
import 'package:whoop_companion/ui2/ui2.dart';

import 'body_history_actions_test.dart' show flush;
import '../../support/audit_visual.dart' show loadAuditFonts;
import '../../support/coverage_store.dart';
import '../../support/localized_coverage.dart';

void main() {
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('home-activity-without-recovery');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  for (final hasStrain in [false, true]) {
    testWidgets(
      'Today retains measured activity with Recovery absent and strain present: $hasStrain',
      (t) async {
        final day = todayLabel();
        final repo = LocalRepositoryImpl(getProfileMap: () => {});
        final app = AppState.forTesting()..repo = repo;
        final theme = ThemeController.seed(
          AppThemeChoice.light,
          Brightness.light,
        );
        final units = UnitsController.seed(UnitSystem.metric);
        addTearDown(app.dispose);
        addTearDown(theme.dispose);
        addTearDown(units.dispose);
        final db = (await t.runAsync(() async {
          await LocalDb.putDayResult(
            dayId: day,
            algoVersion: kAlgoVersion,
            payloadJson: jsonEncode({
              'scalars': {'calories': 45, if (hasStrain) 'strain': 4.2},
            }),
            windowJson: '{}',
            series: {if (hasStrain) 'strain': 4.2},
          );
          await LocalDb.putComputeFreshness(
            'today',
            jsonEncode({
              'today_day': day,
              'overnight_state': 'missing',
              'activity_state': 'ready',
            }),
          );
          return LocalDb.instance;
        }))!;
        final before = await t.runAsync(() => db.query('day_result'));
        final data = (await t.runAsync(() => HomeData.load(repo)))!;
        expect(data.readiness.value, isNull);
        expect(data.sleepMin.value, isNull);
        expect(data.calories.value, 45);
        expect(data.strain.value, hasStrain ? 4.2 : null);

        await localizedPage(
          t,
          Scaffold(body: HomeScreen(data: data)),
          app: app,
          themeController: theme,
          units: units,
        );
        final Finder control;
        if (hasStrain) {
          control = find.byWidgetPredicate(
            (w) => w is HeroStat && w.label == 'Recovery',
          );
          await reveal(t, control);
          final hero = t.widget<HeroStat>(control);
          expect(hero.value, isNull);
          expect(hero.lines.single, isNotEmpty);
          hero.onTap!();
        } else {
          control = find.byWidgetPredicate(
            (w) => w is StatusCard && w.what == 'Recovery is not scored today',
          );
          await reveal(t, control);
          final absence = t.widget<StatusCard>(control);
          expect(absence.fix, 'See what was missing');
          absence.onFix!();
        }
        await flush(t);
        expect(find.byType(ReadinessDetail), findsOneWidget);
        Navigator.of(t.element(find.byType(ReadinessDetail))).pop();
        await flush(t);
        expect(control, findsOneWidget);
        expect(await t.runAsync(() => db.query('day_result')), before);
        expect(await t.runAsync(LocalDb.frozenHeadline), isNull);
      },
    );
  }
}
