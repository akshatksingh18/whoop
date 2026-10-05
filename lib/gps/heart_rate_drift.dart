import 'route_models.dart';
import 'route_math.dart';
import 'workout_clock.dart';

class HeartRateDrift {
  const HeartRateDrift(
    this.earlierHr,
    this.laterHr,
    this.earlierPace,
    this.laterPace,
    this.hrCoverage,
    this.routeCoverage,
  );
  final double earlierHr,
      laterHr,
      earlierPace,
      laterPace,
      hrCoverage,
      routeCoverage;
  double get change => laterHr - earlierHr;
}

/// Observed contiguous route windows for descriptive session comparisons.
/// Pauses, sensor gaps and implausible jumps cannot establish pace coverage.
Iterable<({double start, double end, double seconds, double meters})>
activeRouteSegments(
  List<RoutePoint> route,
  WorkoutClock clock,
  DateTime end,
) sync* {
  final seconds = clock.activeSeconds(end).toDouble();
  for (var i = 1; i < route.length; i++) {
    final a = route[i - 1], b = route[i];
    final dt = (b.tsMs - a.tsMs) / 1000;
    if (b.seq != a.seq + 1 || dt <= 0 || dt > 30) continue;
    final start = DateTime.fromMillisecondsSinceEpoch(a.tsMs);
    final stop = DateTime.fromMillisecondsSinceEpoch(b.tsMs - 1);
    if (!clock.includes(start) || !clock.includes(stop)) continue;
    final activeStart = clock.secondsAt(start).toDouble();
    final activeEnd = clock.secondsAt(stop).toDouble();
    if ((activeEnd - activeStart - dt).abs() > 1 || activeStart >= seconds)
      continue;
    final m = haversineMeters(a.lat, a.lng, b.lat, b.lng);
    if (!m.isFinite || m / dt > 10) continue;
    yield (start: activeStart, end: activeEnd, seconds: dt, meters: m);
  }
}

double activeRouteCoverage(
  List<RoutePoint> route,
  WorkoutClock clock,
  DateTime end,
) {
  final total = clock.activeSeconds(end);
  if (total <= 0) return 0;
  return (activeRouteSegments(
            route,
            clock,
            end,
          ).fold<double>(0, (n, s) => n + s.end - s.start) /
          total)
      .clamp(0.0, 1.0);
}

/// Descriptive within-session comparison. No fitness, diagnosis or calorie claim.
HeartRateDrift? heartRateDrift(
  List<RoutePoint> route,
  List<double?> hr,
  WorkoutClock clock,
  DateTime end, {
  List<String> tags = const [],
}) {
  final seconds = clock.activeSeconds(end).toDouble();
  if (seconds < 1200 || tags.contains('hills') || tags.contains('treadmill'))
    return null;
  final half = seconds / 2;
  final meters = [0.0, 0.0], covered = [0.0, 0.0];
  for (final segment in activeRouteSegments(route, clock, end)) {
    for (var h = 0; h < 2; h++) {
      final from = segment.start.clamp(h * half, (h + 1) * half);
      final to = segment.end.clamp(h * half, (h + 1) * half);
      final duration = to - from;
      if (duration > 0) {
        covered[h] += duration;
        meters[h] += segment.meters * duration / segment.seconds;
      }
    }
  }
  final beats = [0.0, 0.0], hrSeconds = [0.0, 0.0];
  for (var i = 0; i < hr.length; i++) {
    final v = hr[i];
    if (v == null || !v.isFinite || v <= 0 || v > 250) continue;
    for (var h = 0; h < 2; h++) {
      final duration =
          ((i + 1) * 60.0).clamp(h * half, (h + 1) * half) -
          (i * 60.0).clamp(h * half, (h + 1) * half);
      if (duration > 0) {
        beats[h] += v * duration;
        hrSeconds[h] += duration;
      }
    }
  }
  if (covered.any((s) => s / half < .8) ||
      hrSeconds.any((s) => s / half < .8) ||
      meters.any((m) => m < 250))
    return null;
  final p0 = half * 1000 / meters[0], p1 = half * 1000 / meters[1];
  if ((p0 / p1 - 1).abs() > .05) return null;
  return HeartRateDrift(
    beats[0] / hrSeconds[0],
    beats[1] / hrSeconds[1],
    p0,
    p1,
    hrSeconds.reduce((a, b) => a < b ? a : b) / half,
    covered.reduce((a, b) => a < b ? a : b) / half,
  );
}
