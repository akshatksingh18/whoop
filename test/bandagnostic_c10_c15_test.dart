// BANDAGNOSTIC group C, wave 2 — the five changes that stop a band id or a
// gen4 constant standing in for evidence. One group per item; every case is
// pure (no DB, no BLE), because every rule under test is.

import 'package:openstrap_analytics/onehz.dart' as ana;
import 'package:openstrap_edge/compute/substrate.dart';
import 'package:openstrap_edge/data/live_coverage_policy.dart';
import 'package:flutter_test/flutter_test.dart';

Substrate _sub({
  required List<int> hr,
  List<double>? ax,
  List<double>? ay,
  List<double>? az,
  List<int> stepCount = const [],
  String? family,
}) {
  final n = hr.length;
  return Substrate(
    tsSec: [for (var i = 0; i < n; i++) 1_700_000_000 + i],
    hr: hr,
    rrTsMs: const [],
    rrMs: const [],
    ax: ax ?? List<double>.filled(n, 0.0),
    ay: ay ?? List<double>.filled(n, 0.0),
    az: az ?? List<double>.filled(n, 1.0),
    spo2Red: List<int>.filled(n, 0),
    spo2Ir: List<int>.filled(n, 0),
    skinTemp: List<int>.filled(n, 0),
    skinContact: List<int>.filled(n, 0),
    stepCount: stepCount,
    deviceFamily: family,
  );
}

