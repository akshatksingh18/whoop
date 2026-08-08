// P0 REGRESSION — absent gravity must not be read back as perfect stillness.
//
// `sampleFromGen5V18Lenient` correctly ABSTAINS on a gravity vector that fails
// the magnitude gate (ax/ay/az stay null) while keeping HR/RR. But
// `decoded_onehz.ax/ay/az` are REAL NOT NULL, so the persistence layer writes
// `decoded.ax ?? 0` and the substrate loader reads `?? 0` back — turning
// "we did not measure this" into "the wrist was at exactly (0,0,0)".
//
// That is not an inert default. zAngle(0,0,0) is exactly 0.0 in Dart (atan2
// (0,0) == 0.0, NOT NaN), so a run of absent seconds has a PERFECTLY CONSTANT
// z-angle, which is the van Hees immobility criterion satisfied maximally.
// Measured against the pinned analytics: 8 h of (0,0,0) yields 28 501 immobile
// seconds and `vanHeesSleepWindow.present == true` — a fabricated ~7.9 h night,
// fully staged, from data that does not exist. The PR's own commit message
// notes the strict gate rejected EVERY v18 record on fw 50.40.1.0, so this is
// the ordinary case for that firmware, not a corner.
//
// Two sentinels were tried and REJECTED, both verified against the pinned
// analytics rather than assumed:
//   * NaN — fails OPEN. The rule tests "did the angle change by >= thr", and
//     every comparison against NaN is false, so it never trips: NaN scores the
//     SAME 28 501 immobile seconds as zeros.
//   * dropping the seconds — `immobilityMask` is a pure index-wise angle rule
//     with no timestamp/gap awareness (unlike `nap.dart`'s `stillAt`), so it
//     simply joins across the hole.
// Hence the gate below: absent accel must not be allowed to ANCHOR a window.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_analytics/onehz.dart' as ana;
import 'package:openstrap_edge/compute/substrate.dart';

Substrate _sub({
  required int n,
  required bool accelPresent,
  int startSec = 1750000000,
}) {
  final ts = <int>[];
  final hr = <int>[];
  final ax = <double>[];
  final ay = <double>[];
  final az = <double>[];
  for (var i = 0; i < n; i++) {
    ts.add(startSec + i);
    hr.add(58);
    if (accelPresent) {
      // A real, still-ish wrist: unit-magnitude gravity with a slight drift.
      final rad = (i % 3) * 0.5 * math.pi / 180.0;
      ax.add(math.sin(rad));
      ay.add(0.0);
      az.add(math.cos(rad));
    } else {
      // What the NOT NULL column forces for an abstaining decoder.
      ax.add(0.0);
      ay.add(0.0);
      az.add(0.0);
    }
  }
  return Substrate(
    tsSec: ts,
    hr: hr,
    rrTsMs: const [],
    rrMs: const [],
    ax: ax,
    ay: ay,
    az: az,
    spo2Red: List<int>.filled(n, 0),
    spo2Ir: List<int>.filled(n, 0),
    skinTemp: List<int>.filled(n, 0),
    skinContact: List<int>.filled(n, 0),
  );
}

