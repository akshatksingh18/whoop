// Dated metric inputs and retained doors use authored history, never a private capture.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/derivation_engine.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/data/progress_review.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/theme/theme_controller.dart';
import 'package:whoop_companion/ui2/screens/day_steps.dart';
import 'package:whoop_companion/ui2/activity/day_strain.dart';
import 'package:whoop_companion/ui2/screens/home_screen.dart' show prettyDay;
import 'package:whoop_companion/ui2/screens/metric_detail.dart';
import 'package:whoop_companion/ui2/screens/readiness_detail.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'coverage_session_destination_boundaries_test.dart' show io;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

class Reader extends LocalRepositoryImpl {
  Reader()
    : super(
        getProfileMap: () => {
          'age': 30,
          'weight_kg': 70,
          'sex': 'f',
          'height_cm': 170,
        },
      );
  bool refuse = false;
  Map<String, dynamic>? chart;
  @override
  Future<Map<String, dynamic>> getChart(String key, {int? from, int? to}) =>
      chart == null
      ? super.getChart(key, from: from, to: to)
      : Future.value(chart!);
  @override
  Future<Map<String, dynamic>> getToday() async {
    if (refuse) throw StateError('synthetic today read refusal');
    return super.getToday();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Reader repo;
  late ThemeController theme;
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('metric-read-boundaries');
  });
  setUp(() async {
    await resetCoverageStore();
    repo = Reader();
    theme = ThemeController.seed(AppThemeChoice.light, Brightness.light);
  });
  tearDown(() => theme.dispose());
  tearDownAll(LocalDb.close);
  int noon(String day) =>
      DateTime.parse(
        day,
      ).add(const Duration(hours: 12)).millisecondsSinceEpoch ~/
      1000;
  Future<void> seed(
    String day,
    Map<String, dynamic> payload, {
    Map<String, double?> series = const {},
  }) => LocalDb.putDayResult(
    dayId: day,
    algoVersion: kAlgoVersion,
    payloadJson: jsonEncode(payload),
    windowJson: '{}',
    series: series,
  );

  for (final measured in [false, true]) {
    test(
      'Recovery retains the actual missing-input reasons and dated diagnostic $measured',
      () async {
        const day = '2021-04-06';
        await seed(day, {
          'scalars': {if (measured) 'resp_rate': 14.5},
          'clinical': {
            'rmssd_sleep_session': {
              if (measured) 'value': 40,
              'note': 'need_rr',
            },
          },
          'respiration': {
            'rsa': {'note': 'need_rr'},
          },
          'readiness_absent_diag': {
            'note': 'authored input diagnostic',
            'hrv': {'baseline_n': 0},
          },
        });
        final d = await ReadinessData.load(repo, day: day);
        expect(d.readiness.value, isNull);
        expect(d.absentDiag!['note'], 'authored input diagnostic');
        expect(d.breathingNote, measured ? isNull : isNotNull);
        expect(await hrvMissingReason(day), measured ? isNull : isNotNull);
      },
    );
  }
  test(
    'an unpinned historical score explains its own stored inputs and comparison',
    () async {
      final current = DateTime.parse(todayLabel());
      final day = dayLabelOf(
        DateTime(current.year, current.month, current.day - 1),
      );
      for (var i = 1; i <= 29; i++) {
        final d = dayLabelOf(
          DateTime(current.year, current.month, current.day - i),
        );
        await LocalDb.putMetricSeriesValue(d, 'rhr', 50.0 + i % 5);
      }
      await seed(
        day,
        {
          'clinical': {
            'readiness_composite': {
              'drivers': [
                {'label': 'RHR', 'contribution': .2},
              ],
            },
          },
        },
        series: {'readiness': 60, 'rhr': 55},
      );
      final data = await ReadinessData.load(repo, day: day);
      expect(data.readiness.value, 60);
      final rhr = data.breakdown.singleWhere((r) => r['label'] == 'rhr');
      expect(rhr['used'], true);
      expect(rhr['value_text'], '55 bpm');
      expect(rhr['usual_text'], startsWith('usual '));
      expect(data.savedMorningExplanation, false);
    },
  );
  testWidgets(
    'Recovery read refusal keeps Retry and reopens honest absence after retry',
    (t) async {
      final app = AppState.forTesting()..repo = repo;
      addTearDown(app.dispose);
      repo.refuse = true;
      await localizedPage(t, const ReadinessDetail(), app: app, settle: false);
      await io(t);
      final status = find.byWidgetPredicate(
        (w) => w is StatusCard && w.what == 'Recovery could not load',
      );
      expect(status, findsOneWidget);
      repo.refuse = false;
      await invokeControl(t, t.widget<StatusCard>(status).onFix);
      await io(t);
      expect(status, findsNothing);
      expect((await readPage(t)).join(' '), contains('Recovery is not scored'));
    },
  );
  testWidgets(
    'a seven-day strain row opens the exact saved day; arrows preserve holes',
    (t) async {
      final now = DateTime.parse(todayLabel());
      final yesterday = dayLabelOf(DateTime(now.year, now.month, now.day - 1));
      final app = AppState.forTesting()..repo = repo;
      addTearDown(app.dispose);
      await localizedPage(
        t,
        MetricDetail(
          'strain',
          range: 1,
          data: MetricData(
            daysAvailable: 7,
            series: [(t: noon(yesterday), v: 3.5)],
          ),
        ),
        app: app,
        themeController: theme,
      );
      final previous = find.byWidgetPredicate(
        (w) => w is Pressable && w.semanticLabel == 'Previous day',
      );
      await reveal(t, previous);
      await t.tap(previous);
      await t.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Surface &&
              w.semanticLabel ==
                  '${prettyDay(dayLabelOf(DateTime(now.year, now.month, now.day - 2)))}, no record',
        ),
        findsOneWidget,
      );
      final row = find.byWidgetPredicate(
        (w) => w is Pressable && w.semanticLabel?.contains('3.5') == true,
      );
      await reveal(t, row);
      t.widget<Pressable>(row).onTap!();
      await io(t);
      expect(
        t.widget<DayStrainDetail>(find.byType(DayStrainDetail)).day,
        yesterday,
      );
    },
  );
  for (final calories in [false, true]) {
    testWidgets(
      'the ${calories ? 'step calorie' : 'step'} detail door preserves the requested view',
      (t) async {
        final app = AppState.forTesting()..repo = repo;
        addTearDown(app.dispose);
        await localizedPage(
          t,
          MetricDetail(
            calories ? 'step_kcal' : 'steps',
            data: MetricData(
              daysAvailable: 1,
              series: [(t: noon(todayLabel()), v: 1200)],
            ),
          ),
          app: app,
          themeController: theme,
        );
        final link = find.text('Open today, yesterday or another saved day');
        await reveal(t, link);
        await t.tap(link);
        await io(t);
        expect(
          t.widget<DayStepsDetail>(find.byType(DayStepsDetail)).calories,
          calories,
        );
      },
    );
  }
  test(
    'suppressed temperature stays unavailable while an active metric retains algorithm boundaries',
    () async {
      await seed('2021-04-06', {'source': 'whoop_export', 'imported': true});
      await seed('2021-04-07', {'device_family': 'gen5'});
      repo.chart = {
        'points': [
          {'t': noon('2021-04-06'), 'v': 2.0},
          {'t': noon('2021-04-07'), 'v': 1.0},
        ],
        'algo_breaks': [
          null,
          {'t': noon('2021-04-07')},
          {'t': 'bad'},
        ],
      };
      final d = await MetricData.load(repo, 'skin_temp');
      expect(d.series, isEmpty);
      expect(d.algoBreaks, isEmpty);
      final active = await MetricData.load(repo, 'resting_hr');
      expect(active.series, hasLength(2));
      expect(active.algoBreaks, [noon('2021-04-07')]);
      expect(const StepsMetric().label, 'Steps');
      expect(const StepsMetric().unit, 'steps');
    },
  );
  for (final language in ['fr', 'de', 'es', 'zh']) {
    for (final older in [false, true]) {
      testWidgets(
        '$language own-history percentile names its actual date and measured units: $older',
        (t) async {
          final today = DateTime.parse(todayLabel());
          final data = MetricData(
            daysAvailable: 30,
            series: [
              for (var i = older ? 9 : 7; i >= (older ? 2 : 0); i--)
                (
                  t:
                      DateTime(
                        today.year,
                        today.month,
                        today.day - i,
                        12,
                      ).millisecondsSinceEpoch ~/
                      1000,
                  v: 50.0 + i,
                ),
            ],
            percentile: {
              'percentile_of_you': 75,
              if (older) 'label': 'authored own range',
            },
          );
          await localizedPage(
            t,
            MetricDetail('resting_hr', data: data, range: 2),
            language: language,
          );
          final text = (await readPage(t)).join(' ');
          expect(
            text,
            contains(switch (language) {
              'fr' => '75e',
              'de' => '75.',
              'es' => '75º',
              _ => '75',
            }),
          );
          if (older) expect(text, contains('authored own range'));
          expect(text, contains('bpm'));
        },
      );
    }
  }
}
