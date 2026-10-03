// What a run is made of, worked out from its recorded track: best efforts,
// a pace curve, pace zones, and a one-line verdict. Pure functions of the
// points, no database and no clock, so every rule here is directly testable.
//
// Nothing is guessed. A best effort exists only when the run covered the
// distance; a pace zone split exists only when there is a 5K pace to scale
// it against; the verdict only names what the numbers show.

import 'dart:math' as math;

import 'route_math.dart';
import 'route_models.dart';

/// The standard best-effort distances, shortest first: (label, metres).
const kBestEffortDistances = <(String, double)>[
  ('400m', 400),
  ('1/2 mile', kMetersPerMile / 2),
  ('1K', 1000),
  ('1 mile', kMetersPerMile),
  ('2 mile', kMetersPerMile * 2),
  ('5K', 5000),
  ('10K', 10000),
  ('Half marathon', 21097.5),
];

/// Cumulative distance in metres at each point, with the same teleport filter
/// the headline distance uses, so efforts and the headline agree.
List<double> cumulativeMeters(List<RoutePoint> raw) {
  final pts = smoothTrack(raw);
  final out = List<double>.filled(pts.length, 0);
  for (var i = 1; i < pts.length; i++) {
    final m = haversineMeters(
        pts[i - 1].lat, pts[i - 1].lng, pts[i].lat, pts[i].lng);
    out[i] = out[i - 1] +
        (isImplausibleSegment(m, pts[i].tsMs - pts[i - 1].tsMs) ? 0 : m);
  }
  return out;
}

/// The fastest time, in seconds, over any stretch of exactly [meters] inside
/// the run, or null when the run is shorter than that.
///
/// The start of each stretch is interpolated between fixes, so an effort is
/// not rounded to whichever fix happened to land near its start.
double? bestEffortSeconds(
    List<RoutePoint> pts, List<double> cum, double meters) {
  if (pts.length < 2 || cum.last < meters) return null;
  double? best;
  var i = 0;
  for (var j = 1; j < pts.length; j++) {
    final target = cum[j] - meters;
    if (target < 0) continue;
    while (i + 1 < j && cum[i + 1] <= target) {
      i++;
    }
    final span = cum[i + 1] - cum[i];
    final frac = span <= 0 ? 0.0 : ((target - cum[i]) / span).clamp(0.0, 1.0);
    final startMs = pts[i].tsMs + (pts[i + 1].tsMs - pts[i].tsMs) * frac;
    final sec = (pts[j].tsMs - startMs) / 1000;
    if (sec > 0 && (best == null || sec < best)) best = sec;
  }
  return best;
}

/// Every standard best effort this run covered: label → seconds.
Map<String, double> bestEfforts(List<RoutePoint> pts) {
  final cum = cumulativeMeters(pts);
  return {
    for (final (label, m) in kBestEffortDistances)
      label: ?bestEffortSeconds(pts, cum, m),
  };
}

/// Where this run's effort ranks among the same effort in [earlier] runs:
/// 1 = fastest ever, 2 = second best, 3 = third. Null when it is outside the
/// top three, or when nothing earlier ran that distance (a first effort is
/// not called a record).
int? effortRank(double seconds, Iterable<double> earlier) {
  final list = earlier.toList();
  if (list.isEmpty) return null;
  final faster = list.where((s) => s < seconds).length;
  return faster < 3 ? faster + 1 : null;
}

/// The fastest earlier effort, for "1:05 faster than your best".
double? previousBest(Iterable<double> earlier) =>
    earlier.isEmpty ? null : earlier.reduce(math.min);

/// A predicted time over [toMeters] from an effort of [seconds] over
/// [fromMeters] (Riegel, exponent 1.06). Used to scale pace zones and to show
/// predicted 5K/10K times; it is a projection, labelled as one.
double riegel(double seconds, double fromMeters, double toMeters) =>
    seconds * math.pow(toMeters / fromMeters, 1.06);

/// One point of the pace curve: seconds from the start, pace in seconds per
/// km (null while standing still), and metres covered.
typedef PacePoint = ({double tSec, double? paceSecPerKm, double meters});

/// Pace through the run, smoothed over a [windowSec] window either side so
/// single-fix GPS noise does not draw spikes, thinned to at most [maxPoints].
List<PacePoint> paceCurve(List<RoutePoint> pts,
    {double windowSec = 15, int maxPoints = 300}) {
  if (pts.length < 2) return const [];
  final cum = cumulativeMeters(pts);
  final t0 = pts.first.tsMs;
  final step = math.max(1, pts.length ~/ maxPoints);
  final out = <PacePoint>[];
  var lo = 0, hi = 0;
  for (var k = 0; k < pts.length; k += step) {
    final t = pts[k].tsMs;
    while (lo < k && pts[lo].tsMs < t - windowSec * 1000) {
      lo++;
    }
    if (hi < k) hi = k;
    while (hi + 1 < pts.length && pts[hi + 1].tsMs <= t + windowSec * 1000) {
      hi++;
    }
    final dt = (pts[hi].tsMs - pts[lo].tsMs) / 1000;
    final dm = cum[hi] - cum[lo];
    final speed = dt <= 0 ? 0.0 : dm / dt;
    out.add((
      tSec: (t - t0) / 1000,
      // Below 1.2 m/s (about 14 min/km) is standing or walking to a stop,
      // not a pace worth drawing.
      paceSecPerKm: speed < 1.2 ? null : 1000 / speed,
      meters: cum[k],
    ));
  }
  return out;
}

