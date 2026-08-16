// Goldens for Home, Health and the shared drill-down.
//
// Every screen is captured twice: once with data and once with none. The
// second half is the point — "absent" is a first-class state in this app, it
// is where `StatusCard` copy lives, and it is the state a new user spends
// their first fortnight in. A screen whose empty state nobody ever looked at
// is a screen that ships with an em-dash in it.
//
// Regenerate deliberately:
//     flutter test --update-goldens test/ui2_home_health_golden_test.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/lab_catalogue.dart';
import 'package:openstrap_edge/models/metric.dart';
import 'package:openstrap_edge/ui2/screens/screens.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

/// Deterministic — a golden that depends on a random number is a golden that
/// records noise.
List<double> _series(int n, double base, double amp) => List<double>.generate(
    n, (i) => base + ((i * 37) % 17) / 17 * amp - amp / 2);

/// The same series with the timestamps a real `getChart` carries: one point per
/// day, ending TODAY, stamped at local noon the way `metric_series` reads back.
///
/// Anchored to the run date on purpose. The screens label their axes and their
/// "as of" line RELATIVE to today, so a fixture pinned to a fixed calendar date
/// would render "88 days ago" on one morning and "89 days ago" the next — a
/// golden that fails on the passage of time. Anchored here, the rendered text
/// is identical on every run, and a gap in the fixture would show up as one.
List<ChartPoint> _points(int n, double base, double amp) {
  final vs = _series(n, base, amp);
  final now = DateTime.now();
  return [
    for (var i = 0; i < n; i++)
      (
        t: DateTime(now.year, now.month, now.day - (n - 1 - i), 12)
                .millisecondsSinceEpoch ~/
            1000,
        v: vs[i],
      ),
  ];
}

Map<String, dynamic> _metric(num? v, String tier, {String? note}) => {
      'value': v ?? '—',
      'confidence': v == null ? 0 : 0.8,
      'tier': tier,
      'inputs_used': const <String>[],
      'note': ?note,
    };

// ── fixtures ──

final _home = HomeData(
  name: 'Alex',
  dayId: '2026-05-20',
  readiness: const Metric(value: 82, confidence: .8, tier: MetricTier.high),
  drivers: const [
    {'label': 'hrv', 'contribution': 6.2, 'detail': 'lifting your score'},
    {'label': 'rhr', 'contribution': 3.1, 'detail': 'lifting your score'},
    {'label': 'temp', 'contribution': -1.4, 'detail': 'dragging your score down'},
  ],
  sleepMin: const Metric(value: 465, unit: 'min', confidence: .8, tier: MetricTier.estimate),
  sleepEff: const Metric(value: 91, unit: '%', confidence: .8, tier: MetricTier.estimate),
  rhr: const Metric(value: 52, unit: 'bpm', confidence: .8, tier: MetricTier.high),
  steps: const Metric(value: 8642, unit: 'steps', confidence: .6, tier: MetricTier.estimate),
  calories: const Metric(value: 640, unit: 'kcal', confidence: .6, tier: MetricTier.estimate),
  caloriesTotal: const Metric(value: 2310, unit: 'kcal', confidence: .6, tier: MetricTier.estimate),
  stepGoal: 8000,
  sleepNeedMin: const Metric(value: 462, unit: 'min', confidence: .7, tier: MetricTier.estimate),
  bedtime: const Metric(value: 1360, confidence: .7, tier: MetricTier.estimate),
  strainTarget: const {'value': 11.4, 'low': 9.2, 'high': 13.6},
);

/// A first-week user: the band is on, nothing has a baseline yet.
const _homeCold = HomeData(
  name: 'Alex',
  dayId: '2026-05-20',
  readiness: Metric(note: 'need_baseline:have=3,need=14'),
);

