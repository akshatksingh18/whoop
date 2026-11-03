// Approved missing-evidence repair through actual readers, pages and cache.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/state/units_controller.dart';
import 'package:whoop_companion/theme/theme_controller.dart';
import 'package:whoop_companion/ui2/screens/health_screen.dart';
import 'package:whoop_companion/ui2/screens/home_screen.dart' show pointsOf;
import 'package:whoop_companion/ui2/screens/metric_detail.dart';
import 'package:whoop_companion/ui2/screens/day_steps.dart';
import 'package:whoop_companion/ui2/ui2.dart'
    show MetricLine, Pressable, Surface, dayNavLabel;
import 'support/audit_visual.dart';
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

class _History {
  _History(WidgetTester t, {required this.mixed, required this.today}) {
    app = AppState.forTesting()
      ..user = const Profile(
        ageYears: 30,
        weightKg: 70,
        heightCm: 170,
        sex: 'f',
      ).toMap();
    repo = LocalRepositoryImpl(getProfileMap: () => app.user);
    app.repo = repo;
    units = UnitsController.seed(UnitSystem.metric);
    theme = ThemeController.seed(AppThemeChoice.light, Brightness.light);
    addTearDown(app.dispose);
    addTearDown(units.dispose);
    addTearDown(theme.dispose);
    final now = DateTime.now();
    dates = [
      for (final ago in [2, 1, 0]) DateTime(now.year, now.month, now.day - ago),
    ];
  }
  final bool mixed, today;
  late final AppState app;
  late final LocalRepositoryImpl repo;
  late final UnitsController units;
  late final ThemeController theme;
  late final List<DateTime> dates;
  int get unknown => today ? 2 : 1;
  int get zero => today ? 1 : 2;
  List<double> get values => today ? [1000, 0, 2000] : [1000, 2000, 0];
  int noon(int i) =>
      DateTime(
        dates[i].year,
        dates[i].month,
        dates[i].day,
        12,
      ).millisecondsSinceEpoch ~/
      1000;
  Future<void> measured(int i, int steps) async {
    final start = noon(i), end = start + 3600;
    await LocalDb.replacePhoneCoverageForDay(
      dayLabelOf(dates[i]),
      [(startTs: start, endTs: end, steps: steps)],
      distances: {'$start-$end': steps / 2},
    );
  }

