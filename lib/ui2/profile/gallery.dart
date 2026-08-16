// The component gallery, and the one set of fixtures behind it.
//
// Two things live here, and the second is the reason for the first.
//
//   · [galleryCases] — every reusable component in lib/ui2, built once, with
//     a name. `test/ui2_golden_test.dart` shoots the same map, so the picture
//     on the phone and the picture in the goldens cannot describe two
//     different design systems.
//   · [GalleryScreen] — that map on a real device, at a real text scale, in
//     both themes. Every layout bug this project has shipped lived in one of
//     those two dimensions, and neither is visible on a laptop at 1.0×.
//
// The fixtures are deliberately the LONGEST realistic value for every slot,
// never the tidiest. Three shipped bugs — cards overflowing at 2.0×, a status
// row that fitted only the word "Connected", a greeting baked in the evening
// so the morning branch never rendered — were all invisible because the
// example was two characters long and the happy branch.
//
// Nothing here reads the database, the band or the repository: a gallery that
// needs data is a gallery nobody opens on a fresh install.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/journal_fields.dart';
import '../../data/med_store.dart';
import '../../data/nutrition_store.dart';
import '../../models/metric.dart';
import '../activity/catalogue.dart';
import '../activity/live.dart';
import '../activity/picker.dart' show ActivityRow;
import '../activity/poster.dart' show PosterCard;
import '../activity/share.dart' show ShareCard;
import '../activity/summary.dart';
import '../onboarding/profile_setup.dart' show UnlockContract;
import '../onboarding/welcome.dart' show ImportOutcome, ImportReport;
// Screens are deliberately not re-exported from the ui2 barrel (see the
// barrel test), so their components are imported by path.
import '../screens/screens.dart';
import '../ui2.dart';
import 'devices.dart';
import 'profile.dart';

/// A deterministic series — a gallery cannot depend on random data, and
/// neither can a golden.
final _series =
    List<double>.generate(24, (i) => 52 + (i * 37 % 23) - (i % 5) * 2.0);

const _night = <SleepStage>[
  ...[SleepStage.awake, SleepStage.light, SleepStage.light, SleepStage.deep],
  ...[SleepStage.deep, SleepStage.light, SleepStage.rem, SleepStage.light],
  ...[SleepStage.deep, SleepStage.light, SleepStage.rem, SleepStage.awake],
  ...[SleepStage.light, SleepStage.rem, SleepStage.light, SleepStage.awake],
];

/// Everything, in the order the gallery lists it.
Map<String, Widget> galleryCases() => {...goldenCases(), ...extraCases()};

/// The cases the goldens photograph. Named separately from [extraCases] only
/// because a PNG per case per theme per scale is a file somebody has to
/// review — see the note at the bottom of the golden test.
Map<String, Widget> goldenCases() => {
      // The one number the whole app is judged by, and the picture the app
      // leaves someone else's phone. Both are photographed rather than merely
      // swept: they are the two components a regression would be noticed in
      // last and cost the most.
      'readiness_hero': const ReadinessHero(
        readiness:
            Metric(value: 72, confidence: .8, tier: MetricTier.high),
        drivers: [
          {'label': 'hrv'},
          {'label': 'sleep_debt'},
          {'label': 'rhr'},
        ],
      ),
      'readiness_hero_held_over': const ReadinessHero(
        readiness:
            Metric(value: 41, confidence: .6, tier: MetricTier.estimate),
        heldOverNight: '2026-08-14',
      ),
      'share_card': _shareCard(0),
      'share_card_art': _shareCard(1),
      'signal': const SignalCard(
          LucideIcons.heartPulse, C.blue, 'Resting heart rate', '52',
          unit: 'bpm', sub: '4 BELOW YOUR BASELINE'),
      // A REALISTIC value, not two characters. Every card below used to be
      // shot with '52' / '38 min' / '+6', and the 2.0x tier passed because of
      // it: with a duration or a thousands separator in the same slot, six
      // components overflowed at the very scale the goldens claimed to cover.
      'progress': const ProgressCard(
          'Time asleep', '1h 38m', 'of 2h 00m', .63, C.domMove,
          icon: LucideIcons.footprints),
      'trend': TrendCard('Time asleep', '7h 42m', 'last night', '+38m',
          'vs 14-day baseline', _series, C.green,
          up: true),
      'insight': const InsightCard(
        'Your sleep debt cleared overnight',
        'Seven hours forty, the longest this week, and your heart rate '
            'settled forty minutes earlier than usual.',
        action: 'See the night',
      ),
      'action': const ActionCard('Charge the strap', '18% remaining',
          'Remind me', LucideIcons.batteryLow, C.orange),
      'status': const StatusCard(
        'No respiratory rate last night',
        'The strap was off your wrist between 01:10 and 06:40, so there was '
            'nothing to measure.',
        fix: 'How wear position affects this',
      ),
      'deep_dive': DeepDiveCard('Heart rate variability', '7h 42m', 'ms',
          'Open the full night', C.purple,
          preview: SizedBox(
            height: 48,
            child: CustomPaint(
                size: Size.infinite, painter: LineChart(_series, C.purple)),
          )),
      'metric_row': const Column(children: [
        MetricRow(LucideIcons.thermometer, C.orange, 'Skin temperature', '+0.3',
            sub: 'RELATIVE TO BASELINE', unit: '°'),
        // A long name, a thousands-separated value and a word in the trailing
        // slot — 'ON TRACK' needs 92 pt at 1.0x and was clipped inside a fixed
        // 52 pt box before any scaling at all.
        MetricRow(LucideIcons.flame, C.orange, 'Active energy burned', '2,310',
            unit: 'kcal', status: 'ON TRACK'),
      ]),
      'inline_metrics': const InlineMetrics([
        ('ASLEEP', '7h 40m', C.blue),
        ('EFFICIENCY', '91%', C.green),
        ('AWAKE', '22m', C.orange),
      ]),
      'recommendation': const Recommendation(
        'Keep it easy today',
        'HRV is six milliseconds below your baseline and resting heart rate '
            'is up three — the same pattern as the day before your last cold.',
        'See what changed',
      ),
      'goal_trajectory': const GoalTrajectory(
          'Weight', '78.4 kg', '75 kg', '0.3 kg per week', .62, C.teal),
      'observation': const Observation(
        'Your resting heart rate has risen on six of the last seven nights',
        'From 51 to 58 bpm, alongside a 0.4° skin-temperature rise.',
        advice: 'Worth mentioning if it continues past a week.',
      ),
      'consistency': const Consistency(
          18, 24, 'Nights with a full sleep record', C.domHealth),
      'pill_row': const Wrap(spacing: S.x2, runSpacing: S.x2, children: [
        Pill('Estimated', C.yellow, icon: LucideIcons.circleDashed),
        Pill('Relative', C.purple),
      ]),
      'big_button': const Column(children: [
        BigButton('Start workout', icon: LucideIcons.play, color: C.domMove),
        SizedBox(height: S.x3),
        BigButton('Not now', color: C.domMove, soft: true),
      ]),
      'sub_tabs': SubTabs(
          const ['Today', 'Sleep', 'Recovery', 'Strain'], 1, (_) {},
          color: C.domHealth),
      'nav_bar': const NavBar('Last night', sub: 'MON 14 AUG'),
      'section': const Section('Recovery', StatusCard('Nothing yet today',
          'The first sync of the day has not landed.'),
          action: 'History'),
      ..._chartCases(),
      ..._nutritionAndWellnessCases(),
    };

