// The idle watch behind the "Still working out?" nudge (forgotten sessions).
//
// The reported bug this feature answers: a workout started and never finished
// keeps recording rest for hours — the session refuses every later workout,
// holds the full live streams armed all night, and (before the derive-hold
// cap) blanked Home. There is deliberately NO auto-stop: the watch only ever
// asks, and only the user ends a session. So the contract worth pinning is
// the asking itself — when it speaks up, when it stays quiet, and that a
// dropped ask (quiet hours) is retried rather than lost.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/state/workout_idle.dart';

void main() {
  final t0 = DateTime(2026, 8, 25, 18, 0);
  DateTime at(int min) => t0.add(Duration(minutes: min));

  WorkoutIdleWatch watch() => WorkoutIdleWatch(startedAt: t0);

  group('going quiet', () {
    test('a session quiet from the start asks at the threshold, not before',
        () {
      final w = watch();
      expect(w.onTick(at(19), hr: null, gate: 100), isFalse);
      expect(w.onTick(at(20), hr: null, gate: 100), isTrue);
    });

    test('an active sample resets the streak', () {
      final w = watch();
      expect(w.onTick(at(10), hr: 140, gate: 100), isFalse);
      expect(w.onTick(at(29), hr: null, gate: 100), isFalse,
          reason: 'only 19 quiet minutes since the last active sample');
      expect(w.onTick(at(30), hr: null, gate: 100), isTrue);
    });

    test('a reading below the activity gate is rest, not activity', () {
      final w = watch();
      // 20 minutes of measured-at-rest wrist is exactly the forgotten case —
      // the strap is worn, the workout is over.
      expect(w.onTick(at(10), hr: 62, gate: 100), isFalse);
      expect(w.onTick(at(20), hr: 62, gate: 100), isTrue);
    });

    test('with no gate, any real reading counts as active', () {
      // No calorie anchors → no gate → intensity cannot be judged. A worn
      // strap must not be nudged on a guess; only absence counts as quiet.
      final w = watch();
      expect(w.onTick(at(19), hr: 62, gate: null), isFalse);
      expect(w.onTick(at(38), hr: null, gate: null), isFalse,
          reason: 'the 62 bpm at minute 19 reset the streak');
      expect(w.onTick(at(39), hr: null, gate: null), isTrue,
          reason: '20 quiet minutes since that reading');
    });

    test('a non-positive reading is off-skin, not a heart rate', () {
      // Same rule accrueHr applies: 0 is not a measurement. It must not
      // count as activity even with no gate to compare against.
      final w = watch();
      expect(w.onTick(at(10), hr: 0, gate: null), isFalse);
      expect(w.onTick(at(20), hr: 0, gate: null), isTrue);
    });

    test('a session resumed long after its start may ask on the first tick',
        () {
      // The reconcile path rehydrates a crashed session with its ORIGINAL
      // start time, hours old. That is the most forgotten a workout can be.
      final w = watch();
      expect(w.onTick(at(300), hr: null, gate: 100), isTrue);
    });
  });

  group('asking is retried until it lands, then never again', () {
    test('an unconfirmed ask backs off, then re-asks', () {
      // The flagship scenario is an evening workout forgotten overnight —
      // which lands the first ask inside default quiet hours (22:00–07:00),
      // where the notification gate drops it. A fire-and-forget ask would be
      // silently lost for the whole night; the retry is what turns it into
      // the morning nudge.
      final w = watch();
      expect(w.onTick(at(20), hr: null, gate: 100), isTrue);
      expect(w.onTick(at(21), hr: null, gate: 100), isFalse,
          reason: 'a 1 Hz tick loop must not hammer the notification gate');
      expect(w.onTick(at(29), hr: null, gate: 100), isFalse);
      expect(w.onTick(at(30), hr: null, gate: 100), isTrue,
          reason: 'retryEvery elapsed and nothing confirmed the ask landed');
    });

    test('confirmFired ends it — one nudge per session, ever', () {
      final w = watch();
      expect(w.onTick(at(20), hr: null, gate: 100), isTrue);
      w.confirmFired();
      expect(w.onTick(at(40), hr: null, gate: 100), isFalse);
      // Even a fresh quiet stretch after real activity stays silent: the
      // session was asked about once and answered.
      expect(w.onTick(at(41), hr: 150, gate: 100), isFalse);
      expect(w.onTick(at(90), hr: null, gate: 100), isFalse);
    });

    test('activity between asks resets the backoff with the streak', () {
      final w = watch();
      expect(w.onTick(at(20), hr: null, gate: 100), isTrue);
      expect(w.onTick(at(25), hr: 150, gate: 100), isFalse);
      // A new 20-minute quiet stretch asks at its own threshold — not held
      // to the old ask's backoff clock.
      expect(w.onTick(at(45), hr: null, gate: 100), isTrue);
    });
  });
}
