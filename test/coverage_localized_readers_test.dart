// Dated gaps, units and honest absence under the real shipped delegates.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/findings.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/models/metric.dart';
import 'package:whoop_companion/ui2/screens/home_screen.dart';
import 'package:whoop_companion/ui2/screens/findings_log.dart';
import 'package:whoop_companion/ui2/screens/metric_detail.dart';
import 'package:whoop_companion/ui2/screens/readiness_detail.dart';
import 'package:whoop_companion/ui2/screens/sleep_detail.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

Metric measured(num value) =>
    Metric(value: value.toDouble(), confidence: .8, tier: MetricTier.estimate);

void main() {
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('readers');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  final now = DateTime.now();
  int noon(int ago) =>
      DateTime(now.year, now.month, now.day - ago, 12).millisecondsSinceEpoch ~/
      1000;
  final day = dayLabelOf(now);
  for (final key in [
    'resting_hr',
    'hrv',
    'resp_rate',
    'efficiency',
    'deep',
    'rem',
    'wear',
    'steps',
    'step_kcal',
    'skin_temp',
    'stress',
    'nap_min',
    'active_min',
  ]) {
    for (final warm in [false, true]) {
      testWidgets(
        'COV-44 localized metric $key preserves dated gaps and units: $warm',
        (t) async {
          final d = MetricData(
            daysAvailable: 90,
            series: warm
                ? [for (var i = 0; i < 30; i += 2) (t: noon(i), v: 40.0 + i)]
                : [],
            acsmSeries: key == 'step_kcal' && warm
                ? [for (var i = 0; i < 30; i += 2) (t: noon(i), v: 50.0 + i)]
                : [],
            wear: [for (var i = 0; i < 90; i++) (t: noon(i), v: 1440.0)],
            percentile: const {'percentile_of_you': 75.0, 'n': 28},
            movers: const [
              {
                'tag': 'Synthetic comparison',
                'n_with': 12,
                'n_without': 16,
                'delta': -2.5,
                'unit': 'ms',
                'helped': false,
              },
            ],
          );
          await localizedPage(t, MetricDetail(key, data: d, range: 2));
          final content = await readPage(t);
          expect(content, contains(specOf(key).title));
          t
              .state<ScrollableState>(find.byType(Scrollable).first)
              .position
              .jumpTo(0);
          await t.pumpAndSettle();
          expect(find.text(specOf(key).title), findsWidgets);
          if (warm && !metricSuppressed(key)) {
            final scrub = find.byType(Scrubber);
            expect(scrub, findsWidgets);
            final first = t.widget<Scrubber>(scrub.first);
            expect(first.describe(1), contains('40'));
            first.onChanged(0);
            await t.pumpAndSettle();
            final atGap = t.widget<Scrubber>(find.byType(Scrubber).first);
            expect(atGap.value, 0);
            expect(atGap.describe(0), isNot(contains('40')));
            atGap.onChanged(1);
            await t.pumpAndSettle();
            expect(t.widget<Scrubber>(find.byType(Scrubber).first).value, 1);
          } else {
            expect(find.byType(StatusCard), findsWidgets);
          }
          expect(t.takeException(), isNull);
        },
      );
    }
  }

  for (final kind in ['empty', 'measured', 'unknown-food', 'stale']) {
    testWidgets(
      'COV-44 localized Today keeps measured and missing inputs distinct: $kind',
      (t) async {
        final populated = kind != 'empty';
        final d = HomeData(
          dayId: day,
          readiness: populated
              ? measured(70)
              : const Metric(note: 'need_baseline:have=2,need=7'),
          sleepMin: populated ? measured(420) : Metric.empty,
          hrv: populated ? measured(50) : Metric.empty,
          rhr: populated ? measured(55) : Metric.empty,
          strain: populated ? measured(8) : Metric.empty,
          steps: populated ? measured(0) : Metric.empty,
          sleepNeedMin: populated ? measured(450) : Metric.empty,
          bedtime: populated ? measured(1320) : Metric.empty,
          proteinToday: populated ? 30 : null,
          proteinTarget: 100,
          kcalTarget: 2000,
          foodLogged: populated,
          foodUnknownOnly: kind == 'unknown-food',
          foodFloor: kind == 'unknown-food',
          proteinFloor: kind == 'unknown-food',
          heldOverNight: kind == 'empty' ? '2021-04-06' : null,
          insightsStale: kind == 'stale'
              ? {'pending': true, 'reason': 'synthetic pending calculation'}
              : null,
        );
        await localizedPage(
          t,
          HomeScreen(data: d, hour: 8, workoutLive: false),
        );
        expect(find.byType(HomeScreen), findsOneWidget);
        final cards = t.widgetList<StatusCard>(find.byType(StatusCard));
        if (kind == 'empty') expect(cards, isNotEmpty);
        expect(find.textContaining('NaN'), findsNothing);
        expect(find.textContaining('Infinity'), findsNothing);
      },
    );
  }

  for (final state in ['empty', 'new', 'typical', 'rough']) {
    testWidgets(
      'COV-44 localized Sleep keeps observed stages and baseline limits: $state',
      (t) async {
        final onset = noon(1) - 14 * 3600;
        final valid = state != 'empty';
        final history = state == 'typical' || state == 'rough';
        final d = SleepData(
          day: day,
          night: valid
              ? {
                  'duration_min': 420,
                  'in_bed_min': 480,
                  'awake_min': 30,
                  'efficiency': .875,
                  'onset_ts': onset,
                  'wake_ts': onset + 480 * 60,
                  'deep_min': 80,
                  'light_min': 240,
                  'rem_min': 100,
                  'hypnogram': [
                    {'t': onset, 'stage': 'light'},
                    {'t': onset + 240 * 60, 'stage': 'unobserved'},
                    {'t': onset + 300 * 60, 'stage': 'rem'},
                    {'t': onset + 480 * 60, 'stage': 'wake'},
                  ],
                  'sleep_source': 'detected',
                  'cycle_count': 4,
                  'cycles_mean_min': 90,
                  'nocturnal': {
                    'sleeping_hr_avg': 55,
                    'sleeping_hr_min': 48,
                    'day_hr_avg': 70,
                    'vs_baseline_bpm': state == 'rough' ? 5.0 : 0.1,
                    'dip_pct': .2,
                    'elevated': state == 'rough',
                  },
                }
              : {},
          tstHistory: history
              ? List<double>.generate(28, (i) => 440 + (i % 5) * 5.0)
              : [],
          deepHistory: history ? List<double>.filled(28, 70) : [],
          effHistory: history ? List<double>.filled(28, 90) : [],
          onsetHistory: history
              ? [for (var i = 1; i <= 28; i++) onset - i * 86400]
              : [],
          need: valid ? measured(450) : Metric.empty,
          debt: valid ? measured(30) : Metric.empty,
          bedtime: valid ? measured(1320) : Metric.empty,
          solMin: valid ? 32 : null,
          unobservedMin: valid ? 60 : null,
          awakenings: valid ? 2 : null,
          longestSleepMin: valid ? 180 : null,
          skinTempZ: state == 'rough' ? 1.6 : null,
          hrvNight: valid ? 45 : null,
          strainBonusMin: state == 'rough' ? 20 : null,
        );
        await localizedPage(t, SleepDetail(data: d));
        expect(find.text('Sleep'), findsWidgets);
        if (valid) {
          expect(d.stages, contains(null));
          expect(find.textContaining('7h'), findsWidgets);
        } else {
          expect(find.byType(StatusCard), findsWidgets);
        }
      },
    );
  }

  for (final state in ['empty', 'thin', 'pinned', 'missing-original']) {
    testWidgets(
      'COV-44 localized Recovery does not invent a score or old explanation: $state',
      (t) async {
        final present = state == 'pinned' || state == 'missing-original';
        final d = ReadinessData(
          readiness: present ? measured(65) : Metric.empty,
          savedMorningExplanation: state == 'pinned',
          originalExplanationMissing: state == 'missing-original',
          absentDiag: present
              ? null
              : {
                  'note': 'need_baseline',
                  'hrv': {'value': null, 'baseline_n': 2},
                },
          heldOverNight: present ? null : '2021-04-06',
          inputsUsed: present ? 2 : 0,
          breathingNote: 'too much movement or signal noise',
          hrvNote: state == 'thin' ? 'not enough clean intervals' : null,
          breakdown: state == 'pinned'
              ? [
                  {
                    'label': 'hrv',
                    'contribution': 3.0,
                    'detail': 'synthetic original comparison',
                  },
                ]
              : [],
        );
        await localizedPage(t, ReadinessDetail(data: d));
        expect(find.text('Recovery'), findsWidgets);
        if (state == 'missing-original')
          expect(find.text('Morning breakdown unavailable'), findsOneWidget);
        if (!present) expect(find.text('65'), findsNothing);
      },
    );
  }
  testWidgets(
    'COV-44 localized observations retain all detector kinds and dates',
    (t) async {
      final findings = [
        for (final k in FindingKind.values)
          Finding(k, '2021-04-06', risen: false),
      ];
      await localizedPage(t, FindingsLog(findings));
      for (final f in findings) {
        await reveal(t, find.text(f.title).first);
        expect(find.text(f.title), findsWidgets);
      }
    },
  );
}
