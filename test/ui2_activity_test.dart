// The activity experience: catalogue, archetypes, strength maths, and the
// screens that render them.
//
// Three things this file is actually protecting:
//
//   1. Every activity has a published MET and every archetype has a screen —
//      so the "different visual centre of gravity" claim is checkable, not a
//      design-doc assertion.
//   2. Volume never counts a bodyweight set as zero kilos. That single null
//      is why `load_kg` is nullable in the schema.
//   3. No screen renders a bare em-dash. Absence is a StatusCard, and the
//      widget tests sweep for the dash directly.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/gps/gps_source.dart';
import 'package:openstrap_edge/state/prefs.dart';
import 'package:openstrap_edge/state/units_controller.dart';
import 'package:openstrap_edge/ui2/activity/catalogue.dart';
import 'package:openstrap_edge/ui2/activity/live.dart';
import 'package:openstrap_edge/ui2/activity/picker.dart';
import 'package:openstrap_edge/ui2/activity/setup.dart';
import 'package:openstrap_edge/ui2/activity/share.dart';
import 'package:openstrap_edge/ui2/activity/summary.dart';
import 'package:openstrap_edge/ui2/screens/workout_screen.dart';
import 'package:openstrap_edge/ui2/ui2.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── deterministic fixtures ─────────────────────────────────────────────────

final _start = DateTime(2026, 5, 20, 7, 15);

Activity _first(Arch a) =>
    allActivities.firstWhere((x) => archOf(x) == a);

List<double> _series(int n, double base, double amp) =>
    [for (var i = 0; i < n; i++) base + (i * 37 % 23) - (i % 5) * amp];

final _sets = <LoggedSet>[
  LoggedSet('bench_press', 8,
      loadKg: 80, rpe: 7, at: _start.add(const Duration(minutes: 3))),
  LoggedSet('bench_press', 7,
      loadKg: 82.5, rpe: 8, at: _start.add(const Duration(minutes: 6))),
  LoggedSet('triceps_pushdown', 12,
      loadKg: 30, rpe: 7, at: _start.add(const Duration(minutes: 12))),
  LoggedSet('pull_up', 9, rpe: 8, at: _start.add(const Duration(minutes: 18))),
];

/// A fully-populated result for [arch] — every archetype's own data present,
/// so the goldens show the defining object rather than nine StatusCards.
ActivityResult _result(Arch arch) {
  final a = _first(arch);
  return ActivityResult(
    a,
    start: _start,
    duration: const Duration(minutes: 45, seconds: 28),
    avgHr: 148,
    maxHr: 176,
    calories: 612,
    strain: 12.4,
    hr: _series(120, 150, 3),
    zoneMinutes: const [4, 9, 17, 11, 4],
    route: arch == Arch.route || arch == Arch.journey
        ? [for (var i = 0; i < 60; i++) Offset(.1 + i / 75, .5 + (i % 9) / 30)]
        : const [],
    routePace: arch == Arch.route
        ? [for (var i = 0; i < 60; i++) (i % 10) / 10]
        : null,
    distanceKm: arch == Arch.route || arch == Arch.journey ? 8.72 : null,
    elevationM: arch == Arch.journey ? _series(80, 900, 12) : const [],
    gainM: arch == Arch.journey ? 642 : null,
    lossM: arch == Arch.journey ? 618 : null,
    splits: arch == Arch.route
        ? const [
            KmSplit(1, 308, avgHr: 152),
            KmSplit(1, 307, avgHr: 156),
            KmSplit(1, 312, avgHr: 162),
            KmSplit(1, 298, avgHr: 176),
          ]
        : const [],
    strength: arch == Arch.strength ? StrengthLog(_sets) : StrengthLog.empty,
    lapSecs: arch == Arch.laps ? const [38, 40, 41, 43, 45, 52] : const [],
    poolLengthM: arch == Arch.laps ? 25 : null,
    stroke: arch == Arch.laps ? 'Free' : null,
    rounds: arch == Arch.interval
        ? const [
            IntervalRound(45, 30, avgHr: 154),
            IntervalRound(45, 30, avgHr: 161),
            IntervalRound(45, 30, avgHr: 168),
            IntervalRound(45, 30, avgHr: 172),
          ]
        : const [],
    poses: arch == Arch.flow
        ? const ['Mountain', 'Plank', 'Warrior II']
        : const [],
    breathsPerMin: arch == Arch.flow ? 6.2 : null,
    gameScore: arch == Arch.match ? const [(6, 4), (4, 6)] : const [],
  );
}