/// The six pace zones, scaled to a 5K pace. Bounds are pace as a fraction of
/// 5K pace (lower is faster): Z6 below 0.867, Z5 to 0.924, Z4 to 0.985,
/// Z3 to 1.10, Z2 to 1.276, Z1 above.
const kPaceZoneNames = [
  'Recovery', 'Endurance', 'Tempo', 'Threshold', 'VO2 max', 'Anaerobic',
];
const _paceZoneBounds = [1.276, 1.10, 0.985, 0.924, 0.867];

int paceZone(double paceSecPerKm, double fiveKPaceSecPerKm) {
  final r = paceSecPerKm / fiveKPaceSecPerKm;
  for (var z = 0; z < _paceZoneBounds.length; z++) {
    if (r > _paceZoneBounds[z]) return z;
  }
  return 5;
}

/// The pace bounds of each zone, slowest first, in seconds per km:
/// (faster edge, slower edge), null meaning open-ended.
List<(double?, double?)> paceZoneBounds(double fiveKPace) => [
      for (var z = 0; z < 6; z++)
        (
          z == 5 ? null : fiveKPace * _paceZoneBounds[z],
          z == 0 ? null : fiveKPace * _paceZoneBounds[z - 1],
        ),
    ];

/// Share of moving time in each of the six pace zones, Z1 first.
List<double> paceZoneShares(List<PacePoint> curve, double fiveKPace) {
  final secs = List<double>.filled(6, 0);
  for (var k = 1; k < curve.length; k++) {
    final pace = curve[k].paceSecPerKm;
    if (pace == null) continue;
    secs[paceZone(pace, fiveKPace)] += curve[k].tSec - curve[k - 1].tSec;
  }
  final total = secs.fold<double>(0, (a, b) => a + b);
  return total <= 0 ? secs : [for (final s in secs) s / total];
}

/// One plain sentence about the run, built from fixed rules: the zone mix,
/// how even the splits were, and how the finish compared with the start.
/// Null when there is too little to say anything.
String? runVerdict({
  required List<double> zoneShares,
  required List<Split> splits,
}) {
  final parts = <String>[];
  if (zoneShares.any((s) => s > 0)) {
    final order = [for (var z = 0; z < 6; z++) z]
      ..sort((a, b) => zoneShares[b].compareTo(zoneShares[a]));
    final top = order.first, second = order[1];
    String pct(int z) => '${(zoneShares[z] * 100).round()}%';
    final name = kPaceZoneNames[top].toLowerCase();
    parts.add(zoneShares[second] >= 0.15
        ? 'Mostly $name (${pct(top)}) and '
            '${kPaceZoneNames[second].toLowerCase()} (${pct(second)})'
        : 'Mostly $name (${pct(top)})');
  }
  final full = [
    for (final s in splits)
      if (s.meters >= kMetersPerKm * 0.99) s.durationSec,
  ];
  if (full.length >= 3) {
    final spread = full.reduce(math.max) - full.reduce(math.min);
    parts.add(spread <= 30
        ? 'very even pacing'
        : spread <= 60
            ? 'even pacing'
            : 'uneven pacing (${spread}s between fastest and slowest km)');
    final firstHalf = full.sublist(0, full.length ~/ 2);
    final lastHalf = full.sublist(full.length - full.length ~/ 2);
    double avg(List<int> v) => v.reduce((a, b) => a + b) / v.length;
    final diff = avg(lastHalf) - avg(firstHalf);
    if (diff <= -5) {
      parts.add('faster second half');
    } else if (diff >= 10) {
      parts.add('slowed in the second half');
    }
  }
  if (parts.isEmpty) return null;
  final s = parts.join(', ');
  return '${s[0].toUpperCase()}${s.substring(1)}.';
}

/// Elevation gain in metres with the altitude smoothed over [windowSec] and a
/// [deadbandM] hysteresis, because raw GPS altitude wanders several metres
/// standing still and summing that wander invents a hill.
double? elevationGain(List<RoutePoint> pts,
    {double windowSec = 30, double deadbandM = 3}) {
  final alt = [for (final p in pts) p.alt];
  if (pts.length < 2 || alt.any((a) => a == null)) return null;
  final smooth = <double>[];
  var lo = 0, hi = 0;
  var sum = 0.0;
  for (var k = 0; k < pts.length; k++) {
    while (hi < pts.length && pts[hi].tsMs <= pts[k].tsMs + windowSec * 500) {
      sum += alt[hi]!;
      hi++;
    }
    while (pts[lo].tsMs < pts[k].tsMs - windowSec * 500) {
      sum -= alt[lo]!;
      lo++;
    }
    smooth.add(sum / (hi - lo));
  }
  var gain = 0.0;
  var anchor = smooth.first;
  for (final a in smooth.skip(1)) {
    if (a - anchor >= deadbandM) {
      gain += a - anchor;
      anchor = a;
    } else if (anchor - a >= deadbandM) {
      anchor = a;
    }
  }
  return gain;
}
