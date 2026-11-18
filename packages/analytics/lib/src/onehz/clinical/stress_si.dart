// CLINICAL — Baevsky Stress Index (SI), a transparent HRV stress metric.
//
// Baevsky R.M. et al., "Methodological aspects of heart rate variability
// analysis" — the Stress Index (a.k.a. Tension/Regulation Index) quantifies
// sympathetic activation / autonomic "tension" from the RR-interval histogram:
//
//   SI = AMo / (2 · Mo · MxDMn)
//     Mo     = mode of RR (most frequent value, 50 ms bins)  [seconds]
//     AMo    = amplitude of the mode (% of RR in the modal bin)  [%]
//     MxDMn  = variation range = max(RR) − min(RR)  [seconds]
//
// Higher SI = narrower, more regular RR distribution = more sympathetic / less
// vagal = more "stress". Published resting bands (Baevsky): <50 low, 50–150
// normal, 150–500 elevated, >500 high. No ML, no training — pure histogram math
// on cleaned NN beats. tier ESTIMATE (PRV at the 1 Hz beat-timing ceiling).

import 'dart:math' as math;
import '../types.dart';
import '../util.dart';

class StressIndex {
  final double si; // Baevsky Stress Index (dimensionless)
  final String level; // 'low' | 'normal' | 'elevated' | 'high'
  final double modeS; // Mo, seconds
  final double amoPct; // AMo, %
  final double mxdmnS; // MxDMn, seconds
  const StressIndex({
    required this.si,
    required this.level,
    required this.modeS,
    required this.amoPct,
    required this.mxdmnS,
  });
  Map<String, dynamic> toJson() => {
        'si': round6(si),
        'level': level,
        'mode_s': round6(modeS),
        'amo_pct': round6(amoPct),
        'mxdmn_s': round6(mxdmnS),
      };
}

/// Baevsky Stress Index over cleaned NN intervals (ms). CRUCIAL: SI must be
/// computed over SHORT, near-stationary windows — over a whole night the RR
/// variation range (MxDMn) is maximal, which drives SI to ~0 (a bug we hit on
/// real data: whole-night SI read ~7). So we slide ~5-min windows (~256 beats),
/// compute SI per window, and report the MEDIAN — the robust resting SI.
///
/// [minRangeMs] guards the MxDMn denominator. Baevsky's SI is defined on an RR
/// histogram whose variation range is a physiological quantity (0.15–0.5 s at
/// rest); a 5-min window whose whole RR range is a few ms is beat-timing
/// QUANTIZATION, not physiology, and 1/MxDMn then explodes (300 beats
/// alternating 1000/1001 ms → SI ≈ 48 780, reported as 'high'). Windows below
/// the guard are dropped; if no window survives, the metric is ABSENT.
///
/// B88-03 qualification (engineering policy, not a clinical constant): the
/// night needs ≥[minTotalSec] of accepted beats and ≥[minWindows] FULL
/// 256-beat windows. With [nnTimesMs] (each interval's end time, ms) a window
/// whose wall-clock span exceeds [maxSpanRatio] × the sum of its intervals
/// hides a gap and is refused. It used to publish from 30 beats (~30 s).
Metric<StressIndex> baevskyStressIndex(
  List<double> nnMs, {
  double minRangeMs = 20.0,
  List<double>? nnTimesMs,
  double minTotalSec = 1200,
  int minWindows = 3,
  double maxSpanRatio = 1.3,
}) {
  const inputs = ['rr_cleaned'];
  final timed = nnTimesMs != null && nnTimesMs.length == nnMs.length;
  final nn = <double>[], ts = <double>[];
  for (var i = 0; i < nnMs.length; i++) {
    final v = nnMs[i];
    if (v < 300 || v > 2000) continue;
    nn.add(v);
    if (timed) ts.add(nnTimesMs[i]);
  }
  if (nn.length < 30) {
    return const Metric<StressIndex>.absent(
      tier: Tier.estimate,
      inputs_used: inputs,
      note: 'need ≥30 clean beats for a Stress Index histogram',
    );
  }
  final totalSec = nn.reduce((a, b) => a + b) / 1000.0;
  if (totalSec < minTotalSec) {
    return Metric<StressIndex>.absent(
      tier: Tier.estimate,
      inputs_used: inputs,
      note: 'stress_not_qualified:beats_sec=${totalSec.round()},'
          'need=${minTotalSec.round()}',
    );
  }

  // Window ~5 min of beats (256), 50% overlap; compute SI per FULL window.
  const win = 256, step = 128;
  final sis = <double>[];
  final modes = <double>[], amos = <double>[], ranges = <double>[];
  var gapped = 0;
  for (var start = 0; start + win <= nn.length; start += step) {
    final seg = nn.sublist(start, start + win);
    if (timed) {
      final span = ts[start + win - 1] - ts[start] + seg.first;
      final sum = seg.reduce((a, b) => a + b);
      if (span > maxSpanRatio * sum) {
        gapped++;
        continue;
      }
    }
    final r = _siOfSegment(seg, minRangeMs);
    if (r != null) {
      sis.add(r[0]);
      modes.add(r[1]);
      amos.add(r[2]);
      ranges.add(r[3]);
    }
  }
  if (sis.isEmpty && gapped == 0) {
    return const Metric<StressIndex>.absent(
      tier: Tier.estimate,
      inputs_used: inputs,
      note: 'no valid Stress Index window',
    );
  }
  if (sis.isEmpty || sis.length < minWindows) {
    return Metric<StressIndex>.absent(
      tier: Tier.estimate,
      inputs_used: inputs,
      note: 'stress_not_qualified:windows=${sis.length},need=$minWindows,'
          'gapped=$gapped',
    );
  }
  final si = median(sis)!;
  final level = si < 50
      ? 'low'
      : si < 150
          ? 'normal'
          : si < 500
              ? 'elevated'
              : 'high';

  return Metric<StressIndex>(
    value: StressIndex(
      si: si,
      level: level,
      modeS: (median(modes) ?? 0),
      amoPct: (median(amos) ?? 0),
      mxdmnS: (median(ranges) ?? 0),
    ),
    confidence: (0.4 + sis.length / 60.0).clamp(0.4, 0.7),
    tier: Tier.estimate,
    inputs_used: inputs,
    note: 'Baevsky Stress Index — median of ~5-min-window SI '
        '(AMo/(2·Mo·MxDMn)); resting autonomic tension, PRV — not psychological.',
  );
}

/// SI of one short NN segment → [si, modeS, amoPct, mxdmnS], or null if
/// degenerate (mode undefined, or a variation range below [minRangeMs]).
List<double>? _siOfSegment(List<double> seg, double minRangeMs) {
  const binMs = 50.0;
  final counts = <int, int>{};
  for (final v in seg) {
    final b = (v / binMs).floor();
    counts[b] = (counts[b] ?? 0) + 1;
  }
  var modeBin = counts.keys.first, modeCount = 0;
  counts.forEach((b, c) {
    if (c > modeCount) {
      modeCount = c;
      modeBin = b;
    }
  });
  final modeS = ((modeBin + 0.5) * binMs) / 1000.0;
  final amoPct = 100.0 * modeCount / seg.length;
  final mxdmnMs = seg.reduce(math.max) - seg.reduce(math.min);
  final mxdmnS = mxdmnMs / 1000.0;
  // MxDMn sits in the denominator: a range at or below the beat-timing
  // resolution is not a measurement of autonomic tension, it is quantization.
  if (modeS <= 0 || mxdmnMs < minRangeMs) return null;
  return [amoPct / (2.0 * modeS * mxdmnS), modeS, amoPct, mxdmnS];
}
