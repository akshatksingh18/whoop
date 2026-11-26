// Existing Sleep actions retain the viewed day and leave stored observations intact.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/theme/theme_controller.dart';
import 'package:whoop_companion/ui2/screens/metric_detail.dart';
import 'package:whoop_companion/ui2/screens/naps.dart';
import 'package:whoop_companion/ui2/screens/sleep_breathing.dart';
import 'package:whoop_companion/ui2/screens/sleep_detail.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import '../../support/audit_visual.dart' show loadAuditFonts;
import '../../support/coverage_store.dart';
import '../../support/localized_coverage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const day = '2021-04-06';
  final onset = DateTime(2021, 4, 5, 23).millisecondsSinceEpoch ~/ 1000;
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('sleep-retained-routes');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  for (final scale in [1.0, 3.1]) {
    for (final route in [
      'unknown-report',
      'known-report',
      'empty-naps',
      'nap-row',
      'nap-edit',
      'respiration',
    ]) {
      testWidgets(
        '$route from the historical Sleep page retains data at ${scale}x',
        (t) async {
          final db = await LocalDb.instance;
          await LocalDb.putMetricSeriesValue(day, 'steps', 1234);
          final before = await db.query('metric_series');
          final app = AppState.forTesting()
            ..repo = LocalRepositoryImpl(getProfileMap: () => {});
          final theme = ThemeController.seed(
            AppThemeChoice.light,
            Brightness.light,
          );
          addTearDown(app.dispose);
          addTearDown(theme.dispose);
          final data = SleepData(
            day: day,
            days: const [day],
            night: route == 'unknown-report'
                ? const {'sleep_source': 'rejected'}
                : {
                    'duration_min': 420,
                    'in_bed_min': 480,
                    'onset_ts': onset,
                    'wake_ts': onset + 28800,
                    'sleep_source': 'confirmed',
                    if (route == 'respiration') 'resp': {'value': 14.0},
                  },
            naps: route == 'nap-row'
                ? [
                    {
                      'start': onset + 54000,
                      'end': onset + 55800,
                      'duration_min': 30,
                      'source': 'manual',
                    },
                  ]
                : const [],
          );
          await localizedPage(
            t,
            SleepDetail(data: data),
            app: app,
            themeController: theme,
            scale: scale,
          );
          Finder target;
          if (route.endsWith('report')) {
            target = find.text('Breathing pattern in sleep');
          } else if (route == 'nap-edit') {
            target = find.byWidgetPredicate(
              (w) => w is Section && w.title == 'Naps',
            );
          } else if (route == 'respiration') {
            target = find.byWidgetPredicate(
              (w) =>
                  w is Pressable &&
                  (w.semanticLabel?.contains('14.0 br/min, open its trend') ??
                      false),
            );
          } else {
            target = find.text(
              route == 'empty-naps' ? 'No naps logged' : 'Added by you',
            );
          }
          await reveal(t, target);
          if (route == 'nap-edit') {
            t.widget<Section>(target).onAction!();
          } else {
            await t.tap(target);
          }
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 150)),
          );
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
          final destination = route.endsWith('report')
              ? find.byType(SleepBreathingScreen)
              : route == 'respiration'
              ? find.byType(MetricDetail)
              : find.byType(NapsScreen);
          expect(destination, findsOneWidget);
          if (!route.endsWith('report') && route != 'respiration') {
            expect(t.widget<NapsScreen>(destination).day, day);
          }
          Navigator.of(t.element(destination)).pop();
          await t.pumpAndSettle();
          expect(find.byType(SleepDetail), findsOneWidget);
          expect(
            t.widget<SleepDetail>(find.byType(SleepDetail)).data,
            same(data),
          );
          expect(await t.runAsync(() => db.query('metric_series')), before);
          expect(await t.runAsync(() => db.query('sleep_nap')), isEmpty);
          expect(await t.runAsync(() => db.query('sleep_override')), isEmpty);
        },
      );
    }
  }
}
