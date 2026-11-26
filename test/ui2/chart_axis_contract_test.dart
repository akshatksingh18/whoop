// The optional component scale keeps the same labelled positions across lanes.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/ui2/charts.dart';

class LaneCanvas implements Canvas {
  final strokes = <(int, Rect)>[];

  @override
  void drawPath(Path path, Paint paint) =>
      strokes.add((paint.color.toARGB32(), path.getBounds()));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'upper and lower anchors use the same scale for labels and measured values',
    () {
      final axis = AxisSpec.of(
        [25, 40],
        floor: 0,
        ceil: 100,
        step: 20,
        ticks: 6,
      )!;
      expect(axis.tickValues, [100, 80, 60, 40, 20, 0]);
      expect(axis.format(axis.tickValues[2]), '60');
      expect(axis.t(25), .25);
      expect(axis.t(40), .4);
    },
  );

  test('a smaller upper anchor cannot crop a measured peak', () {
    final axis = AxisSpec.of(
      [25, 120],
      floor: 0,
      ceil: 100,
      step: 20,
      ticks: 7,
    )!;
    expect(axis.tickValues, [120, 100, 80, 60, 40, 20, 0]);
    expect(axis.t(120), 1);
    expect(AxisSpec.of([double.nan], ceil: 100), isNull);
  });

  test(
    'a fixed-axis night lane keeps gaps and leaves the second lane auto-scaled',
    () {
      final canvas = LaneCanvas();
      const axis = AxisSpec(min: 0, max: 100, format: axisInt);
      const red = Color(0xfff44336), blue = Color(0xff2196f3);
      NightStack(
        const [
          [25, 50, null, 75, 50],
          [10, 20, 30, 40, 50],
        ],
        const [red, blue],
        axes: const [axis],
      ).paint(canvas, const Size(160, 120));

      expect(canvas.strokes, [
        (red.toARGB32(), const Rect.fromLTRB(0, 31, 40, 42.5)),
        (red.toARGB32(), const Rect.fromLTRB(120, 19.5, 160, 31)),
        (blue.toARGB32(), const Rect.fromLTRB(0, 68, 160, 114)),
      ]);
    },
  );
}
