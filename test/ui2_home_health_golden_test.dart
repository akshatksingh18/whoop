// Goldens for Home, Health and the shared drill-down.
//
// Every screen is captured twice: once with data and once with none. The
// second half is the point â€” "absent" is a first-class state in this app, it
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
import 'package:openstrap_edge/models/metric.dart';
import 'package:openstrap_edge/ui2/screens/screens.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

/// Deterministic â€” a golden that depends on a random number is a golden that
/// records noise.
List<double> _series(int n, double base, double amp) => List<double>.generate(
  n,
  (i) => base + ((i * 37) % 17) / 17 * amp - amp / 2,
);

/// The same series with the timestamps a real `getChart` carries: one point per
/// day, ending TODAY, stamped at local noon the way `metric_series` reads back.
///
/// Anchored to the run date on purpose. The screens label their axes and their
/// "as of" line RELATIVE to today, so a fixture pinned to a fixed calendar date
/// would render "88 days ago" on one morning and "89 days ago" the next â€” a
/// golden that fails on the passage of time. Anchored here, the rendered text
/// is identical on every run, and a gap in the fixture would show up as one.
List<ChartPoint> _points(int n, double base, double amp) {
  final vs = _series(n, base, amp);
  final now = DateTime.now();
  return [
    for (var i = 0; i < n; i++)
      (
        t:
            DateTime(
              now.year,
              now.month,
              now.day - (n - 1 - i),
              12,
            ).millisecondsSinceEpoch ~/
            1000,
        v: vs[i],
      ),
  ];
}

Map<String, dynamic> _metric(num? v, String tier, {String? note}) => {
  'value': v ?? 'â€”',
  'confidence': v == null ? 0 : 0.8,
  'tier': tier,
  'inputs_used': const <String>[],
  'note': ?note,
};

// â”€â”€ fixtures â”€â”€

final _home = HomeData(
  name: 'Alex',
  dayId: '2026-05-20',
  readiness: const Metric(value: 82, confidence: .8, tier: MetricTier.high),
  drivers: const [
    {'label': 'hrv', 'contribution': 6.2, 'detail': 'lifting your score'},
    {'label': 'rhr', 'contribution': 3.1, 'detail': 'lifting your score'},
    {
      'label': 'temp',
      'contribution': -1.4,
      'detail': 'dragging your score down',
    },
  ],
  sleepMin: const Metric(
    value: 465,
    unit: 'min',
    confidence: .8,
    tier: MetricTier.estimate,
  ),
  strain: const Metric(
    value: 14.2,
    confidence: .6,
    tier: MetricTier.estimate,
  ),
  rhr: const Metric(
    value: 52,
    unit: 'bpm',
    confidence: .8,
    tier: MetricTier.high,
  ),
  steps: const Metric(
    value: 8642,
    unit: 'steps',
    confidence: .6,
    tier: MetricTier.estimate,
  ),
  calories: const Metric(
    value: 640,
    unit: 'kcal',
    confidence: .6,
    tier: MetricTier.estimate,
  ),
  caloriesTotal: const Metric(
    value: 2310,
    unit: 'kcal',
    confidence: .6,
    tier: MetricTier.estimate,
  ),
  stepGoal: 8000,
  sleepNeedMin: const Metric(
    value: 462,
    unit: 'min',
    confidence: .7,
    tier: MetricTier.estimate,
  ),
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
    // tier), not a bare score â€” the screen reads the tier off it.
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
    // absent â€” so the golden was recording a real deviation dotted "Not
    // measured".
    'skin_temp': {
      'value': 0.31,
      'confidence': .5,
      'tier': 'RELATIVE',
      'inputs_used': const ['skin_temp_raw'],
      'note':
          'relative deviation (z) vs your baseline; raw ADC, no absolute Â°C',
    },
    'illness': {'state': 'green'},
  },
  charts: {
    'resting_hr': _points(60, 54, 6),
    'hrv': _points(60, 66, 16),
    'sleep': _points(60, 440, 70),
    'recovery': _points(60, 62, 30),
    'strain': _points(60, 10, 8),
    'steps': _points(60, 8000, 5000),
    'resp_rate': _points(60, 14.2, 1.8),
  },
);

const _healthCold = HealthData();


final _metricDetail = MetricData(
  series: _points(60, 54, 6),
  daysAvailable: 60,
  percentile: const {
    'percentile_of_you': 22.0,
    'n': 59,
    'label': 'lower than usual',
  },
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
    {
      'label': 'hrv',
      'weight': .4,
      'weighted_contribution': 6.2,
      'past_mdc': true,
      'used': true,
    },
    {
      'label': 'rhr',
      'weight': .3,
      'weighted_contribution': 3.1,
      'past_mdc': true,
      'used': true,
    },
    {
      'label': 'resp',
      'weight': .2,
      'weighted_contribution': 0.4,
      'past_mdc': false,
      'used': true,
    },
    {
      'label': 'temp',
      'weight': .1,
      'weighted_contribution': -1.4,
      'past_mdc': true,
      'used': true,
    },
  ],
  inputsUsed: 4,
  series: _series(90, 74, 18),
);

const _readinessCold = ReadinessData(
  readiness: Metric(note: 'need_baseline:have=5,need=14'),
);

/// Onset as a LOCAL wall-clock instant, not a fixed epoch. The screen formats
/// timestamps in the device zone, so anchoring the fixture the same way is what
/// makes these goldens byte-identical on a machine in another timezone.
final _onsetTs = DateTime(2026, 5, 19, 23, 7).millisecondsSinceEpoch ~/ 1000;

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
  'light_min': 263, // 443 − 85 − 95: stages sum to total sleep, as in real data
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
  // Relative skin temperature â€” the fourth lane, in deviation units, never Â°C.
  'skin_temp': [
    for (var i = 0; i < 60; i++)
      {'t': _onsetTs + i * 480, 'v': -0.2 + (i % 7) / 20},
  ],
};