/// Charts, framed. Every one of these is captured with the thing that was
/// missing before: a unit in the header, numbers on the y axis, labels under
/// the x axis, a key for every colour — and, for the empty case, an honest
/// sentence where the axis would have been.
Map<String, Widget> _chartCases() {
  // 40…80 bpm, deterministic.
  final rhr = List<double>.generate(30, (i) => 52 + (i * 13 % 17) - (i % 4) * 1.0);
  final minutes = List<double>.generate(7, (i) => 380 + (i * 47 % 90).toDouble());
  // A `Builder`, because a painter's palette is now solved against the surface
  // it lands on — the same case has to draw different ink in the two themes,
  // and this map is built once and shot in both.
  return {
    'chart_line': Builder(builder: (c) {
      final p = P.of(c);
      return Surface(
        child: ChartFrame(
          title: 'Resting heart rate',
          unit: 'bpm',
          yAxis: AxisSpec.of(rhr, floor: 40),
          xLabels: const ['30 Jul', '14 Aug', 'Today'],
          footnote: 'Your usual range is 52–64 bpm.',
          series: rhr,
          child: CustomPaint(
            size: Size.infinite,
            painter: LineChart(rhr, p.on(C.blue),
                axis: AxisSpec.of(rhr, floor: 40), dots: true),
          ),
        ),
      );
    }),
    'chart_bars': Builder(builder: (c) {
      final p = P.of(c);
      return Surface(
        child: ChartFrame(
          title: 'Time asleep',
          unit: 'per night',
          height: 110,
          yAxis: AxisSpec.of(minutes, floor: 0, format: axisHm, step: 120),
          xLabels: const ['Mon', 'Thu', 'Sun'],
          series: minutes,
          child: CustomPaint(
            size: Size.infinite,
            painter: Bars(minutes, p.on(C.domHealth), p.track,
                axis: AxisSpec.of(minutes, floor: 0, format: axisHm, step: 120)),
          ),
        ),
      );
    }),
    'chart_hypnogram': Builder(builder: (c) {
      final p = P.of(c);
      return Surface(
        child: ChartFrame(
          title: 'Last night',
          unit: 'sleep stages',
          height: 96,
          xLabels: const ['23:10', '03:00', '06:40'],
          legend: Hypnogram.legend(p),
          footnote: 'Deep sleep is inferred from heart-rate flatness.',
          child: CustomPaint(size: Size.infinite, painter: Hypnogram(_night, p)),
        ),
      );
    }),
    'chart_zones': Builder(builder: (c) {
      final p = P.of(c);
      return Surface(
        child: ChartFrame(
          title: 'Time in heart-rate zones',
          unit: 'share of the session',
          height: 28,
          legend: ZoneBar.legend(p),
          child: CustomPaint(
              size: Size.infinite,
              painter: ZoneBar(const [.18, .34, .28, .15, .05], p)),
        ),
      );
    }),
    'chart_empty': const Surface(
      child: ChartFrame(
        title: 'Respiratory rate',
        unit: 'breaths/min',
        yAxis: AxisSpec(min: 10, max: 20, format: axisInt),
        xLabels: ['Mon', 'Sun'],
        empty: NoData(message: 'No nights recorded this week'),
        child: SizedBox.shrink(),
      ),
    ),
  };
}

