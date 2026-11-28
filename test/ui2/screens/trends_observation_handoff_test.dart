import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/derivation_engine.dart'
    show kAlgoVersion;
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/theme/theme_controller.dart';
import 'package:whoop_companion/ui2/screens/health_screen.dart';
import 'package:whoop_companion/ui2/screens/metric_detail.dart';
import 'package:whoop_companion/ui2/screens/what_changed.dart';
import 'package:whoop_companion/ui2/ui2.dart' show Observation;

import 'nutrition_root_test.dart' show io;
import '../../support/audit_visual.dart' show loadAuditFonts;
import '../../support/coverage_store.dart';
import '../../support/localized_coverage.dart';

void main() {
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('trends-observation-handoff', fresh: true);
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  for (final scale in [1.0, 3.1]) {
    testWidgets(
      'Trends opens both the history and sleeping heart rate at ${scale}x',
      (tester) async {
        final day = todayLabel();
        await MetricSeriesStore.putBaseline(
          'crossday',
          jsonEncode({
            'algo_version': kAlgoVersion,
            'built_for_day': day,
            'illness': {'state': 'red', 'date': day},
          }),
        );
        await LocalDb.putDayResult(
          dayId: day,
          algoVersion: kAlgoVersion,
          payloadJson: '{"scalars":{"rhr":64}}',
          windowJson: '{}',
          finalized: true,
          rhr: 64,
          series: const {'rhr': 64},
        );
        final artifact = await MetricSeriesStore.baseline('crossday');
        final result = await LocalDb.dayResult(day);
        final history = await MetricSeriesStore.series('rhr');
        final app = AppState.forTesting()
          ..repo = LocalRepositoryImpl(getProfileMap: () => {});
        final theme = ThemeController.seed(
          AppThemeChoice.light,
          Brightness.light,
        );
        addTearDown(app.dispose);
        addTearDown(theme.dispose);
        await localizedPage(
          tester,
          const Scaffold(body: HealthScreen()),
          app: app,
          themeController: theme,
          scale: scale,
          settle: false,
        );
        await io(tester);
        expect(find.text('Trends could not be read'), findsNothing);

        final observation = find.byWidgetPredicate(
          (widget) =>
              widget is Observation &&
              widget.detail ==
                  'Your sleeping heart rate has been running high.',
        );
        await reveal(tester, observation);
        await tester.tap(observation);
        await io(tester);
        final metric = find.byType(MetricDetail);
        expect(tester.widget<MetricDetail>(metric).metricKey, 'resting_hr');
        Navigator.of(tester.element(metric)).pop();
        await io(tester);
        expect(metric, findsNothing);

        final historyRow = find.text('What changed');
        await reveal(tester, historyRow);
        await tester.tap(historyRow);
        await io(tester);
        final review = find.byType(WhatChangedScreen);
        expect(tester.widget<WhatChangedScreen>(review).day, isNull);
        expect(tester.widget<WhatChangedScreen>(review).reportId, isNull);
        Navigator.of(tester.element(review)).pop();
        await io(tester);
        expect(review, findsNothing);
        expect(find.byType(HealthScreen), findsOneWidget);
        expect(await MetricSeriesStore.baseline('crossday'), artifact);
        expect(await LocalDb.dayResult(day), result);
        expect(await MetricSeriesStore.series('rhr'), history);
      },
    );
  }
}
