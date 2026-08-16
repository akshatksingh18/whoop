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
  final Map<String, dynamic> insights;
  final List<String> days;

  /// day id -> the `daytime_hrv` block `getDayHeart` serves for it.
  final Map<String, Map<String, dynamic>> daytimeHrv;

  _FakeRepo(
      {this.insights = const {},
      this.days = const [],
      this.daytimeHrv = const {}});

  @override
  Future<Map<String, dynamic>> getDayHeart(String date) async =>
      {'daytime_hrv': ?daytimeHrv[date]};
  @override
  Future<Map<String, dynamic>> getDaySleepV2(String date) async => const {};

  @override
  Future<Map<String, dynamic>> getToday() async => const {};
  @override
  Future<Map<String, dynamic>> getInsights() async => insights;
  @override
  Future<Map<String, dynamic>> getProfile() async => const {};
  @override
  Future<List<String>> availableDays() async => days;
  @override
  Future<Map<String, dynamic>> getChart(String metric, {int? from, int? to}) async =>
      const {'points': []};
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
  group('HealthData.load', () {
    test('consistency counts the last 30 calendar days, not all history', () async {
      final repo = _FakeRepo(
        // 45 derived days, but only 10 of them inside the last month.
        days: [
          for (var i = 0; i < 10; i++) _day(i),
          for (var i = 40; i < 75; i++) _day(i),
        ],
      );
      expect((await HealthData.load(repo)).daysWithData, 10);
    });

    test('a withheld rollup arrives as a reason, not as silence', () async {
      final d = await HealthData.load(_FakeRepo(insights: const {
        'stale': {'kind': 'algo_version'},
      }));
      expect(d.insightsStale?['kind'], 'algo_version');
      expect(d.need.value, isNull);
    });
  });

  // ── the caption and the number have to be the same subtraction ──
  group('Health · Trends', () {
    HealthData sleepFixture({Metric need = Metric.empty}) => HealthData(
          today: const {
            'sleep': {
              'duration_min': {
                'value': 420,
                'confidence': .8,
                'tier': 'ESTIMATE',
              },
            },
          },
          charts: {
            'sleep': [
              for (var i = 29; i >= 1; i--) (t: _noon(i), v: 400.0),
              (t: _noon(0), v: 420.0),
            ],
          },
          need: need,
        );

    Future<void> pump(WidgetTester t, HealthData d) async {
      t.view.physicalSize = const Size(390 * 3, 2400 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(body: HealthScreen(data: d, tab: 1)),
      ));
      await t.pumpAndSettle();
    }

    testWidgets('with no sleep need, the delta is vs the stored average',
        (t) async {
      await pump(t, sleepFixture());
      expect(find.text('20m'), findsOneWidget); // 420 − 400
      expect(find.text('vs your 28-day average'), findsOneWidget);
    });

    testWidgets('captioned "vs your need", the delta IS vs the need',
        (t) async {
      // The bug: the caption changed and the subtraction did not, so the user
      // read 20m — the distance from their own average — under the words "vs
      // your 7h 42m need". The real shortfall is 42m.
      await pump(
          t,
          sleepFixture(
              need: const Metric(
                  value: 462, unit: 'min', confidence: .7, tier: MetricTier.estimate)));
      expect(find.text('42m'), findsOneWidget);
      expect(find.text('20m'), findsNothing);
      expect(find.text('vs your 7h 42m need'), findsOneWidget);
    });

    testWidgets('the window says how many days it actually holds', (t) async {
      // "vs your 28-day average" printed from the SECOND stored value.
      await pump(
          t,
          HealthData(charts: {
            'sleep': [(t: _noon(1), v: 400.0), (t: _noon(0), v: 420.0)],
          }));
      expect(find.text('vs your 1-day average'), findsOneWidget);
    });
  });

  // ── the headline number must not claim a day it did not come from ──
  group('held-over overnight', () {
    Widget frame(HomeData d) => MaterialApp(
        theme: buildTheme(Brightness.light), home: Scaffold(body: HomeScreen(data: d, hour: 20)));

    final readiness = const Metric(value: 82, confidence: .8, tier: MetricTier.high);

    testWidgets('a settled overnight still says Today', (t) async {
      await t.pumpWidget(frame(HomeData(readiness: readiness, dayId: '2026-05-20')));
      expect(find.text("Today's readiness"), findsOneWidget);
    });

    testWidgets('a held-over night names its own date instead', (t) async {
      // getToday holds the last scored night over until today's settles, so
      // this is an ordinary morning before the first sync — not a rare case.
      await t.pumpWidget(frame(HomeData(
          readiness: readiness, dayId: '2026-05-20', heldOverNight: '2026-05-16')));
      expect(find.text("Today's readiness"), findsNothing,
          reason: 'the number is four days old; calling it today is the bug');
      expect(find.textContaining('16 May'), findsOneWidget);
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

  // ── CV-10: three states, and "not screened" is not "clear" ──
  group('irregular-rhythm strip', () {
    testWidgets('counts the days it ran and refuses to reassure', (t) async {
      t.view.physicalSize = const Size(390 * 3, 3000 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Investigate('hrv',
            data: InvestigateData(day: _day(0), rhythmPoints: [
              for (var i = 9; i >= 0; i--) (t: _noon(i), v: i == 3 ? 1.0 : 0.0),
            ])),
      ));
      await t.pumpAndSettle();
      expect(find.text('Irregular-rhythm screen'), findsOneWidget);
      expect(find.textContaining('Ran on 10 days, raised its flag on 1'),
          findsOneWidget);
      // The permanent line. Not a tooltip, and not optional.
      expect(find.textContaining('A clear strip is not a negative result'),
          findsOneWidget);
    });
  });

  // ── CV-09: daytime HRV by hour, weekly median, today excluded ──
  //
  // The gate is the feature (an ungated bin of walking enters as low HRV), so
  // the aggregation on top of it must not undo the honesty: never today alone,
  // never a mean an outlier can drag, and an hour with too few quiet stretches
  // behind it is ABSENT rather than drawn.
  group('daytime HRV by hour', () {
    /// One `daytime_hrv` block: bins at [hour] on the day [back] days ago.
    Map<String, dynamic> block(int back, int hour, List<double> vs) {
      final n = DateTime.now();
      final base = DateTime(n.year, n.month, n.day - back, hour)
              .millisecondsSinceEpoch ~/
          1000;
      return {
        'timeline': [
          for (var i = 0; i < vs.length; i++)
            {'t': base + i * 300, 'rmssd': vs[i], 'n': 9},
        ],
      };
    }

    test('an hour needs three stretches, and takes their middle value',
        () async {
      final d = await CircadianData.load(_FakeRepo(
        days: [for (var i = 1; i <= 3; i++) _day(i)],
        daytimeHrv: {
          // 09:00 gets three bins across three days -> drawn, median 40.
          _day(1): block(1, 9, [10, 40]),
          _day(2): block(2, 9, [90]),
          // 14:00 gets two -> not enough, absent.
          _day(3): block(3, 14, [50, 55]),
        },
      ));
      expect(d.hourly[9], 40, reason: 'the middle of 10, 40, 90 — not the mean');
      expect(d.hourly[14], isNull, reason: 'two stretches is not an hour');
      expect(d.hourlyN[9], 3);
      expect(d.hourlyDays, 3);
    });

    test('today is never in it', () async {
      final d = await CircadianData.load(_FakeRepo(
        days: [_day(0), _day(1)],
        daytimeHrv: {
          _day(0): block(0, 9, [10, 10, 10, 10]),
          _day(1): block(1, 20, [30, 30, 30]),
        },
      ));
      expect(d.hourly[9], isNull,
          reason: "today's own bins are a handful of windows, not a median");
      expect(d.hourly[20], 30);
      expect(d.hourlyDays, 1);
    });

    testWidgets('the card refuses to read as a stress meter', (t) async {
      t.view.physicalSize = const Size(390 * 3, 2600 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.light),
        home: CircadianDetail(
            data: CircadianData(
          hourly: [for (var h = 0; h < 24; h++) h.isEven ? 40.0 + h : null],
          hourlyN: List<int>.filled(24, 5),
          hourlyDays: 7,
          jetlag: const Metric(value: 1.5, confidence: .6, tier: MetricTier.estimate),
          midFreeH: 4.5,
          midWorkH: 3.0,
          nFree: 3,
          nWork: 9,
        )),
      ));
      await t.pumpAndSettle();
      expect(find.textContaining('This is not a stress score'), findsOneWidget);
      // How deep each drawn hour is, not just a grand total.
      expect(find.textContaining('middle value of 5–5 five-minute stretches'),
          findsOneWidget);
      expect(find.textContaining('12 of 24 hours'), findsOneWidget);
      // The InsightCard this section was paid for with is gone, and its one
      // extra fact — the DIRECTION, which is the sign of free minus work — is
      // on the row it belongs to.
      expect(find.textContaining('free-day clock runs'), findsNothing);
      expect(find.text('1h 30m later'), findsOneWidget);
      expect(find.text('3 / 9'), findsOneWidget);
    });
  });
}
