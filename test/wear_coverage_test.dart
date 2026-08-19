// `coverage_pct` is rendered as the SENTENCE "The band saw N% of this day"
// (day_strain.dart), so the only denominator that makes that sentence true is
// the day. It used to be `last sample - first sample`, which made a band worn
// 9-11am and nowhere else report 100%.
//
// Everything here goes through `applyDayActivity`, not the wear helper, for the
// reason stated above that function: the calorie invariant held in the helper
// and broke on the way out of it, and a test that only exercised the helper
// could not see it.
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/derivation_engine.dart';
import 'package:openstrap_edge/compute/profile.dart';
import 'package:openstrap_edge/compute/substrate.dart';

const _profile = Profile(ageYears: 35, sex: 'm', weightKg: 75, heightCm: 178);

/// Local midnight opening [d], and the start of the next local day. Built from
/// DateTime so the test is correct in any timezone the CI happens to run in —
/// and so a DST day is genuinely 23 h/25 h rather than a hardcoded 86400.
(int, int) _localDay(DateTime d) => (
  DateTime(d.year, d.month, d.day).millisecondsSinceEpoch ~/ 1000,
  DateTime(d.year, d.month, d.day + 1).millisecondsSinceEpoch ~/ 1000,
);

/// A substrate present for each [spans] range, sampled every [stepSec]. The
/// default is the real 1 Hz cadence, which matters: a run is closed at
/// `lastSample + 1`, so a coarser fixture step would lose a step's worth of
/// worn time at every boundary and the off-by-one would look like the code's.
Substrate _sub(List<(int, int)> spans, {int stepSec = 1}) {
  final ts = <int>[];
  for (final s in spans) {
    for (var t = s.$1; t < s.$2; t += stepSec) {
      ts.add(t);
    }
  }
  final n = ts.length;
  return Substrate(
    tsSec: ts,
    hr: List<int>.filled(n, 60),
    rrTsMs: const [],
    rrMs: const [],
    ax: List<double>.filled(n, 0),
    ay: List<double>.filled(n, 0),
    az: List<double>.filled(n, 1),
    spo2Red: List<int>.filled(n, 0),
    spo2Ir: List<int>.filled(n, 0),
    skinTemp: List<int>.filled(n, 0),
    skinContact: List<int>.filled(n, 0),
    deviceFamily: 'gen4',
  );
}

Map<String, dynamic> _wear(
  Substrate sub, {
  required int dayStartSec,
  required int dayCalendarEndSec,
  required int dataNowSec,
}) {
  final bundle = <String, dynamic>{};
  DerivationEngine.applyDayActivity(
    bundle: bundle,
    scalars: <String, dynamic>{},
    daySub: sub,
    profile: _profile,
    sleepOnsetSec: 0,
    sleepOffsetSec: 0,
    dayStartSec: dayStartSec,
    dayCalendarEndSec: dayCalendarEndSec,
    dataNowSec: dataNowSec,
  );
  return (bundle['wear'] as Map).cast<String, dynamic>();
}

