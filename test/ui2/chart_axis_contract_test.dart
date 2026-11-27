// The optional component scale keeps the same labelled positions across lanes.
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/ui2/charts.dart';

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
}
