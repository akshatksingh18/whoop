// Measurement only. No production caller and no private inputs in this file.
import 'dart:math' as math;
import 'package:whoop_analytics/onehz.dart' as ana;

/// Uses the shipped scoring and coverage functions. The alternate accumulator
/// is the research question, not an adopted replacement for the shipped score.
Map<String, double>? compareStrainForms({
  required List<int> timestamps,
  required List<double> heartRates,
  required double restingHr,
  required double maxHr,
  required bool female,
  List<double> sessionStrains = const [],
}) {
  if (timestamps.length != heartRates.length || timestamps.isEmpty) return null;
  final sums = <int, (double, int)>{};
  final kept = <int>[];
  for (var i = 0; i < timestamps.length; i++) {
    final hr = heartRates[i];
    if (!hr.isFinite || hr <= 0) continue;
    final key = timestamps[i] ~/ 60;
    final old = sums[key] ?? (0.0, 0);
    sums[key] = (old.$1 + hr, old.$2 + 1);
    kept.add(timestamps[i]);
  }
  final keys = sums.keys.toList()..sort();
  final hrs = [for (final k in keys) sums[k]!.$1 / sums[k]!.$2];
  final coverage = ana.minuteCoverage([
    for (final t in kept) t.toDouble(),
  ], keys);
  final weights = coverage.length == keys.length
      ? coverage
      : List<double>.filled(keys.length, 1);
  final gross = ana
      .banisterTrimp(
        hrs,
        restingHr: restingHr,
        maxHr: maxHr,
        sex: female ? ana.Sex.female : ana.Sex.male,
        minuteWeights: weights,
      )
      .value;
  if (gross == null) return null;
  final minutes = weights.fold<double>(0, (a, b) => a + b.clamp(0.0, 1.0));
  const q = ana.quietWakingHrr;
  final baseline = ana.baselineTrimp(1, quietHrr: q, female: female);
  var alternate = 0.0;
  for (var i = 0; i < hrs.length; i++) {
    final x = ((hrs[i] - restingHr) / (maxHr - restingHr)).clamp(0.0, 1.0);
    alternate +=
        weights[i].clamp(0.0, 1.0) *
        math.max(
          0.0,
          x * ana.StrainScorer.banisterY(x, female: female) - baseline,
        );
  }
  final whole = ana.strainScore(
    gross,
    wakeMinutes: minutes,
    quietHrr: q,
    female: female,
  );
  final excess = ana.strainFromNetTrimp(alternate);
  final sessionNet = sessionStrains
      .where((v) => v.isFinite && v > 0)
      .fold<double>(0, (sum, v) => sum + ana.netTrimpFromStrain(v));
  final floor = ana.strainFromNetTrimp(sessionNet);
  return {
    'gross_trimp': gross,
    'covered_waking_minutes': minutes,
    'whole_day': whole,
    'per_minute_excess': excess,
    'session_floor': floor,
    'whole_with_floor': math.max(whole, floor),
    'excess_with_floor': math.max(excess, floor),
  };
}
