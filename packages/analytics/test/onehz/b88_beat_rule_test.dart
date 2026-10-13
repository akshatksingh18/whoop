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

/// WHOOP 4 history timing: one beat per 1 Hz record, stamped at the record's
/// second plus that record's fixed sub-second phase — so successive beats
/// read 1000 or 2000 ms apart, never their own ~1300 ms interval.
({List<double> rr, List<double> ts, List<double> trueTs}) _recordStamped(
    int n, {double t0 = 1.7e12, double phaseMs = 430}) {
  final rr = <double>[], ts = <double>[], trueTs = <double>[];
  var t = t0;
  for (var i = 0; i < n; i++) {
    final v = 1300 + 45 * math.sin(i * 0.9) + 20 * math.sin(i * 0.23);
    t += v;
    rr.add(v);
    trueTs.add(t);
    ts.add((t / 1000).floor() * 1000.0 + phaseMs);
  }
  return (rr: rr, ts: ts, trueTs: trueTs);
}

void main() {
  group('record-stamped WHOOP 4 beats', () {
    test('a continuous night still makes a nightly HRV, at the true value', () {
      final b = _recordStamped(23000); // ~8 h
      final start = (b.trueTs.first / 1000).ceil();
      final end = (b.trueTs.last / 1000).floor();
      final stamped =
          sleepSessionWindowedRmssd(b.rr, b.ts, startSec: start, endSec: end);
      final exact = sleepSessionWindowedRmssd(b.rr, b.trueTs,
          startSec: start, endSec: end);
      expect(stamped.present, isTrue, reason: stamped.note);
      expect(exact.present, isTrue);
      expect(stamped.value, closeTo(exact.value!, exact.value! * 0.05));
    });

    test('the rolling curve covers the same night', () {
      final b = _recordStamped(3000);
      final pts = rollingRmssd(b.rr, b.ts);
      expect(pts.length, greaterThan(40));
      for (final p in pts) {
        expect(p.pairs, greaterThanOrEqualTo(120));
      }
    });

    test('a real dropout still splits the night', () {
      final a = _recordStamped(600);
      final b = _recordStamped(600, t0: a.trueTs.last + 20000);
      final rr = [...a.rr, ...b.rr], ts = [...a.ts, ...b.ts];
      final m = sleepSessionWindowedRmssd(
        [rr[599], rr[600]],
        [ts[599], ts[600]],
        startSec: (ts[599] / 1000).floor() - 1,
        endSec: (ts[600] / 1000).ceil() + 1,
        minCoveredSec: 0, minPairs: 1, minWindows: 1, minNightCoverage: 0,
        maxArtifactFrac: 1,
      );
      // The two beats either side of the 20 s gap never form a pair.
      expect(m.present, isFalse);
    });
  });

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
