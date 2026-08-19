// MIND-06 — the paired pre/post test, and the copy it is allowed to produce.
//
// The statistic is small; what this guards is the ceiling. "No detectable
// change" has to be a real, reachable answer, the floor has to hold, and no
// per-session number may come out of here at all.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/stress/session_effect.dart';

List<Map<String, dynamic>> _rows(List<(double, double)> pairs) => [
  for (final (pre, post) in pairs) {'pre_rmssd': pre, 'post_rmssd': post},
];

void main() {
  group('breathingEffect', () {
    test('under the floor it does not test, and says how far off it is', () {
      final e = breathingEffect(
        _rows([for (var i = 0; i < 5; i++) (40.0, 60.0)]),
      );
      expect(e.pairs, 5);
      expect(e.p, isNull);
      expect(e.detected, isFalse);
      final line = breathingEffectLine(e);
      expect(line, contains('5 sessions'));
      expect(line, contains('${kBreathingEffectPairs - 5} more'));
    });

    test('no sessions reads as an explanation, not as a result', () {
      final e = breathingEffect(const <Map<String, dynamic>>[]);
      expect(e.pairs, 0);
      expect(breathingEffectLine(e), contains('quiet minutes either side'));
    });

    test('rows missing either window are dropped, never imputed', () {
      final rows = [
        ..._rows([for (var i = 0; i < 12; i++) (40.0, 55.0)]),
        {'pre_rmssd': 40.0, 'post_rmssd': null},
        {'pre_rmssd': null, 'post_rmssd': 55.0},
        <String, dynamic>{},
      ];
      expect(breathingEffect(rows).pairs, 12);
    });

    test('a consistent rise is detected and named as higher', () {
      // Twelve pairs, all up by a different amount — W+ = 78, the maximum,
      // which is p ≈ 0.0025 two-sided.
      final e = breathingEffect(
        _rows([for (var i = 0; i < 12; i++) (40.0, 41.0 + i)]),
      );
      expect(e.pairs, 12);
      expect(e.p, lessThan(0.05));
      expect(e.p, greaterThan(0.0));
      expect(e.direction, 1);
      expect(breathingEffectLine(e), contains('usually higher'));
      expect(breathingEffectLine(e), contains('12 sessions'));
    });

    test('a consistent fall is named as lower, not hidden', () {
      final e = breathingEffect(
        _rows([for (var i = 0; i < 12; i++) (41.0 + i, 40.0)]),
      );
      expect(e.direction, -1);
      expect(breathingEffectLine(e), contains('usually lower'));
    });

    test('"no detectable change" is a reachable, shippable answer', () {
      // Eleven up, eleven down, same magnitudes: the ranks cancel exactly.
      final e = breathingEffect(
        _rows([
          for (var i = 1; i <= 11; i++) ...[(40.0, 40.0 + i), (40.0 + i, 40.0)],
        ]),
      );
      expect(e.pairs, 22);
      expect(e.detected, isFalse);
      expect(e.direction, 0);
      expect(
        breathingEffectLine(e),
        contains('No detectable change across 22 sessions'),
      );
    });

    test('every pair tied is not a finding', () {
      final e = breathingEffect(
        _rows([for (var i = 0; i < 14; i++) (44.0, 44.0)]),
      );
      expect(e.detected, isFalse);
      expect(breathingEffectLine(e), contains('No detectable change'));
    });

    test('one wild session cannot carry a verdict the ranks reject', () {
      // Eleven small falls and one enormous rise. The MEAN difference is
      // strongly positive; the ranks are not, and the rank test is what runs.
      final e = breathingEffect(
        _rows([for (var i = 1; i <= 11; i++) (40.0 + i, 40.0), (40.0, 400.0)]),
      );
      expect(e.direction, isNot(1));
    });

    test('no per-session number is reachable from the result', () {
      final e = breathingEffect(
        _rows([for (var i = 0; i < 12; i++) (40.0, 41.0 + i)]),
      );
      // The whole public surface: a sample size, a p, a direction. No delta,
      // no list, no latest session.
      final line = breathingEffectLine(e);
      for (final banned in const ['ms', 'RMSSD', 'rmssd', 'streak', 'score']) {
        expect(line.contains(banned), isFalse, reason: 'line said "$banned"');
      }
      expect(kBreathingEffectCaveat, contains('cannot tell the two apart'));
    });
  });

  test('the quiet window is the same length on both sides', () {
    // A shorter "before" against a longer "after" is a difference made of
    // sample size. One constant, used twice, is what prevents that.
    expect(kBreathingWindow.inMinutes, 2);
  });
}
