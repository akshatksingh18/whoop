// Real Sleep host + reader + measured-only series, authored observations only.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/derivation_engine.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/state/prefs.dart';
import 'package:whoop_companion/theme/theme_controller.dart';
import 'package:whoop_companion/ui2/screens/sleep_detail.dart';
import 'package:whoop_companion/ui2/screens/rough_night.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'coverage_nutrition_root_test.dart' show io;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('sleep-rough-host');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  for (final mode in ['current', 'historical', 'ordinary']) {
    final historical = mode == 'historical';
    testWidgets(
      'COV-48 Sleep host $mode keeps one measured-night message',
      (t) async {
        final today = DateTime.parse(todayLabel());
        String label(int ago) =>
            dayLabelOf(DateTime(today.year, today.month, today.day - ago));
        for (var i = 18; i >= 0; i--) {
          final day = label(i), midnight = localDayStartSec(label(i))!;
          final unusual = mode != 'ordinary' && i <= 1;
          final scalars = <String, double?>{
            'rhr': unusual ? 90 : 60.0 + i % 3,
            'rmssd': unusual ? 20 : 65.0 + i % 3,
            'dip_pct': unusual ? 5 : 30.0 + i % 3,
            'tst_min': 420,
          };
          await LocalDb.putDayResult(
            dayId: day,
            algoVersion: kAlgoVersion,
            payloadJson: jsonEncode({
              'date': day,
              'device_family': 'gen4',
              'sleep_source': 'auto',
              'scalars': scalars,
              'sleep': {
                'accounting': {
                  'confidence': .8,
                  'value': {
                    'tst_sec': 25200,
                    'waso_sec': 3600,
                    'efficiency_pct': 87.5,
                    'light_sec': 12000,
                    'deep_sec': 4800,
                    'rem_sec': 8400,
                    'nrem_sec': 16800,
                  },
                },
                'window': {
                  'value': {
                    'onset_ms': (midnight - 3600) * 1000,
                    'offset_ms': (midnight + 7 * 3600) * 1000,
                    'spt_sec': 28800,
                  },
                },
              },
            }),
            windowJson: '{}',
            finalized: true,
            source: 'band',
            series: scalars,
          );
        }
        final db = await LocalDb.instance;
        final before = await db.query('metric_series', orderBy: 'date,key');
        final bundles = await db.query('day_result', orderBy: 'day_id');
        final app = AppState.forTesting()
          ..repo = LocalRepositoryImpl(getProfileMap: () => {});
        final theme = ThemeController.seed(
          AppThemeChoice.light,
          Brightness.light,
        );
        addTearDown(app.dispose);
        addTearDown(theme.dispose);
        final day = label(historical ? 1 : 0);
        Future<void> open() async {
          await localizedPage(
            t,
            SleepDetail(day: day),
            app: app,
            themeController: theme,
            settle: false,
          );
          await io(t);
          await readPage(t);
        }

        await open();
        if (historical || mode == 'ordinary') {
          expect(find.byType(RoughNightCard), findsNothing);
          expect(Prefs.getString(kRoughNightDismissed, ''), isEmpty);
          if (mode == 'ordinary') {
            expect(
              (await readPage(t)).join(' '),
              contains('Nothing stood out.'),
            );
          }
        } else {
          expect(find.byType(RoughNightCard), findsOneWidget);
          expect(
            t.widget<RoughNightCard>(find.byType(RoughNightCard)).night.day,
            day,
          );
          expect(
            t.widget<RoughNightCard>(find.byType(RoughNightCard)).night.signs,
            3,
          );
          expect(
            t.widget<RoughNightCard>(find.byType(RoughNightCard)).ask,
            'never',
          );
          expect(find.text('Sleeping heart rate ran high'), findsNothing);
          expect(find.text('Tell it what happened'), findsNothing);
          final dismiss = find.byWidgetPredicate(
            (w) => w is Pressable && w.semanticLabel == 'Dismiss',
          );
          await reveal(t, dismiss);
          await t.tap(dismiss);
          await io(t);
          expect(find.byType(RoughNightCard), findsNothing);
          expect(Prefs.getString(kRoughNightDismissed, ''), day);
          app.bumpInsights();
          await io(t);
          await readPage(t);
          expect(find.byType(RoughNightCard), findsNothing);
          await t.pumpWidget(const SizedBox());
          await t.pumpAndSettle();
          await open();
          expect(find.byType(RoughNightCard), findsNothing);
          expect(Prefs.getString(kRoughNightDismissed, ''), day);
        }
        expect(
          await t.runAsync(
            () => db.query('metric_series', orderBy: 'date,key'),
          ),
          before,
        );
        expect(
          await t.runAsync(() => db.query('day_result', orderBy: 'day_id')),
          bundles,
        );
        expect(await t.runAsync(() => db.query('journal')), isEmpty);
        expect(t.takeException(), isNull);
      },
      timeout: const Timeout(Duration(seconds: 35)),
    );
  }
}
