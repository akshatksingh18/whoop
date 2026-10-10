// Flexible goals (build 86): the phase you choose sets the aim; the review
// suggests and never applies, waits for enough data, and never suggests a
// calorie goal below resting energy.
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/goal_plan.dart';

GoalAdvice advise(
  GoalPlan g, {
  double? weekly = 0,
  int weighIns = 6,
  int foodDays = 6,
  double kg = 80,
  double? goal = 2300,
  double? resting = 1800,
  int better = 1,
  int worse = 0,
  double? protein = 1.8,
}) => goalAdvice(
  plan: g,
  weeklyPct: weekly,
  weighIns: weighIns,
  foodDays: foodDays,
  kg: kg,
  currentGoal: goal,
  restingKcal: resting,
  liftsBetter: better,
  liftsWorse: worse,
  proteinPerKg: protein,
);

void main() {
  test('each phase has its own aim, in the direction it says', () {
    expect(const GoalPlan(phase: GoalPhase.fatLoss).band.high, lessThan(0));
    expect(const GoalPlan(phase: GoalPhase.leanGain).band.low, greaterThan(0));
    final recomp = const GoalPlan(phase: GoalPhase.recomp).band;
    expect(recomp.low, lessThan(0));
    expect(recomp.high, greaterThanOrEqualTo(0));
    expect(
      const GoalPlan(
        phase: GoalPhase.leanGain,
        trainingAge: TrainingAge.novice,
      ).band.high,
      greaterThan(
        const GoalPlan(
          phase: GoalPhase.leanGain,
          trainingAge: TrainingAge.advanced,
        ).band.high,
      ),
      reason: 'a novice can add muscle faster',
    );
  });

  test('a goal round-trips and defaults to recomposition', () {
    const g = GoalPlan(
      phase: GoalPhase.fatLoss,
      pace: GoalPace.faster,
      since: '2026-10-10',
    );
    final back = GoalPlan.fromJson(g.toJson())!;
    expect(back.phase, GoalPhase.fatLoss);
    expect(back.pace, GoalPace.faster);
    expect(back.since, '2026-10-10');
    expect(GoalPlan.fromJson({'phase': 'nonsense'}), isNull);
  });

  test('too little data asks for more instead of judging', () {
    final a = advise(const GoalPlan(phase: GoalPhase.fatLoss), weighIns: 2);
    expect(a.verdict, GoalVerdict.needMore);
    expect(a.kcalChange, isNull);
  });

  test('fat loss: on pace, too slow, too fast', () {
    const g = GoalPlan(phase: GoalPhase.fatLoss);
    expect(advise(g, weekly: -0.6).verdict, GoalVerdict.onTrack);
    final slow = advise(g, weekly: 0.0);
    expect(slow.verdict, GoalVerdict.adjust);
    expect(slow.kcalChange, lessThan(0));
    expect(slow.kcalChange!.abs(), inInclusiveRange(100, 250));
    final fast = advise(g, weekly: -1.6);
    expect(fast.kcalChange, greaterThan(0));
  });

  test('never suggests going below resting energy', () {
    final a = advise(
      const GoalPlan(phase: GoalPhase.fatLoss),
      weekly: 0.2,
      goal: 1850,
      resting: 1800,
    );
    expect(a.kcalChange, -50);
    final floor = advise(
      const GoalPlan(phase: GoalPhase.fatLoss),
      weekly: 0.2,
      goal: 1800,
      resting: 1800,
    );
    expect(floor.kcalChange, isNull);
    expect(floor.headline, contains('floor'));
  });

  test('lean gain: gaining too fast suggests eating a little less', () {
    final a = advise(const GoalPlan(phase: GoalPhase.leanGain), weekly: 0.9);
    expect(a.verdict, GoalVerdict.adjust);
    expect(a.kcalChange, lessThan(0));
  });

  test('slipping lifts come before any calorie change', () {
    final a = advise(
      const GoalPlan(phase: GoalPhase.recomp),
      weekly: -0.1,
      better: 0,
      worse: 3,
    );
    expect(a.verdict, GoalVerdict.reviewRecovery);
    expect(a.kcalChange, isNull);
  });

  test('on track with low protein names protein', () {
    final a = advise(
      const GoalPlan(phase: GoalPhase.maintain),
      weekly: 0,
      protein: 1.1,
    );
    expect(a.verdict, GoalVerdict.onTrack);
    expect(a.next, contains('Protein'));
  });

  test('two weeks on a new goal before any judgement', () {
    final a = goalAdvice(
      plan: const GoalPlan(phase: GoalPhase.fatLoss),
      weeklyPct: 0.3,
      weighIns: 7,
      foodDays: 7,
      kg: 80,
      currentGoal: 2300,
      restingKcal: 1800,
      liftsBetter: 1,
      liftsWorse: 0,
      proteinPerKg: 2.0,
      daysOnGoal: 5,
    );
    expect(a.verdict, GoalVerdict.needMore);
  });

  test('protein comes before a calorie cut', () {
    final a = advise(
      const GoalPlan(phase: GoalPhase.fatLoss),
      weekly: 0.2,
      protein: 1.2,
    );
    expect(a.verdict, GoalVerdict.adjust);
    expect(a.kcalChange, isNull);
    expect(a.headline, contains('protein'));
  });

  test('keep it off is judged against the weight you hold', () {
    GoalAdvice hold(double kg) => goalAdvice(
      plan: const GoalPlan(phase: GoalPhase.maintain, holdKg: 80),
      weeklyPct: 0.2,
      weighIns: 6,
      foodDays: 6,
      kg: kg,
      currentGoal: 2400,
      restingKcal: 1800,
      liftsBetter: 1,
      liftsWorse: 0,
      proteinPerKg: 1.8,
    );
    expect(
      hold(80.8).verdict,
      GoalVerdict.onTrack,
      reason: '+1% is inside ±1.5%',
    );
    final over = hold(82.4);
    expect(over.verdict, GoalVerdict.adjust);
    expect(over.kcalChange, lessThan(0));
  });

  test('a waist rising faster than weight explains flags fat gain', () {
    final a = goalAdvice(
      plan: const GoalPlan(phase: GoalPhase.leanGain),
      weeklyPct: 0.3,
      weighIns: 6,
      foodDays: 6,
      kg: 80,
      currentGoal: 2900,
      restingKcal: 1800,
      liftsBetter: 1,
      liftsWorse: 0,
      proteinPerKg: 1.8,
      waistChange: 0.5,
      kgChange: 0.6,
    );
    expect(a.verdict, GoalVerdict.adjust);
    expect(a.kcalChange, lessThan(0));
  });

  test('the minimum-intake floor applies when resting energy is lower', () {
    final a = goalAdvice(
      plan: const GoalPlan(phase: GoalPhase.fatLoss),
      weeklyPct: 0.3,
      weighIns: 6,
      foodDays: 6,
      kg: 60,
      currentGoal: 1300,
      restingKcal: 1250,
      liftsBetter: 1,
      liftsWorse: 0,
      proteinPerKg: 2.0,
      female: true,
    );
    expect(
      a.kcalChange,
      -50,
      reason: 'down to 1,250 resting energy, above 1,200',
    );
  });
}
