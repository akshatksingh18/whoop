// Running calories (Method 1 by distance, Method 2 by heart rate), the
// Running row of maintenance, and how a run splits into running and walking.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/profile.dart';
import 'package:openstrap_edge/gps/motion_window.dart';
import 'package:openstrap_edge/gps/route_models.dart';
import 'package:openstrap_edge/gps/run_analysis.dart';
import 'package:openstrap_edge/gps/run_history.dart';

void main() {
  const me = Profile(ageYears: 23, weightKg: 80.5, heightCm: 186.69, sex: 'm');

  group('Method 1, distance', () {
    test('0.005 x kg x 0.143 x metres on the flat', () {
      // 5.06 km at 80.5 kg.
      expect(
        runFloorKcal(runMeters: 5060, weightKg: 80.5),
        closeTo(291.24, 0.01),
      );
    });

    test('equals Akshat\'s four steps for any pace', () {
      // 5,000 m in 30 min: speed 166.7 m/min, O2 23.83, kcal/h 575.5.
      const d = 5000.0, t = 30.0, kg = 80.5;
      final speed = d / t;
      final o2 = 0.143 * speed + 0.9 * speed * 0;
      final perHour = o2 * kg * 0.3;
      final steps = perHour / 60 * t;
      expect(runFloorKcal(runMeters: d, weightKg: kg), closeTo(steps, 1e-9));
    });

    test('walk breaks cost 0.1 per metre and climbing 0.9', () {
      final flat = runFloorKcal(runMeters: 4600, weightKg: 80.5)!;
      expect(
        runFloorKcal(runMeters: 4600, walkMeters: 400, weightKg: 80.5),
        closeTo(flat + 0.005 * 80.5 * 0.1 * 400, 1e-9),
      );
      expect(
        runFloorKcal(runMeters: 4600, climbMeters: 30, weightKg: 80.5),
        closeTo(flat + 0.005 * 80.5 * 0.9 * 30, 1e-9),
      );
    });

    test('no weight, no number', () {
      expect(runFloorKcal(runMeters: 5000), isNull);
    });
  });

  group('Method 2, heart rate (Keytel)', () {
    test('active kcal over a steady 151 bpm, 35 minutes', () {
      // An extra boundary sample at 35:00 has zero duration.
      final r = keytelActiveKcal(List.filled(36, 151.0), 35, me)!;
      // gross (-55.0969 + 0.6309*151 + 0.1988*80.5 + 0.2017*23)/4.184
      // = 14.534 kcal/min; resting 1861.8/1440 = 1.293; x 35 min.
      expect(r.kcal, closeTo((14.5343 - 1.2929) * 35, 0.2));
      expect(r.measured, 35);
      expect(r.slots, 35);
    });

    test('an easy minute below resting counts as zero, not negative', () {
      final r = keytelActiveKcal([60, 60, 151.0], 3, me)!;
      expect(r.kcal, closeTo(14.5343 - 1.2929, 0.05));
    });

    test('missing minutes count as nothing and are reported', () {
      final r = keytelActiveKcal([151, null, 151, null], 4, me)!;
      expect(r.measured, 2);
      expect(r.kcal, closeTo(2 * (14.5343 - 1.2929), 0.1));
    });

    test('women use their own equation', () {
      const f = Profile(ageYears: 30, weightKg: 60, heightCm: 165, sex: 'f');
      final r = keytelActiveKcal([150], 1, f)!;
      final gross =
          (-20.4022 + 0.4472 * 150 - 0.1263 * 60 + 0.074 * 30) / 4.184;
      expect(r.kcal, closeTo(gross - bmrMifflin(f)! / 1440, 1e-9));
    });

    test('no age or no heart rate, no number', () {
      expect(keytelActiveKcal([150], 1, const Profile(weightKg: 80)), isNull);
      expect(keytelActiveKcal([null, null], 2, me), isNull);
    });
  });

  group('maintenance with a run', () {
    test('Akshat\'s example: run steps come off the step row', () {
      final run = runFloorKcal(runMeters: 5000, weightKg: 80.5)!;
      final m = maintenance(
        me,
        steps: 15000,
        eatenKcal: 2500,
        runKcal: run,
        runSteps: 4835,
      )!;
      expect(m.steps, closeTo(2.74 * 10165 * 80.5 / 8368, 1e-6)); // 267.9
      expect(m.run, closeTo(287.8, 0.1));
      expect(m.total, closeTo(1861.8 + 267.9 + 287.8 + 250, 0.3));
    });

    test('without a run it is the build 68 number', () {
      final m = maintenance(me, steps: 15000, eatenKcal: 2500)!;
      expect(m.run, 0);
      expect(m.total, closeTo(2507.2, 0.2));
    });

    test('run steps never take the step row below zero', () {
      final m = maintenance(me, steps: 1000, runKcal: 100, runSteps: 5000)!;
      expect(m.steps, 0);
    });

    test('the Running row adds only runs with a distance', () {
      final day = DateTime(2026, 10, 3, 7);
      final runs = [
        RunSummary(
          'a',
          day,
          5000,
          1800,
          const {},
          mix: (runM: 5000, walkM: 0, climbM: 0, runSec: 1800, walkSec: 0),
          phoneSteps: 4835,
        ),
        // Band only, no phone: no distance, so its steps stay walking steps.
        RunSummary(
          'b',
          day.add(const Duration(hours: 9)),
          0,
          0,
          const {},
          bandSteps: 3000,
        ),
      ];
      final r = runEnergyOn(
        runs,
        '2026-10-03',
        weightKg: 80.5,
        daySteps: 15000,
      );
      expect(r.count, 1);
      expect(r.steps, 4835);
      expect(r.kcal, closeTo(287.8, 0.1));
      expect(r.km, closeTo(5, 1e-9));
    });
  });

  group('running vs walking', () {
    List<RoutePoint> track(List<(int sec, double mps)> legs) {
      const mPerDegLat = 111195.0;
      final pts = <RoutePoint>[];
      var lat = 29.9;
      var t = 0;
      var seq = 0;
      for (final (sec, v) in legs) {
        for (var i = 0; i < sec; i++) {
          pts.add(RoutePoint(seq: seq++, tsMs: t * 1000, lat: lat, lng: -95.6));
          lat += v / mPerDegLat;
          t++;
        }
      }
      return pts;
    }

    test('a walk break is priced as walking', () {
      final mix = runMix(track([(600, 3.0), (120, 1.4), (300, 3.0)]));
      expect(mix.runM, closeTo(2700, 60));
      expect(mix.walkM, closeTo(168, 60));
      expect(mix.runSec, closeTo(900, 40));
    });

    test('standing still is neither', () {
      final mix = runMix(track([(300, 3.0), (120, 0.0), (300, 3.0)]));
      expect(mix.walkM, lessThan(40));
      expect(mix.runM, closeTo(1800, 60));
    });

    test('from the phone alone, cadence decides', () {
      final mix = motionMix(
        steps: [170, 170, 110, 0],
        meters: [180, 180, 80, null],
        chunkSec: 60,
      );
      expect(mix.runM, 360);
      expect(mix.walkM, 80);
      expect(mix.climbM, 0);
    });
  });

  test('phone splits interpolate each kilometre', () {
    // 180 m a minute for 7 minutes: 1 km at 5:33, then 260 m left over.
    final w = MotionWindow(
      DateTime(2026, 10, 3, 7),
      60,
      List.filled(7, 170),
      List.filled(7, 180.0),
    );
    final s = w.splits(hrAtMinute: (_) => 150);
    expect(s.length, 2);
    expect(s.first.sec, 333);
    expect(s.first.hr, 150);
    expect(s.last.km, closeTo(0.26, 1e-9));
    expect(w.totalSteps, 1190);
    expect(w.cadence, closeTo(170, 1e-9));
  });

  test('a saved phone answer round-trips', () {
    final w = MotionWindow(
      DateTime(2026, 10, 3, 7),
      60,
      const [10, 0],
      const [8.5, null],
    );
    final back = MotionWindow.fromJson(w.toJson())!;
    expect(back.steps, w.steps);
    expect(back.meters, w.meters);
    expect(back.start, w.start);
  });

  test('predictions use efforts of 3 km and more', () {
    final now = DateTime.now();
    expect(
      predicted5k([
        RunSummary('a', now, 1000, 300, const {'1K': 240}),
      ]),
      isNull,
    );
    final p = predicted5k([
      RunSummary('a', now, 3000, 900, const {'3K': 840}),
    ]);
    expect(p, closeTo(840 * 1.7181, 1)); // (5/3)^1.06
  });
}
