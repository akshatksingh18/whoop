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
// Screens are deliberately not re-exported from the ui2 barrel (see the
// barrel test), so their components are imported by path.
import '../screens/screens.dart';
import '../ui2.dart';

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

final _metres = List<double>.generate(120, (i) => 210 + (i * 31 % 140) * 1.0);
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
      'activity_muscle_map': Builder(builder: (c) {
        final p = P.of(c);
        return Surface(
          child: ChartFrame(
            title: 'What yesterday’s session loaded',
            unit: 'relative volume',
            height: 180,
            child: CustomPaint(
              size: Size.infinite,
              painter: MuscleMap(const {
                'shoulders': .3,
                'chest': .9,
                'back': .55,
                'core': .2,
                'triceps': .7,
              }, p.on(C.domMove), p.track),
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