void main() {
  group('C11 — a plausibility bound refuses a reading, it does not replace it',
      () {
    test('the HR window is human physiology, so it is band-independent', () {
      // Not a sensor property: nothing about the strap moves 25 or 230, which
      // is why this does not go through calibrationFor and an unstamped record
      // still gets it.
      expect(plausibleHrOrNull(24), isNull);
      expect(plausibleHrOrNull(25), 25);
      expect(plausibleHrOrNull(230), 230);
      expect(plausibleHrOrNull(231), isNull);
    });

    test('R-R is bounded as an INTERVAL, not as a rate', () {
      expect(plausibleRrOrNull(249), isNull);
      expect(plausibleRrOrNull(250), 250.0);
      // 2,400 ms is 25 bpm only if you read one gap as a rate. One dropped
      // beat doubles a gap without the heart doing anything unusual, and the
      // ectopic filters downstream are built to see exactly this.
      expect(plausibleRrOrNull(2400), 2400.0);
      expect(plausibleRrOrNull(2401), isNull);
      expect(plausibleRrOrNull(0), isNull);
      expect(plausibleRrOrNull(-800), isNull);
    });

    test('accel is bounded on what a wrist SUSTAINS, not on the FSR', () {
      // Exact zero is a fill, not a reading.
      expect(accelPlausible(0, 0, 0), isFalse);
      // Ordinary wear and real movement both pass, including well past
      // protocol's gravity window (magSq 0.25..3.24) that 539a97b had to drop
      // from the gen5 decoder for rejecting real workout seconds.
      expect(accelPlausible(0, 0, 1.0), isTrue);
      expect(accelPlausible(0.1, 0.2, 0.95), isTrue);
      expect(accelPlausible(2.0, 2.0, 1.0), isTrue); // |a| = 3 g
      // A second-long mean above 4 g is not a wrist.
      expect(accelPlausible(0, 0, 4.0), isTrue);
      expect(accelPlausible(0, 0, 4.01), isFalse);
      // THE POINT OF NOT USING THE FSR: a decoder that is off by 10x on scale
      // reads as absent instead of as violent movement. A +/-16 g test would
      // have passed this.
      expect(accelPlausible(0, 0, 10.0), isFalse);
    });

    test('an implausible second is absent, and absent is not "not worn"', () {
      // A gravity vector out of range no longer counts as a present sample, so
      // van Hees cannot score it as perfect immobility.
      final s = _sub(
        hr: const [60, 60, 60],
        ax: const [0, 0, 0],
        ay: const [0, 0, 0],
        az: const [1.0, 0.0, 9.9],
      );
      expect(s.accelPresentAt(0), isTrue);
      expect(s.accelPresentAt(1), isFalse); // all-zero fill
      expect(s.accelPresentAt(2), isFalse); // impossible magnitude
      expect(s.accelPresentFraction(0, 3), closeTo(1 / 3, 1e-12));
    });
  });

  group('C12 — the flag is the row\'s own, not the badge\'s', () {
    test('a real flag is believed whatever the stamp says', () {
      for (final family in [null, 'gen5', 'gen6', '']) {
        final s = Substrate(
          tsSec: const [1, 2],
          hr: const [60, 60],
          rrTsMs: const [],
          rrMs: const [],
          ax: const [0.0, 0.0],
          ay: const [0.0, 0.0],
          az: const [1.0, 1.0],
          spo2Red: const [0, 0],
          spo2Ir: const [0, 0],
          skinTemp: const [0, 0],
          skinContact: const [0, 0],
          hrValid: const [1, 0],
          deviceFamily: family,
        );
        expect(s.hrValidAt(0), isTrue, reason: 'family=$family');
        expect(s.hrValidAt(1), isFalse, reason: 'family=$family');
      }
    });
  });

  group('C13 — an undeclared counter gets no number', () {
    List<int> counters(List<int> v) => v;

    test('abstains rather than assume the counter never resets', () {
      final s = _sub(
        hr: List<int>.filled(4, 60),
        stepCount: counters([4200, 4260, 4300, 4340]),
      );
      // The whole failure this replaces: sum-of-deltas over a MIDNIGHT-RESET
      // counter publishes 140 for a morning that started at 4,200, at tier
      // HIGH. Undeclared behaviour ⇒ no claim.
      expect(
        hardwareStepsFromCounter(s, cumulativeCounterModulus: null),
        isNull,
      );
      // Declared ⇒ the deltas, exactly as before.
      expect(
        hardwareStepsFromCounter(s, cumulativeCounterModulus: 65536),
        140,
      );
    });

    test('the modulus is the source\'s, not a constant in the function', () {
      // A u8 counter wrapping 250 -> 10 is a delta of 16, and only a caller
      // that declares 256 can say so. Read as u16 it is 65,296 and dropped.
      final s = _sub(hr: const [60, 60], stepCount: counters([250, 10]));
      expect(hardwareStepsFromCounter(s, cumulativeCounterModulus: 256), 16);
      expect(hardwareStepsFromCounter(s, cumulativeCounterModulus: 65536), 0);
    });
  });

  group('C15 — equal rank competes ACROSS devices, sums within one', () {
    CoverageSpan span(int from, int to, int steps,
            {bool band = true, String id = ''}) =>
        CoverageSpan(
          startTs: from,
          endTs: to,
          steps: steps,
          fromBand: band,
          deviceId: id,
        );

    test('two straps on one walk report the walk once', () {
      // Both spans look like gait (100 spm), so both rank 2 — which is exactly
      // the pair that used to skip overlap subtraction and publish 6,000.
      final r = resolveDaySteps([
        span(0, 1800, 3000, id: 'A'),
        span(0, 1800, 3000, id: 'B'),
      ]);
      expect(r.total, 3000);
    });

    test('partial overlap is pro-rated, not all-or-nothing', () {
      final r = resolveDaySteps([
        span(0, 1800, 3000, id: 'A'),
        span(900, 2700, 3000, id: 'B'),
      ]);
      // B keeps the half of its span A did not cover.
      expect(r.total, 4500);
    });

    test('SAME device still sums — this is what re-import relies on', () {
      final r = resolveDaySteps([
        span(0, 1800, 3000),
        span(0, 1800, 3000),
      ]);
      expect(r.total, 6000);
    });

    test('the result does not depend on the order the rows came back in', () {
      final a = span(0, 1800, 3000, id: 'A');
      final b = span(600, 2400, 2500, id: 'B');
      expect(resolveDaySteps([a, b]).total, resolveDaySteps([b, a]).total);
    });

    test('two devices tied on rank AND start still answer the same way', () {
      // The pair the rank/start keys cannot separate, so the sort was free to
      // order it either way — and here the answer really does depend on that
      // order: B is the denser span, so crediting A first leaves B a remainder
      // and crediting B first does not. 2,100 or 1,800, by whatever order
      // SQLite happened to return the rows in.
      final a = span(0, 1800, 1800, id: 'A'); // 60 spm
      final b = span(0, 900, 1200, id: 'B'); //  80 spm, same start
      expect(resolveDaySteps([a, b]).total, resolveDaySteps([b, a]).total);
    });
  });

  group('C10 — the family list is open', () {
    test('a band gets constants per METRIC, not per enum entry', () {
      const gate = ana.hrCeilingMotionGateG;
      expect(ana.calibrationFor(gate, 'gen4'), 0.10);
      expect(ana.calibrationFor(gate, 'gen6'), isNull);
      // The refusal note's grammar is parsed by the UI — pinned here because
      // this is the one thing C10 was not allowed to move.
      expect(ana.unknownFamilyNote('gen6'), 'unknown_device_family:id=gen6');
      expect(ana.unknownFamilyNote(null), 'unknown_device_family:id=none');
    });
  });
}