Widget _frame(Widget child, Brightness b, double scale) => MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(b),
        home: child,
      ),
    );

Future<void> _loadType() async {
  final files = Directory('assets/fonts/Manrope')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.ttf'));
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
  // ── the catalogue ────────────────────────────────────────────────────────
  group('catalogue', () {
    test('eight groups, ~70 activities, no duplicate names', () {
      expect(activityLibrary.length, 8);
      expect(allActivities.length, greaterThanOrEqualTo(65));
      final names = allActivities.map((a) => a.name).toSet();
      expect(names.length, allActivities.length,
          reason: 'a duplicate name would collide in activityByName');
      for (final g in activityLibrary) {
        expect(g.items, isNotEmpty, reason: '${g.name} is empty');
      }
    });

    test('every activity carries a physiologically plausible MET', () {
      for (final a in allActivities) {
        expect(a.met, greaterThanOrEqualTo(1.0), reason: a.name);
        expect(a.met, lessThanOrEqualTo(25.0), reason: a.name);
      }
    });

    test('Intimacy is a normal entry with a privacy default', () {
      final it = allActivities.firstWhere((a) => a.name == 'Intimacy');
      expect(it.met, 5.8);
      expect(it.private, isTrue);
      // Not special-cased anywhere: it resolves through the same lookup.
      expect(activityByName('intimacy')?.name, 'Intimacy');
    });

    test('quick start entries all exist in the library', () {
      for (final q in quickStart) {
        expect(activityByName(q.typeKey)?.name, q.name);
      }
    });

    test('activityByName tolerates display names and unknown types', () {
      expect(activityByName('Weight training')?.track, Track.sets);
      expect(activityByName('weight_training')?.track, Track.sets);
      expect(activityByName('underwater basket weaving'), isNull);
      expect(activityByName(null), isNull);
    });

    test('kcal is MET × 3.5 × kg / 200 × min, and null without a weight', () {
      final run = activityByName('running')!;
      // 9.8 × 3.5 × 70 / 200 × 30 = 360.15
      expect(run.kcal(70, 30), 360);
      expect(run.kcal(null, 30), isNull);
      expect(run.kcal(0, 30), isNull,
          reason: 'a zero weight is a missing weight, not a weightless user');
    });
  });

  // ── archetypes ───────────────────────────────────────────────────────────
  group('archetypes', () {
    test('every activity maps to an archetype', () {
      for (final a in allActivities) {
        expect(Arch.values, contains(archOf(a)), reason: a.name);
      }
    });

    test('all nine archetypes are reachable from the catalogue', () {
      final seen = allActivities.map(archOf).toSet();
      expect(seen, hasLength(Arch.values.length),
          reason: 'unreachable: '
              '${Arch.values.where((x) => !seen.contains(x)).toList()}');
    });

    test('named exceptions beat the tracking mode', () {
      // Hiking is tracked by distance but is about the climb.
      expect(archOf(activityByName('hiking')!), Arch.journey);
      // Swimming is tracked by distance but is about the lap.
      expect(archOf(activityByName('swimming')!), Arch.laps);
      expect(archOf(activityByName('tennis')!), Arch.match);
      expect(archOf(activityByName('running')!), Arch.route);
      expect(archOf(activityByName('yoga')!), Arch.flow);
      expect(archOf(activityByName('hiit')!), Arch.interval);
      expect(archOf(activityByName('weight_training')!), Arch.strength);
      expect(archOf(activityByName('golf')!), Arch.basic);
    });

    test('every archetype has a live screen', () {
      for (final arch in Arch.values) {
        expect(liveFor(_first(arch)), isA<Widget>());
      }
    });

    test('there is no power archetype, and the machines that claimed it are '
        'heart-rate sessions', () {
      expect([for (final a in Arch.values) a.name], isNot(contains('power')));
      for (final key in const [
        'indoor_bike',
        'treadmill',
        'elliptical',
        'stair_climber',
      ]) {
        expect(archOf(activityByName(key)!), Arch.basic,
            reason: '$key has no power meter and no indoor distance');
      }
    });

    test('hard minutes are Z4 + Z5, and absent without a zone split', () {
      final r = _result(Arch.match);
      expect(r.hardMinutes, closeTo(15, .001)); // 11 + 4
      expect(
          ActivityResult(_first(Arch.match),
                  start: _start, duration: const Duration(minutes: 20))
              .hardMinutes,
          isNull,
          reason: 'nobody counted is not zero hard minutes');
    });
  });

  // ── strength maths ───────────────────────────────────────────────────────
  group('strength', () {
    test('volume excludes unloaded sets and says so', () {
      const log = StrengthLog([]);
      expect(log.volumeKg, isNull);

      final full = StrengthLog(_sets);
      // 80×8 + 82.5×7 + 30×12 = 640 + 577.5 + 360 = 1577.5; the pull-up is out.
      expect(full.volumeKg, closeTo(1577.5, .001));
      expect(full.hasUnloadedSets, isTrue);
      expect(full.setCount, 4);
      expect(full.repCount, 36);
      expect(full.exercises,
          ['bench_press', 'triceps_pushdown', 'pull_up']);
    });

    test('a bodyweight-only session has no volume, not zero volume', () {
      final log = StrengthLog([
        LoggedSet('pull_up', 8, at: _start),
        LoggedSet('plank', 1, at: _start),
      ]);
      expect(log.volumeKg, isNull,
          reason: 'zero would claim a real session did no work');
      expect(log.setCount, 2);
    });

    test('top set is the heaviest, ties broken by reps', () {
      expect(StrengthLog(_sets).topSet?.loadKg, 82.5);
      final tie = StrengthLog([
        LoggedSet('bench_press', 5, loadKg: 100, at: _start),
        LoggedSet('bench_press', 6, loadKg: 100, at: _start),
      ]);
      expect(tie.topSet?.reps, 6);
    });

    test('Epley 1RM, and null without a load', () {
      final s = LoggedSet('bench_press', 6, loadKg: 100, at: _start);
      expect(oneRepMax(s), closeTo(120, .001)); // 100 × (1 + 6/30)
      expect(oneRepMax(LoggedSet('pull_up', 6, at: _start)), isNull);
      expect(oneRepMax(null), isNull);
    });

  });

  // ── the live feed ────────────────────────────────────────────────────────
  group('live feed', () {
    test('the session average comes from the curve, not the last sample', () {
      // The bug this replaces: `avgHr: feed.hr` — whatever the strap happened
      // to be reading when the user pressed stop, labelled "Avg HR".
      const f = LiveFeed(hr: 190, hrCurve: [120, 130, 140]);
      expect(f.avgHr, 130);
      expect(const LiveFeed(hr: 190).avgHr, isNull,
          reason: 'no curve means no average — not the instant');
    });

    test('lap speeds are derived from lap seconds, so they cannot disagree',
        () {
      final r = ActivityResult(_first(Arch.laps),
          start: _start,
          duration: const Duration(minutes: 10),
          lapSecs: const [40, 80]);
      expect(r.lapCount, 2);
      expect(r.lapSpeeds, [1.0, .5]);
    });

    test('an unfinished session survives being killed', () async {
      SharedPreferences.setMockInitialValues(const {});
      await Prefs.ensureLoaded();
      addTearDown(LiveDraft.clear);

      final d = LiveDraft.begin(activityByName('swimming')!, weightKg: 72.4);
      d.put('lap_at', const [30, 65]);
      d.setPaused(true);

      // The process dies. Everything in memory goes with it.
      LiveDraft.debugForget();

      final back = LiveDraft.current;
      expect(back, isNotNull, reason: 'the workout is still running');
      expect(back!.activityKey, 'swimming');
      expect(back.weightKg, 72.4);
      expect(back.data['lap_at'], const [30, 65]);
      expect(back.pausedAt, isNotNull, reason: 'it was paused, and still is');

      LiveDraft.clear();
      LiveDraft.debugForget();
      expect(LiveDraft.current, isNull);
    });
  });

  // ── formatting ───────────────────────────────────────────────────────────
  // ── the daily-load axis ──────────────────────────────────────────────────
  group('daily load is bucketed by date, not by position', () {
    // Noon local on `d`, which is what `getChart` emits.
    Map<String, Object?> pt(DateTime d, double v) => {
          't': DateTime(d.year, d.month, d.day, 12).millisecondsSinceEpoch ~/
              1000,
          'v': v,
        };

    final end = DateTime(2026, 5, 20); // a Wednesday

    test('a day that derived nothing is a hole, not a shift', () {
      // Three days derived: today, two days ago, and six days ago. The old
      // code took the last seven POINTS and labelled them M…S regardless.
      final out = lastSevenDays([
        pt(end.subtract(const Duration(days: 6)), 10),
        pt(end.subtract(const Duration(days: 2)), 40),
        pt(end, 55),
      ], end);
      expect(out, [10, null, null, null, 40, null, 55]);
      expect(out.length, 7, reason: 'seven days, always — labels depend on it');
    });

    test('points outside the window and junk rows are dropped', () {
      final out = lastSevenDays([
        pt(end.subtract(const Duration(days: 7)), 99),
        pt(end.add(const Duration(days: 1)), 99),
        {'t': 'nonsense', 'v': 5},
        'not a row',
        pt(end, 12),
      ], end);
      expect(out, [null, null, null, null, null, null, 12]);
      expect(lastSevenDays(null, end), List<double?>.filled(7, null));
    });
  });

  group('formatting', () {
    test('clock rolls into hours, grouped separates thousands', () {
      expect(clock(59), '00:59');
      expect(clock(605), '10:05');
      expect(clock(3725), '1:02:05');
      expect(grouped(6842), '6,842');
      expect(grouped(999), '999');
      // `pace()` (the metric-only formatter that used to live in summary.dart)
      // is gone — UnitsController.formatPace is the one pace formatter now.
      expect(UnitsController.formatPace(308), '5:08');
    });
  });

  // ── the screens ──────────────────────────────────────────────────────────
  group('screens', () {
    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      await _loadType();
    });

    for (final arch in Arch.values) {
      testWidgets('${arch.name} summary renders and never shows a bare dash',
          (tester) async {
        tester.view.physicalSize = const Size(390 * 3, 2200 * 3);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(_frame(
            ActivitySummary(_result(arch), weightKg: 72.4),
            Brightness.light,
            1.0));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('—'), findsNothing);
      });

      testWidgets('${arch.name} summary survives a session that measured '
          'nothing', (tester) async {
        tester.view.physicalSize = const Size(390 * 3, 2200 * 3);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);

        // No heart rate, no distance, no sets — the absent case, which is what
        // a strap-less first session actually looks like.
        await tester.pumpWidget(_frame(
            ActivitySummary(ActivityResult(_first(arch),
                start: _start, duration: const Duration(minutes: 20))),
            Brightness.dark,
            1.0));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('—'), findsNothing);
        // Flow is the one archetype whose defining object is not a
        // measurement — the breath ring is a pacer and the elapsed time is
        // real — so it has nothing to apologise for. Every other archetype
        // must explain what is missing.
        if (arch != Arch.flow) {
          expect(find.byType(StatusCard), findsWidgets,
              reason: 'absence must be explained, not blank');
        }
      });
    }

    testWidgets('a match shows heart rate, not a court map', (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 2200 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_frame(
          ActivitySummary(_result(Arch.match), weightKg: 72.4),
          Brightness.light,
          1.0));
      await tester.pumpAndSettle();

      expect(find.text('HEART RATE'), findsOneWidget);
      expect(find.text('bpm'), findsWidgets);
      expect(find.textContaining('above 80%'), findsOneWidget);
      expect(find.textContaining('COURT'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('every chart in a summary states its unit', (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 2600 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      for (final (arch, unit) in const [
        (Arch.route, 'km'),
        (Arch.journey, 'm'),
        (Arch.laps, 'seconds per lap'),
        (Arch.interval, 'seconds'),
        // No `strength` row. A lift has no chart in its overview: the muscle
        // map that used to be there was a lookup table painted on a body, not
        // a measurement, and it is the one archetype whose defining object is
        // the log itself.
        (Arch.basic, 'bpm'),
      ]) {
        await tester.pumpWidget(_frame(
            ActivitySummary(_result(arch), weightKg: 72.4),
            Brightness.light,
            1.0));
        await tester.pumpAndSettle();
        expect(find.text(unit), findsWidgets, reason: '${arch.name} chart');
        // Five bands of colour with the minutes in the key.
        expect(find.text('minutes'), findsWidgets, reason: '${arch.name} zones');
        expect(find.textContaining('Z1 · '), findsWidgets);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('MET calories always carry estimated confidence and the band',
        (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 2200 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      for (final w in const [null, 72.4]) {
        await tester.pumpWidget(_frame(
            ActivitySummary(_result(Arch.basic), weightKg: w),
            Brightness.light,
            1.0));
        await tester.pumpAndSettle();
        // No error bar is quoted, because nothing computes one. The "±15%"
        // this screen used to print had no estimator behind it, and the
        // Workout tab says so in as many words two taps away.
        expect(find.textContaining('±'), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('finishing hands the session to the app, with its sets',
        (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 2400 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      ActivityResult? handed;
      await tester.pumpWidget(_frame(
          liveFor(activityByName('weight_training')!,
              weightKg: 72.4,
              host: ActivityHost(onFinish: (draft) async {
                handed = draft;
                return draft;
              })),
          Brightness.light,
          1.0));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Log set'));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Finish session'));
      await tester.pumpAndSettle();

      expect(handed, isNotNull, reason: 'the app has to be told, or the '
          'session exists only on this screen');
      expect(handed!.strength.setCount, 1);
      expect(handed!.strength.sets.first.loadKg, 40);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a swim counts the same laps live and on the summary',
        (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 2400 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      ActivityResult? handed;
      await tester.pumpWidget(_frame(
          liveFor(activityByName('swimming')!,
              weightKg: 72.4,
              host: ActivityHost(onFinish: (draft) async {
                handed = draft;
                return draft;
              })),
          Brightness.light,
          1.0));
      await tester.pumpAndSettle();

      await tester.tap(find.text('LAP'));
      await tester.pump();
      await tester.tap(find.text('LAP'));
      await tester.pump();

      // Live: two taps, two laps, two pool lengths.
      expect(find.text('2 laps · Free'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Finish session'));
      await tester.pumpAndSettle();

      // And the summary agrees. `lapSecs` used to hold the GAPS between taps,
      // so it was one shorter than the swim: 50 m live, 25 m on the summary.
      expect(handed!.lapCount, 2);
      expect(handed!.swimMetres, 50);
      expect(handed!.lapSecs.length, 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a minimised session keeps the sets that were typed into it',
        (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 2400 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      addTearDown(LiveDraft.clear);

      final a = activityByName('weight_training')!;
      // What the setup screen does once the app accepts the session.
      LiveDraft.begin(a, weightKg: 72.4);

      await tester.pumpWidget(
          _frame(liveFor(a, weightKg: 72.4), Brightness.light, 1.0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Log set'));
      await tester.pump();
      expect(find.text('40 kg × 8'), findsWidgets);

      // Minimise: the route is gone and every widget with it. The set was
      // held in `_LiveStrengthState` and died here — silently, while
      // `activeWorkout` stayed open and refused every later workout.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      await tester.pumpWidget(
          _frame(liveFor(a, weightKg: 72.4), Brightness.light, 1.0));
      await tester.pumpAndSettle();
      expect(find.text('40 kg × 8'), findsWidgets,
          reason: 'a typed set is the one thing nothing can recompute');
      expect(find.text('320'), findsOneWidget, reason: 'volume, restored');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a collapsed group builds none of its rows', (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 1400 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
          _frame(const ActivityPicker(weightKg: 72.4), Brightness.light, 1.0));
      await tester.pumpAndSettle();

      // AnimatedCrossFade builds both of its children whatever it is showing,
      // so every group's rows used to exist while every group was shut.
      expect(find.byType(ActivityRow), findsNothing);

      await tester.tap(find.text(activityLibrary.first.name));
      await tester.pumpAndSettle();
      expect(find.byType(ActivityRow).evaluate().length,
          activityLibrary.first.items.length,
          reason: 'the open group, and only the open group');
    });

    testWidgets('a location denial is named on the live screen',
        (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 2200 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      var fixed = 0;
      await tester.pumpWidget(_frame(
          LiveMeasured(activityByName('running')!,
              feed: () => LiveFeed(
                    hr: 132,
                    bandConnected: true,
                    routeIssue: GpsPermissionStatus.deniedForever,
                    onFixRoute: () => fixed++,
                  )),
          Brightness.light,
          1.0));
      await tester.pumpAndSettle();

      // The old screen drew no pill, no map and no sentence.
      expect(find.text('No route: location not allowed'), findsOneWidget);
      await tester.tap(find.text('Open Settings'));
      await tester.pump();
      expect(fixed, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an absent heart rate says which absence it is',
        (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 2200 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      Future<void> pumpWith(bool connected) async {
        await tester.pumpWidget(_frame(
            LiveMeasured(activityByName('running')!,
                feed: () => LiveFeed(bandConnected: connected)),
            Brightness.light,
            1.0));
        await tester.pumpAndSettle();
      }

      await pumpWith(false);
      expect(find.textContaining('not connected'), findsOneWidget);
      await pumpWith(true);
      expect(find.textContaining('finger-width'), findsOneWidget,
          reason: 'a fit instruction only makes sense for a band that is there');
    });

    testWidgets('the strength screen still follows the band it does not tick '
        'for', (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 2400 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      addTearDown(LiveDraft.clear);

      var hr = 96;
      await tester.pumpWidget(_frame(
          LiveStrength(activityByName('weight_training')!,
              feed: () => LiveFeed(hr: hr, bandConnected: true)),
          Brightness.light,
          1.0));
      await tester.pumpAndSettle();
      expect(find.text('96'), findsOneWidget);

      // The body is built once and left alone by the 1 Hz tick — but the heart
      // rate on it is measured, so it must not freeze with the rest.
      hr = 141;
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('141'), findsOneWidget);
    });

    testWidgets('a session that failed to save says so and can retry',
        (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 2200 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      var attempts = 0;
      final r = _result(Arch.route);
      await tester.pumpWidget(_frame(
          ActivitySummary(r, weightKg: 72.4, onRetrySave: () async {
            attempts++;
            if (attempts == 1) throw StateError('disk');
            return r;
          }),
          Brightness.light,
          1.0));
      await tester.pumpAndSettle();

      // The summary used to be identical to a successful one.
      expect(find.text('This session is not saved yet'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('This session is not saved yet'), findsOneWidget,
          reason: 'a retry that threw has not saved anything either');

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('This session is not saved yet'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the picker lists every activity and searches by name',
        (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 1400 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
          _frame(const ActivityPicker(weightKg: 72.4), Brightness.light, 1.0));
      await tester.pumpAndSettle();

      expect(find.text('Search ${allActivities.length} activities'),
          findsOneWidget);
      await tester.enterText(find.byType(TextField), 'kayak');
      await tester.pumpAndSettle();
      expect(find.text('Kayaking'), findsOneWidget);
      expect(find.text('Running'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('setup hides goals nothing can measure', (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 1400 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      // A lift: no GPS, and no weight on file → no distance and no calorie
      // goal, because neither could be honoured.
      await tester.pumpWidget(_frame(
          ActivitySetup(activityByName('weight_training')!),
          Brightness.light,
          1.0));
      await tester.pumpAndSettle();
      expect(find.text('Distance'), findsNothing);
      expect(find.text('Calories'), findsNothing);

      await tester.pumpWidget(_frame(
          ActivitySetup(activityByName('running')!, weightKg: 72.4),
          Brightness.light,
          1.0));
      await tester.pumpAndSettle();
      expect(find.text('Distance'), findsOneWidget);
      expect(find.text('Calories'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the strength logger accumulates volume, sets and reps',
        (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 2400 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_frame(
          liveFor(activityByName('weight_training')!, weightKg: 72.4),
          Brightness.light,
          1.0));
      await tester.pumpAndSettle();

      // Default entry is 40 kg × 8 = 320 kg of volume for one set.
      await tester.tap(find.text('Log set'));
      await tester.pump();

      expect(find.text('320'), findsOneWidget); // volume
      expect(find.text('40 kg × 8'), findsWidgets);
      expect(find.textContaining('RESTING'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('share offers only stats the session actually has',
        (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 1600 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
          _frame(ShareSheet(_result(Arch.strength)), Brightness.light, 1.0));
      await tester.pumpAndSettle();
      expect(find.text('Volume'), findsWidgets);
      // A lift has no art. The muscle map that used to be offered here was a
      // lookup table painted on a body, and this is the card that leaves the
      // phone — so a lift shares as the minimal card and nothing else.
      expect(find.text('Muscle map'), findsNothing);
      expect(find.text('Minimal'), findsOneWidget);
      // A lift has no distance, so it cannot be shared as one.
      expect(find.text('Distance'), findsNothing);

      await tester.pumpWidget(
          _frame(ShareSheet(_result(Arch.route)), Brightness.light, 1.0));
      await tester.pumpAndSettle();
      expect(find.text('Route'), findsOneWidget);
      expect(find.text('Distance'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  // ── goldens ──────────────────────────────────────────────────────────────
  //
  // Regenerate deliberately:
  //   flutter test --update-goldens test/ui2_activity_test.dart
  group('goldens', () {
    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      await _loadType();
    });

    final cases = <String, Widget>{
      'summary_route': ActivitySummary(_result(Arch.route), weightKg: 72.4),
      'summary_strength':
          ActivitySummary(_result(Arch.strength), weightKg: 72.4),
      'summary_journey': ActivitySummary(_result(Arch.journey), weightKg: 72.4),
      // The two whose defining object changed: a match is now its heart-rate
      // trace (there was a court map), and a swim is now its lap times.
      'summary_match': ActivitySummary(_result(Arch.match), weightKg: 72.4),
      'summary_laps': ActivitySummary(_result(Arch.laps), weightKg: 72.4),
      'share_strength': ShareSheet(_result(Arch.strength)),
      'picker': const ActivityPicker(weightKg: 72.4),
      'setup_run': ActivitySetup(activityByName('running')!, weightKg: 72.4),
    };

    for (final scale in const [1.0, 2.0]) {
      final tag = scale == 1.0 ? '1x' : '2x';
      for (final brightness in Brightness.values) {
        final theme = brightness.name;
        cases.forEach((name, widget) {
          testWidgets('$name · $theme · $tag', (tester) async {
            tester.view.physicalSize = const Size(390 * 3, 1200 * 3);
            tester.view.devicePixelRatio = 3;
            addTearDown(tester.view.reset);

            await tester.pumpWidget(_frame(widget, brightness, scale));
            await tester.pumpAndSettle();

            await expectLater(find.byType(MaterialApp),
                matchesGoldenFile('goldens/activity_${name}_${theme}_$tag.png'));
          });
        });
      }
    }
  });
}
