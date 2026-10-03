// Best efforts, pace zones, the verdict and elevation gain, from synthetic
// tracks with known answers.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/gps/route_math.dart';
import 'package:openstrap_edge/gps/route_models.dart';
import 'package:openstrap_edge/gps/run_analysis.dart';

/// A straight run north at [speeds] m/s per segment, one fix per second.
List<RoutePoint> track(List<double> speeds, {List<double>? alt}) {
  const mPerDegLat = 111195.0; // haversine radius used by latlong2, close enough
  var lat = 29.9;
  final out = <RoutePoint>[
    RoutePoint(seq: 0, tsMs: 0, lat: lat, lng: -95.6, alt: alt?.first),
  ];
  for (var i = 0; i < speeds.length; i++) {
    lat += speeds[i] / mPerDegLat;
    out.add(RoutePoint(
        seq: i + 1,
        tsMs: (i + 1) * 1000,
        lat: lat,
        lng: -95.6,
        alt: alt?[i + 1]));
  }
  return out;
}

void main() {
  test('a steady 4 m/s run has a 250 s best kilometre', () {
    final pts = track(List.filled(1500, 4.0));
    final cum = cumulativeMeters(pts);
    expect(cum.last, closeTo(6000, 30));
    expect(bestEffortSeconds(pts, cum, 1000), closeTo(250, 3));
    expect(bestEffortSeconds(pts, cum, 10000), isNull);
  });

  test('the best effort finds the fast stretch, not the average', () {
    final pts = track([...List.filled(600, 3.0), ...List.filled(300, 5.0),
      ...List.filled(600, 3.0)]);
    final cum = cumulativeMeters(pts);
    // 1 km inside the 1.5 km fast stretch: 200 s.
    expect(bestEffortSeconds(pts, cum, 1000), closeTo(200, 3));
  });

  test('ranking: first, second, third, then nothing; no record without history', () {
    expect(effortRank(100, [110, 120]), 1);
    expect(effortRank(115, [110, 120]), 2);
    expect(effortRank(125, [110, 120, 122]), null);
    expect(effortRank(100, const []), isNull);
    expect(previousBest([110, 105, 120]), 105);
  });

  test('Riegel scales a 5K to a 10K by 2^1.06', () {
    expect(riegel(1800, 5000, 10000), closeTo(1800 * 2.0849, 1));
  });

  test('pace zones follow the 5K pace', () {
    const p5 = 406.0; // 6:46 /km
    expect(paceZone(406, p5), 2); // tempo
    expect(paceZone(380, p5), 3); // threshold
    expect(paceZone(470, p5), 1); // endurance
    expect(paceZone(560, p5), 0); // recovery
    expect(paceZone(340, p5), 5); // anaerobic
  });

  test('the verdict names the zone mix and the pacing', () {
    final v = runVerdict(
      zoneShares: [0.05, 0.08, 0.61, 0.23, 0.01, 0.02],
      splits: [
        for (final (i, s) in [402, 420, 452, 425, 408].indexed)
          Split(index: i + 1, meters: 1000, durationSec: s),
      ],
    );
    expect(v, startsWith('Mostly tempo (61%) and threshold (23%)'));
    expect(v, contains('even pacing'));
  });

  test('GPS altitude wander adds no climb; a real hill does', () {
    final flat = track(List.filled(600, 3.0),
        alt: [for (var i = 0; i <= 600; i++) 48 + (i % 2 == 0 ? 1.5 : -1.5)]);
    expect(elevationGain(flat), lessThan(1));
    final hill = track(List.filled(600, 3.0),
        alt: [for (var i = 0; i <= 600; i++) 40 + i * 0.05]);
    expect(elevationGain(hill), closeTo(30, 4));
  });

  test('moving time drops a standing stop', () {
    final pts = [
      ...track(List.filled(60, 3.0)),
    ];
    final last = pts.last;
    // 60 s standing still at the same spot, one fix every 3 s.
    for (var k = 1; k <= 20; k++) {
      pts.add(RoutePoint(
          seq: last.seq + k, tsMs: last.tsMs + k * 3000, lat: last.lat, lng: last.lng));
    }
    expect(movingSeconds(pts), closeTo(60, 1));
  });
}