  Future<void> seed() async {
    for (final i in mixed ? [0, 1, 2] : [unknown]) {
      await LocalDb.putMetricSeriesValue(
        dayLabelOf(dates[i]),
        'steps',
        values[i],
      );
    }
    if (mixed) {
      await measured(0, 1000);
      await measured(zero, 0);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await coverageStore('step-calorie-history-pages');
    await loadAuditFonts();
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  for (final target in ['detail_range', 'detail_today', 'trends']) {
    for (final mixed in [true, false]) {
      for (final scale
          in target == 'detail_range'
              ? [1.0, 1.3, 1.3001, 2.0, 3.1]
              : [1.0, 2.0, 3.1]) {
        testWidgets(
          'COV-62 $target ${mixed ? 'mixed' : 'empty'} ${scale}x complete approved page',
          (t) async {
            final f = _History(
              t,
              mixed: mixed,
              today: target == 'detail_today',
            );
            final input = await t.runAsync(() async {
              await f.seed();
              final before = await (await LocalDb.instance).query(
                'metric_series',
              );
              final data = await MetricData.load(
                f.repo,
                'step_kcal',
                calorieDays: 7,
              );
              expect(
                data.series.where((p) => p.t == f.noon(f.unknown)),
                isEmpty,
              );
              expect(
                data.series.map((p) => p.v),
                mixed ? [2.74 * 1000 * 70 / 8368, 0] : <double>[],
              );
              expect(
                data.acsmSeries.map((p) => p.v),
                mixed ? [17.5, 0] : <double>[],
              );
              expect(
                pointsOf(await f.repo.getChart('steps')).map((p) => p.v),
                mixed ? f.values : [2000],
              );
              expect(
                await (await LocalDb.instance).query('metric_series'),
                before,
              );
              final health = target == 'trends'
                  ? await HealthData.load(f.repo)
                  : null;
              if (health != null) {
                expect(health.points('step_kcal'), data.series);
                expect(health.points('step_kcal_acsm'), data.acsmSeries);
              }
              return (data: data, health: health);
            });
            final Widget page = target == 'trends'
                ? HealthScreen(data: input!.health, range: 1)
                : target == 'detail_today'
                ? const MetricDetail('step_kcal', range: 0)
                : MetricDetail(
                    'step_kcal',
                    range: 1,
                    data: input!.data,
                    day: dayLabelOf(f.dates[f.unknown]),
                  );
            await localizedPage(
              t,
              page,
              app: f.app,
              units: f.units,
              themeController: f.theme,
              scale: scale,
              push: true,
              capture: true,
            );
            t.view.physicalSize = const Size(430, 932);
            await t.pumpAndSettle();
            final seen = await readPage(t);
            if (target == 'trends') {
              await reveal(t, find.text('Step calories'));
              final line = t.widget<MetricLine>(
                find
                    .ancestor(
                      of: find.text('Step calories'),
                      matching: find.byType(MetricLine),
                    )
                    .first,
              );
              expect(line.onTap, isNotNull);
              expect(line.value, mixed ? '11' : null);
            } else {
              expect(seen, contains('Browse days'));
              if (target == 'detail_today' || !mixed) {
                expect(seen, contains('Step calories unavailable'));
                expect(
                  seen.any((s) => s.contains('Wear the band overnight')),
                  false,
                );
              }
              if (target == 'detail_today') {
                expect(
                  seen.any(
                    (s) => s.contains(
                      'This is the walking part of maintenance; resting is separate.',
                    ),
                  ),
                  true,
                );
              } else {
                final date = find.text(
                  dayNavLabel(dayLabelOf(f.dates[f.unknown])),
                );
                final value = find.text(
                  'Budget unavailable\nmovement estimate unavailable',
                );
                expect(date, findsOneWidget);
                expect(value, findsOneWidget);
                if (scale > 1.3) {
                  expect(
                    t.getRect(date).bottom,
                    lessThanOrEqualTo(t.getRect(value).top),
                  );
                  expect(t.widget<Text>(date).maxLines, isNull);
                } else {
                  expect(t.getRect(date).left, lessThan(t.getRect(value).left));
                }
              }
            }
            await captureAuditScroll(
              t,
              '${scale}x',
              prefix:
                  'step_calorie_actual_${target}_${mixed ? 'mixed' : 'empty'}',
              scrollable: find.byType(Scrollable).first,
            );
            expect(t.takeException(), isNull);
          },
        );
      }
    }
  }
  for (final mixed in [false, true]) {
    for (final action in ['selected unknown day', 'Browse days']) {
      testWidgets(
        'COV-62 $action remains reachable with mixed=$mixed and Back preserves its history',
        (t) async {
          final f = _History(t, mixed: mixed, today: false);
          final data = await t.runAsync(() async {
            await f.seed();
            return MetricData.load(f.repo, 'step_kcal', calorieDays: 7);
          });
          final before = await t.runAsync(
            () => (LocalDb.instance).then((db) => db.query('metric_series')),
          );
          await localizedPage(
            t,
            MetricDetail(
              'step_kcal',
              range: 1,
              data: data,
              day: dayLabelOf(f.dates[f.unknown]),
            ),
            app: f.app,
            units: f.units,
            themeController: f.theme,
            push: true,
          );
          final link = action == 'Browse days'
              ? find.text('Browse days')
              : find.byWidgetPredicate(
                  (w) =>
                      w is Surface &&
                      w.onTap != null &&
                      w.semanticLabel?.contains('no record') == true,
                );
          await reveal(t, link);
          await t.tap(link);
          await t.pumpAndSettle();
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await t.pumpAndSettle();
          final opened = t.widget<DayStepsDetail>(
            find.byType(DayStepsDetail).last,
          );
          expect(opened.calories, true);
          expect(
            opened.day,
            action == 'Browse days' ? null : dayLabelOf(f.dates[f.unknown]),
          );
          final back = find.byWidgetPredicate(
            (w) => w is Pressable && w.semanticLabel == 'Back',
          );
          expect(back, findsOneWidget);
          await t.tap(back);
          await t.pumpAndSettle();
          expect(find.byType(DayStepsDetail), findsNothing);
          expect(find.text('Browse days'), findsOneWidget);
          expect(
            await t.runAsync(
              () => (LocalDb.instance).then((db) => db.query('metric_series')),
            ),
            before,
          );
          expect(t.takeException(), isNull);
        },
      );
    }
  }
  for (final language in ['en', 'de', 'es', 'fr', 'hi', 'zh']) {
    for (final scale in [1.0, 3.1]) {
      testWidgets(
        'COV-62 $language ${scale}x missing step-energy inputs retain day access',
        (t) async {
          await localizedPage(
            t,
            const MetricDetail('step_kcal', range: 1, data: MetricData()),
            language: language,
            scale: scale,
            push: true,
          );
          t.view.physicalSize = const Size(430, 932);
          await t.pumpAndSettle();
          final seen = await readPage(t);
          expect(seen, contains('Browse days'));
          expect(seen.any((s) => s.contains('Wear the band overnight')), false);
          expect(t.takeException(), isNull);
        },
      );
    }
  }
  for (final range in [0, 1, 2, 3]) {
    testWidgets(
      'COV-62 range $range refreshes unknown and repriced input caches without rewriting stored totals',
      (t) async {
        final f = _History(t, mixed: false, today: true);
        await t.runAsync(f.seed);
        final page = MetricDetail('step_kcal', range: range);
        await localizedPage(
          t,
          page,
          app: f.app,
          units: f.units,
          themeController: f.theme,
          push: true,
        );
        expect(await readPage(t), contains('Step calories unavailable'));
        final before = await t.runAsync(
          () => (LocalDb.instance).then((db) => db.query('metric_series')),
        );
        await t.runAsync(() => f.measured(2, 1000));
        f.app.bumpInsights();
        await t.pumpAndSettle();
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 120)),
        );
        await t.pumpAndSettle();
        expect(await readPage(t), contains('23'));
        f.app.user = {...f.app.user!, 'weight_kg': 50};
        f.app.bumpInsights();
        await t.pumpAndSettle();
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 120)),
        );
        await t.pumpAndSettle();
        expect(await readPage(t), contains('16'));
        expect(
          await t.runAsync(
            () => (LocalDb.instance).then((db) => db.query('metric_series')),
          ),
          before,
        );
        expect(t.takeException(), isNull);
      },
    );
  }
}
