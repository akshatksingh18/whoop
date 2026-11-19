// Admitted older composite rows without per-driver contributions use the
// retained plain renderer,not a fabricated direct private-widget invocation.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/state/units_controller.dart';
import 'package:whoop_companion/theme/theme_controller.dart';
import 'package:whoop_companion/ui2/screens/metric_detail.dart';
import 'package:whoop_companion/ui2/screens/readiness_detail.dart';
import 'package:whoop_companion/ui2/ui2.dart' show Pressable;
import 'coverage_food_calendar_recovery_test.dart' show flush;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('legacy-recovery-driver-handoff');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  const day = '2021-04-06';
  for (final scale in [1.0, 3.1]) {
    for (final item in [
      (stored: 'HRV', key: 'hrv', metric: 'hrv'),
      (stored: 'RHR', key: 'rhr', metric: 'resting_hr'),
      (stored: 'RR', key: 'resp', metric: 'resp_rate'),
      (stored: 'sleep', key: 'sleep', metric: 'sleep'),
    ]) {
      testWidgets(
        'retained ${item.key} without contribution keeps dated navigation at ${scale}x',
        (t) async {
          await LocalDb.putDayResult(
            dayId: day,
            algoVersion: 99,
            payloadJson: jsonEncode({
              'scalars': {'readiness': 70},
              'clinical': {
                'readiness_composite': {
                  'value': {'score': 70},
                  'drivers': [
                    {'label': item.stored},
                  ],
                },
              },
            }),
            windowJson: '{}',
            series: {'readiness': 70},
          );
          final db = await LocalDb.instance;
          final raw = await db.query('day_result');
          final series = await db.query('metric_series', orderBy: 'date,key');
          final repo = LocalRepositoryImpl(getProfileMap: () => {});
          final data = (await t.runAsync(
            () => ReadinessData.load(repo, day: day),
          ))!;
          expect(data.readiness.value, 70);
          final used = data.breakdown.where((r) => r['used'] == true).single;
          expect(used['label'], item.key);
          expect(used['weighted_contribution'], isNull);
          expect(used.containsKey('points'), false);
          final app = AppState.forTesting()..repo = repo;
          final theme = ThemeController.seed(
            AppThemeChoice.light,
            Brightness.light,
          );
          final units = UnitsController.seed(UnitSystem.metric);
          addTearDown(() {
            app.dispose();
            theme.dispose();
            units.dispose();
          });
          await localizedPage(
            t,
            const ReadinessDetail(day: day),
            app: app,
            themeController: theme,
            units: units,
            scale: scale,
            push: true,
          );
          await flush(t);
          final row = find.byWidgetPredicate(
            (w) =>
                w is Pressable &&
                (w.semanticLabel?.endsWith(', About usual') ?? false),
          );
          expect(row, findsOneWidget);
          await reveal(t, row);
          await t.tap(row);
          await flush(t);
          final detail = t.widget<MetricDetail>(find.byType(MetricDetail));
          expect(detail.metricKey, item.metric);
          expect(detail.day, day);
          await t.tap(
            find
                .byWidgetPredicate(
                  (w) => w is Pressable && w.semanticLabel == 'Back',
                )
                .first,
          );
          await flush(t);
          expect(find.byType(MetricDetail), findsNothing);
          expect(find.byType(ReadinessDetail), findsOneWidget);
          expect(await db.query('day_result'), raw);
          expect(await db.query('metric_series', orderBy: 'date,key'), series);
          expect(await LocalDb.frozenHeadline(), isNull);
          expect(t.takeException(), isNull);
        },
      );
    }
  }
}
