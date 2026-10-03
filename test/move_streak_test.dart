// The run-or-walk streak, and the rule that hides a breathing-rate row that
// is rarely measured.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/streak.dart';
import 'package:openstrap_edge/ui2/screens/health_screen.dart'
    show breathingMeasuredOften;

void main() {
  final now = DateTime(2026, 10, 3, 18);
  MoveSession on(int daysBack, int minutes, {bool run = true, int hour = 7}) => (
        start: DateTime(now.year, now.month, now.day - daysBack, hour),
        minutes: minutes,
        run: run,
      );

  test('counts consecutive days with ten minutes or more', () {
    final s = moveStreak([on(0, 30), on(1, 12, run: false), on(2, 40)], now);
    expect(s.current, 3);
    expect(s.todayDone, isTrue);
    expect(s.last7.last, MoveDay.run);
    expect(s.last7[5], MoveDay.walk);
  });

  test('today does not break the streak until it is over', () {
    final s = moveStreak([on(1, 20), on(2, 20)], now);
    expect(s.todayDone, isFalse);
    expect(s.current, 2);
  });

  test('a day under ten minutes breaks it', () {
    final s = moveStreak([on(0, 20), on(1, 9), on(2, 20)], now);
    expect(s.current, 1);
  });

  test('two short sessions on one day add up', () {
    final s = moveStreak([on(0, 6), on(0, 5, run: false, hour: 18)], now);
    expect(s.current, 1);
  });

  test('longest is kept across a gap', () {
    final s = moveStreak([
      on(0, 15),
      for (var d = 5; d < 10; d++) on(d, 15),
    ], now);
    expect(s.current, 1);
    expect(s.longest, 5);
  });

  test('walks across a month end and a clock change count as days', () {
    final march = DateTime(2026, 3, 30, 9);
    final s = moveStreak([
      for (var d = 0; d < 5; d++)
        (start: DateTime(2026, 3, 30 - d, 9), minutes: 15, run: false),
    ], march);
    expect(s.current, 5);
  });

  test('breathing row shows only when measured on half the nights', () {
    final t = DateTime(2026, 10, 3, 12);
    ({int t, double v}) pt(int back) =>
        (t: DateTime(2026, 10, 3 - back).millisecondsSinceEpoch ~/ 1000, v: 1);
    final sleep = [for (var d = 0; d < 20; d++) pt(d)];
    expect(breathingMeasuredOften(sleep, [for (var d = 0; d < 9; d++) pt(d)], t),
        isFalse);
    expect(breathingMeasuredOften(sleep, [for (var d = 0; d < 10; d++) pt(d)], t),
        isTrue);
    expect(breathingMeasuredOften(sleep, const [], t), isFalse);
  });
}
