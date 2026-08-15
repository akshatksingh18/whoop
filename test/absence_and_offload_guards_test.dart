// Guards for the "absence read as a measurement" defect class, plus the two
// offload guards that were structurally bypassable.
//
// Each group here corresponds to a shipped bug, not a hypothetical:
//   * a run of absent accelerometer seconds read as a perfectly still wrist to
//     ENMO, immobility, the activity curve and auto-workout detection;
//   * a corrupt-but-CRC-valid HR byte of 250 on the gen4 TRUSTED decode path
//     became the day's max heart rate;
//   * a burst the band counted more frames in than we received was logged and
//     then handed a trim authorisation anyway, so the gap left flash forever;
//   * one non-finite double made `jsonEncode` throw and dropped the ENTIRE
//     cross-day bundle — every user, first week.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_analytics/onehz.dart' as ana;
import 'package:openstrap_edge/ble/ble_state.dart';
import 'package:openstrap_edge/compute/crossday_pipeline.dart';
import 'package:openstrap_edge/compute/substrate.dart';

/// A substrate of [n] seconds where the seconds in [absent] carry no gravity
/// vector (the positional absent marker, exact `(0,0,0)`).
Substrate _sub({required int n, Set<int> absent = const {}}) {
  final ts = <int>[], hr = <int>[];
  final ax = <double>[], ay = <double>[], az = <double>[];
  for (var i = 0; i < n; i++) {
    ts.add(1780000000 + i);
    hr.add(60);
    final gone = absent.contains(i);
    ax.add(gone ? 0 : 0.1);
    ay.add(gone ? 0 : 0.2);
    az.add(gone ? 0 : 0.95);
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
  group('accelSamples marks absent seconds invalid, never still', () {
    test('an absent second is carried, but not as a reading', () {
      final s = _sub(n: 10, absent: {3, 4});
      final samples = s.accelSamples();
      // 1:1 with tsSec — dropping them would shift every downstream index.
      expect(samples.length, 10);
      expect(samples[3].valid, isFalse);
      expect(samples[4].valid, isFalse);
      expect(samples[0].valid, isTrue);
    });

    test('the analytics readers that filter on `valid` do not see them', () {
      // enmoSeries filters `valid`, so an all-absent stream has nothing to
      // score — no minutes, rather than a full set of maximally-still ones.
      final absent = _sub(n: 600, absent: {for (var i = 0; i < 600; i++) i});
      expect(ana.enmoSeries(absent.accelSamples()).minutes, isEmpty);
      final present = _sub(n: 600);
      expect(ana.enmoSeries(present.accelSamples()).minutes, isNotEmpty);
    });
  });

  group('plausibleHrOrZero — the gen4 trusted path had no upper bound', () {
    test('a physiological HR passes through untouched', () {
      expect(plausibleHrOrZero(60), 60);
      expect(plausibleHrOrZero(kMinPlausibleHr), kMinPlausibleHr);
      expect(plausibleHrOrZero(kMaxPlausibleHr), kMaxPlausibleHr);
    });

    test('an impossible HR reads ABSENT, and is never clamped into range', () {
      // 250 used to pass the `hr > 0` filter and become the displayed max HR.
      expect(plausibleHrOrZero(250), 0);
      expect(plausibleHrOrZero(255), 0);
      expect(plausibleHrOrZero(7), 0);
      // Clamping would have produced a plausible-looking 230/25 — a number the
      // wrist never reported.
      expect(plausibleHrOrZero(250), isNot(kMaxPlausibleHr));
    });

    test('the off-skin sentinel is preserved', () {
      expect(plausibleHrOrZero(0), 0);
    });
  });

  group('BurstShortfallGate — bounded, because always-FAIL wedged sync', () {
    test('the first short burst is refused, the redelivery is not', () {
      final g = BurstShortfallGate();
      expect(g.refuse('aa'), isTrue);
      expect(g.refuse('aa'), isFalse,
          reason: 'a stable token must never ping-pong');
    });

    test('a fresh token in the same session is still capped', () {
      final g = BurstShortfallGate();
      expect(g.refuse('aa'), isTrue);
      // A band re-issuing a NEW token for the same data would defeat the
      // per-token bound; the per-session budget catches it.
      expect(g.refuse('bb'), isFalse);
    });

    test('a new session refills the session budget but not the run total', () {
      final g = BurstShortfallGate(maxPerSession: 1, maxTotal: 2);
      expect(g.refuse('a'), isTrue);
      g.onSessionStart();
      expect(g.refuse('b'), isTrue);
      g.onSessionStart();
      expect(g.refuse('c'), isFalse, reason: 'run total is the backstop');
      expect(g.refusalsTotal, 2);
    });
  });

  group('TrimAckPolicy — the shortfall refusal is last, and only post-commit',
      () {
    TrimAckVerdict eval({bool shortfall = false, bool durable = true}) =>
        TrimAckPolicy.evaluate(
          sessionCurrent: true,
          burstDiscarded: false,
          commitDurable: durable,
          shortfallRetry: shortfall,
        );

    test('no shortfall still sends', () => expect(eval(), TrimAckVerdict.send));

    test('a shortfall withholds the token', () {
      expect(eval(shortfall: true), TrimAckVerdict.blockedBurstShortfall);
    });

    test('a hard block still outranks it', () {
      // The others mean "this chunk must not be trimmed at all"; shortfall
      // means "ask for it again". Reporting the weaker reason would lose the
      // stronger one from the ledger.
      expect(eval(shortfall: true, durable: false),
          TrimAckVerdict.blockedCommitFailed);
    });
  });

  group('sanitizeForJson — one bad leaf must not cost the whole artifact', () {
    test('a NaN becomes absent and is recorded by path', () {
      final dropped = <String>[];
      final out = sanitizeForJson({
        'readiness_glassbox': {
          'value': {
            'items': [
              {'label': 'hrv', 'percentile_of_you': double.nan},
            ],
          },
        },
        'vo2max': {'value': 42.0},
      }, dropped);
      // Everything that CAN be encoded still is.
      expect(jsonEncode(out), contains('"vo2max"'));
      expect(jsonEncode(out), contains('42'));
      expect(dropped, [
        'readiness_glassbox.value.items[0].percentile_of_you',
      ]);
    });

    test('infinities go too, and a clean bundle is untouched', () {
      final dropped = <String>[];
      final clean = {
        'a': 1,
        'b': 'two',
        'c': [1.5, true, null],
        'd': {'e': 3.25},
      };
      expect(sanitizeForJson(clean, dropped), clean);
      expect(dropped, isEmpty);

      expect(sanitizeForJson(double.infinity, dropped), isNull);
      expect(sanitizeForJson(double.negativeInfinity, dropped), isNull);
      expect(dropped.length, 2);
    });

    test('an object with no JSON form is dropped, not thrown', () {
      final dropped = <String>[];
      final out = sanitizeForJson(
          {'when': DateTime.utc(2026), 'n': 1}, dropped) as Map;
      expect(out['when'], isNull);
      expect(out['n'], 1);
      expect(dropped, ['when']);
      expect(() => jsonEncode(out), returnsNormally);
    });

    test('the whole point: the encode no longer throws', () {
      final bundle = {'x': double.nan};
      expect(() => jsonEncode(bundle), throwsA(isA<JsonUnsupportedObjectError>()));
      expect(() => jsonEncode(sanitizeForJson(bundle, [])), returnsNormally);
    });
  });
}
