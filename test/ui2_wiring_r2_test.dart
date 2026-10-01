// R2 wiring regressions — the numbers the screens were reading wrong.
//
// Each group below pins one bug that shipped, so the fix cannot quietly come
// undone:
//
//  · the cross-day rollup was served VERBATIM, with no version and no date, so
//    every readiness driver, the sleep coach and the body clock could be weeks
//    old under an older algorithm with nothing on screen to say so;
//  · chart points lost their timestamps, so "Today" and "N days ago" were
//    counted off the ARRAY INDEX and a sync gap read as continuous;
//  · the sleep trend captioned itself "vs your need" while subtracting the
//    28-day average;
//  · "days with a derived record in the last month" counted every derived day
//    since install, so anyone past their first month read "30 of 30".

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/derivation_engine.dart';
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/data/local_repository.dart';
import 'package:openstrap_edge/data/local_repository_impl.dart';
import 'package:openstrap_edge/models/metric.dart';
import 'package:openstrap_edge/ui2/screens/screens.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

/// Local noon of `today - back`, the stamp `getChart` puts on a stored point.
int _noon(int back) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day - back, 12).millisecondsSinceEpoch ~/
      1000;
}

String _day(int back) {
  final n = DateTime.now();
  return dayLabelOf(DateTime(n.year, n.month, n.day - back));
}

class _FakeRepo extends LocalRepository {
  final Map<String, dynamic> today;

  _FakeRepo({this.today = const {}});

  @override
  Future<Map<String, dynamic>> getDayHeart(String date) async => const {};
  @override
  Future<Map<String, dynamic>> getDaySleepV2(String date) async => const {};
  @override
  Future<Map<String, dynamic>> getToday() async => today;
  @override
  Future<Map<String, dynamic>> getInsights() async => const {};
  @override
  Future<Map<String, dynamic>> getProfile() async => const {};
  @override
  Future<List<String>> availableDays() async => const [];
  @override
  Future<Map<String, dynamic>> getChart(String metric, {int? from, int? to}) async =>
      const {'points': []};
  @override
  Future<Map<String, dynamic>> getDayWear(String date) async => const {};
  @override
  Future<Map<String, dynamic>> getDayNaps(String date) async => const {};
}

