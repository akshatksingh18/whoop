// MIND-06 — did the breathing sessions do anything.
//
// The question the paced-breathing feature could never answer about itself:
// you have done eleven of these, and is your resting variability any different
// afterwards than it was before?
//
// WHAT THIS DELIBERATELY DOES NOT MEASURE
//
// RMSSD rises DURING slow breathing. That is respiratory sinus arrhythmia — a
// mechanical consequence of breathing at ~0.1 Hz, present in anyone who breathes
// slowly, including someone who finds the whole exercise unpleasant. Measuring
// it during the paced block and calling it benefit is circular, so the during
// number is not stored, not passed here, and never shown.
//
// Only pre-vs-post carries information, and even that is weak: unblinded,
// order-confounded (you sat still for ten minutes, which is itself a plausible
// mechanism and cannot be separated from the pacing), and state-dependent on
// what you walked in from. So the output is one sentence about a run of
// sessions and never about one session.
//
// NO PER-SESSION NUMBER LEAVES THIS FILE. A user chasing a bigger post-session
// delta has had their stress raised by the feature, which is the exact opposite
// of what it is for. There is no score, no ranking, and no run of sessions
// shown as a streak — [BreathingEffect.pairs] is a sample size and resets to
// nothing when a session is deleted, which is what makes it not one.
//
// Pure — no widgets, no database, no clock.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// How long each quiet window runs.
///
/// Two minutes is the floor for an RMSSD estimate with enough beats behind it
/// at a resting rate, and it is the same window on both sides — a shorter
/// "before" compared against a longer "after" would produce a difference that
/// is entirely sample size. Declared here rather than on the screen because it
/// is a property of the measurement, not of the layout.
const kBreathingWindow = Duration(minutes: 2);

/// Paired sessions needed before anything is said.
///
/// Twelve is where the Wilcoxon's normal approximation is tolerable AND where a
/// two-sided test can reach p < 0.05 on rank evidence alone. Under it there is
/// no test worth running, which is a fact about the arithmetic and not a target
/// to hit.
const kBreathingEffectPairs = 12;

/// What a run of sessions with both quiet windows shows, if anything.
@immutable
class BreathingEffect {
  const BreathingEffect({
    required this.pairs,
    required this.p,
    required this.direction,
  });

  /// Sessions that measured BOTH windows. Sessions run without the windows, or
  /// where a window could not be read, are not here.
  final int pairs;

  /// Two-sided Wilcoxon signed-rank p, or null below [kBreathingEffectPairs]
  /// (and when every pair tied, which leaves nothing to rank).
  final double? p;

  /// +1 higher after, -1 lower after, 0 for no detectable change. Zero is a
  /// real answer, not a missing one.
  final int direction;

  bool get detected => direction != 0;
}

/// The paired test over `breathing_session` rows.
///
/// Reads `pre_rmssd` / `post_rmssd`; rows missing either are dropped rather
/// than imputed. Returns the sample size even when it is too small to test, so
/// the screen can say how far off it is instead of going silent.
BreathingEffect breathingEffect(Iterable<Map<String, dynamic>> rows) {
  final diffs = <double>[];
  for (final r in rows) {
    final pre = (r['pre_rmssd'] as num?)?.toDouble();
    final post = (r['post_rmssd'] as num?)?.toDouble();
    if (pre == null || post == null) continue;
    diffs.add(post - pre);
  }
  if (diffs.length < kBreathingEffectPairs) {
    return BreathingEffect(pairs: diffs.length, p: null, direction: 0);
  }
  // A run where every pair tied (or where ties eat the whole variance) is NOT
  // "not enough sessions yet" — it is fourteen sessions that moved nothing,
  // which is the answer. p = 1 is what no rank evidence means, and it keeps p
  // non-null above the floor so the copy never reports a shortfall it does not
  // have.
  final p = _wilcoxonP(diffs) ?? 1.0;
  if (p >= 0.05) {
    return BreathingEffect(pairs: diffs.length, p: p, direction: 0);
  }
  // Direction off the sum of signed ranks, not the mean difference: the test
  // is a rank test, and a single wild session must not be able to flip the
  // direction of a verdict the ranks did not support.
  final signed = _signedRankSum(diffs);
  return BreathingEffect(
    pairs: diffs.length,
    p: p,
    direction: signed == 0 ? 0 : (signed > 0 ? 1 : -1),
  );
}

