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

  _FakeRepo({this.insights = const {}, this.days = const []});

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

  // ── a card that takes a confidence has to draw it ──
  group('SignalCard', () {
    Widget frame(Widget w) => MaterialApp(
        theme: buildTheme(Brightness.light), home: Scaffold(body: w));

    testWidgets('renders the tier it was handed', (t) async {
      await t.pumpWidget(frame(const SignalCard(
          Icons.favorite, C.red, 'Heart rate', '52',
          unit: 'bpm', conf: Conf.estimated)));
      expect(find.byType(ConfDots), findsOneWidget);
      expect(t.widget<ConfDots>(find.byType(ConfDots)).c, Conf.estimated);
    });

    testWidgets('no conf means NO dots — not three, and not "Not measured"',
        (t) async {
      await t.pumpWidget(frame(
          const SignalCard(Icons.scale, C.teal, 'Weight', '72.4', unit: 'kg')));
      expect(find.byType(ConfDots), findsNothing);
    });
  });
}
