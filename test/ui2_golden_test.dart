// Goldens for the grammar.
//
// The repo had ZERO goldens across forty screens, which is the mechanical
// reason every visual fix regressed something else: nothing recorded what the
// components were supposed to look like, so "it looks right on my screen" was
// the whole acceptance test.
//
// Each component is captured in four states — light and dark, at 1.0× and
// 2.0× text scale. The 2.0× pass is not decoration: accessibility text sizes
// are where cards overflow, and a golden is the only cheap way to notice.
//
// Regenerate deliberately, never reflexively:
//     flutter test --update-goldens test/ui2_golden_test.dart
// and look at the diff. A golden updated without looking is a golden that
// records the bug.
//
// These were baked on Flutter 3.44.9 (the `flutter` on PATH). An older SDK
// anti-aliases hairlines differently and fails a handful of them on nothing
// but sub-pixel blend — that is an SDK mismatch, not a regression. The iOS
// build uses ~/flutter-sdks/flutter (3.41.6) for an unrelated reason; do not
// run goldens with it.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:openstrap_edge/data/journal_fields.dart';
import 'package:openstrap_edge/data/med_store.dart';
import 'package:openstrap_edge/data/nutrition_store.dart';
import 'package:openstrap_edge/models/metric.dart';
// Screens are deliberately NOT re-exported from the ui2 barrel (see the
// barrel test), so their components are imported by path.
import 'package:openstrap_edge/ui2/screens/screens.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

/// A deterministic series — goldens cannot depend on random data, and neither
/// can the app.
final _series = List<double>.generate(
    24, (i) => 52 + (i * 37 % 23) - (i % 5) * 2.0);

/// Every component, each with a name for its golden file.
Map<String, Widget> _cases() => {
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
            sub: 'RELATIVE TO BASELINE', unit: '°', conf: Conf.estimated),
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
        'Worth mentioning if it continues past a week.',
      ),
      'consistency': const Consistency(
          18, 24, 'Nights with a full sleep record', C.domHealth),
      'conf_dots': const Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ConfDots(Conf.high),
            ConfDots(Conf.estimated),
            ConfDots(Conf.none)
          ]),
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
  const night = <SleepStage>[
    ...[SleepStage.awake, SleepStage.light, SleepStage.light, SleepStage.deep],
    ...[SleepStage.deep, SleepStage.light, SleepStage.rem, SleepStage.light],
    ...[SleepStage.deep, SleepStage.light, SleepStage.rem, SleepStage.awake],
    ...[SleepStage.light, SleepStage.rem, SleepStage.light, SleepStage.awake],
  ];
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
          conf: Conf.high,
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
          conf: Conf.high,
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
          conf: Conf.estimated,
          footnote: 'Deep sleep is inferred from heart-rate flatness.',
          child: CustomPaint(size: Size.infinite, painter: Hypnogram(night, p)),
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

/// The golden is the component, not the page: capturing this boundary means a
/// PNG the size of the thing under test, and a diff that points at the card
/// that changed rather than at a screenshot of everything.
final _shot = GlobalKey();

Widget _frame(Widget child, Brightness b, double scale) => MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(b),
        home: Builder(
          builder: (c) => Scaffold(
            backgroundColor: P.of(c).bg,
            // Top-aligned, not centred: a component that grows past the
            // viewport at 2x text should be tall in the golden, not clipped
            // in the middle.
            // A scroll view, because that is what every real screen is: it
            // hands the component an unbounded height, so a card shrink-wraps
            // its content here exactly as it does in the app.
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(S.x4),
                child: RepaintBoundary(key: _shot, child: child),
              ),
            ),
          ),
        ),
      ),
    );