final _health = HealthData(
  today: {
    'daily': {
      'resting_hr': _metric(52, 'HIGH'),
      'readiness': _metric(82, 'HIGH'),
    },
    'sleep': {'duration_min': _metric(465, 'ESTIMATE')},
    'hrv': {'rmssd': 68, 'confidence': .6},
    // The pipeline emits a full envelope for stress (value + confidence +
    // tier), not a bare score — the screen reads the tier off it.
    'stress': {
      'value': 28,
      'score': 28,
      'level': 'Low',
      'confidence': .55,
      'tier': 'ESTIMATE',
    },
    'resp': {'value': 14.2, 'confidence': .6},
    // The ENVELOPE the repo emits, not a bare `{'value': z}`. The bare form is
    // what shipped, and `Metric.isEmpty` reads a confidence-less block as
    // absent — so the golden was recording a real deviation dotted "Not
    // measured".
    'skin_temp': {
      'value': 0.31,
      'confidence': .5,
      'tier': 'RELATIVE',
      'inputs_used': const ['skin_temp_raw'],
      'note': 'relative deviation (z) vs your baseline; raw ADC, no absolute °C',
    },
    'illness': {'state': 'green'},
  },
  insights: {
    'chronotype': {
      'value': {'type_label': 'slight evening type'},
      'confidence': .6,
      'tier': 'ESTIMATE',
    },
    'social_jetlag': {
      'value': {
        'abs_hours': 1.7,
        'mid_sleep_free_h': 4.2,
        'mid_sleep_work_h': 2.5,
        'n_free': 9,
        'n_work': 22,
      },
      'confidence': .6,
      'tier': 'ESTIMATE',
    },
    'regularity': {
      'value': {'sri': 78, 'band': 'steady'},
      'confidence': .7,
      'tier': 'ESTIMATE',
    },
    'sleep_coach': {
      'need': {
        'value': {'need_sec': 27720},
        'confidence': .7,
        'tier': 'ESTIMATE',
      },
    },
  },
  profile: const {'weight_kg': 72.4, 'sex': 'm'},
  charts: {
    'resting_hr': _points(60, 54, 6),
    'hrv': _points(60, 66, 16),
    'sleep': _points(60, 440, 70),
    'stress': _points(60, 30, 14),
    'resp_rate': _points(60, 14.2, 1.8),
  },
  daysWithData: 24,
  need: const Metric(value: 462, unit: 'min', confidence: .7, tier: MetricTier.estimate),
);

const _healthCold = HealthData(daysWithData: 2);

final _vitals = VitalsData(
  timeline: const {
    'highs': {
      'low_hr': {'v': 48},
      'peak_hr': {'v': 142},
      'avg_hr': {'v': 71},
    },
  },
  lungs: const {
    'resp': {'value': 14.2, 'confidence': .6},
  },
  wear: const {'worn_min': 1300, 'coverage_pct': 94},
  hrv: const {'rmssd': 68.2},
);

const _labs = LabsData(markers: kLabMarkers, results: [
  {'marker': 'ldl', 'taken_on': '2026-03-12', 'value': 104.0, 'unit': 'mg/dL'},
  {'marker': 'hdl', 'taken_on': '2026-03-12', 'value': 58.0, 'unit': 'mg/dL'},
  {'marker': 'hba1c', 'taken_on': '2026-03-12', 'value': 5.2, 'unit': '%'},
  {'marker': 'ferritin', 'taken_on': '2026-03-12', 'value': 96.0, 'unit': 'ng/mL'},
]);

final _metricDetail = MetricData(
  series: _points(60, 54, 6),
  daysAvailable: 60,
  percentile: const {'percentile_of_you': 22.0, 'n': 59, 'label': 'lower than usual'},
  movers: const [
    {
      'tag': 'alcohol',
      'outcome': 'rhr',
      'delta': 5.8,
      'unit': 'bpm',
      'helped': false,
      'n_with': 7,
      'n_without': 41,
    },
    {
      'tag': 'late meal',
      'outcome': 'rhr',
      'delta': 2.1,
      'unit': 'bpm',
      'helped': false,
      'n_with': 12,
      'n_without': 36,
    },
  ],
);

final _readiness = ReadinessData(
  readiness: const Metric(value: 82, confidence: .8, tier: MetricTier.high),
  breakdown: const [
    {'label': 'hrv', 'weight': .4, 'weighted_contribution': 6.2, 'past_mdc': true, 'used': true},
    {'label': 'rhr', 'weight': .3, 'weighted_contribution': 3.1, 'past_mdc': true, 'used': true},
    {'label': 'resp', 'weight': .2, 'weighted_contribution': 0.4, 'past_mdc': false, 'used': true},
    {'label': 'temp', 'weight': .1, 'weighted_contribution': -1.4, 'past_mdc': true, 'used': true},
  ],
  inputsUsed: 4,
  series: _series(90, 74, 18),
);

const _readinessCold = ReadinessData(
    readiness: Metric(note: 'need_baseline:have=5,need=14'));

