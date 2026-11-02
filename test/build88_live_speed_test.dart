// B88-05: live speed is smoothed over seconds, recognises a stop, shows
// nothing (never the average) without a fresh fix, and the live average
// divides by moving time.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/gps/route_math.dart';
import 'package:whoop_companion/gps/route_models.dart';
import 'package:whoop_companion/gps/route_tracker.dart';

const double _mPerDegLngAtEq = 111319.49;

GpsSample _at(double meters, int ms, {double? speed}) => GpsSample(
  lat: 0,
  lng: meters / _mPerDegLngAtEq,
  tsMs: ms,
  speed: speed,
  speedAccuracy: speed == null ? null : 0.5,
);

void main() {
  test('smoothing settles over seconds, not per fix', () {
    // A 2 → 4 m/s step: after one 5 s reading it is 63% of the way there,
    // and one 1 s reading moves it only 1 − e^(−1/5) ≈ 18%.
    expect(
      emaSpeedOverTime(2, 4, 5),
      closeTo(2 + 2 * (1 - math.exp(-1)), 1e-9),
    );
    expect(
      emaSpeedOverTime(2, 4, 1),
      closeTo(2 + 2 * (1 - math.exp(-0.2)), 1e-9),
    );
    expect(emaSpeedOverTime(null, 3, 0), 3);
    expect(emaSpeedOverTime(3, 9, 0), 3, reason: 'same-timestamp reading');
  });

  test('a stop reads 0 after 5 s, and no fix for 10 s reads unknown', () async {
    final ctrl = StreamController<GpsSample>();
    final t = RouteTracker(sink: (_) async {}, batchSize: 100);
    t.start(ctrl.stream);
    ctrl.add(_at(0, 0, speed: 3));
    ctrl.add(_at(15, 5000, speed: 3));
    ctrl.add(_at(25, 10000, speed: 0.3)); // slowing to a stop
    await pumpEventQueue();
    expect(t.freshSpeedMps(11000), isNotNull);
    expect(t.freshSpeedMps(11000), greaterThan(0));
    expect(t.freshSpeedMps(15000), 0, reason: 'no fix for 5 s after slowing');
    expect(t.freshSpeedMps(20001), isNull, reason: 'D5: unknown, not avg');
    await t.stop();
    await ctrl.close();
  });

  test('a fast runner whose fixes pause is not called stopped', () async {
    final ctrl = StreamController<GpsSample>();
    final t = RouteTracker(sink: (_) async {}, batchSize: 100);
    t.start(ctrl.stream);
    ctrl.add(_at(0, 0, speed: 3));
    ctrl.add(_at(15, 5000, speed: 3));
    await pumpEventQueue();
    expect(t.freshSpeedMps(11000), greaterThan(2));
    await t.stop();
    await ctrl.close();
  });

  test('moving time leaves out a stop between fixes', () async {
    final ctrl = StreamController<GpsSample>();
    final t = RouteTracker(sink: (_) async {}, batchSize: 100);
    t.start(ctrl.stream);
    ctrl.add(_at(0, 0));
    ctrl.add(_at(30, 10000)); // 3 m/s: moving
    ctrl.add(_at(40, 50000)); // 10 m in 40 s: stopped at a crossing
    ctrl.add(_at(70, 60000)); // moving again
    await pumpEventQueue();
    expect(t.movingSeconds, 20);
    await t.stop();
    await ctrl.close();
  });
}
