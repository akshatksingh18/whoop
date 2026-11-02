// Actual stored-day chart and active-track seams used by route readers.
// Authored locations only; no platform GPS, provider traffic or native claim.
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/gps/route_models.dart';
import 'package:whoop_companion/gps/route_math.dart';
import 'package:whoop_companion/gps/session_track.dart';
import 'package:whoop_companion/gps/workout_clock.dart';

final start = DateTime.utc(2026, 8, 1);
DateTime at(int seconds) => start.add(Duration(seconds: seconds));
RoutePoint point(int seconds, {int? seq, double? alt = 10}) => RoutePoint(
  seq: seq ?? seconds ~/ 10,
  tsMs: at(seconds).millisecondsSinceEpoch,
  lat: seconds * .000001,
  lng: seconds * .000002,
  alt: alt,
  accuracy: 3,
  speed: 2,
);

void main() {
  tearDown(() => DayClock.install([], []));

  test(
    'pause inside two measured segments inserts exact bounded endpoints',
    () {
      final points = [for (var s = 0; s <= 40; s += 10) point(s)];
      final clock = WorkoutClock(
        'authored',
        at(5),
        end: at(35),
        pauses: [(start: at(15), end: at(25))],
      );
      final track = activeTrack(points, clock);
      expect(
        track.map((p) => p.tsMs),
        [5, 10, 15, 25, 30, 35].map((s) => at(s).millisecondsSinceEpoch),
      );
      expect(track.first.lat, closeTo(.000005, 1e-12));
      expect(track.first.lng, closeTo(.000010, 1e-12));
      expect(track.first.alt, 10);
      expect(track.first.accuracy, 3);
      expect(track.first.speed, 2);
      expect(
        routeBreak(track[2], track[3]),
        isTrue,
        reason: 'Pause stays a chart gap',
      );
      expect(routeBreak(track[0], track[1]), isFalse);
      expect(points.map((p) => p.seq), [0, 1, 2, 3, 4]);
      expect(clock.activeSeconds(), 20);
    },
  );

  test(
    'a missing endpoint altitude stays unknown in interpolated boundaries',
    () {
      final track = activeTrack([
        point(0),
        point(10, alt: null),
      ], WorkoutClock('a', at(2), end: at(8)));
      expect(track.map((p) => p.tsMs), [
        at(2).millisecondsSinceEpoch,
        at(8).millisecondsSinceEpoch,
      ]);
      expect(track.every((p) => p.alt == null), isTrue);
    },
  );

  for (final gap in ['sequence', 'time', 'teleport']) {
    test('$gap gaps never supply invented pause or end points', () {
      final a = point(0);
      final b = switch (gap) {
        'sequence' => point(20, seq: 9),
        'time' => point(120, seq: 1),
        _ => RoutePoint(
          seq: 1,
          tsMs: at(20).millisecondsSinceEpoch,
          lat: 10,
          lng: 10,
        ),
      };
      final track = activeTrack([a, b], WorkoutClock('a', at(5), end: at(15)));
      expect(routeBreak(a, b), isTrue);
      expect(track, isEmpty);
    });
  }

  test(
    'a live until bound clips once without changing the clock or source points',
    () {
      final clock = WorkoutClock('a', at(0));
      final points = [point(0), point(10), point(20)];
      final track = activeTrack(points, clock, until: at(15));
      expect(
        track.map((p) => p.tsMs),
        [0, 10, 15].map((s) => at(s).millisecondsSinceEpoch),
      );
      expect(clock.end, isNull);
      expect(points.length, 3);
      expect(activeTrack([], clock, until: at(15)), isEmpty);
    },
  );

  for (final c in [
    ('2026-03-08', 'America/Chicago', 23),
    ('2026-11-01', 'America/Chicago', 25),
    ('2026-08-01', 'Asia/Kolkata', 24),
  ]) {
    test(
      'stored ${c.$2} ${c.$1} chart uses local noon on its ${c.$3}-hour day',
      () {
        final lo = dayZoneCalendarStart(c.$1, c.$2)!;
        final date = DateTime.parse(c.$1);
        final next = dayLabelOf(DateTime(date.year, date.month, date.day + 1));
        final hi = dayZoneCalendarStart(next, c.$2)!;
        DayClock.install([
          DayZone(
            date: c.$1,
            zoneId: c.$2,
            startSec: lo,
            endSec: hi,
            startOffsetSec: 0,
            endOffsetSec: 0,
          ),
        ], []);
        final anchor = dayChartAnchorSec(c.$1);
        expect(hi - lo, c.$3 * 3600);
        expect(anchor, inInclusiveRange(lo, hi - 1));
        expect(DayClock.localAt(anchor!).hour, 12);
        expect(DayClock.chartAnchor('2099-01-01'), isNull);
      },
    );
  }

  test(
    'a travel-truncated day anchors inside its real interval instead of absent noon',
    () {
      final lo = dayZoneCalendarStart('2026-08-01', 'UTC')! + 18 * 3600;
      DayClock.install([
        DayZone(
          date: '2026-08-01',
          zoneId: 'UTC',
          startSec: lo,
          endSec: lo + 7200,
          startOffsetSec: 0,
          endOffsetSec: 0,
        ),
      ], []);
      expect(dayChartAnchorSec('2026-08-01'), lo + 3600);
      DayClock.install([
        DayZone(
          date: 'not-a-date',
          zoneId: 'UTC',
          startSec: lo,
          endSec: lo + 7200,
          startOffsetSec: 0,
          endOffsetSec: 0,
        ),
      ], []);
      expect(DayClock.chartAnchor('not-a-date'), isNull);
    },
  );
}