/// Onset as a LOCAL wall-clock instant, not a fixed epoch. The screen formats
/// timestamps in the device zone, so anchoring the fixture the same way is what
/// makes these goldens byte-identical on a machine in another timezone.
final _onsetTs =
    DateTime(2026, 5, 19, 23, 7).millisecondsSinceEpoch ~/ 1000;

/// One night, built as segments the way the repo emits them.
List<Map<String, dynamic>> _hypno() {
  final t0 = _onsetTs;
  const plan = [
    ('light', 40),
    ('deep', 55),
    ('light', 30),
    ('rem', 25),
    ('awake', 8),
    ('light', 45),
    ('deep', 30),
    ('rem', 40),
    ('light', 35),
    ('rem', 30),
    ('awake', 12),
    ('light', 20),
  ];
  final out = <Map<String, dynamic>>[];
  var t = t0;
  for (final (stage, mins) in plan) {
    out.add({'t': t, 'stage': stage});
    t += mins * 60;
  }
  out.add({'t': t, 'stage': 'awake'});
  return out;
}

/// One night's map. [elevated] drives the nocturnal-heart-rate detection, which
/// is the one "unusual" item that comes from the night itself rather than from
/// a comparison against history.
Map<String, dynamic> _night({bool elevated = false}) => {
      'duration_min': 443,
      'in_bed_min': 486,
      'awake_min': 20,
      'efficiency': .91,
      'onset_ts': _onsetTs,
      'wake_ts': _onsetTs + 486 * 60,
      'light_min': 170,
      'deep_min': 85,
      'rem_min': 95,
      'hypnogram': _hypno(),
      'cycle_count': 5,
      'cycles_mean_min': 92,
      'advanced': const {'sol_s': 780},
      'nocturnal': {
        'sleeping_hr_avg': 52,
        'sleeping_hr_min': 46,
        'day_hr_avg': 68,
        'vs_baseline_bpm': elevated ? 4.6 : 0.4,
        'dip_pct': .24,
        'elevated': elevated,
      },
      'resp': const {'value': 14.2, 'confidence': .6},
    };

final _timeline = {
  'hr': [
    for (var i = 0; i < 120; i++)
      {'t': _onsetTs + i * 240, 'v': 52 + (i % 11) - 5},
  ],
  'hrv': [
    for (var i = 0; i < 120; i++)
      {'t': _onsetTs + i * 240, 'v': 62 + (i % 17) - 8},
  ],
  'resp': [
    for (var i = 0; i < 120; i++)
      {'t': _onsetTs + i * 240, 'v': 14 + (i % 5) / 2},
  ],
  // Relative skin temperature — the fourth lane, in deviation units, never °C.
  'skin_temp': [
    for (var i = 0; i < 60; i++)
      {'t': _onsetTs + i * 480, 'v': -0.2 + (i % 7) / 20},
  ],
};

/// [n] nights of history, deterministic, centred on [base] with a spread of
/// ±[amp]. The screen's comparison is quartiles of the user's own nights, so a
/// fixture only has to be a distribution — not a plausible calendar.
List<double> _nights(int n, double base, double amp) => [
      for (var i = 0; i < n; i++) base + ((i * 37) % 17) / 17 * amp - amp / 2,
    ];

/// Last night landed OUTSIDE the recent range on deep sleep (85 min against a
/// 55–80 history) and the sleeping heart rate ran high — so the comparison
/// rows, both extremes and the nocturnal detection are all on screen.
final _sleep = SleepData(
  day: '2026-05-20',
  night: _night(elevated: true),
  timeline: _timeline,
  need: const Metric(value: 462, unit: 'min', confidence: .7, tier: MetricTier.estimate),
  debt: const Metric(value: 22, unit: 'min', confidence: .7, tier: MetricTier.estimate),
  bedtime: const Metric(value: 1360, confidence: .7, tier: MetricTier.estimate),
  tstHistory: _nights(28, 452, 90),
  deepHistory: _nights(28, 67, 25),
  effHistory: _nights(28, 89, 8),
  onsetHistory: [
    for (var i = 0; i < 28; i++)
      _onsetTs - (i + 1) * 86400 + (((i * 37) % 17) - 8) * 300,
  ],
);

/// The common night: everything inside the user's own range, nothing to report.
/// "Nothing stood out" is an answer, and this is the state most nights are in.
final _sleepTypical = SleepData(
  day: '2026-05-20',
  night: _night(),
  timeline: _timeline,
  need: const Metric(value: 462, unit: 'min', confidence: .7, tier: MetricTier.estimate),
  bedtime: const Metric(value: 1360, confidence: .7, tier: MetricTier.estimate),
  tstHistory: _nights(28, 443, 120),
  deepHistory: _nights(28, 85, 40),
  effHistory: _nights(28, 91, 12),
  onsetHistory: [
    for (var i = 0; i < 28; i++)
      _onsetTs - (i + 1) * 86400 + (((i * 37) % 17) - 8) * 600,
  ],
);