/// Nutrition and Wellness. Every one of these is a widget the screens compose
/// from, captured with the state that is easiest to get wrong: a day whose
/// energy is a floor rather than a total, an occasion with no numbers, a dose
/// that has not come due yet.
Map<String, Widget> _nutritionAndWellnessCases() {
  const bare = FoodEntry(
      id: 'a', date: '2026-08-14', meal: 'dinner', label: 'Dinner');
  const known = FoodEntry(
      id: 'b',
      date: '2026-08-14',
      meal: 'breakfast',
      label: 'Porridge and berries',
      kcal: 420,
      proteinG: 14,
      carbsG: 62,
      fatG: 9,
      confirmed: true);
  return {
    // A day that summed past an unknown: the number is a FLOOR and says so.
    'day_energy_floor': DayEnergyCard(
      day: rollupDay('2026-08-14', const [known, bare], today: '2026-08-15'),
      burned: const Metric(
          value: 2350, unit: 'kcal', confidence: .6, tier: MetricTier.estimate),
    ),
    'meal_row': const Column(children: [
      MealRow(meal: 'breakfast', entries: [known]),
      MealRow(meal: 'dinner', entries: []),
    ]),
    'food_row': const Surface(
        pad: EdgeInsets.symmetric(horizontal: S.x4),
        child: Column(children: [
          FoodRow(entry: known, trailing: LucideIcons.circlePlus),
          FoodRow(entry: bare),
        ])),
    'mood_picker': MoodPicker(value: 4, onChanged: (_) {}),
    'mood_picker_blank': MoodPicker(onChanged: (_) {}),
    'field_stepper': Surface(
        child: Column(children: [
          FieldStepper(
              spec: kJournalFieldsByKey['water_ml']!,
              value: 1500,
              onChanged: (_) {}),
          FieldStepper(
              spec: kJournalFieldsByKey['caffeine_mg']!,
              value: null,
              onChanged: (_) {}),
        ])),
    'text_field': OsTextField(
        controller: TextEditingController(text: 'Slept badly, big lunch.'),
        label: 'Anything else',
        lines: 3),
    'breath_circle': const BreathCircle(t: .7, label: 'Inhale'),
    'driver_row': const Surface(
        pad: EdgeInsets.symmetric(horizontal: S.x4),
        child: Column(children: [
          DriverRow(
              label: 'HRV above your baseline',
              detail: '68 ms against a 14-night mean of 61'),
          DriverRow(
              label: 'Slept 52 minutes short', detail: '7h 08m against 8h 00m'),
        ])),
    'med_row': Surface(
        pad: const EdgeInsets.symmetric(horizontal: S.x4),
        child: Column(children: [
          for (final s in _medSlots) MedRow(slot: s),
        ])),
  };
}

// ══════════════════ a finished session ══════════════════

/// One completed activity, carrying enough of everything that every share
/// style has something to draw: a route, splits, a heart-rate curve WITH a
/// dropout in it, and elevation.
final _finished = ActivityResult(
  const Activity('Trail running', LucideIcons.mountain, C.green,
      Track.distance, 10.5,
      gps: true),
  // Fixed, never `DateTime.now()` — a gallery case that moves is a golden
  // that fails on a Tuesday.
  start: DateTime(2026, 8, 13, 18, 20),
  // `Motion.tick * seconds` rather than a literal: theme.dart is the only
  // file allowed to spell a Duration, and this is one second times N.
  duration: Motion.tick * 3734,
  avgHr: 148,
  maxHr: 176,
  calories: 812,
  strain: 14.6,
  hr: [
    for (var i = 0; i < 62; i++)
      i > 28 && i < 34 ? null : 132 + (i * 19 % 31) * 1.0,
  ],
  zoneMinutes: const [6, 14, 22, 16, 4],
  route: _route,
  routePace: [for (var i = 0; i < _route.length; i++) (i % 20) / 20],
  distanceKm: 12.42,
  elevationM: _metres,
  gainM: 318,
  lossM: 302,
  splits: const [
    KmSplit(1, 302, avgHr: 141),
    KmSplit(2, 288, avgHr: 149),
    KmSplit(3, 331, avgHr: 152),
  ],
);

/// The share card at one style. Every stat the session can offer is ticked —
/// the longest realistic card, not the tidiest.
Widget _shareCard(int style) => ShareCard(_finished, style, const {
      'Time',
      'Distance',
      'Pace',
      'Heart rate',
      'Calories',
      'Elevation',
    });

const _medDef = MedDef(
    key: 'custom_d',
    label: 'Vitamin D',
    doseValue: 2000,
    doseUnit: 'IU',
    schedule: [MedSchedule(480, [1, 2, 3, 4, 5, 6, 7])]);