void main() {
  group('the hazard this guards against is real', () {
    test(
      'zAngle(0,0,0) is 0.0, not NaN — so absent accel is maximally "still"',
      () {
        expect(ana.zAngle(0.0, 0.0, 0.0), 0.0);
      },
    );

    test(
      '8 h of absent accel scores as an almost entirely immobile night',
      () {
        const n = 8 * 3600;
        final s = _sub(n: n, accelPresent: false);
        final m = ana.vanHeesSleepWindow(s.accelSamples());
        final win = m.value!;
        final immobile = win.immobile.where((b) => b).length;
        expect(
          immobile,
          greaterThan((n * 0.95).round()),
          reason: 'this is why the gate exists — missing data reads as sleep',
        );
        expect(m.present, isTrue);
      },
    );

    test(
      'a NaN sentinel would NOT have fixed it — comparisons against NaN are '
      'false, so the "angle changed" test never trips',
      () {
        const n = 8 * 3600;
        final base = 1750000000000.0;
        final nan = <ana.AccelSample>[
          for (var i = 0; i < n; i++)
            ana.AccelSample(
                base + i * 1000, double.nan, double.nan, double.nan),
        ];
        final immobile =
            ana.vanHeesSleepWindow(nan).value!.immobile.where((b) => b).length;
        expect(
          immobile,
          greaterThan((n * 0.95).round()),
          reason: 'NaN fails OPEN here; documented so nobody "fixes" it that way',
        );
      },
    );
  });

  group('Substrate.accelPresentAt / accelPresentFraction', () {
    test('exact (0,0,0) is absent; a real vector is present', () {
      final absent = _sub(n: 10, accelPresent: false);
      final present = _sub(n: 10, accelPresent: true);
      expect(absent.accelPresentAt(0), isFalse);
      expect(present.accelPresentAt(0), isTrue);
      expect(absent.accelPresentFraction(0, 10), 0.0);
      expect(present.accelPresentFraction(0, 10), 1.0);
    });

    test('an empty range reports 0 — no evidence, not "all present"', () {
      final s = _sub(n: 10, accelPresent: true);
      expect(s.accelPresentFraction(5, 5), 0.0);
      expect(Substrate.empty.accelPresentFraction(0, 100), 0.0);
    });

    test('a mixed window reports the real fraction', () {
      final s = _sub(n: 100, accelPresent: true);
      for (var i = 0; i < 40; i++) {
        s.ax[i] = 0.0;
        s.ay[i] = 0.0;
        s.az[i] = 0.0;
      }
      expect(s.accelPresentFraction(0, 100), closeTo(0.60, 1e-9));
    });

    test(
      'the van Hees coverage floor rejects an all-absent night and accepts a '
      'fully-measured one',
      () {
        final absent = _sub(n: 8 * 3600, accelPresent: false);
        final present = _sub(n: 8 * 3600, accelPresent: true);
        expect(
          absent.accelPresentFraction(0, absent.length),
          lessThan(kMinAccelCoverageForVanHees),
        );
        expect(
          present.accelPresentFraction(0, present.length),
          greaterThanOrEqualTo(kMinAccelCoverageForVanHees),
        );
      },
    );
  });

  // CodeRabbit, correctly: everything above tests the PREDICATE
  // (`accelPresentFraction`) and never executes the gate it feeds. That made
  // this a vacuous guard for a P0 -- the coverage floor could have been deleted
  // and every assertion here would still pass. These drive `calendarDays`, the
  // real entry point, and assert on the SLEEP RESULT.
  group('the coverage floor actually gates accel-led detection', () {
    /// A full night of the given accel presence, with a plausible nocturnal HR
    /// dip so the HR-led fallback has something to find.
    Substrate night({required bool accelPresent, double presentFraction = 1.0}) {
      // 22:00 -> 08:00 local, 1 Hz.
      final start = _localMidnightOf(1750000000) + 22 * 3600;
      const n = 10 * 3600;
      final ts = <int>[];
      final hr = <int>[];
      final ax = <double>[];
      final ay = <double>[];
      final az = <double>[];
      for (var i = 0; i < n; i++) {
        ts.add(start + i);
        // Awake ~70, asleep ~50 between 23:00 and 07:00.
        final inNight = i > 3600 && i < 9 * 3600;
        hr.add(inNight ? 50 : 70);
        final present = accelPresent && (i / n) < presentFraction;
        if (present) {
          if (inNight) {
            // Asleep: a constant gravity vector — a genuine immobile block for
            // van Hees to find.
            ax.add(0.0);
            ay.add(0.0);
            az.add(1.0);
          } else {
            // Awake: a 10 deg/s sweep. It has to be a RAMP, not an
            // alternation — the mask smooths the z-angle with a 5-second
            // rolling MEDIAN, which erases a 1 Hz square wave entirely and
            // would make the whole record read immobile.
            final deg = (i % 9) * 10.0;
            final rad = deg * math.pi / 180.0;
            ax.add(math.cos(rad));
            ay.add(0.0);
            az.add(math.sin(rad));
          }
        } else {
          ax.add(0.0);
          ay.add(0.0);
          az.add(0.0);
        }
      }
      return Substrate(
        tsSec: ts,
        hr: hr,
        rrTsMs: const [],
        rrMs: const [],
        ax: ax,
        ay: ay,
        az: az,
        spo2Red: List<int>.filled(n, 0),
        spo2Ir: List<int>.filled(n, 0),
        skinTemp: List<int>.filled(n, 0),
        skinContact: List<int>.filled(n, 0),
      );
    }

    test(
      'when the NIGHT\'s own records carry no gravity, no accel-led `auto` '
      'sleep is produced — the fabricated window never reaches a PhysioDay',
      () {
        // The discriminating shape, and the realistic one: the evening has
        // real accel, the night's records decoded without a gravity vector.
        // Coverage lands below the floor, and the zeros would otherwise form a
        // clean multi-hour "immobile" block for van Hees to anchor on. With
        // the gate removed this test FAILS — verified by mutation.
        final days = calendarDays(night(accelPresent: true, presentFraction: 0.15));
        for (final d in days) {
          expect(
            d.sleepSource,
            isNot('auto'),
            reason: 'accel-led detection ran on data that does not exist',
          );
        }
      },
    );

    test(
      'a night with NO gravity at all is likewise never accel-led',
      () {
        // The pure gen5-lenient case: every record decoded without gravity.
        // Kept as documentation of the headline scenario — note it is not
        // independently discriminating, because a record that is immobile end
        // to end is also rejected downstream. The test above is the one that
        // pins the gate.
        final days = calendarDays(night(accelPresent: false));
        for (final d in days) {
          expect(d.sleepSource, isNot('auto'));
        }
      },
    );

    test('a fully-measured night still detects accel-led sleep normally', () {
      final days = calendarDays(night(accelPresent: true));
      expect(
        days.any((d) => d.sleepSource == 'auto'),
        isTrue,
        reason: 'the gate must not suppress a night we CAN measure',
      );
    });

    test('the boundary: just below the floor gates, at/above it does not', () {
      final below = calendarDays(
          night(accelPresent: true, presentFraction: kMinAccelCoverageForVanHees - 0.1));
      expect(below.any((d) => d.sleepSource == 'auto'), isFalse);

      final atOrAbove = calendarDays(
          night(accelPresent: true, presentFraction: kMinAccelCoverageForVanHees + 0.1));
      expect(atOrAbove.any((d) => d.sleepSource == 'auto'), isTrue);
    });
  });
}

/// Local midnight for [epochSec], matching `substrate.dart`'s own day anchor.
int _localMidnightOf(int epochSec) {
  final d = DateTime.fromMillisecondsSinceEpoch(epochSec * 1000);
  return DateTime(d.year, d.month, d.day).millisecondsSinceEpoch ~/ 1000;
}