/// A first-week user: a real night, and no history to judge it against. This is
/// what the screen looks like for a fortnight, and it must not pretend.
final _sleepNew = SleepData(
  day: '2026-05-20',
  night: _night(),
  timeline: _timeline,
  tstHistory: const [430, 465, 410],
);

const _sleepCold = SleepData();

/// Six weeks of nights, drifting an hour later at weekends.
CircadianData _circadian() {
  final cols = <List<double>?>[];
  final labels = <String>[];
  for (var d = 0; d < 42; d++) {
    if (d % 13 == 5) {
      cols.add(null); // a night the band was off
      labels.add('2026-04-${(d + 1).toString().padLeft(2, '0')}');
      continue;
    }
    final free = d % 7 >= 5;
    final onset = free ? 12.5 : 10.9; // hours after local noon
    final len = free ? 8.4 : 7.2;
    cols.add([
      for (var h = 0; h < 24; h++)
        (((onset + len) < h + 1 ? (onset + len) : h + 1) -
                (onset > h ? onset : h))
            .clamp(0.0, 1.0)
            .toDouble(),
    ]);
    labels.add('2026-04-${(d % 30 + 1).toString().padLeft(2, '0')}');
  }
  return CircadianData(
    actogram: cols,
    labels: labels,
    chronotypeLabel: 'slight evening type',
    jetlag: const Metric(value: 1.7, confidence: .6, tier: MetricTier.estimate),
    regularity: const Metric(value: 78, confidence: .7, tier: MetricTier.estimate),
    midFreeH: 4.2,
    midWorkH: 2.5,
    nFree: 9,
    nWork: 22,
    // The non-parametric battery and the cosinor, as the cross-day pipeline
    // emits them — on HOURLY HR, which is what the card's footnote discloses.
    rhythm: const Metric(value: .68, confidence: .7, tier: MetricTier.high),
    rhythmV: const {
      'IS': 0.68,
      'IV': 0.74,
      'M10': 82.4,
      'L5': 54.1,
      'RA': 0.21,
      'm10_start_epoch': 10,
      'l5_start_epoch': 2,
    },
    cosinorV: const {
      'mesor': 66.2,
      'amplitude': 9.4,
      'acrophase_hours': 15.3,
      'period_hours': 24.0,
      'r2': 0.61,
      'r2_adj': 0.58,
    },
    coverage: const {
      'days_used': 6,
      'days_need_np': 7,
      'days_need_cosinor': 3,
      'signal': 'hourly_hr',
    },
  );
}

/// A cycle with two logged starts — the floor at which a prediction exists at
/// all — plus a partial current cycle of derived nights behind it.
final _cycle = CycleData(
  enabled: true,
  phase: 'luteal',
  cycleDay: 19,
  daysUntilNext: 9,
  meanLength: 28,
  predictedNext: '2026-05-29',
  fertileStart: '2026-05-23',
  fertileEnd: '2026-05-27',
  logs: const [
    {'date': '2026-04-13', 'kind': 'start'},
    {'date': '2026-05-11', 'kind': 'start'},
  ],
  overlay: [
    for (var i = 1; i <= 19; i++)
      {
        'date': '2026-05-${(10 + i).toString().padLeft(2, '0')}',
        'cycle_day': i,
        'resting_hr': 52.0 + ((i * 31) % 9) / 3,
        'hrv_rmssd': 64.0,
        'skin_temp_idx': 0.2,
      },
  ],
  symptoms: const {},
);

/// Tracking on, nothing logged: the state a user lands in the moment they
/// enable it, and the only one with no numbers in it.
const _cycleEmpty = CycleData(enabled: true);

