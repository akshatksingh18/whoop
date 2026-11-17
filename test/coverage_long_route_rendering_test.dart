// The same renderer consumes live and saved GPS routes. A 90-minute 1 Hz trace
// must keep its true endpoints/aspect without issuing one draw per raw fix.
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/ui2/paint_activity.dart';

class _RecordingCanvas implements Canvas {
  final lines = <(Offset, Offset, Color)>[];
  final circles = <(Offset, Color)>[];
  @override
  void drawLine(Offset a, Offset b, Paint paint) =>
      lines.add((a, b, paint.color));
  @override
  void drawCircle(Offset point, double radius, Paint paint) =>
      circles.add((point, paint.color));
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  for (final portrait in [false, true]) {
    for (final paced in [false, true]) {
      test('long ${paced ? 'saved paced' : 'live unpaced'} route '
          'keeps both endpoints in ${portrait ? 'portrait' : 'landscape'}', () {
        final points = [
          for (var i = 0; i <= 5400; i++)
            Offset(
              .1 + .8 * i / 5400,
              .2 + .6 * i / 5400 + .03 * math.sin(2 * math.pi * i / 5400),
            ),
        ];
        points[0] = const Offset(.1, .2);
        points[5400] = const Offset(.9, .8);
        final original = List<Offset>.of(points);
        final pace = paced ? [for (var i = 0; i <= 5400; i++) i / 5400] : null;
        final originalPace = pace == null ? null : List<double>.of(pace);
        final trace = _RecordingCanvas();
        final size = portrait ? const Size(70, 150) : const Size(240, 120);
        RouteMap(
          points,
          pace: pace,
          pinStart: Colors.green,
          pinEnd: Colors.red,
          pinInk: Colors.white,
          slow: Colors.blue,
          fast: Colors.orange,
        ).paint(trace, size);
        final first = portrait ? const Offset(7, 54) : const Offset(72, 24);
        final last = portrait ? const Offset(63, 96) : const Offset(168, 96);
        expect((trace.lines.first.$1 - first).distance, lessThan(.000001));
        expect((trace.lines.last.$2 - last).distance, lessThan(.000001));
        expect(
          trace.lines.length,
          inInclusiveRange(2, 1000),
          reason: 'Screen rendering must stay bounded for a full workout trace',
        );
        expect(
          trace.lines.every((line) => line.$1.isFinite && line.$2.isFinite),
          isTrue,
        );
        expect(
          trace.lines.every((line) => line.$2.dx >= line.$1.dx),
          isTrue,
          reason:
              'The authored route travels east;drawing cannot reverse its order',
        );
        expect(
          trace.circles
              .where((pin) => pin.$2.toARGB32() == Colors.green.toARGB32())
              .single
              .$1,
          first,
        );
        expect(
          trace.circles
              .where((pin) => pin.$2.toARGB32() == Colors.red.toARGB32())
              .single
              .$1,
          last,
        );
        if (paced) {
          expect(
            trace.lines.map((line) => line.$3).toSet().length,
            greaterThan(10),
          );
        } else {
          expect(
            trace.lines.every(
              (line) => line.$3.toARGB32() == Colors.blue.toARGB32(),
            ),
            isTrue,
          );
        }
        expect(points, original);
        expect(pace, originalPace);
      });
    }
  }
}
