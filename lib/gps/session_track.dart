import 'route_models.dart';
import 'route_math.dart';
import 'workout_clock.dart';

/// Clip valid route segments to active windows, preserving gaps and inserting
/// boundary points only inside measured segments (never across a GPS gap).
List<RoutePoint> activeTrack(
  List<RoutePoint> points,
  WorkoutClock clock, {
  DateTime? until,
}) {
  final out = <RoutePoint>[];
  var seq = 0;
  RoutePoint copy(RoutePoint p, int number) => RoutePoint(
    seq: number,
    tsMs: p.tsMs,
    lat: p.lat,
    lng: p.lng,
    alt: p.alt,
    accuracy: p.accuracy,
    speed: p.speed,
  );
  RoutePoint? boundary(int ms) {
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1], b = points[i];
      if (ms <= a.tsMs || ms >= b.tsMs || routeBreak(a, b)) continue;
      final f = (ms - a.tsMs) / (b.tsMs - a.tsMs);
      return RoutePoint(
        seq: a.seq,
        tsMs: ms,
        lat: a.lat + (b.lat - a.lat) * f,
        lng: a.lng + (b.lng - a.lng) * f,
        alt: a.alt == null || b.alt == null
            ? null
            : a.alt! + (b.alt! - a.alt!) * f,
        accuracy: b.accuracy,
        speed: b.speed,
      );
    }
    return null;
  }

  for (final w in clock.windows(until)) {
    seq++;
    final lo = w.start.millisecondsSinceEpoch,
        hi = w.end.millisecondsSinceEpoch;
    final first = boundary(lo), last = boundary(hi);
    final selected = [
      ?first,
      for (final p in points)
        if (p.tsMs >= lo && p.tsMs <= hi) p,
      ?last,
    ];
    RoutePoint? previous;
    for (final p in selected) {
      if (previous != null &&
          (p.seq > previous.seq + 1 ||
              isImplausibleSegment(
                haversineMeters(previous.lat, previous.lng, p.lat, p.lng),
                p.tsMs - previous.tsMs,
              ))) {
        seq++;
      }
      out.add(copy(p, seq++));
      previous = p;
    }
  }
  return out;
}
