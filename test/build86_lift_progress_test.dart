// In-workout progress (build 86): same-setup comparisons only, an estimate
// used for ranking and never shown as a true max, and plain verdicts.
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/lift_log.dart';
import 'package:openstrap_edge/data/lift_progress.dart';

LiftSet s(double load, int reps) =>
    LiftSet(reps: reps, load: load, completedAt: DateTime(2026, 9, 1));

LiftWorkout w(
  DateTime at,
  List<LiftSet> sets, {
  LiftLoadMode mode = LiftLoadMode.perHand,
  String note = '',
  String name = 'Incline press',
}) => LiftWorkout(
  startedAt: at,
  endedAt: at.add(const Duration(hours: 1)),
  exercises: [
    LiftExercise(name: name, loadMode: mode, equipmentNote: note, sets: sets),
  ],
);

void main() {
  test('the estimate ranks heavier and longer sets on one scale', () {
    expect(setScore(s(40, 10))! > setScore(s(40, 8))!, isTrue);
    expect(setScore(s(45, 6)), closeTo(54, 1e-9));
    expect(setScore(s(0, 12)), isNull, reason: 'no load: compare reps');
    expect(setScore(s(30, 15)), isNull, reason: 'too many reps to estimate');
    expect(
      bestSet([s(40, 8), s(45, 6), s(40, 10)]).load,
      45,
      reason: '45 x 6 (54) beats 40 x 10 (53.3)',
    );
  });

  test('history keeps only the same exercise, load meaning and equipment', () {
    final today = LiftExercise(
      name: 'incline press',
      loadMode: LiftLoadMode.perHand,
    );
    final h = exerciseHistory(today, [
      w(DateTime(2026, 9, 1), [s(40, 8)]),
      w(DateTime(2026, 9, 5), [s(40, 9)], mode: LiftLoadMode.stack),
      w(DateTime(2026, 9, 8), [s(40, 9)], note: 'Smith'),
      w(DateTime(2026, 9, 12), [s(40, 10)]),
    ]);
    expect([for (final x in h) x.date.day], [12, 1]);
  });

  test('trend: up, stalled for three sessions, or too few', () {
    final today = LiftExercise(
      name: 'Incline press',
      loadMode: LiftLoadMode.perHand,
    );
    List<ExerciseSession> hist(List<List<LiftSet>> sessions) =>
        exerciseHistory(today, [
          for (var i = 0; i < sessions.length; i++)
            w(DateTime(2026, 9, 1 + i), sessions[i]),
        ]);
    expect(
      liftTrend(
        hist([
          [s(40, 8)],
        ]),
      ).trend,
      LiftTrend.tooFew,
    );
    expect(
      liftTrend(
        hist([
          [s(40, 8)],
          [s(40, 9)],
          [s(42.5, 8)],
        ]),
      ).trend,
      LiftTrend.up,
    );
    final stalled = liftTrend(
      hist([
        [s(40, 10)],
        [s(40, 9)],
        [s(40, 10)],
        [s(40, 9)],
      ]),
    );
    expect(stalled.trend, LiftTrend.flat);
    expect(stalled.text, contains('No new best in your last 3 sessions'));
  });

  test('today against last time, set by set, and the set to beat', () {
    final last = LiftExercise(
      name: 'Row',
      sets: [s(60, 8), s(60, 8), s(60, 7)],
    );
    final today = LiftExercise(name: 'Row', sets: [s(60, 9), s(60, 8)]);
    final v = versusLast(today, last)!;
    expect(v.verdict, SetVerdict.better);
    expect(v.text, 'Ahead of last time on 1 of 2 sets (+1 reps)');
    expect(nextToBeat(today, last), startsWith('Set 3 to beat: 60 × 7.'));
    final behind = LiftExercise(name: 'Row', sets: [s(55, 8)]);
    expect(versusLast(behind, last)!.verdict, SetVerdict.worse);
    expect(
      compareSet(s(65, 6), s(60, 8)),
      SetVerdict.better,
      reason: '65 × 6 estimates above 60 × 8',
    );
    expect(versusLast(LiftExercise(name: 'Row'), last), isNull);
  });

  test('records: the heaviest load at each rep count', () {
    final today = LiftExercise(name: 'Row', loadMode: LiftLoadMode.perHand);
    final h = exerciseHistory(today, [
      w(DateTime(2026, 9, 1), [s(50, 8), s(55, 6)], name: 'Row'),
      w(DateTime(2026, 9, 4), [s(52.5, 8)], name: 'Row'),
    ]);
    final r = repRecords(h);
    expect([for (final x in r) '${x.reps}:${x.load}'], ['6:55.0', '8:52.5']);
  });
}
