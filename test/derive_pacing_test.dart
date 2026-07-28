// Regression tests for foreground vs background derivation pacing.
//
// The production bug these lock down (Crashlytics 0.9.20, iOS 27): the engine
// ran 3 concurrent day-lanes with a 90 s per-day wall-clock timeout REGARDLESS
// of whether it was in the foreground or inside a throttled BGProcessingTask.
// In background that combination reliably produced `day_blocks_failed`
// TimeoutExceptions for days that were computing correctly, just slowly —
// three lanes dividing one throttled CPU slice three ways, each then blowing a
// budget calibrated for an un-throttled core.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/derive_pacing.dart';

void main() {
  const fg = DerivePacing(background: false);
  const bg = DerivePacing(background: true);

  group('concurrency', () {
    test('background is ALWAYS one lane, however many cores exist', () {
      for (final cores in [1, 2, 4, 8, 16]) {
        expect(bg.concurrency(cores), 1,
            reason: 'a throttled slot gains nothing from $cores lanes');
      }
    });

    test('foreground uses spare cores, capped', () {
      expect(fg.concurrency(1), 1);
      expect(fg.concurrency(2), 2);
      expect(fg.concurrency(3), 3);
      expect(fg.concurrency(8), DerivePacing.maxForegroundConcurrency);
      expect(fg.concurrency(64), DerivePacing.maxForegroundConcurrency);
    });

    test('a nonsense core count still yields a usable lane count', () {
      expect(fg.concurrency(0), 1);
      expect(fg.concurrency(-4), 1);
      expect(bg.concurrency(0), 1);
    });
  });

  group('per-day timeout', () {
    test('background gets a materially larger budget than foreground', () {
      expect(bg.perDayTimeout, greaterThan(fg.perDayTimeout));
    });

    test('foreground budget is unchanged at 90s', () {
      expect(fg.perDayTimeout, const Duration(seconds: 90));
    });

    test('background budget covers the observed throttled overrun', () {
      // The reported failures were days exceeding 90 s under throttling. The
      // background budget must clear that by a real margin, while still being
      // a bound (a hung day must not run forever).
      expect(bg.perDayTimeout, greaterThanOrEqualTo(const Duration(minutes: 3)));
      expect(bg.perDayTimeout, lessThanOrEqualTo(const Duration(minutes: 10)));
    });
  });

  test('the two modes differ in BOTH dimensions, not just one', () {
    // Widening the timeout alone would leave three lanes fighting for one
    // slice; serializing alone would leave the 90 s cliff in place. The fix is
    // only correct as a pair.
    expect(bg.concurrency(8), isNot(equals(fg.concurrency(8))));
    expect(bg.perDayTimeout, isNot(equals(fg.perDayTimeout)));
  });
}
