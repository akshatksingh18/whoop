// Build 70's pure rules: phone-first steps, why a day has no readiness score,
// the spoken kilometre, maintenance measured from weight, moving and copying
// food between days and groups, and where a best effort ended.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/live_coverage_policy.dart';
import 'package:openstrap_edge/data/nutrition_store.dart';
import 'package:openstrap_edge/gps/route_models.dart';
import 'package:openstrap_edge/gps/run_analysis.dart';
import 'package:openstrap_edge/gps/run_voice.dart';
import 'package:openstrap_edge/ui2/screens/readiness_detail.dart'
    show breathingWhy, readinessGap;

void main() {
  group('phone-first steps', () {
    // 09:00–10:00 local-ish epoch seconds; the exact base does not matter.
    const h9 = 1000000 * 60;
    CoverageSpan phone(int from, int to, int n) =>
        CoverageSpan(startTs: from, endTs: to, steps: n, fromBand: false);
    CoverageSpan band(int from, int to, int n) =>
        CoverageSpan(startTs: from, endTs: to, steps: n, fromBand: true);

    test('a counted phone hour belongs to the phone outright', () {
      // The wrist read 7,000 "steps" of arm work in an hour the phone counted
      // 3,000. Ranked, the band won; phone first, the phone does.
      final rows = [phone(h9, h9 + 3600, 3000), band(h9, h9 + 3600, 7000)];
      expect(resolveDaySteps(rows, phoneFirst: false).total, 7000);
      final r = resolveDaySteps(rows, phoneFirst: true);
      expect(r.total, 3000);
      expect(r.strap, 0);
    });

    test('a run inside a busy hour is not counted twice', () {
      // Phone hour 6,000 (a 5,200-step run and 800 more); the band counted
      // the run at 4,835 over 35 minutes.
      final rows = [
        phone(h9, h9 + 3600, 6000),
        band(h9 + 600, h9 + 600 + 35 * 60, 4835),
      ];
      expect(resolveDaySteps(rows, phoneFirst: true).total, 6000);
    });

    test('the band keeps time the phone did not count', () {
      final rows = [
        phone(h9, h9 + 3600, 3000),
        band(h9 + 7200, h9 + 7200 + 1200, 1500), // no phone window here
      ];
      final r = resolveDaySteps(rows, phoneFirst: true);
      expect(r.total, 4500);
      expect(r.strap, 1500);
    });

    test('a walk the phone missed (left behind) stays the band\'s', () {
      // Phone counted 50 in the hour; the band saw a 30-minute walk of 3,000.
      final rows = [
        phone(h9, h9 + 3600, 50),
        band(h9 + 600, h9 + 600 + 1800, 3000),
      ];
      expect(resolveDaySteps(rows, phoneFirst: true).total, greaterThanOrEqualTo(3000));
    });

    test('a band span crossing a phone hour keeps only its uncovered part', () {
      // Band 10:30–11:30, 6,000 steps; phone counted 10:00–11:00 only.
      final rows = [
        phone(h9 + 3600, h9 + 7200, 4000),
        band(h9 + 5400, h9 + 9000, 6000),
      ];
      final r = resolveDaySteps(rows, phoneFirst: true);
      expect(r.phone, 4000);
      expect(r.strap, 3000); // the half after 11:00
    });
  });

  group('why a day has no readiness score', () {
    test('no data, no sleep, building, missing input, held back', () {
      expect(readinessGap(null, hasDay: false), 'no data that day');
      expect(
          readinessGap({
            'hrv': {'value': false, 'baseline_n': 20},
            'rhr': {'value': false, 'baseline_n': 20},
          }, hasDay: true),
          'no sleep heart data that night');
      expect(
          readinessGap({
            'hrv': {'value': true, 'baseline_n': 9},
            'rhr': {'value': true, 'baseline_n': 12},
          }, hasDay: true),
          'building your baseline: 9 of 14 nights');
      expect(
          readinessGap({
            'hrv': {'value': false, 'baseline_n': 20},
            'rhr': {'value': true, 'baseline_n': 20},
          }, hasDay: true),
          'HRV not measured that night');
      expect(
          readinessGap({
            'hrv': {'value': true, 'baseline_n': 20},
            'rhr': {'value': true, 'baseline_n': 20},
          }, hasDay: true),
          startsWith('held back'));
    });

    test('a withheld breathing rate says why in words', () {
      expect(breathingWhy('artifact fraction 0.31 > gate 0.25'),
          'too much movement or signal noise');
      expect(breathingWhy('sub-window consensus 0.38 < 0.5'),
          contains('disagreed'));
      expect(breathingWhy(''), 'not measured');
    });
  });

  group('spoken kilometre', () {
    test('says the distance and that kilometre\'s pace', () {
      expect(kmCue(3, 401), '3 kilometres. Last kilometre 6 minutes 41.');
      expect(kmCue(1, 360), '1 kilometre. Last kilometre 6 minutes.');
    });

    test('speaks once per kilometre, with the split since the last one', () {
      final v = KmVoice();
      expect(v.update(0.01, 5, speak: false), isNull); // first fix primes
      expect(v.update(0.9, 380, speak: false), isNull);
      expect(v.update(1.0, 401, speak: false), contains('6 minutes 41'));
      expect(v.update(1.4, 560, speak: false), isNull);
      expect(v.update(2.02, 830, speak: false), contains('7 minutes 9'));
    });

    test('a screen reopened mid-run does not announce a stale kilometre', () {
      final v = KmVoice();
      expect(v.update(2.5, 1000, speak: false), isNull);
      expect(v.update(3.0, 1400, speak: false), contains('6 minutes 40'));
    });
  });

  group('maintenance measured from weight', () {
    test('a steady loss on steady eating gives the energy it implies', () {
      // 21 days losing 0.1 kg a day on 2,000 kcal: 2,000 + 0.1 × 7,700.
      final weights = [
        for (var i = 0; i < 21; i++)
          (
            date: '2026-09-${(10 + i).toString().padLeft(2, '0')}',
            kg: 82.0 - 0.1 * i
          ),
      ];
      final m = measuredMaintenance(weights, List.filled(20, 2000.0))!;
      expect(m.kcal, closeTo(2770, 1));
      expect(m.kgPerWeek, closeTo(-0.7, 1e-6));
    });

    test('too few weigh-ins or too short a span gives nothing', () {
      final few = [
        (date: '2026-09-01', kg: 80.0),
        (date: '2026-09-20', kg: 79.0),
      ];
      expect(measuredMaintenance(few, List.filled(20, 2000.0)), isNull);
      final short = [
        for (var i = 0; i < 9; i++) (date: '2026-09-0${i + 1}', kg: 80.0),
      ];
      expect(measuredMaintenance(short, List.filled(12, 2000.0)), isNull);
    });

    test('the trend is a 7-day trailing mean', () {
      final t = weightTrend([
        (date: '2026-09-01', kg: 80.0),
        (date: '2026-09-02', kg: 82.0),
        (date: '2026-09-09', kg: 78.0),
      ]);
      expect(t[1].kg, 81.0);
      expect(t[2].kg, 78.0); // the first two are more than 6 days earlier
    });
  });

  group('food entries move and copy', () {
    const e = FoodEntry(
      id: 'a',
      date: '2026-10-02',
      meal: 'breakfast',
      label: 'Oats',
      atTs: 1790000000, // a clock time on some day
      foodKey: 'my:oats',
      quantity: 50,
      kcal: 200,
      group: 'Oatmeal',
    );

    test('a copy gets a new id, the new day, the same clock time and group', () {
      final c = e.copyTo('2026-10-05', 'lunch', newId: 'b');
      expect(c.id, 'b');
      expect(c.date, '2026-10-05');
      expect(c.meal, 'lunch');
      expect(c.group, 'Oatmeal');
      expect(c.source, FoodSource.repeat);
      final t0 = DateTime.fromMillisecondsSinceEpoch(e.atTs! * 1000);
      final t1 = DateTime.fromMillisecondsSinceEpoch(c.atTs! * 1000);
      expect((t1.hour, t1.minute), (t0.hour, t0.minute));
      expect(t1.day, 5);
    });

    test('moving to a group keeps the entry itself', () {
      final m = e.inGroup('Omelette');
      expect(m.id, 'a');
      expect(m.group, 'Omelette');
      expect(m.source, e.source);
      expect(FoodEntry.fromRow(m.toRow(0)).group, 'Omelette');
    });
  });

  test('a best effort knows where it ended', () {
    // 2 km at 3 m/s, then 1 km at 4 m/s: the fastest 1K is the last one.
    const mPerDegLat = 111195.0;
    final pts = <RoutePoint>[];
    var lat = 29.9;
    var t = 0;
    void leg(int sec, double v) {
      for (var i = 0; i < sec; i++) {
        pts.add(RoutePoint(seq: pts.length, tsMs: t * 1000, lat: lat, lng: -95.6));
        lat += v / mPerDegLat;
        t++;
      }
    }

    leg(667, 3.0);
    leg(250, 4.0);
    final end = bestEffortEnds(pts)['1K']!;
    expect(end, greaterThan(pts.length - 5));
  });
}
