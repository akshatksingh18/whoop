// Current Today controls retain their evidence destination and original snapshot.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/models/metric.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/theme/theme_controller.dart';
import 'package:whoop_companion/ui2/screens/home_screen.dart';
import 'package:whoop_companion/ui2/screens/metric_detail.dart';
import 'package:whoop_companion/ui2/screens/readiness_detail.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('home-evidence-handoff');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  for (final scale in [1.0, 3.1]) {
    for (final target in ['recovery', 'amber', 'red']) {
      testWidgets('Today $target evidence returns intact at ${scale}x', (
        t,
      ) async {
        final app = AppState.forTesting()
          ..repo = LocalRepositoryImpl(getProfileMap: () => {});
        final theme = ThemeController.seed(
          AppThemeChoice.light,
          Brightness.light,
        );
        addTearDown(app.dispose);
        addTearDown(theme.dispose);
        final db = await LocalDb.instance;
        await LocalDb.putMetricSeriesValue(todayLabel(), 'resting_hr', 62);
        final before = await db.query('metric_series');
        final data = HomeData(
          dayId: todayLabel(),
          readiness: const Metric(value: 75, confidence: 1),
          illnessState: target == 'recovery' ? null : target,
          illnessDay: target == 'recovery' ? null : todayLabel(),
          illnessZ: target == 'recovery' ? null : 2.5,
        );
        await localizedPage(
          t,
          Scaffold(body: HomeScreen(data: data)),
          app: app,
          themeController: theme,
          scale: scale,
        );
        final control = target == 'recovery'
            ? find.byWidgetPredicate(
                (w) => w is HeroStat && w.label == 'Recovery',
              )
            : find.byType(Observation);
        await reveal(t, control);
        expect(control, findsOneWidget);
        await t.tap(control);
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        final destination = target == 'recovery'
            ? find.byType(ReadinessDetail)
            : find.byType(MetricDetail);
        expect(destination, findsOneWidget);
        if (target != 'recovery') {
          expect(t.widget<MetricDetail>(destination).metricKey, 'resting_hr');
          expect(t.widget<MetricDetail>(destination).day, isNull);
        }
        Navigator.of(t.element(destination)).pop();
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await t.pumpAndSettle();
        expect(find.byType(HomeScreen), findsOneWidget);
        final hero = find.byWidgetPredicate(
          (w) => w is HeroStat && w.label == 'Recovery',
        );
        await reveal(t, hero);
        expect(t.widget<HeroStat>(hero).value, '75');
        expect(await t.runAsync(() => db.query('metric_series')), before);
        expect(t.takeException(), isNull);
      });
    }
  }
}
