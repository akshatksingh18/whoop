// step_cadence.dart — the ONE windows→minutes cadence mapping.
//
// `Calories.dailyEnergy`'s walking term (analytics) prices a sub-flex-gate
// minute from its MEASURED cadence. The measurements live in `live_coverage`
// as resolved, credited step windows (see `resolveDaySteps` — overlap between
// band and phone already settled there, so summing here cannot double-count a
// step). This maps those windows onto the wake-minute series both energy call
// sites use — `DerivationEngine.wakeDayEnergy` and the pure pipeline's
// early-read mirror. ONE implementation, imported by both: two copies of this
// mapping is how the derived day and its early read would drift apart, the
// exact bug class the single `wakeDayEnergy` pass exists to prevent.
//
// Pure and isolate-safe: no I/O, no clock, plain lists in and out.

/// Steps credited to each minute of [minuteKeys] (epoch-seconds ~/ 60, the
/// wake-series bucket key), from [spans] of `[startSec, endSec, steps]`.
///
/// Each span's count is spread uniformly over its own duration, so a minute
/// reads the steps that landed IN IT: a span covering only half a minute
/// credits half its per-minute rate there, and a walk's boundary minute
/// under-bills rather than half a minute of walking pricing a full
/// MET-minute. Null for a minute no span touches — nobody measured it, which
/// is not the same claim as a measured zero.
List<double?> cadenceSpmForMinutes(
  List<int> minuteKeys,
  List<List<int>> spans,
) {
  if (minuteKeys.isEmpty) return const [];
  final steps = <int, double>{};
  for (final s in spans) {
    if (s.length < 3) continue;
    final start = s[0], end = s[1], count = s[2];
    if (end <= start || count < 0) continue;
    final rate = count / (end - start); // steps per second, uniform
    for (var k = start ~/ 60; k * 60 < end; k++) {
      final lo = k * 60 < start ? start : k * 60;
      final hi = (k + 1) * 60 > end ? end : (k + 1) * 60;
      if (hi <= lo) continue;
      steps[k] = (steps[k] ?? 0.0) + rate * (hi - lo);
    }
  }
  return [for (final k in minuteKeys) steps[k]];
}
