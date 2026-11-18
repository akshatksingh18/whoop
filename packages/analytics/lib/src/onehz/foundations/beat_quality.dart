import 'dart:math' as math;
import '../util.dart' show kBeatAdjacencyTolMs;

/// Reporting estimate from record HR/60 versus retained reported RR counts.
/// Unknown counts/HR have no denominator. This never qualifies or changes HRV.
Map<String, dynamic>? beatReportingQuality(List<int> hr, List<int> rrCount) {
  if (hr.isEmpty || hr.length != rrCount.length) return null;
  var expected = 0.0, reported = 0, records = 0;
  for (var i = 0; i < hr.length; i++) {
    if (hr[i] <= 0 || rrCount[i] < 0) continue;
    expected += hr[i] / 60;
    reported += rrCount[i];
    records++;
  }
  if (expected <= 0) return null;
  return {
    'omitted_beat_share_estimate': (1 - reported / expected).clamp(0.0, 1.0),
    'expected_beats_estimate': expected,
    'reported_beats': reported,
    'records_with_hr': records,
    'method': 'record HR/60 versus retained RR count; quality only'
  };
}

/// A counted spectral segment has at least 90% measured interval coverage and
/// no clock re-anchor inside it. Existing timing tolerance is used only for
/// older callers without explicit clock metadata, not as a new threshold.
bool spectralSegmentQualified(List<double> timesSec, List<double> intervalsMs,
    int lo, int hi, double startSec, double endSec,
    {List<bool> gapBefore = const [], double minCoverage = 0.90}) {
  if (endSec <= startSec || hi <= lo || timesSec.length != intervalsMs.length)
    return false;
  var covered = 0.0;
  for (var i = lo; i < hi; i++) {
    final time = timesSec[i], interval = intervalsMs[i] / 1000;
    if (!time.isFinite || !interval.isFinite || interval <= 0) return false;
    final gap = gapBefore.length == timesSec.length
        ? gapBefore[i]
        : i > 0 &&
            (time - timesSec[i - 1]) * 1000 - intervalsMs[i] >
                kBeatAdjacencyTolMs;
    if (gap && time > startSec && time < endSec) return false;
    covered += math.max(
        0, math.min(endSec, time) - math.max(startSec, time - interval));
  }
  return covered >= math.max(0.90, minCoverage) * (endSec - startSec);
}