final _investigate = InvestigateData(
  day: '2026-05-20',
  algoVersion: 65,
  hrv: const {
    'rmssd': 68.2,
    'sdnn': 84.1,
    'ln_rmssd': 4.22,
    'baseline': 64.0,
    'hrv_time': {
      'value': {
        'rmssd_ms': 68.2,
        'sdnn_ms': 84.1,
        'sdann_ms': 61.4,
        'pnn50_pct': 18.6,
        'n_beats': 28441,
      },
      'confidence': .7,
      'tier': 'ESTIMATE',
    },
    'hrv_freq': {
      'value': {
        'lf': 1204.0,
        'hf': 892.0,
        'vlf': 1314.0,
        'total': 3410.0,
        'lf_hf': 1.35,
        'nu_lf': 57.4,
        'nu_hf': 42.6,
        'hf_gated': false,
      },
      'confidence': .6,
      'tier': 'ESTIMATE',
    },
    'prsa_dc': {
      'value': {'capacity_ms': 6.8, 'anchors': 4120, 'kind': 'dc'},
      'confidence': .6,
      'tier': 'ESTIMATE',
    },
    'prsa_ac': {
      'value': {'capacity_ms': -7.1, 'anchors': 4108, 'kind': 'ac'},
      'confidence': .6,
      'tier': 'ESTIMATE',
    },
  },
  heart: const {
    'hrv': {'cv': 12.4},
    // Production shape: a plain map for the sleep window...
    'irregular': {'sd1': 29.2, 'sd2': 76.8, 'flag': false, 'confidence': .5},
    // ...and an envelope for the 24 h screen, which is the only one carrying
    // the ratio and pNNx.
    'irregular_24h': {
      'value': {
        'sd1_ms': 31.4,
        'sd2_ms': 80.2,
        'sd1_sd2': 0.39,
        'pnn_pct': 1.2,
        'n_beats': 71204,
        'flag': false,
      },
      'confidence': .7,
      'tier': 'ESTIMATE',
    },
  },
  coveragePct: 94,
  windowStart: _onsetTs,
  windowEnd: _onsetTs + 486 * 60,
);

Map<String, Widget> _cases() => {
      'home': HomeScreen(data: _home, hour: 20),
      'home_cold': const HomeScreen(data: _homeCold, hour: 20),
      'health_overview': HealthScreen(data: _health, tab: 0),
      'health_overview_cold': const HealthScreen(data: _healthCold, tab: 0),
      'health_trends': HealthScreen(data: _health, tab: 1),
      'health_vitals': HealthScreen(data: _health, vitals: _vitals, tab: 2),
      'health_labs': HealthScreen(data: _health, labs: _labs, tab: 3),
      'health_labs_cold':
          HealthScreen(data: _health, labs: const LabsData(), tab: 3),
      'metric_detail': MetricDetail('resting_hr', data: _metricDetail),
      'metric_detail_cold':
          const MetricDetail('resting_hr', data: MetricData()),
      'metric_detail_suppressed':
          const MetricDetail('skin_temp', data: MetricData()),
      'readiness_detail': ReadinessDetail(data: _readiness),
      'readiness_detail_cold': const ReadinessDetail(data: _readinessCold),
      'sleep_detail': SleepDetail(data: _sleep),
      'sleep_detail_typical': SleepDetail(data: _sleepTypical),
      'sleep_detail_new': SleepDetail(data: _sleepNew),
      'sleep_detail_cold': const SleepDetail(data: _sleepCold),
      'circadian_detail': CircadianDetail(data: _circadian()),
      'circadian_detail_cold':
          const CircadianDetail(data: CircadianData()),
      'investigate_hrv': Investigate('hrv', data: _investigate),
      'investigate_generic':
          const Investigate('steps', data: InvestigateData(series: [])),
      // CycleTab renders a Column so it drops into Wellness's own ListView;
      // the golden supplies the scroller the tab does not own.
      'cycle': _scroll(CycleTab(data: _cycle)),
      'cycle_empty': _scroll(const CycleTab(data: _cycleEmpty)),
      'cycle_off': _scroll(const CycleTab(data: CycleData())),
    };

Widget _scroll(Widget child) => ListView(
      padding: const EdgeInsets.fromLTRB(S.x4, S.x4, S.x4, S.x16),
      children: [child],
    );

final _shot = GlobalKey();

/// Full-viewport, because these are pages. A page golden that is shrink-wrapped
/// hides exactly the overflow a page golden exists to catch.
Widget _frame(Widget child, Brightness b, double scale) => MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(b),
        home: Builder(
          builder: (c) => RepaintBoundary(
            key: _shot,
            child: child is Scaffold
                ? child
                : Scaffold(
                    backgroundColor: P.of(c).bg,
                    body: SafeArea(child: child),
                  ),
          ),
        ),
      ),
    );