/// Taken, missed and not-yet-due, side by side — the third is the one that
/// must never read as a failure.
const _medSlots = <MedSlot>[
  MedSlot(def: _medDef, date: '2026-08-14', slotMin: 480, state: DoseState.taken),
  MedSlot(
      def: MedDef(key: 'custom_m', label: 'Magnesium', doseValue: 300, doseUnit: 'mg'),
      date: '2026-08-14',
      slotMin: 780,
      state: DoseState.missed),
  MedSlot(
      def: MedDef(key: 'custom_z', label: 'Zinc'),
      date: '2026-08-14',
      slotMin: 1260,
      state: DoseState.upcoming),
];

// ══════════════════ the rest of the vocabulary ══════════════════
//
// The primitives and the painters the goldens do not photograph. They are
// still swept for overflow and for the 44 pt minimum at every text tier by
// the golden test, which is the half of the coverage that catches bugs
// without adding a PNG nobody reviews.

/// An out-and-back loop, normalised 0…1 in both axes — the projection is the
/// caller's job, and here the caller is a fixture.
final _route = [
  for (var i = 0; i < 90; i++)
    Offset(.5 + .38 * cos(i / 90 * 2 * pi),
        .5 + .30 * sin(i / 90 * 2 * pi) * (1 - i / 260)),
];

// A climb and a descent with a rough surface on it, not noise: an elevation
// profile shaped like white noise is a reference picture nobody can tell a
// broken painter from.
final _metres = List<double>.generate(
    120, (i) => 180 + 240 * sin(i / 120 * pi) + (i % 7) * 3.0);
final _watts = List<double>.generate(60, (i) => 340 - i * 3.4 + (i % 7) * 6.0);
final _psd = List<double>.generate(64, (i) => (i < 20 ? 40 - i : 26 - i * .3)
    .clamp(1, 60)
    .toDouble());

