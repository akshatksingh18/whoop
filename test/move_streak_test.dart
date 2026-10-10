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
        kind: run ? MoveKind.run : MoveKind.walk,
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
        (start: DateTime(2026, 3, 30 - d, 9), minutes: 15, kind: MoveKind.walk),
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

  group('build 86: lifting counts, and protected days keep continuity', () {
    test('a ten-minute lift earns the day and shows as a lift', () {
      final s = moveStreak([
        (start: DateTime(2026, 10, 3, 7), minutes: 45, kind: MoveKind.lift),
        (start: DateTime(2026, 10, 2, 7), minutes: 20, kind: MoveKind.other),
      ], now);
      expect(s.current, 2);
      expect(s.last7.last, MoveDay.lift);
      expect(s.last7[5], MoveDay.other);
    });

    test('a protected day bridges the streak but is not an activity day', () {
      final s = moveStreak(
        [on(0, 30), on(2, 30), on(3, 30)],
        now,
        protectedDays: {'2026-10-02': Protection.rest},
      );
      expect(s.current, 3, reason: 'three activity days');
      expect(s.protectedInStreak, 1);
      expect(s.last7[5], MoveDay.rest);
      expect(s.longest, 3);
    });

    test('an unprotected gap still breaks it', () {
      final s = moveStreak([on(0, 30), on(2, 30)], now);
      expect(s.current, 1);
    });

    test('allowance: no two in a row, two per seven, one Life happens', () {
      expect(
        protectionRefusal({'2026-10-02': Protection.rest}, '2026-10-03', Protection.rest),
        isNotNull,
      );
      expect(
        protectionRefusal({'2026-09-29': Protection.rest}, '2026-10-02', Protection.rest),
        isNull,
      );
      expect(
        protectionRefusal(
          {'2026-09-28': Protection.rest, '2026-09-30': Protection.rest},
          '2026-10-02',
          Protection.rest,
        ),
        isNotNull,
      );
      expect(
        protectionRefusal({'2026-09-29': Protection.life}, '2026-10-02', Protection.life),
        isNotNull,
      );
      expect(
        protectionRefusal({'2026-09-20': Protection.life}, '2026-10-02', Protection.life),
        isNull,
      );
    });

    test('meditation and chores are not exercise; a dog walk is', () {
      expect(isExerciseType('meditation'), isFalse);
      expect(isExerciseType('housework'), isFalse);
      expect(isExerciseType('dog_walking'), isTrue);
      expect(isExerciseType('weight_training'), isTrue);
    });
  });
}
