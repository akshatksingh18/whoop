// Existing advisory policies only: no formula, floor, band or intake changes.
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/body_log.dart';
import 'package:whoop_companion/data/goal_plan.dart';
import 'package:whoop_companion/data/goal_review.dart';
import 'package:whoop_companion/data/lift_log.dart';
import 'package:whoop_companion/data/lift_progress.dart' show SetVerdict;

GoalAdvice advice({
  GoalPhase phase = GoalPhase.recomp,
  int days = 56,
  int better = 0,
  int worse = 0,
  double weekly = 0,
  double? waist = 0,
  String? waistFrom,
  String? waistTo,
}) => goalAdvice(
  plan: GoalPlan(phase: phase),
  weeklyPct: weekly,
  weighIns: 7,
  foodDays: 7,
  kg: 80,
  currentGoal: 2400,
  restingKcal: 1800,
  liftsBetter: better,
  liftsWorse: worse,
  liftsComparable: 1,
  proteinPerKg: 2,
  proteinDays: 7,
  waistChange: waist,
  waistFrom: waistFrom,
  waistTo: waistTo,
  daysOnGoal: days,
);

void main() {
  for (final days in [55, 56, 57]) {
    test(
      'recomposition names a stalled observation only at eight weeks: $days days',
      () {
        final a = advice(days: days);
        expect(a.verdict, GoalVerdict.onTrack);
        expect(a.kcalChange, isNull);
        expect(a.headline.contains('eight weeks'), days >= 56);
        expect(a.next, days >= 56 ? contains('dedicated') : 'Keep going.');
        expect(a.because.join(' '), contains('Waist unchanged'));
        expect(a.because.join(' '), isNot(contains('fat gained')));
      },
    );
  }
  for (final (better, waist) in [(1, 0.0), (0, -0.25)]) {
    test(
      'a stronger lift or smaller waist remains progress after eight weeks: $better/$waist',
      () {
        final a = advice(better: better, waist: waist);
        expect(a.headline, 'On track for recomposition');
        expect(a.kcalChange, isNull);
        expect(a.next, 'Keep going.');
      },
    );
  }
  test(
    'a fast cut with slipping lifts suggests recovery before any further cut',
    () {
      final a = advice(phase: GoalPhase.fatLoss, weekly: -1.0, worse: 3);
      expect(a.verdict, GoalVerdict.reviewRecovery);
      expect(a.kcalChange, 150);
      expect(a.next, contains('one to two weeks at maintenance'));
      expect(a.next, contains('does not speed fat loss'));
    },
  );
  for (final dates in [false, true]) {
    test(
      'waist evidence ${dates ? 'retains its two dates' : 'does not invent dates'}',
      () {
        final a = advice(
          waist: -0.25,
          waistFrom: dates ? 'Sep 14' : null,
          waistTo: dates ? 'Oct 8' : null,
        );
        expect(a.because.join(' '), contains('Waist down 0.25 in'));
        expect(a.because.join(' ').contains('(Sep 14 to Oct 8)'), dates);
        expect(a.kcalChange, isNull);
      },
    );
  }

  for (final (load, verdict, expected) in [
    (110.0, SetVerdict.better, GoalVerdict.onTrack),
    (90.0, SetVerdict.worse, GoalVerdict.onTrack),
    (100.0, SetVerdict.same, GoalVerdict.onTrack),
  ]) {
    test(
      'the complete goal review uses its exact closed-week waist and comparable lift: $verdict',
      () {
        final dates = [
          for (var i = 0; i < 28; i++)
            DateTime(2026, 9, 14 + i).toIso8601String().substring(0, 10),
        ];
        LiftWorkout lift(String date, double weight) {
          final at = DateTime.parse(date).add(const Duration(hours: 12));
          return LiftWorkout(
            id: 'authored-$date',
            startedAt: at,
            endedAt: at.add(const Duration(minutes: 30)),
            exercises: [
              LiftExercise(
                name: 'Authored press',
                loadMode: LiftLoadMode.total,
                sets: [LiftSet(reps: 8, load: weight, completedAt: at)],
              ),
            ],
          );
        }

        final r = goalReview(
          plan: const GoalPlan(phase: GoalPhase.recomp, since: '2026-08-01'),
          today: '2026-10-14',
          weights: [
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
          ],
          measures: [
            for (final (date, inches) in [
              ('2026-09-14', 33.0),
              ('2026-10-08', 32.5),
            ])
              BodyMeasure(
                id: 'authored-$date',
                date: date,
                recordedAt: DateTime.parse(date),
                inches: {BodySite.waistNavel.name: inches},
              ),
          ],
          lifts: [lift('2026-09-16', 100), lift('2026-10-07', load)],
          food: [
            for (final d in dates)
              (
                date: d,
                kcal: 2400.0,
                counts: true,
                protein: 160.0,
                proteinComplete: true,
              ),
          ],
          steps: const [],
          sleepMin: const [],
          recovery: const [],
          sessions: const [],
          currentGoal: 2400,
          restingKcal: 1800,
        );
        expect(r.before.from, '2026-09-14');
        expect(r.after.to, '2026-10-11');
        expect(r.waistFrom!.date, '2026-09-14');
        expect(r.waistTo!.date, '2026-10-08');
        expect(r.lifts.single.change, verdict);
        expect(r.advice.because.join(' '), contains('(Sep 14 to Oct 8)'));
        expect(r.advice.verdict, expected);
        expect(r.firstCheck, isNull);
        expect(r.advice.kcalChange, isNull);
      },
    );
  }
}