/// Load the bundled type so the goldens show words instead of the test
/// harness's block glyphs. A golden nobody can read is a golden nobody
/// reviews, and an unreviewed golden gets `--update-goldens`-ed over the top
/// of the bug it was supposed to catch.
Future<void> _loadType() async {
  final files = Directory('assets/fonts/Manrope')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.ttf'));
  // Registered under both names. `.SF Pro Text` does not exist off Apple
  // hardware, so on Android and in the test harness the type IS Manrope —
  // registering it under the primary name makes the goldens show what a
  // non-Apple user actually sees, rather than the harness's fallback blocks.
  for (final family in const ['Manrope', '.SF Pro Text']) {
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
            // Phone width, generous height — the width is what components are
            // designed against; the height only has to be enough that 2x text
            // is not artificially clipped.
            tester.view.physicalSize = const Size(390 * 3, 1800 * 3);
            tester.view.devicePixelRatio = 3;
            addTearDown(tester.view.reset);

            await tester.pumpWidget(_frame(widget, brightness, scale));
            await tester.pumpAndSettle();

            await expectLater(
              find.byKey(_shot),
              matchesGoldenFile('goldens/${name}_${theme}_$tag.png'),
            );
          });
        });
      });
    }
  }

  testWidgets('the shell has five destinations and cannot grow a sixth',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: AppShell(
        builder: (c, d) => Center(child: Text(d.label)),
      ),
    ));
    expect(ShellDomain.values, hasLength(5));
    for (final d in ShellDomain.values) {
      expect(find.text(d.label), findsWidgets, reason: '${d.label} tab missing');
    }
  });

  testWidgets('every tap target in the shell clears 44 pt', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: AppShell(builder: (c, d) => const SizedBox.shrink()),
    ));
    for (final e in tester.widgetList<Pressable>(find.byType(Pressable))) {
      if (e.onTap == null) continue;
      final size = tester.getSize(find.byWidget(e));
      expect(size.height, greaterThanOrEqualTo(S.tap),
          reason: '${e.semanticLabel} is ${size.height} pt tall');
      expect(size.width, greaterThanOrEqualTo(S.tap),
          reason: '${e.semanticLabel} is ${size.width} pt wide');
    }
  });

  // ── the tiers the PNGs do not cover ────────────────────────────────────
  //
  // iOS reaches 3.1x with Larger Accessibility Sizes and Android about 2.6x
  // effective, so 2.0x is not the ceiling — but 174 more images per tier is
  // 174 more images nobody reviews, and an unreviewed golden records the bug.
  // These two sweeps run the SAME case list past the top of the range and
  // assert the two things a picture would only show if somebody looked.
  //
  // Both also cover 1.0x, because F-06 was a component clipped at 1.0x that
  // four goldens photographed and nobody noticed.
  group('past the golden ceiling', () {
    for (final scale in const [1.0, 1.4, 2.0, 3.0, 3.1]) {
      testWidgets('nothing overflows at ${scale}x', (tester) async {
        tester.view.physicalSize = const Size(390 * 3, 4000 * 3);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        final broke = <String>[];
        for (final e in cases.entries) {
          final errors = <String>[];
          final previous = FlutterError.onError;
          FlutterError.onError = (d) => errors.add(d.exceptionAsString());
          await tester.pumpWidget(_frame(e.value, Brightness.light, scale));
          await tester.pump();
          FlutterError.onError = previous;
          for (final err in errors) {
            if (err.contains('overflowed')) broke.add('${e.key}: $err');
          }
        }
        expect(broke, isEmpty,
            reason: 'a card that overflows at an accessibility text size is a '
                'measurement pushed off the screen:\n${broke.join('\n')}');
      });
    }

    testWidgets('every tap target in every case clears 44 pt', (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 4000 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final small = <String>[];
      for (final e in cases.entries) {
        await tester.pumpWidget(_frame(e.value, Brightness.light, 1.0));
        await tester.pump();
        for (final w in tester.widgetList<Pressable>(find.byType(Pressable))) {
          if (w.onTap == null) continue;
          final s = tester.getSize(find.byWidget(w));
          if (s.height < S.tap || s.width < S.tap) {
            small.add('${e.key} · ${w.semanticLabel ?? 'unlabelled'} '
                'is ${s.width} × ${s.height}');
          }
        }
      }
      expect(small, isEmpty,
          reason: 'the 44 pt guarantee only held for the five shell tabs, '
              'which is how seven sub-44 controls shipped:\n${small.join('\n')}');
    });
  });
}
