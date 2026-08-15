// The activity painters, where the geometry itself is the claim.
//
// A route is the one chart whose SHAPE is the data, and an elevation profile
// is the one whose baseline is a place. Both had a way of drawing something
// the run did not do.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/charts.dart';
import 'package:openstrap_edge/ui2/paint_activity.dart';

class _Rec implements Canvas {
  final paths = <Path>[];
  final circles = <Offset>[];
  final lines = <(Offset, Offset)>[];

  @override
  void drawPath(Path p, Paint _) => paths.add(p);

  @override
  void drawCircle(Offset c, double _, Paint _) => circles.add(c);

  @override
  void drawLine(Offset a, Offset b, Paint _) => lines.add((a, b));

  @override
  dynamic noSuchMethod(Invocation i) => null;
}

void main() {
  group('RouteMap keeps the shape it was handed', () {
    test('a square box is not stretched to the card', () {
      // The caller does careful aspect work — one span for both axes plus a
      // cos(lat) correction — to land the route in a square 0…1 box. Mapping
      // dx by width and dy by height threw all of it away: on a 300×100 card
      // that is a 3:1 stretch, so the shape drawn was not the shape run.
      final rec = _Rec();
      RouteMap(const [Offset(0, 0), Offset(1, 1)], pins: false)
          .paint(rec, const Size(300, 100));
      final (a, b) = rec.lines.single;
      expect(b.dx - a.dx, closeTo(b.dy - a.dy, .001));
      // …and it is centred rather than pinned to the left edge.
      expect(a.dx, closeTo(100, .001));
      expect(b.dx, closeTo(200, .001));
    });

    test('a degenerate bounding box upstream draws nothing, not NaN', () {
      final rec = _Rec();
      RouteMap(const [Offset(double.nan, double.nan), Offset(.5, .5)])
          .paint(rec, const Size(300, 100));
      expect(rec.lines, isEmpty);
      expect(rec.circles.every((o) => o.isFinite), isTrue);
    });
  });

  group('Elevation', () {
    const size = Size(300, 100);

    test('a flat walk is not drawn as a hill starting at sea level', () {
      final rec = _Rec();
      Elevation(List.filled(20, 40.0), Colors.green).paint(rec, size);
      // The old fallback anchored the minimum to the canvas floor, so a
      // perfectly flat 40 m walk sat on the bottom edge of the card.
      expect(rec.paths.last.getBounds().top, lessThan(80));
    });

    test('a GPS dropout breaks the profile instead of spanning it', () {
      final rec = _Rec();
      Elevation(const [10.0, 20.0, double.nan, 40.0, 50.0], Colors.green)
          .paint(rec, size);
      // Two runs, each with its own area and line.
      expect(rec.paths, hasLength(4));
    });

    test('the peak marker still lands on the real maximum', () {
      final rec = _Rec();
      const axis = AxisSpec(min: 0, max: 100, format: axisInt);
      Elevation(const [10.0, 90.0, 20.0], Colors.green, axis: axis)
          .paint(rec, size);
      expect(rec.circles.first.dy, closeTo(10, .5));
    });
  });

  group('IntervalLadder', () {
    test('rounds normalised 0/0 draw nothing rather than a NaN rect', () {
      final rec = _Rec();
      expect(
          () => IntervalLadder(
                const [(work: double.nan, rest: double.nan)],
                Colors.red,
                Colors.grey,
              ).paint(rec, const Size(300, 100)),
          returnsNormally);
    });
  });
}