/// [n] nights of history, deterministic, centred on [base] with a spread of
/// Â±[amp]. The screen's comparison is quartiles of the user's own nights, so a
/// fixture only has to be a distribution â€” not a plausible calendar.
List<double> _nights(int n, double base, double amp) => [
  for (var i = 0; i < n; i++) base + ((i * 37) % 17) / 17 * amp - amp / 2,
];

/// Last night landed OUTSIDE the recent range on deep sleep (85 min against a
/// 55â€“80 history) and the sleeping heart rate ran high â€” so the comparison
/// rows, both extremes and the nocturnal detection are all on screen.
final _sleep = SleepData(
  day: '2026-05-20',
  night: _night(elevated: true),
  timeline: _timeline,
  need: const Metric(
    value: 462,
    unit: 'min',
    confidence: .7,
    tier: MetricTier.estimate,
  ),
  debt: const Metric(
    value: 22,
    unit: 'min',
    confidence: .7,
    tier: MetricTier.estimate,
  ),
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
  need: const Metric(
    value: 462,
    unit: 'min',
    confidence: .7,
    tier: MetricTier.estimate,
  ),
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

Map<String, Widget> _cases() => {
  'home': HomeScreen(data: _home, hour: 20),
  'home_cold': const HomeScreen(data: _homeCold, hour: 20),
  'trends': HealthScreen(data: _health),
  'trends_week': HealthScreen(data: _health, range: 0),
  'trends_cold': const HealthScreen(data: _healthCold),
  'metric_detail': MetricDetail('resting_hr', data: _metricDetail),
  'metric_detail_cold': const MetricDetail('resting_hr', data: MetricData()),
  'metric_detail_suppressed': const MetricDetail(
    'skin_temp',
    data: MetricData(),
  ),
  'readiness_detail': ReadinessDetail(data: _readiness),
  'readiness_detail_cold': const ReadinessDetail(data: _readinessCold),
  'sleep_detail': SleepDetail(data: _sleep),
  'sleep_detail_typical': SleepDetail(data: _sleepTypical),
  'sleep_detail_new': SleepDetail(data: _sleepNew),
  'sleep_detail_cold': const SleepDetail(data: _sleepCold),
};

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
  final files = Directory(
    'assets/fonts/Manrope',
  ).listSync().whereType<File>().where((f) => f.path.endsWith('.ttf'));
  for (final family in const ['Manrope', '.SF Pro Text', 'Menlo']) {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(
        f.readAsBytes().then(
          (b) => ByteData.sublistView(Uint8List.fromList(b)),
        ),
      );
    }
    await loader.load();
  }
}

/// The golden PNGs are NOT in the repo. They are machine-specific â€” two Flutter
/// SDKs disagree on antialiasing â€” and 27 MB of them was purged from history,
/// so this group can only pass on a machine that has them.
///
/// Skipped with a stated reason rather than filtered out by a CI flag: the run
/// then says out loud that nobody checked the pixels, which is the honest
/// report. Drop the images back into test/goldens/ and it runs again.
final Object _noGoldens = Directory('test/goldens').existsSync()
    ? false
    : 'golden images are not committed â€” run this suite locally';

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
      group('$theme Â· $tag text', () {
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
      }, skip: _noGoldens);
    }
  }

  testWidgets('a min-unit metric does not print its unit twice', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390 * 3, 1400 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    // `metricValue('min', v)` is already "7h 23m"; the hero used to print
    // `spec.unit` beside it, so Time asleep read "7h 23m min".
    await tester.pumpWidget(
      _frame(
        MetricDetail(
          'sleep',
          data: MetricData(series: _points(30, 443, 0), daysAvailable: 30),
        ),
        Brightness.light,
        1,
      ),
    );
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
    await tester.pumpWidget(
      _frame(
        MetricDetail(
          'resting_hr',
          data: MetricData(
            series: stale,
            daysAvailable: 30,
            percentile: const {'percentile_of_you': 22.0},
          ),
        ),
        Brightness.light,
        1,
      ),
    );
    await tester.pumpAndSettle();
    // The screen opens on Today, which has no stored point here â€” the rank is
    // a property of the history, so the sentence lives on a wider range.
    await tester.tap(find.text('30 days'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Your reading from 4 days ago sits at the 22nd'),
      findsOneWidget,
    );
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
      const MetricDetail('resting_hr', data: MetricData()),
      const MetricDetail('skin_temp', data: MetricData()),
      // The readiness row that used to hold the app's one reachable em-dash:
      // a driver marked used whose weighted contribution never arrived.
      const ReadinessDetail(
        data: ReadinessData(
          readiness: Metric(value: 74, confidence: .8, tier: MetricTier.high),
          breakdown: [
            {'label': 'hrv', 'weight': .4, 'used': true, 'past_mdc': true},
          ],
          inputsUsed: 1,
        ),
      ),
    ]) {
      await tester.pumpWidget(_frame(w, Brightness.light, 1));
      await tester.pumpAndSettle();
      final dashes = tester
          .widgetList<Text>(find.byType(Text))
          .where((t) => (t.data ?? '').trim() == 'â€”');
      expect(
        dashes,
        isEmpty,
        reason:
            '${w.runtimeType} rendered a bare em-dash. An absent value '
            'is a StatusCard: what is missing, why, what fixes it.',
      );
    }
  });
}
