// B88-03: every rolling-RMSSD curve and PRSA use the shared beat rule — no
// pair across a gap, and a window plots only with enough beat coverage.

import 'dart:math' as math;

import 'package:openstrap_analytics/onehz.dart';
import 'package:test/test.dart';

/// Continuous beats around 1000 ms with real variability, end times in ms.
({List<double> rr, List<double> ts}) _beats(int n, {double t0 = 0}) {
  final rr = <double>[], ts = <double>[];
  var t = t0;
  for (var i = 0; i < n; i++) {
    final v = 1000 + 40 * math.sin(i * 0.7);
    t += v;
    rr.add(v);
    ts.add(t);
  }
  return (rr: rr, ts: ts);
}

void main() {
  group('rollingRmssd', () {
    test('a continuous stretch plots with full coverage', () {
      final b = _beats(1200, t0: 1.7e12);
      final pts = rollingRmssd(b.rr, b.ts);
      expect(pts, isNotEmpty);
      // Every window ends inside the data and is nearly fully covered.
      expect(pts.map((p) => p.coverage).reduce(math.max), greaterThan(0.95));
      expect(pts.last.tSec * 1000.0, lessThanOrEqualTo(b.ts.last));
      for (final p in pts) {
        expect(p.coverage, greaterThanOrEqualTo(0.6));
        expect(p.rmssd, greaterThan(0));
      }
    });

    test('beats split by an hour-long gap never form a pair across it', () {
      final a = _beats(200, t0: 1.7e12);
      final b = _beats(200, t0: a.ts.last + 3600 * 1000.0);
      final rr = [...a.rr, ...b.rr], ts = [...a.ts, ...b.ts];
      for (final p in rollingRmssd(rr, ts)) {
        // No window can be built from beats on both sides of the hour.
        final endMs = p.tSec * 1000.0;
        expect(endMs - 300000 >= a.ts.last || endMs <= b.ts.first, isTrue);
      }
    });

    test('a window under 60% covered does not plot', () {
      // 150 beats (~150 s) inside a 300 s window: 50% coverage.
      final b = _beats(150, t0: 1.7e12);
      expect(rollingRmssd(b.rr, b.ts), isEmpty);
    });

    test('excluded beats break adjacency like a gap', () {
      final b = _beats(1200, t0: 1.7e12);
      final all = rollingRmssd(b.rr, b.ts);
      // Exclude every other beat: no two kept beats are adjacent.
      var k = 0;
      final none = rollingRmssd(b.rr, b.ts, include: (_) => (k++).isEven);
      expect(all, isNotEmpty);
      expect(none, isEmpty);
    });
  });

  group('PRSA adjacency', () {
    test('dropouts remove the anchors whose window spans them',
        () {
      final b = _beats(400);
      final plain = decelerationCapacity(b.rr);
      // A 5 s dropout before every 20th beat.
      final ts = [
        for (var i = 0; i < b.ts.length; i++) b.ts[i] + (i ~/ 20) * 5000.0
      ];
      final timed = decelerationCapacity(b.rr, nnTimesMs: ts);
      expect(plain.present, isTrue);
      expect(timed.present, isTrue);
      expect(timed.value!.anchors, lessThan(plain.value!.anchors));
    });
  });
}