Map<String, Widget> extraCases() => {
      'surface': Builder(
        builder: (c) => Surface(
          child: Text(
            'The base card. Elevation, not outline — and the only surface a '
            'component may sit on.',
            style: F.body.copyWith(color: P.of(c).ink),
          ),
        ),
      ),
      'pressable': Builder(
        builder: (c) => Pressable(
          onTap: () {},
          semanticLabel: 'Open the full night',
          child: Text('Open the full night',
              style: F.body.copyWith(color: P.of(c).on(C.green))),
        ),
      ),
      'screen_title': const ScreenTitle('Sleep and recovery',
          trailing: Pill('Estimated', C.yellow)),
      // Static on purpose: the gallery shows the control, and its position is
      // a fixture like every other value here.
      'scrubber': Builder(builder: (c) {
        final p = P.of(c);
        return Surface(
          child: ChartFrame(
            title: 'Last night',
            unit: 'sleep stages',
            height: 96,
            xLabels: const ['23:10', '03:00', '06:40'],
            legend: Hypnogram.legend(p),
            child: Scrubber(
              value: .42,
              onChanged: (_) {},
              label: 'Hypnogram',
              describe: (_) => '03:12, light sleep',
              child:
                  CustomPaint(size: Size.infinite, painter: Hypnogram(_night, p)),
            ),
          ),
        );
      }),
      'chart_ring': Builder(builder: (c) {
        final p = P.of(c);
        return Surface(
          child: ChartFrame(
            title: 'Readiness',
            unit: 'out of 100',
            height: 120,
            footnote: 'Against your own 14-day baseline, not a population.',
            child: CustomPaint(
                size: Size.infinite,
                painter: Ring(.72, p.on(C.green), p.track)),
          ),
        );
      }),
      'chart_macro_ring': Builder(builder: (c) {
        final p = P.of(c);
        return Surface(
          child: ChartFrame(
            title: 'Protein',
            unit: 'of 140 g',
            height: 44,
            child: CustomPaint(
                size: Size.infinite,
                painter: MacroRing(.48, p.on(C.orange), p.track)),
          ),
        );
      }),
      'chart_actogram': Builder(builder: (c) {
        final p = P.of(c);
        return Surface(
          child: ChartFrame(
            title: 'Rest and activity by hour',
            unit: 'last 28 days',
            height: 120,
            xLabels: const ['18 Jul', '1 Aug', 'Today'],
            // A missing day is a null column, not a quiet one.
            child: CustomPaint(
              size: Size.infinite,
              painter: Actogram([
                for (var d = 0; d < 28; d++)
                  d == 9 || d == 10
                      ? null
                      : [for (var h = 0; h < 24; h++) ((h + d) % 24) / 24],
              ], p.on(C.domMove)),
            ),
          ),
        );
      }),
      'chart_heatmap': Builder(builder: (c) {
        final p = P.of(c);
        return Surface(
          child: ChartFrame(
            title: 'Nights with a full sleep record',
            unit: 'last 12 weeks',
            height: 96,
            xLabels: const ['24 May', '19 Jul', 'This week'],
            child: CustomPaint(
              size: Size.infinite,
              painter: HeatMap([
                for (var w = 0; w < 12; w++)
                  [
                    for (var d = 0; d < 7; d++)
                      (w * 7 + d) % 11 == 0 ? null : ((w + d) % 5) / 4,
                  ],
              ], p.on(C.domHealth), p.track),
            ),
          ),
        );
      }),
      'chart_spectrum': Builder(builder: (c) {
        final p = P.of(c);
        final painter = Spectrum(_psd, lf: p.on(C.blue), hf: p.on(C.purple));
        return Surface(
          child: ChartFrame(
            title: 'Heart-rate variability spectrum',
            unit: 'ms² per Hz',
            height: 96,
            legend: painter.legend,
            footnote: 'Beat timing at 1 Hz is pulse-rate variability, not ECG.',
            child: CustomPaint(size: Size.infinite, painter: painter),
          ),
        );
      }),
      'chart_night_stack': Builder(builder: (c) {
        final p = P.of(c);
        return Surface(
          child: ChartFrame(
            title: 'Heart rate, movement and skin temperature',
            unit: 'over one night',
            height: 140,
            xLabels: const ['23:10', '03:00', '06:40'],
            child: CustomPaint(
              size: Size.infinite,
              painter: NightStack([
                [for (var i = 0; i < 96; i++) 52 + (i * 17 % 19) * 1.0],
                [for (var i = 0; i < 96; i++) (i * 29 % 13) * 1.0],
                // A lane with a gap in it — the honest shape of a night the
                // strap spent partly off the wrist.
                [
                  for (var i = 0; i < 96; i++)
                    i > 40 && i < 52 ? null : 33 + (i % 9) * .1,
                ],
              ], [p.on(C.red), p.on(C.domMove), p.on(C.orange)]),
            ),
          ),
        );
      }),
      'activity_route': Builder(builder: (c) {
        final p = P.of(c);
        return Surface(
          child: ChartFrame(
            title: 'Thursday evening, along the canal',
            unit: '8.4 km',
            height: 160,
            child: CustomPaint(
              size: Size.infinite,
              painter: RouteMap(_route,
                  pace: [for (var i = 0; i < _route.length; i++) (i % 20) / 20],
                  slow: p.on(C.green),
                  fast: p.on(C.orange),
                  pinStart: p.on(C.green),
                  pinEnd: p.on(C.red),
                  pinInk: p.inkOnFill),
            ),
          ),
        );
      }),
      'activity_elevation': Builder(builder: (c) {
        final p = P.of(c);
        return Surface(
          child: ChartFrame(
            title: 'Elevation',
            unit: 'm',
            height: 110,
            yAxis: AxisSpec.of(_metres, floor: 0),
            xLabels: const ['Start', '4.2 km', '8.4 km'],
            series: _metres,
            child: CustomPaint(
              size: Size.infinite,
              painter: Elevation(_metres, p.on(C.teal),
                  markerInk: p.inkOnFill, axis: AxisSpec.of(_metres, floor: 0)),
            ),
          ),
        );
      }),
      'activity_power_curve': Builder(builder: (c) {
        final p = P.of(c);
        return Surface(
          child: ChartFrame(
            title: 'Best power over time',
            unit: 'W',
            height: 110,
            yAxis: AxisSpec.of(_watts, floor: 0),
            xLabels: const ['5 s', '5 min', '60 min'],
            series: _watts,
            child: CustomPaint(
              size: Size.infinite,
              painter: PowerCurve(_watts, 400, p.on(C.domMove),
                  targetLo: .45,
                  targetHi: .68,
                  axis: AxisSpec.of(_watts, floor: 0)),
            ),
          ),
        );
      }),
      'activity_lap_bars': Builder(builder: (c) {
        final p = P.of(c);
        return Surface(
          child: ChartFrame(
            title: 'Laps',
            unit: '50 m, fastest first',
            height: 120,
            child: CustomPaint(
              size: Size.infinite,
              painter: LapBars(const [1, .92, .88, .95, .71, .64],
                  p.on(C.domHealth), p.track,
                  done: 3),
            ),
          ),
        );
      }),
      'activity_breath_ring': Builder(builder: (c) {
        final p = P.of(c);
        return Surface(
          child: ChartFrame(
            title: 'Box breathing',
            unit: 'four counts in',
            height: 140,
            child: CustomPaint(
                size: Size.infinite,
                painter: BreathRing(.55, p.on(C.domMind))),
          ),
        );
      }),
      'activity_movement_map': Builder(builder: (c) {
        final p = P.of(c);
        return Surface(
          child: ChartFrame(
            title: 'Where you covered the court',
            unit: 'singles, 62 minutes',
            height: 160,
            child: CustomPaint(
              size: Size.infinite,
              painter: MovementMap([
                for (var i = 0; i < 140; i++)
                  Offset(.18 + (i * 7 % 60) / 100, .14 + (i * 11 % 70) / 100),
              ], p.on(C.domMove), p.line),
            ),
          ),
        );
      }),
      'activity_interval_ladder': Builder(builder: (c) {
        final p = P.of(c);
        final painter = IntervalLadder(const [
          (work: .9, rest: .4),
          (work: .85, rest: .45),
          (work: .8, rest: .5),
          (work: .72, rest: .6),
          (work: .64, rest: .7),
        ], p.on(C.orange), p.on(C.blue));
        return Surface(
          child: ChartFrame(
            title: 'Work and rest, round by round',
            unit: 'share of the hardest round',
            height: 110,
            legend: painter.legend,
            child: CustomPaint(size: Size.infinite, painter: painter),
          ),
        );
      }),
      'activity_pace_bar': Builder(
        builder: (c) => Surface(
          child: Column(children: [
            PaceBar(.78, P.of(c).on(C.domMove)),
            const SizedBox(height: S.x2),
            PaceBar(.21, P.of(c).on(C.domMove)),
          ]),
        ),
      ),
      ..._liveCases(),
      ..._listCases(),
      ..._onboardingCases(),
      ..._stateCases(),
      ..._shareCases(),
      // No `mosaic`: a gallery that needs the network is a gallery that fails
      // on a plane. This is the card's honest no-basemap face, which is also
      // what a user with no signal gets.
      'poster': PosterCard(_finished, const {'Time', 'Pace', 'Heart rate'}),
      'poster_no_stats': PosterCard(_finished, const {}),
    };

