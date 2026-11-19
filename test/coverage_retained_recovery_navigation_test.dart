// Saved composite evidence can outlive its baseline rows;do not invent comparison text.
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/derivation_engine.dart'
    show kAlgoVersion;
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/day_label.dart';
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
    await coverageStore('retained-recovery-navigation');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  for (final scale in [1.0, 3.1]) {
    for (final mode in ['one-driver', 'two-drivers', 'pin-without-evidence']) {
      testWidgets(
        '$mode retained Recovery keeps honest baseline absence and dated navigation at ${scale}x',
        (t) async {
          final today = DateTime.parse(todayLabel());
          final day = dayLabelOf(
            DateTime(today.year, today.month, today.day - 2),
          );
          final two = mode == 'two-drivers';
          final score = (100 / (1 + math.exp(-(two ? 1.2 : 1.0)))).round();
          await LocalDb.putDayResult(
            dayId: day,
            algoVersion: kAlgoVersion,
            payloadJson: jsonEncode({
              'scalars': {'readiness': score},
              'clinical': {
                'readiness_composite': {
                  'value': {'score': score},
                  'confidence': .8,
                  'drivers': [
                    {'label': 'HRV', 'contribution': 1.0},
                    if (two) {'label': 'RHR', 'contribution': .2},
                  ],
                },
              },
            }),
            windowJson: '{}',
            series: {'readiness': score.toDouble()},
          );
          if (mode == 'pin-without-evidence') {
            await LocalDb.setFrozenHeadline(day, score);
          }
          final repo = LocalRepositoryImpl(getProfileMap: () => {});
          final app = AppState.forTesting()
            ..user = {}
            ..repo = repo;
          addTearDown(app.dispose);
          final theme = ThemeController.seed(
            AppThemeChoice.light,
            Brightness.light,
          );
          final units = UnitsController.seed(UnitSystem.metric);
          addTearDown(theme.dispose);
          addTearDown(units.dispose);
          final data = (await t.runAsync(
            () => ReadinessData.load(repo, day: day),
          ))!;
          expect(data.readiness.value, score.toDouble());
          if (mode == 'pin-without-evidence') {
            expect(data.originalExplanationMissing, true);
            expect(data.breakdown, isEmpty);
          } else {
            expect(data.originalExplanationMissing, false);
            final used = data.breakdown
                .where((r) => r['used'] == true)
                .toList();
            expect(used.length, two ? 2 : 1);
            expect(
              used.every(
                (r) =>
                    r['points'] is int &&
                    !r.containsKey('word') &&
                    !r.containsKey('usual_text'),
              ),
              true,
            );
            expect(
              50 + used.fold<int>(0, (n, r) => n + (r['points'] as int)),
              score,
            );
          }
          final db = await LocalDb.instance;
          final stored = await db.query('day_result', orderBy: 'day_id');
          final series = await db.query('metric_series', orderBy: 'date,key');
          final pin = await LocalDb.frozenHeadline();
          await localizedPage(
            t,
            ReadinessDetail(day: day),
            app: app,
            themeController: theme,
            units: units,
            scale: scale,
            push: true,
          );
          await flush(t);
          final texts = (await readPage(t)).join(' ');
          if (mode == 'pin-without-evidence') {
            expect(texts, contains('Morning breakdown unavailable'));
            expect(texts, isNot(contains('Mostly HRV')));
          } else {
            expect(
              texts,
              contains(
                two
                    ? 'Mostly HRV, then resting HR.'
                    : 'Mostly HRV. Everything else was close to usual.',
              ),
            );
            expect(texts, isNot(contains('usual 52')));
            final row = find.byWidgetPredicate(
              (w) =>
                  w is Pressable &&
                  (w.semanticLabel?.startsWith('HRV,') ?? false),
            );
            expect(row, findsOneWidget);
            await reveal(t, row);
            await t.tap(row);
            await flush(t);
            final metric = t.widget<MetricDetail>(find.byType(MetricDetail));
            expect(metric.metricKey, 'hrv');
            expect(metric.day, day);
            await t.tap(
              find
                  .byWidgetPredicate(
                    (w) => w is Pressable && w.semanticLabel == 'Back',
                  )
                  .first,
            );
            await flush(t);
            expect(find.byType(MetricDetail), findsNothing);
            expect(
              t.widget<ReadinessDetail>(find.byType(ReadinessDetail)).day,
              day,
            );
          }
          expect(await db.query('day_result', orderBy: 'day_id'), stored);
          expect(await db.query('metric_series', orderBy: 'date,key'), series);
          final afterPin = await LocalDb.frozenHeadline();
          expect(afterPin?.day, pin?.day);
          expect(afterPin?.value, pin?.value);
          expect(t.takeException(), isNull);
        },
        timeout: const Timeout(Duration(seconds: 30)),
      );
    }
  }
}
