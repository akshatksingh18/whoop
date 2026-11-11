// The same closed-window helpers used by Progress; no goal policy changes.
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/body_log.dart';
import 'package:whoop_companion/data/goal_plan.dart';
import 'package:whoop_companion/data/goal_review.dart';
import 'package:whoop_companion/data/lift_log.dart';

LiftWorkout lift(String day, {bool empty = false}) {
  final at = DateTime.parse(day).add(const Duration(hours: 12));
  return LiftWorkout(
    id: 'authored-$day',
    startedAt: at,
    endedAt: at.add(const Duration(minutes: 20)),
    exercises: [
      LiftExercise(
        name: 'Authored press',
        loadMode: LiftLoadMode.total,
        sets: empty ? [] : [LiftSet(reps: 8, load: 100, completedAt: at)],
      ),
    ],
  );
}

void main() {
  for (final (name, date, empty, expected) in [
    ('first boundary', '2026-10-12', false, '2026-11-09'),
    ('last boundary', '2026-10-25', false, '2026-11-09'),
    ('empty session', '2026-10-20', true, '2026-11-16'),
    ('outside first half', '2026-10-11', false, '2026-11-16'),
  ]) {
    test('recomposition $name preserves actual completed-set evidence', () {
      expect(
        recompCheckDate(
          from: '2026-11-09',
          today: '2026-11-01',
          windowWeeks: 2,
          waist: const [(date: '2026-10-13', value: 33.5)],
          lifts: [lift(date, empty: empty)],
        ),
        expected,
      );
    });
  }
  test(
    'waiting on a repeated lift in the second half retains an actionable current window',
    () {
      final dates = [
        for (var i = 0; i < 60; i++)
          DateTime(2026, 9, 1 + i).toIso8601String().substring(0, 10),
      ];
      final weights = <BodyWeightRow>[
        for (final d in dates)
          (
            date: d,
            kg: 80.0,
            atTs: 1,
            unit: 'kg',
            entered: 80.0,
            source: 'authored',
            originId: null,
            historyOnly: false,
          ),
      ];
      final food = <FoodDay>[
        for (final d in dates)
          (
            date: d,
            kcal: 2400.0,
            counts: true,
            protein: 160.0,
            proteinComplete: true,
          ),
      ];
      final measures = [
        BodyMeasure(
          id: 'authored-waist',
          date: '2026-10-06',
          recordedAt: DateTime(2026, 10, 6),
          inches: {'waistNavel': 34},
        ),
      ];
      final lifts = [lift('2026-10-08')];
      final result = goalReview(
        plan: const GoalPlan(phase: GoalPhase.recomp, since: '2026-09-01'),
        today: '2026-10-30',
        weights: weights,
        food: food,
        measures: measures,
        lifts: lifts,
        steps: const [],
        sleepMin: const [],
        recovery: const [],
        sessions: const [],
        currentGoal: 2400,
        restingKcal: 1800,
      );
      expect(result.advice.verdict, GoalVerdict.needMore);
      expect(result.firstCheck, '2026-11-02');
      expect(result.advice.kcalChange, isNull);
      final needs = goalNeeds(
        result,
        today: '2026-10-30',
        weights: weights,
        food: food,
        measures: measures,
        lifts: lifts,
      );
      final requiredLift = needs.singleWhere(
        (n) => n.kind == GoalNeedKind.lift,
      );
      expect(requiredLift.state, NeedState.partly);
      expect(requiredLift.actNow, true);
      expect(requiredLift.sub, contains('Authored press'));
      expect(requiredLift.sub, contains('Oct 19'));
      expect(requiredLift.sub, contains('Nov 1'));
    },
  );
}