/// The SECOND state of every card.
///
/// Each card above is shown once, holding a number. Every one of them also has
/// a state where the number is missing, negative, over target, or long — and
/// that is the state a screenshot never catches, because a demo device always
/// has data. A card is not in this design system until both of its faces are
/// in here.
Map<String, Widget> _stateCases() => {
      'signal_absent': const SignalCard(
          LucideIcons.wind, C.teal, 'Respiratory rate', '—',
          sub: 'BEAT TIMING WAS TOO NOISY LAST NIGHT'),
      'progress_over': const ProgressCard(
          'Protein', '164 g', 'of 140 g', 1.17, C.orange,
          icon: LucideIcons.beef),
      // Down AND bad, which is the pairing the colour logic gets wrong: a
      // falling number is not automatically a win.
      'trend_down_bad': TrendCard('Heart-rate variability', '48', 'ms', '−13',
          'vs 14-day baseline', _series, C.orange,
          good: false),
      // A gap in the middle of the series — the strap was off the wrist for
      // three days, and the line must BREAK rather than interpolate across it.
      'trend_with_gap': TrendCard(
          'Resting heart rate',
          '58',
          'bpm',
          '+4',
          'vs 14-day baseline',
          [for (var i = 0; i < 24; i++) i > 9 && i < 13 ? null : _series[i]],
          C.red,
          up: true,
          good: false),
      'insight_no_action': const InsightCard(
        'You went to bed at the same time four nights running',
        'That is the longest stretch since May, and your resting heart rate '
            'fell on three of them.',
      ),
      'status_title_only': const StatusCard('Location is off',
          '', fix: 'Allow location'),
      'deep_dive_no_preview': const DeepDiveCard(
          'Sleep debt', '2h 14m', 'owed', 'See the fortnight', C.indigo),
      'goal_trajectory_gaining': const GoalTrajectory(
          'Weight', '71.2 kg', '76 kg', '0.25 kg per week', .34, C.teal,
          rateDown: false),
      'observation_no_advice': const Observation(
        'Your skin temperature has been above baseline for three nights',
        '+0.6° against your own 28-night mean.',
      ),
      'consistency_none': const Consistency(
          0, 7, 'Nights with a full sleep record', C.domHealth),
      'consistency_full': const Consistency(
          7, 7, 'Nights with a full sleep record', C.domHealth),
      // Every accent, so a palette change is one picture rather than a hunt.
      'pill_every_colour': const Wrap(spacing: S.x2, runSpacing: S.x2, children: [
        Pill('Measured', C.green),
        Pill('Estimated', C.yellow, icon: LucideIcons.circleDashed),
        Pill('Relative', C.purple),
        Pill('Private', C.n500, icon: LucideIcons.lock),
        Pill('Beta', C.blue),
        Pill('Needs attention', C.orange),
        Pill('Not scored', C.red),
      ]),
      'big_button_no_icon': const BigButton('Save the night', color: C.domHealth),
      'sub_tabs_five': SubTabs(
          const ['Today', '7 days', '30 days', '6 months', 'Year'], 0, (_) {},
          color: C.domHealth),
      'nav_bar_no_sub': const NavBar('Component gallery'),
      'section_no_action': const Section(
          'Recovery', StatusCard('Nothing yet today', '')),
      'inline_metrics_two': const InlineMetrics([
        ('VOLUME', '1,578 kg', C.purple),
        ('SETS', '4', C.n500),
      ]),
      'metric_row_absent': const MetricRow(
          LucideIcons.wind, C.teal, 'Respiratory rate', '—',
          sub: 'NEED 4 MORE NIGHTS'),
    };

/// The share card in every archetype it can be.
///
/// Eight activity archetypes, and the card's whole point is that the picture
/// changes with the sport while the type and the spacing do not. Shown at the
/// art style, since the minimal style is identical across all eight.
Map<String, Widget> _shareCases() => {
      for (final s in _sessions.entries)
        'share_${s.key}': ShareCard(s.value, 1, const {
          'Time',
          'Distance',
          'Pace',
          'Heart rate',
          'Calories',
          'Volume',
          'Sets',
          'Laps',
        }),
    };