/// The one sentence. "No detectable change" is shippable copy on purpose — a
/// feature that can only say yes is not measuring anything.
String breathingEffectLine(BreathingEffect e) {
  if (e.p == null) {
    final left = kBreathingEffectPairs - e.pairs;
    return e.pairs == 0
        ? 'Two quiet minutes either side, so there is a before and an after to '
              'compare. Nothing is said until about $kBreathingEffectPairs '
              'sessions have both.'
        : 'Measured on ${e.pairs} '
              '${e.pairs == 1 ? 'session' : 'sessions'} so far. About $left '
              'more before there is enough to compare.';
  }
  if (!e.detected) {
    return 'No detectable change across ${e.pairs} sessions. Your resting '
        'variability afterwards looks like it did before.';
  }
  return e.direction > 0
      ? 'After your sessions, your resting variability is usually higher for a '
            'few minutes. Across ${e.pairs} sessions.'
      : 'After your sessions, your resting variability is usually lower for a '
            'few minutes. Across ${e.pairs} sessions.';
}

/// Why the sentence above is weaker than it sounds. Shown WITH the finding,
/// never as a footnote on another screen: sitting still for ten minutes is
/// itself the plausible mechanism, and nothing here can separate it from the
/// pacing.
const kBreathingEffectCaveat =
    'You knew you were doing it, and you also sat still for ten minutes — that '
    'on its own would do something, and this cannot tell the two apart. It is '
    'a few minutes either side, not a lasting change.';

/// Signed-rank sum (W+ − W−) over the non-zero differences.
double _signedRankSum(List<double> diffs) {
  final nz = [
    for (final d in diffs)
      if (d != 0) d,
  ];
  final ranks = _averageRanks([for (final d in nz) d.abs()]);
  var sum = 0.0;
  for (var i = 0; i < nz.length; i++) {
    sum += nz[i] > 0 ? ranks[i] : -ranks[i];
  }
  return sum;
}

/// Two-sided Wilcoxon signed-rank p by normal approximation, with the tie
/// correction and a continuity correction. Null when every pair tied.
double? _wilcoxonP(List<double> diffs) {
  final abs = [
    for (final d in diffs)
      if (d != 0) d.abs(),
  ];
  final n = abs.length;
  if (n < 2) return null;
  final ranks = _averageRanks(abs);
  var wPlus = 0.0;
  var i = 0;
  for (final d in diffs) {
    if (d == 0) continue;
    if (d > 0) wPlus += ranks[i];
    i++;
  }
  final mu = n * (n + 1) / 4.0;
  // Tie correction: each group of t equal |d| removes (t³ − t)/48 of variance.
  final sorted = [...abs]..sort();
  var tieTerm = 0.0;
  var run = 1;
  for (var k = 1; k <= sorted.length; k++) {
    if (k < sorted.length && sorted[k] == sorted[k - 1]) {
      run++;
    } else {
      if (run > 1) tieTerm += (run * run * run - run) / 48.0;
      run = 1;
    }
  }
  final variance = n * (n + 1) * (2 * n + 1) / 24.0 - tieTerm;
  if (variance <= 0) return null;
  final z = ((wPlus - mu).abs() - 0.5) / math.sqrt(variance);
  if (z <= 0) return 1.0;
  return 2 * (1 - _phi(z));
}

/// Ranks 1..n with ties averaged, in the ORDER GIVEN (not sorted order).
List<double> _averageRanks(List<double> xs) {
  final order = [for (var i = 0; i < xs.length; i++) i]
    ..sort((a, b) => xs[a].compareTo(xs[b]));
  final out = List<double>.filled(xs.length, 0);
  var i = 0;
  while (i < order.length) {
    var j = i;
    while (j + 1 < order.length && xs[order[j + 1]] == xs[order[i]]) {
      j++;
    }
    // Ranks are 1-based; the average of the block i..j is (i+j)/2 + 1.
    final r = (i + j) / 2.0 + 1;
    for (var k = i; k <= j; k++) {
      out[order[k]] = r;
    }
    i = j + 1;
  }
  return out;
}

/// Standard normal CDF via Abramowitz & Stegun 7.1.26 (|error| < 1.5e-7) —
/// far tighter than a p-value compared against 0.05 needs, and ten lines.
double _phi(double z) {
  final x = z.abs() / math.sqrt2;
  const a1 = 0.254829592,
      a2 = -0.284496736,
      a3 = 1.421413741,
      a4 = -1.453152027,
      a5 = 1.061405429,
      pp = 0.3275911;
  final t = 1.0 / (1.0 + pp * x);
  final y =
      1.0 -
      (((((a5 * t + a4) * t) + a3) * t + a2) * t + a1) * t * math.exp(-x * x);
  final erf = z >= 0 ? y : -y;
  return 0.5 * (1 + erf);
}