void main() {
  // ── the artifact behind four screens ──
  group('crossDayStaleReason', () {
    Map<String, dynamic> artifact({int? version, String? builtFor}) => {
          'algo_version': version ?? kAlgoVersion,
          'built_for_day': ?builtFor,
          'readiness_glassbox': const {'drivers': []},
        };

    test('an artifact stamped with today and this algo version is served', () {
      expect(
        LocalRepositoryImpl.crossDayStaleReason(
            artifact(builtFor: _day(0)), _day(0)),
        isNull,
      );
    });

    test('yesterday is still fine — the families are multi-day by design', () {
      expect(
        LocalRepositoryImpl.crossDayStaleReason(
            artifact(builtFor: _day(1)), _day(0)),
        isNull,
      );
    });

    test('past the age ceiling it is withheld, with the day it was built for',
        () {
      final r = LocalRepositoryImpl.crossDayStaleReason(
          artifact(
              builtFor: _day(LocalRepositoryImpl.crossDayMaxAgeDays + 1)),
          _day(0));
      expect(r?['kind'], 'stale');
      expect(r?['built_for_day'],
          _day(LocalRepositoryImpl.crossDayMaxAgeDays + 1));
    });

    test('an OLDER algo version is withheld however fresh the day', () {
      // The sharp case: a bump that changes the bundle SHAPE would otherwise be
      // served from the pre-bump artifact for the rest of the day, and the new
      // family silently sees nothing on the very pass the bump existed for.
      final r = LocalRepositoryImpl.crossDayStaleReason(
          artifact(version: kAlgoVersion - 1, builtFor: _day(0)), _day(0));
      expect(r?['kind'], 'algo_version');
    });

    test('an UNSTAMPED artifact cannot be shown to be fresh, so it is not', () {
      expect(
          LocalRepositoryImpl.crossDayStaleReason(
              artifact(builtFor: null), _day(0))?['kind'],
          'unstamped');
      expect(
          LocalRepositoryImpl.crossDayStaleReason(
              {'readiness_glassbox': const {}}, _day(0))?['kind'],
          'algo_version');
    });

    test('a day in the FUTURE is a clock that moved, not freshness', () {
      final n = DateTime.now();
      final ahead = dayLabelOf(DateTime(n.year, n.month, n.day + 40));
      expect(
          LocalRepositoryImpl.crossDayStaleReason(
              artifact(builtFor: ahead), _day(0))?['kind'],
          'stale');
    });
  });

  // ── the seam that dropped `t` ──
  group('chart points keep their date', () {
    test('pointsOf carries t through; seriesOf is still values-only', () {
      final chart = {
        'points': [
          {'t': _noon(2), 'v': 51},
          {'t': _noon(0), 'v': 54.5},
        ],
      };
      expect(pointsOf(chart).map((e) => e.v).toList(), [51.0, 54.5]);
      expect(pointsOf(chart).last.t, _noon(0));
      expect(seriesOf(chart), [51.0, 54.5]);
    });

    test('a point with no timestamp is not a dated point', () {
      expect(pointsOf({'points': [{'v': 51}]}), isEmpty);
    });

    test('a gap is a HOLE, not a shorter line', () {
      // The bug in one assertion: three stored points spread over seven days
      // used to be drawn as three evenly spaced samples, and the line ran
      // straight through the four missing days as though they were measured.
      final dense = denseDays([
        (t: _noon(6), v: 50.0),
        (t: _noon(2), v: 54.0),
        (t: _noon(0), v: 52.0),
      ], 7);
      expect(dense, [50.0, null, null, null, 54.0, null, 52.0]);
      expect(dense.length, 7);
    });

    test('a point outside the window is dropped, not clamped into it', () {
      expect(denseDays([(t: _noon(40), v: 50.0)], 7), List.filled(7, null));
    });

    test('the label counts REAL days, not array positions', () {
      // Two stored points a fortnight apart. Labelling off the index called the
      // older one "1 day ago" and the newer one "Today" whatever their dates.
      expect(axisDay(_noon(0)), 'Today');
      expect(axisDay(_noon(0), todayWord: 'Last night'), 'Last night');
      expect(axisDay(_noon(14)), '14 days ago');
      expect(axisDay(_noon(14), unitWord: 'nights'), '14 nights ago');
      expect(axisDay(null), '');
      expect(daysBehind(_noon(3)), 3);
    });

    test('a day is a calendar day, DST boundary or not', () {
      // Spring forward, America/New_York: local midnight on the 8th to local
      // midnight on the 10th is 47 hours, and `inDays` truncated that to ONE.
      // `denseDays` then wrote the 8th and the 9th into the same slot and the
      // older of the two vanished.
      //
      // These assertions are exact in every zone; they only had teeth in a
      // DST one, which is where the bug was reproduced.
      expect(
          calendarDaysBetween(
              DateTime(2026, 3, 8, 23, 59), DateTime(2026, 3, 10, 0, 1)),
          2);
      expect(
          calendarDaysBetween(DateTime(2026, 3, 9), DateTime(2026, 3, 10)), 1);
      // Autumn back, the 25-hour day.
      expect(
          calendarDaysBetween(DateTime(2026, 11, 1), DateTime(2026, 11, 2)), 1);
      // Time of day never counts: one minute before midnight and one minute
      // after are a whole day apart, not zero.
      expect(
          calendarDaysBetween(
              DateTime(2026, 6, 1, 23, 59), DateTime(2026, 6, 2, 0, 1)),
          1);
    });
  });

  // ── the last thirty CALENDAR days ──

  // ── the caption and the number have to be the same subtraction ──

  // ── an older night is not today's number ──
  //
  // This used to say the opposite: getToday holds the last scored night over
  // until today's settles, and Home printed it with one sentence naming the
  // night. On a phone the sentence loses — a figure in the today slot reads as
  // today's, so a morning the strap was never worn showed last week's sleep as
  // this morning's. The numbers stop at the loader now and the reason travels
  // in their place.
  group('held-over overnight', () {
    Map<String, dynamic> bundle(String state, {bool prior = true}) => {
          'status': {
            'today_day': '2026-05-20',
            'overnight_state': state,
            'overnight_day': '2026-05-16',
            'showing_prior_overnight': prior,
          },
          'daily': {
            'readiness': {'value': 82, 'confidence': .8, 'tier': 'HIGH'},
            'resting_hr': {'value': 51, 'confidence': .8, 'tier': 'HIGH'},
          },
          'sleep': {
            'duration_min': {'value': 430, 'confidence': .8, 'tier': 'HIGH'},
          },
        };

    test('the three overnight figures are refused', () async {
      final d = await HomeData.load(_FakeRepo(today: bundle('missing')));
      expect(d.readiness.value, isNull);
      expect(d.sleepMin.value, isNull);
      expect(d.rhr.value, isNull);
      // The night is still resolvable — it is just no longer a reading.
      expect(d.heldOverNight, '2026-05-16');
    });

    // A night still computing and a night that never happened are different
    // absences: one resolves itself, the other wants a sync.
    test('the absence says which of the two it is', () async {
      final building = await HomeData.load(_FakeRepo(today: bundle('building')));
      expect(building.readiness.note, contains('still being worked out'));

      final missing = await HomeData.load(_FakeRepo(today: bundle('missing')));
      expect(missing.readiness.note, contains('reached the app'));
    });

    test("today's own night is served as itself", () async {
      final d = await HomeData.load(
          _FakeRepo(today: bundle('ready', prior: false)));
      expect(d.readiness.value, 82);
      expect(d.rhr.value, 51);
      expect(d.heldOverNight, isNull);
    });

    Widget frame(HomeData d) => MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(body: HomeScreen(data: d, hour: 20)));

    testWidgets('a day with nothing of its own says where the data stops',
        (t) async {
      await t.pumpWidget(frame(
          const HomeData(dayId: '2026-05-20', heldOverNight: '2026-05-16')));
      expect(find.text('Nothing recorded for today'), findsOneWidget);
      expect(find.textContaining('16 May'), findsOneWidget);
    });

    // The same empty screen, on an install that has never scored anything, is
    // a first run and gets the first-run words.
    testWidgets('a genuine first run keeps its own card', (t) async {
      await t.pumpWidget(frame(const HomeData(dayId: '2026-05-20')));
      expect(find.text('Nothing derived yet'), findsOneWidget);
    });

    // A bare day during a live workout is missing COMPUTE, not data: the
    // session holds derivation (DeriveScheduler.setWorkoutActive), so "sync
    // the band" is a false answer — the sync completes and changes nothing.
    // The card must name the workout instead.
    testWidgets('a bare day during a live workout blames the workout, not sync',
        (t) async {
      await t.pumpWidget(MaterialApp(
          theme: buildTheme(Brightness.light),
          home: const Scaffold(
              body: HomeScreen(
                  data: HomeData(
                      dayId: '2026-05-20', heldOverNight: '2026-05-16'),
                  hour: 20,
                  workoutLive: true))));
      expect(find.text('A workout is still running'), findsOneWidget);
      expect(find.text('Nothing recorded for today'), findsNothing);
      expect(find.text('Sync the band'), findsNothing);
    });
  });

  // ── the one observation Home is allowed to make ──
  //
  // The watch earns Home because of WHEN it is useful, not how alarming it is:
  // amber has no notification, so before this the earliest signal the app
  // produces could only be found by opening Health and scrolling to it.
  group('illness watch on Home', () {
    Widget frame(HomeData d) => MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(body: HomeScreen(data: d, hour: 9)));

    const base = HomeData(dayId: '2026-05-20');

    testWidgets('amber shows — this is the whole point of the change',
        (t) async {
      await t.pumpWidget(frame(base.copyOrIllness('amber', '2026-05-20', 2.4)));
      expect(find.textContaining('outside your normal range'), findsOneWidget);
    });

    testWidgets('red shows, and says it is a run rather than one night',
        (t) async {
      await t.pumpWidget(frame(base.copyOrIllness('red', '2026-05-20', 3.1)));
      expect(find.textContaining('Several nights in a row'), findsOneWidget);
    });

    testWidgets('green is SILENT, not a card saying you are fine', (t) async {
      await t.pumpWidget(frame(base.copyOrIllness('green', '2026-05-20', 0.2)));
      expect(find.textContaining('normal range'), findsNothing);
      expect(find.textContaining('Several nights'), findsNothing);
    });

    testWidgets('no state at all is silent too — the CUSUM wants 7 nights',
        (t) async {
      await t.pumpWidget(frame(base));
      expect(find.textContaining('normal range'), findsNothing);
    });

    testWidgets('a negative z says BELOW while the run is still up', (t) async {
      // The stored z is the latest night's own deviation and can be negative
      // while the accumulator is still raised — it only clears after two
      // nights back under. Printing "1.3 deviations" without a direction read
      // as "above your baseline, 1.3 below it".
      await t.pumpWidget(frame(base.copyOrIllness('red', '2026-05-20', -1.3)));
      expect(find.textContaining('1.3 standardised deviations below it'),
          findsOneWidget);
    });

    testWidgets('an older night is named rather than called last night',
        (t) async {
      await t.pumpWidget(frame(base.copyOrIllness('amber', '2026-05-16', 2.2)));
      expect(find.textContaining('16 May'), findsOneWidget);
      expect(find.textContaining('Last night'), findsNothing);
    });
  });

  // ── a rebuild the user never hears about is data quietly vanishing ──
  group('dbRebuiltCard', () {
    test('says nothing when nothing was rebuilt', () {
      expect(dbRebuiltCard(null), isNull);
    });

    test('names the EMPTY tables, not just the recovered count', () {
      final card = dbRebuiltCard((
        cause: 'database disk image is malformed',
        quarantinePath: '/data/openstrap.corrupt.1755300000.db',
        salvaged: const {'day_result': 412, 'food_entry': 0, 'med_dose': 0},
      ))!;
      // The reassuring half.
      expect(card.why, contains('day_result 412'));
      // The half that actually tells someone their food log is gone. A summed
      // "412 rows recovered" would have read as good news.
      expect(card.why, contains('Empty:'));
      expect(card.why, contains('food_entry'));
      expect(card.why, contains('med_dose'));
      // And the original is still on disk — never imply a delete.
      expect(card.why, contains('/data/openstrap.corrupt.1755300000.db'));
      expect(card.why, contains('nothing was '));
    });

    test('does not pretend when nothing came back', () {
      final card = dbRebuiltCard((
        cause: 'file is not a database',
        quarantinePath: '/data/x.db',
        salvaged: const {'day_result': 0},
      ))!;
      expect(card.why, contains('Nothing could be read back'));
    });
  });

  // ── the absence diagnostic reaches the user, not just Firebase ──
  //
  // `readiness_absent_diag` is produced on every day readiness comes back
  // absent — which input was missing, how many of your own nights are behind
  // each — and its only destination was a telemetry breadcrumb.
  group('why is this blank', () {
    Future<void> pump(WidgetTester t, Widget w) async {
      t.view.physicalSize = const Size(390 * 3, 2400 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
          theme: buildTheme(Brightness.light), home: Scaffold(body: w)));
      await t.pumpAndSettle();
    }

    testWidgets('the empty hero on Home is a door, not a dead end', (t) async {
      await pump(
          t,
          HomeScreen(
              hour: 10,
              data: const HomeData(
                  dayId: '2026-05-20',
                  steps: Metric(
                      value: 4200,
                      unit: 'steps',
                      confidence: .9,
                      tier: MetricTier.high))));
      expect(find.text('Readiness is not scored today'), findsOneWidget);
      expect(find.text('See what was missing'), findsOneWidget);
    });

    testWidgets('the detail names each input and QUOTES the pipeline',
        (t) async {
      await pump(
          t,
          const ReadinessDetail(
              data: ReadinessData(absentDiag: {
            'hrv': {'value': true, 'baseline_n': 6, 'baseline_sd': 0.11},
            'rhr': {'value': false, 'baseline_n': 6, 'baseline_sd': 1.2},
            'note': 'need_baseline:have=6,need=14',
          })));
      expect(find.text('What went into it'), findsNothing);
      expect(find.text('What was missing'), findsOneWidget);
      // Presence and history are separate facts, and both are the pipeline's.
      expect(find.textContaining('Measured · 6 nights'), findsOneWidget);
      expect(find.textContaining('Not measured · 6 nights'), findsOneWidget);
      // The note is turned into English by the machinery that already parses
      // it — and never into a date. 14 − 6 = 8.
      expect(find.textContaining('Need 8 more nights'), findsOneWidget);
    });

    testWidgets('a scored day carries no diagnostic at all', (t) async {
      await pump(
          t,
          const ReadinessDetail(
              data: ReadinessData(
                  readiness: Metric(
                      value: 74, confidence: .8, tier: MetricTier.high))));
      expect(find.text('What was missing'), findsNothing);
    });
  });

  // ── L4: the coverage denominator under a long trend ──
  group('wear strip', () {
    Future<void> pump(WidgetTester t, MetricData d) async {
      t.view.physicalSize = const Size(390 * 3, 2400 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
          theme: buildTheme(Brightness.light),
          home: Scaffold(body: MetricDetail('resting_hr', data: d))));
      await t.pumpAndSettle();
    }

    testWidgets('says how much of the window was actually worn', (t) async {
      // Twelve worn days inside a thirty-day window. The line above is drawn
      // from the same twelve and used to be the only thing on the card.
      await pump(
          t,
          MetricData(
            daysAvailable: 40,
            series: [for (var i = 11; i >= 0; i--) (t: _noon(i), v: 54.0)],
            wear: [for (var i = 11; i >= 0; i--) (t: _noon(i), v: 480.0)],
          ));
      // The screen opens on Today; the denominator is a long-range thing.
      await t.tap(find.text('30 days'));
      await t.pumpAndSettle();
      expect(find.text('Worn'), findsOneWidget);
      expect(find.textContaining('12 of these 30 days have a wear record'),
          findsOneWidget);
    });

    testWidgets('a seven-day window does not get one', (t) async {
      // A week you either wore or did not; the denominator changes nothing.
      await pump(
          t,
          MetricData(
            daysAvailable: 40,
            series: [for (var i = 11; i >= 0; i--) (t: _noon(i), v: 54.0)],
            wear: [for (var i = 11; i >= 0; i--) (t: _noon(i), v: 480.0)],
          ));
      await t.tap(find.text('7 days'));
      await t.pumpAndSettle();
      expect(find.text('Worn'), findsNothing);
    });
  });

  // ── a tile opens today, not the widest range the install can fill ──
  group('MetricDetail default range', () {
    Future<void> pump(WidgetTester t, String key, MetricData d) async {
      t.view.physicalSize = const Size(390 * 3, 2400 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
          theme: buildTheme(Brightness.light),
          home: Scaffold(body: MetricDetail(key, data: d))));
      await t.pumpAndSettle();
    }

    // The old default was index 2, clamped to whatever the install could fill
    // — so it landed on 30 days, or on 7 for a young install, and moved as the
    // install aged. It was never today.
    testWidgets('opens on today however much history there is', (t) async {
      await pump(
          t,
          'resting_hr',
          MetricData(
            daysAvailable: 400,
            series: [for (var i = 200; i >= 0; i--) (t: _noon(i), v: 54.0)],
          ));
      expect(find.text('Today'), findsWidgets);
      // Today's headline is today's reading, not a window average.
      expect(find.textContaining('Daily average'), findsNothing);
    });

    testWidgets('the range switcher still goes wide', (t) async {
      await pump(
          t,
          'resting_hr',
          MetricData(
            daysAvailable: 400,
            series: [for (var i = 200; i >= 0; i--) (t: _noon(i), v: 54.0)],
          ));
      await t.tap(find.text('30 days'));
      await t.pumpAndSettle();
      expect(find.textContaining('Daily average'), findsOneWidget);
    });
  });

  // ── the sparkles button is not an advert for a feature you never set up ──

  // ── the breakdown describes today, so it only shows on today ──
  group('steps breakdown', () {
    Future<void> pump(WidgetTester t) async {
      t.view.physicalSize = const Size(390 * 3, 2400 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
          theme: buildTheme(Brightness.light),
          home: Scaffold(
              body: MetricDetail('steps',
                  data: MetricData(
                    daysAvailable: 400,
                    series: [
                      for (var i = 60; i >= 0; i--) (t: _noon(i), v: 8000.0),
                    ],
                  )))));
      await t.pumpAndSettle();
    }

    testWidgets('it is there on today, and it is called Breakdown', (t) async {
      await pump(t);
      expect(find.text('Breakdown'), findsOneWidget);
      // The old name said "today's" while sitting under a month of days.
      expect(find.textContaining("Where today's came from"), findsNothing);
    });

    testWidgets('it is gone on a wider range', (t) async {
      await pump(t);
      await t.tap(find.text('30 days'));
      await t.pumpAndSettle();
      expect(find.text('Breakdown'), findsNothing);
    });
  });

  // ── the screen is called "Nerd stats" everywhere the user can read it ──
  //
  // The file, the class and the gallery keys still say `investigate`; that is
  // deliberate and invisible. What must never come back is the old word on
  // screen, in either of the two places it appeared: the scaffold's overline
  // and the link row every detail screen ends with.

  // ── MIND-11: a shape and a window, and an abstention that must stay ────────
  //
  // The item's own note is that the abstention is what gets quietly removed
  // later if it is not pinned first. So it is pinned first.

  // ── RESP-01: across nights, never on one, and it may not reassure ─────────
}