/// One finished session per archetype, so the eight share cards and the eight
/// summaries have something real to draw. Deterministic throughout.
final _sessions = <String, ActivityResult>{
  'journey': _finished,
  'route': ActivityResult(
    activityByName('Running')!,
    start: DateTime(2026, 8, 12, 7, 5),
    duration: Motion.tick * 2712,
    avgHr: 156,
    maxHr: 181,
    calories: 604,
    hr: [for (var i = 0; i < 45; i++) 140 + (i * 23 % 37) * 1.0],
    zoneMinutes: const [2, 8, 19, 13, 3],
    route: _route,
    routePace: [for (var i = 0; i < _route.length; i++) (i % 20) / 20],
    distanceKm: 8.02,
  ),
  'strength': ActivityResult(
    activityByName('Weight training')!,
    start: DateTime(2026, 8, 11, 18, 40),
    duration: Motion.tick * 3320,
    avgHr: 112,
    calories: 388,
    strength: StrengthLog([
      for (var i = 0; i < 4; i++)
        LoggedSet('bench_press', 8 - i,
            loadKg: 70 + i * 5, at: DateTime(2026, 8, 11, 18, 45 + i * 4)),
      for (var i = 0; i < 3; i++)
        LoggedSet('barbell_row', 10,
            loadKg: 60, at: DateTime(2026, 8, 11, 19, 5 + i * 4)),
    ]),
  ),
  'laps': ActivityResult(
    activityByName('Swimming')!,
    start: DateTime(2026, 8, 10, 12, 15),
    duration: Motion.tick * 1980,
    avgHr: 134,
    calories: 421,
    distanceKm: 1.5,
    poolLengthM: 25,
    stroke: 'Freestyle',
    lapSecs: const [52, 54, 55, 53, 58, 61, 59, 57],
  ),
  'interval': ActivityResult(
    activityByName('Jump rope')!,
    start: DateTime(2026, 8, 9, 6, 30),
    duration: Motion.tick * 1140,
    avgHr: 158,
    maxHr: 186,
    calories: 302,
    rounds: const [
      IntervalRound(40, 20, avgHr: 148),
      IntervalRound(40, 20, avgHr: 159),
      IntervalRound(40, 25, avgHr: 166),
      IntervalRound(40, 30, avgHr: 171),
      IntervalRound(40, 35, avgHr: 174),
    ],
  ),
  'flow': ActivityResult(
    activityByName('Yoga') ?? activityByName('Stretching')!,
    start: DateTime(2026, 8, 8, 21, 10),
    duration: Motion.tick * 2400,
    avgHr: 72,
    calories: 118,
    breathsPerMin: 6.2,
    poses: const ['Down dog', 'Warrior II', 'Pigeon', 'Savasana'],
  ),
  'match': ActivityResult(
    activityByName('Tennis')!,
    start: DateTime(2026, 8, 7, 17, 0),
    duration: Motion.tick * 4560,
    avgHr: 141,
    maxHr: 179,
    calories: 712,
    hr: [for (var i = 0; i < 76; i++) 120 + (i * 31 % 51) * 1.0],
    zoneMinutes: const [8, 17, 24, 22, 5],
    gameScore: const [(6, 4), (3, 6), (7, 5)],
  ),
  'basic': ActivityResult(
    activityByName('Treadmill')!,
    start: DateTime(2026, 8, 6, 19, 30),
    duration: Motion.tick * 1800,
    avgHr: 147,
    maxHr: 168,
    calories: 356,
    hr: [for (var i = 0; i < 30; i++) 130 + (i * 17 % 33) * 1.0],
    zoneMinutes: const [1, 6, 14, 8, 1],
  ),
};

/// The live-session vocabulary. These are the pieces every `Live*` screen is
/// assembled from; the screens themselves are `Scaffold`s and belong on a
/// device, not in a scroll.
Map<String, Widget> _liveCases() => {
      'live_heart': const LiveHeart(LiveFeed(
          hr: 148,
          zone: 4,
          zoneMinutes: [6, 14, 22, 16, 4],
          bandConnected: true)),
      // The two absences say different things, and one card used to cover
      // both — it told a user whose band had dropped to adjust the fit of a
      // band that was not on their wrist.
      'live_heart_waiting':
          const LiveHeart(LiveFeed(bandConnected: true)),
      'live_heart_dropped': const LiveHeart(LiveFeed()),
      'live_big_num': Builder(
        builder: (c) => Surface(
          child: Column(children: [
            bigNum(P.of(c), '1:02:14', ''),
            const SizedBox(height: S.x4),
            bigNum(P.of(c), '12.42', 'km'),
          ]),
        ),
      ),
      'live_stat_row': Builder(
        builder: (c) => Surface(
          child: statRow(P.of(c), const [
            ('148', 'AVG HEART RATE'),
            ('812', 'CALORIES'),
            ('14.6', 'STRAIN'),
          ]),
        ),
      ),
      'live_counter_buttons': Builder(
        builder: (c) {
          final p = P.of(c);
          return Surface(
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              counterButton(p, LucideIcons.minus, p.on(C.red), 'One less rep',
                  () {}),
              const SizedBox(width: S.x5),
              counterButton(p, LucideIcons.plus, p.on(C.green), 'One more rep',
                  () {}),
            ]),
          );
        },
      ),
    };