void main() {
  final (dayStart, dayEnd) = _localDay(DateTime(2026, 8, 10));
  final nineAm = dayStart + 9 * 3600;
  final elevenAm = dayStart + 11 * 3600;

  group('coverage_pct divides by the day', () {
    test('a band worn 9-11am on a finished day is not 100%', () {
      // The shipped bug: 7200 s of records over a 7200 s span read as 100%,
      // and the screen said "The band saw 100% of this day".
      final w = _wear(
        _sub([(nineAm, elevenAm)]),
        dayStartSec: dayStart,
        dayCalendarEndSec: dayEnd,
        // A day two days in the past — long finished, nothing more to arrive.
        dataNowSec: dayEnd + 2 * 86400,
      );
      expect(w['coverage_pct'], 8); // 2 h of 24 h
      expect(w['worn_min'], 120);
    });

    test('a fully-worn day reads 100%', () {
      final w = _wear(
        _sub([(dayStart, dayEnd)]),
        dayStartSec: dayStart,
        dayCalendarEndSec: dayEnd,
        dataNowSec: dayEnd + 86400,
      );
      expect(w['coverage_pct'], 100);
    });

    test('a day still in progress divides by the ELAPSED part', () {
      // 40% through the day, worn throughout. This must NOT read as 60%
      // missing — the hours have not happened yet, and a morning that opens on
      // "the band saw 40% of this day" teaches the user to ignore the number.
      final now = dayStart + (86400 * 0.4).round();
      final w = _wear(
        _sub([(dayStart, now)]),
        dayStartSec: dayStart,
        dayCalendarEndSec: dayEnd,
        dataNowSec: now,
      );
      expect(w['coverage_pct'], 100);
    });

    test('the denominator is the DATA edge, not the wall clock', () {
      // Sync stopped at noon. The afternoon has not been observed, so it is not
      // counted against the user — the same anchoring finalization uses.
      final noon = dayStart + 12 * 3600;
      final w = _wear(
        _sub([(dayStart, noon)]),
        dayStartSec: dayStart,
        dayCalendarEndSec: dayEnd,
        dataNowSec: noon,
      );
      expect(w['coverage_pct'], 100);
    });

    test('an empty day is a measured 0, and null when there is no day', () {
      expect(
        _wear(
          _sub(const []),
          dayStartSec: dayStart,
          dayCalendarEndSec: dayEnd,
          dataNowSec: dayEnd + 86400,
        )['coverage_pct'],
        0,
      );
      expect(
        _wear(
          _sub(const []),
          dayStartSec: 0,
          dayCalendarEndSec: 0,
          dataNowSec: 0,
        )['coverage_pct'],
        isNull,
      );
    });
  });

  group('segments span the observable day', () {
    test('the hole before the first record is on the list', () {
      // Without this the timeline opened at 9am and implied the night before
      // it never existed — and it would contradict the 8% beside it.
      final w = _wear(
        _sub([(nineAm, elevenAm)]),
        dayStartSec: dayStart,
        dayCalendarEndSec: dayEnd,
        dataNowSec: dayEnd + 86400,
      );
      final segs = (w['segments'] as List).cast<Map<String, dynamic>>();
      expect(segs.first['on'], false);
      expect(segs.first['start'], dayStart);
      expect(segs.first['end'], nineAm);
      expect(segs.last['on'], false);
      expect(segs.last['end'], dayEnd);
      // "your band was off your wrist ..." needs the longest gap to be a real
      // measured span, and the 13 h evening one is longer than the 9 h morning.
      expect(w['longest_off_min'], (dayEnd - elevenAm) ~/ 60);
    });

    test('sum(on) / observable is exactly coverage_pct', () {
      // The ribbon and the percentage are two renderings of one measurement and
      // may never disagree.
      final w = _wear(
        _sub([
          (dayStart + 3600, dayStart + 5 * 3600),
          (nineAm, elevenAm),
          (dayStart + 20 * 3600, dayEnd),
        ]),
        dayStartSec: dayStart,
        dayCalendarEndSec: dayEnd,
        dataNowSec: dayEnd + 86400,
      );
      final segs = (w['segments'] as List).cast<Map<String, dynamic>>();
      var onSec = 0;
      for (final s in segs) {
        if (s['on'] == true) {
          onSec += (s['end'] as int) - (s['start'] as int);
        }
      }
      expect(
        (100 * onSec / (dayEnd - dayStart)).round(),
        w['coverage_pct'],
      );
    });

    test('a day in progress does not report its unlived hours as off', () {
      final now = dayStart + 10 * 3600;
      final w = _wear(
        _sub([(dayStart, now)]),
        dayStartSec: dayStart,
        dayCalendarEndSec: dayEnd,
        dataNowSec: now,
      );
      final segs = (w['segments'] as List).cast<Map<String, dynamic>>();
      expect(segs.every((s) => s['on'] == true), isTrue);
      expect(segs.last['end'], lessThanOrEqualTo(now));
    });
  });

  group('charging inside the scored sleep window', () {
    // A battery-pack swap leaves the strap on the wrist, so no wear signal can
    // see it — the band keeps logging and WRIST_ON never drops.
    const onset = 1786480000;
    const offset = onset + 8 * 3600;

    test('an overlapping charge is flagged and clipped to the window', () {
      final f = DerivationEngine.sleepChargingBlock([
        [onset - 1800, onset + 1800], // straddles onset: pre-bed top-up
        [offset + 600, offset + 3600], // after wake: not this night's problem
      ], onset, offset);
      expect(f['present'], true);
      expect(f['minutes'], 30); // only the half inside the window
      expect(f['spans'], [
        [onset, onset + 1800],
      ]);
      expect(f['note'], isNotEmpty);
    });

    test('a night with no charge, and a day with no window, both say so', () {
      expect(
        DerivationEngine.sleepChargingBlock([
          [offset + 600, offset + 3600],
        ], onset, offset)['present'],
        false,
      );
      // No sleep detected: onset == offset == 0. There is no window to caveat,
      // and "present: false" here means "no window", not "no charging".
      expect(
        DerivationEngine.sleepChargingBlock([
          [onset, offset],
        ], 0, 0)['present'],
        false,
      );
    });

    test('the flag carries no confidence penalty for the caller to apply', () {
      // Deliberate. The strap is on the wrist and beat timing has no pathway to
      // degrade, so a confidence multiplier here would be an invented
      // measurement expressing a suspicion. The caveat is published instead.
      final f = DerivationEngine.sleepChargingBlock([
        [onset, onset + 3600],
      ], onset, offset);
      expect(f.containsKey('confidence'), isFalse);
      expect(f.containsKey('confidence_penalty'), isFalse);
      // And it names the channel that DOES have a mechanism.
      expect(f['note'], contains('skin temperature'));
    });
  });
}
