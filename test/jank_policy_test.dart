// Regression tests for the frame-jank watchdog rule.
//
// The production bug these lock down: the watchdog triggered on
// `FrameTiming.totalSpan`, so an app resume — where the "frame" straddles the
// whole time the app was backgrounded — reported as a multi-second stutter
// despite near-zero engine work. Real numbers from Crashlytics 0.9.20:
// "Slow frame: 16358ms (build=0 raster=8)". That class of report was the top
// issue by impacted users on both platforms.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/telemetry/jank_policy.dart';

void main() {
  const policy = JankPolicy(); // 700 ms of engine work

  group('JankPolicy does not report idle time as jank', () {
    test('the exact production false positive stays silent', () {
      // 16.4 s total span, 8 ms of actual work — an app resume, not a stutter.
      final v = policy.evaluate(buildMs: 0, rasterMs: 8, totalMs: 16358);
      expect(v.report, isFalse);
      expect(v.workMs, 8);
      expect(v.idleMs, 16350);
    });

    test('a long span with sub-threshold work stays silent', () {
      final v = policy.evaluate(buildMs: 59, rasterMs: 164, totalMs: 3791);
      expect(v.report, isFalse, reason: '223ms of work is not a 700ms stutter');
    });

    test('the other production sample stays silent too', () {
      final v = policy.evaluate(buildMs: 5, rasterMs: 1, totalMs: 1469);
      expect(v.report, isFalse);
    });
  });

  group('JankPolicy still reports real jank', () {
    test('a genuinely expensive build trips the threshold', () {
      final v = policy.evaluate(buildMs: 900, rasterMs: 20, totalMs: 950);
      expect(v.report, isTrue);
      expect(v.workMs, 920);
    });

    test('build and raster combine — neither alone would trip it', () {
      final v = policy.evaluate(buildMs: 400, rasterMs: 350, totalMs: 800);
      expect(v.report, isTrue, reason: '750ms of combined work is a stutter');
    });

    test('an expensive raster pass alone trips it', () {
      final v = policy.evaluate(buildMs: 10, rasterMs: 1200, totalMs: 1300);
      expect(v.report, isTrue);
    });

    test('exactly at the threshold reports', () {
      expect(policy.evaluate(buildMs: 700, rasterMs: 0, totalMs: 700).report,
          isTrue);
      expect(policy.evaluate(buildMs: 699, rasterMs: 0, totalMs: 699).report,
          isFalse);
    });
  });

  group('JankPolicy is defensive about absurd input', () {
    test('negative durations are floored at zero, never underflowed', () {
      final v = policy.evaluate(buildMs: -5000, rasterMs: 10, totalMs: -1);
      expect(v.report, isFalse);
      expect(v.workMs, 10);
      expect(v.totalMs, 0);
      expect(v.idleMs, 0, reason: 'idle can never go negative');
    });

    test('idle is zero when work exceeds the reported span', () {
      final v = policy.evaluate(buildMs: 800, rasterMs: 100, totalMs: 50);
      expect(v.idleMs, 0);
      expect(v.report, isTrue);
    });
  });

  test('a custom threshold applies to work, not span', () {
    const strict = JankPolicy(thresholdMs: 100);
    expect(strict.evaluate(buildMs: 60, rasterMs: 50, totalMs: 120).report,
        isTrue);
    expect(strict.evaluate(buildMs: 1, rasterMs: 1, totalMs: 99999).report,
        isFalse);
  });

  test('the message names engine work first and span as context', () {
    final v = policy.evaluate(buildMs: 800, rasterMs: 100, totalMs: 5000);
    expect(v.message, contains('900ms of engine work'));
    expect(v.message, contains('total span=5000ms'));
  });
}