/// Rows. Everything that lives in a list — settings, sources, activities,
/// workbench tables. Each is captured with the LONGEST value its slot can
/// hold: `SourceRow` shipped an overflow because every fixture said
/// "Connected", and nothing said "Syncing · 4 minutes ago".
Map<String, Widget> _listCases() => {
      'set_row': Builder(
        builder: (c) => settingsGroup(c, 'Settings row', [
          SetRow(LucideIcons.bell, C.purple, 'Manage notifications',
              sub: 'Bedtime, recovery, and the ones the band raises itself',
              onTap: () {}),
          SetRow(LucideIcons.ruler, C.blue, 'Units',
              value: 'Metric', onTap: () {}),
          const SetRow(LucideIcons.clock, C.n500, 'Last backup',
              value: '2026-08-16 04:12', chevron: false),
          SetRow(LucideIcons.trash2, C.red, 'Delete everything on this device',
              danger: true, onTap: () {}),
        ]),
      ),
      'source_row': Column(children: [
        SourceRow(
          HealthSource(
            name: 'Abdul’s WHOOP band',
            kind: 'WHOOP 4 · wrist optical',
            tier: SourceTier.wristOptical,
            icon: LucideIcons.watch,
            connected: true,
            syncing: true,
            batteryPct: 18,
            lastData: DateTime(2026, 8, 16, 4, 12),
            isBand: true,
          ),
          onTap: () {},
        ),
        const SizedBox(height: S.x3),
        const SourceRow(HealthSource(
          name: 'iPhone',
          kind: 'Motion coprocessor',
          tier: SourceTier.phone,
          icon: LucideIcons.smartphone,
        )),
      ]),
      'tier_row': const Column(children: [
        TierRow(SourceTier.wristOptical, filled: true),
        SizedBox(height: S.x3),
        TierRow(SourceTier.beatToBeat),
      ]),
      'activity_row': Surface(
        pad: const EdgeInsets.symmetric(horizontal: S.x4),
        child: Column(children: [
          const ActivityRow(
              Activity('Trail running', LucideIcons.mountain, C.green,
                  Track.distance, 10.5,
                  gps: true),
              weightKg: 78.4),
          // No weight on file: the row falls back to the MET value rather
          // than inventing a body to burn calories from.
          const ActivityRow(Activity('Weight training', LucideIcons.dumbbell,
              C.purple, Track.sets, 6.0)),
        ]),
      ),
      'legend': const Surface(
        child: Legend([
          ('Deep', C.indigo),
          ('REM', C.purple),
          ('Light', C.blue),
          ('Awake', C.orange),
        ]),
      ),
      'mono_table': const MonoTable('What went into this number', [
        ('rmssd_ms', '61.4'),
        ('baseline_mean_ms', '67.2'),
        ('nights_in_baseline', '14'),
        ('artifact_share', '2.1%'),
      ]),
      'investigate_row': Builder(builder: (c) => investigateRow(c, () {})),
      'no_data': const Surface(
          child: NoData(message: 'No nights recorded this week')),
    };

/// Onboarding and import — the two flows a user sees exactly once, which is
/// why they are the two nobody re-checks after a change.
Map<String, Widget> _onboardingCases() => {
      // `now` is pinned: an unlock date computed from the wall clock is a
      // component whose picture changes every midnight.
      'unlock_contract': UnlockContract(
        metric: 'Heart-rate variability',
        have: 3,
        need: 7,
        liveHr: 62,
        now: DateTime(2026, 8, 16),
      ),
      'import_report': const ImportReport(ImportOutcome(
          source: 'WHOOP export', days: 412, lateRows: 38, strandedDays: 2)),
      'import_report_failed': const ImportReport(ImportOutcome(
          source: 'physiological_cycles.csv',
          error: 'The first row named columns this importer does not know, so '
              'nothing in the file could be placed.')),
    };

// ══════════════════ THE SCREEN ══════════════════

/// The whole design system on one scroll, at a scale and a theme you choose.
///
/// The two controls are the point. 2.0× and 3.1× are what iOS hands an app
/// whose owner turned on Larger Accessibility Sizes, and the dark palette is
/// solved separately from the light one — both are places a component can be
/// wrong while looking perfect on the machine it was written on.
class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  static const _scales = [1.0, 1.4, 2.0, 3.1];

  int _scale = 0;
  int _theme = 0;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final cases = galleryCases();
    final brightness =
        _theme == 0 ? Theme.of(c).brightness : Brightness.values[_theme - 1];
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: S.x4),
            child: NavBar('Component gallery',
                sub: '${cases.length} COMPONENTS'),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x3),
            child: Column(children: [
              SubTabs(const ['1.0×', '1.4×', '2.0×', '3.1×'], _scale,
                  (i) => setState(() => _scale = i),
                  color: C.domHealth),
              const SizedBox(height: S.x2),
              SubTabs(const ['System', 'Light', 'Dark'], _theme,
                  (i) => setState(() => _theme = i),
                  color: C.domHealth),
            ]),
          ),
          // The controls stay at the app's own scale and theme; only what is
          // under test is overridden, or a 3.1× stepper would push itself off
          // the screen it exists to control.
          Expanded(
            child: Theme(
              data: buildTheme(brightness),
              child: Builder(builder: (c) {
                final gp = P.of(c);
                return MediaQuery(
                  data: MediaQuery.of(c)
                      .copyWith(textScaler: TextScaler.linear(_scales[_scale])),
                  child: ColoredBox(
                    color: gp.bg,
                    child: ListView(
                      padding:
                          const EdgeInsets.fromLTRB(S.x4, S.x4, S.x4, S.x10),
                      children: [
                        for (final e in cases.entries) ...[
                          Text(e.key, style: F.over.copyWith(color: gp.ink3)),
                          const SizedBox(height: S.x2),
                          e.value,
                          const SizedBox(height: S.x6),
                        ],
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ]),
      ),
    );
  }
}