Future<void> _loadType() async {
  final files = Directory('assets/fonts/Manrope')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.ttf'));
  for (final family in const ['Manrope', '.SF Pro Text', 'Menlo']) {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(f
          .readAsBytes()
          .then((b) => ByteData.sublistView(Uint8List.fromList(b))));
    }
    await loader.load();
  }
}

void main() {
  final cases = _cases();

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadType();
  });

  for (final scale in const [1.0, 2.0]) {
    final tag = scale == 1.0 ? '1x' : '2x';
    for (final brightness in Brightness.values) {
      final theme = brightness.name;
      group('$theme · $tag text', () {
        cases.forEach((name, widget) {
          testWidgets(name, (tester) async {
            tester.view.physicalSize = const Size(390 * 3, 1400 * 3);
            tester.view.devicePixelRatio = 3;
            addTearDown(tester.view.reset);

            await tester.pumpWidget(_frame(widget, brightness, scale));
            await tester.pumpAndSettle();

            await expectLater(
              find.byKey(_shot),
              matchesGoldenFile('goldens/screen_${name}_${theme}_$tag.png'),
            );
          });
        });
      });
    }
  }

  testWidgets('a min-unit metric does not print its unit twice', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 1400 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    // `metricValue('min', v)` is already "7h 23m"; the hero used to print
    // `spec.unit` beside it, so Time asleep read "7h 23m min".
    await tester.pumpWidget(_frame(
        MetricDetail('sleep',
            data: MetricData(series: _points(30, 443, 0), daysAvailable: 30)),
        Brightness.light,
        1));
    await tester.pumpAndSettle();
    final mins = tester
        .widgetList<Text>(find.byType(Text))
        .where((t) => (t.data ?? '').contains('m min'));
    expect(mins, isEmpty, reason: 'the unit is baked into the formatted value');
    expect(find.text('7h 23m'), findsWidgets);
  });

  testWidgets('the percentile sentence dates itself when the newest stored '
      'reading is not today\'s', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 1400 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    // Four days of stored points ending FOUR DAYS AGO. The rank the rollup
    // carries is that day's; "Today sits at the 22nd percentile" was printed
    // unconditionally, two rows under a hero saying "4 days ago".
    final stale = [
      for (final p in _points(8, 54, 6)) (t: p.t - 4 * 86400, v: p.v),
    ];
    await tester.pumpWidget(_frame(
        MetricDetail('resting_hr',
            data: MetricData(
              series: stale,
              daysAvailable: 30,
              percentile: const {'percentile_of_you': 22.0},
            )),
        Brightness.light,
        1));
    await tester.pumpAndSettle();
    expect(find.textContaining('Your reading from 4 days ago sits at the 22nd'),
        findsOneWidget);
  });

  testWidgets('an absent metric never renders a bare em-dash', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 1400 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    for (final w in <Widget>[
      const HomeScreen(data: _homeCold),
      const HealthScreen(data: _healthCold),
      const ReadinessDetail(data: _readinessCold),
      const SleepDetail(data: _sleepCold),
      SleepDetail(data: _sleepNew),
      const CircadianDetail(data: CircadianData()),
      const MetricDetail('resting_hr', data: MetricData()),
      const MetricDetail('skin_temp', data: MetricData()),
      const Investigate('hrv', data: InvestigateData()),
      const Investigate('steps', data: InvestigateData()),
      const HealthScreen(data: _healthCold, vitals: VitalsData(), tab: 2),
      const HealthScreen(data: _healthCold, labs: LabsData(), tab: 3),
      _scroll(const CycleTab(data: CycleData())),
      _scroll(const CycleTab(data: _cycleEmpty)),
      // The readiness row that used to hold the app's one reachable em-dash:
      // a driver marked used whose weighted contribution never arrived.
      const ReadinessDetail(
          data: ReadinessData(
        readiness: Metric(value: 74, confidence: .8, tier: MetricTier.high),
        breakdown: [
          {'label': 'hrv', 'weight': .4, 'used': true, 'past_mdc': true},
        ],
        inputsUsed: 1,
      )),
    ]) {
      await tester.pumpWidget(_frame(w, Brightness.light, 1));
      await tester.pumpAndSettle();
      final dashes = tester
          .widgetList<Text>(find.byType(Text))
          .where((t) => (t.data ?? '').trim() == '—');
      expect(dashes, isEmpty,
          reason: '${w.runtimeType} rendered a bare em-dash. An absent value '
              'is a StatusCard: what is missing, why, what fixes it.');
    }
  });
}
