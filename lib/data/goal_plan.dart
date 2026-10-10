// Your goal, chosen and changed by you (build 86, Akshat's request): the
// review judges progress against the phase you are in — losing fat,
// recomposition, keeping it off, gaining muscle, or strength at maintenance
// — and the pace you picked, instead of one goal written into the code.
//
// Every number here is a rate of change in the 7-day average weight, as a
// percentage of body weight per week, with the evidence it comes from in
// `fitness-goal-research.md`. The review only ever SUGGESTS; it never
// changes the calorie goal, and never suggests one below estimated resting
// energy. It needs enough data first: two closed weeks with at least four
// weigh-ins each and five fully logged food days each.

import 'dart:convert';

import 'calculation_store.dart';

enum GoalPhase { fatLoss, recomp, maintain, leanGain, strength }

enum GoalPace { gentle, moderate, faster }

enum TrainingAge { novice, intermediate, advanced }

extension GoalPhaseText on GoalPhase {
  String get title => switch (this) {
    GoalPhase.fatLoss => 'Lose fat',
    GoalPhase.recomp => 'Recomposition',
    GoalPhase.maintain => 'Keep it off',
    GoalPhase.leanGain => 'Build muscle',
    GoalPhase.strength => 'Get stronger at this weight',
  };

  String get plain => switch (this) {
    GoalPhase.fatLoss =>
      'Lose fat steadily while keeping your strength. Weight comes down each week.',
    GoalPhase.recomp =>
      'Leaner and stronger at roughly the same weight: waist down, lifts up.',
    GoalPhase.maintain =>
      'Hold the weight you reached, within a small band, while you keep training.',
    GoalPhase.leanGain =>
      'Add muscle with as little fat as possible: weight goes up slowly.',
    GoalPhase.strength =>
      'Weight holds steady; the measure is your lifts going up.',
  };
}

extension GoalPaceText on GoalPace {
  String get title => switch (this) {
    GoalPace.gentle => 'Gentle',
    GoalPace.moderate => 'Moderate',
    GoalPace.faster => 'Faster',
  };
}

extension TrainingAgeText on TrainingAge {
  String get title => switch (this) {
    TrainingAge.novice => 'Under a year of steady lifting',
    TrainingAge.intermediate => 'One to three years',
    TrainingAge.advanced => 'More than three years',
  };
}

/// The weekly change band a goal aims for, in % of body weight per week
/// (negative is loss), and the protein range it asks for, g per kg.
typedef GoalBand = ({
  double low,
  double high,
  double proteinLow,
  double proteinHigh,
});

class GoalPlan {
  const GoalPlan({
    required this.phase,
    this.pace = GoalPace.moderate,
    this.trainingAge = TrainingAge.intermediate,
    this.since,
    this.holdKg,
  });

  final GoalPhase phase;
  final GoalPace pace;
  final TrainingAge trainingAge;

  /// The day this phase started; reviews compare from here.
  final String? since;

  /// For Keep it off: the weight to hold. Null takes the 7-day average on
  /// the day the phase started.
  final double? holdKg;

  static const key = 'goal.plan';

  /// What the review aims for.
  GoalBand get band => switch (phase) {
    // Helms 2014 and Garthe 2011: about 0.5–1% a week keeps lean mass and
    // performance best; faster loss costs more of both.
    GoalPhase.fatLoss => switch (pace) {
      GoalPace.gentle => (
        low: -0.5,
        high: -0.25,
        proteinLow: 1.8,
        proteinHigh: 2.4,
      ),
      GoalPace.moderate => (
        low: -0.75,
        high: -0.5,
        proteinLow: 1.8,
        proteinHigh: 2.4,
      ),
      GoalPace.faster => (
        low: -1.0,
        high: -0.75,
        proteinLow: 2.0,
        proteinHigh: 2.6,
      ),
    },
    // Recomposition (Barakat 2020): weight roughly stable or drifting
    // slightly down; the evidence is waist and strength, not the scale.
    GoalPhase.recomp => (
      low: -0.25,
      high: 0.1,
      proteinLow: 1.6,
      proteinHigh: 2.2,
    ),
    // Holding a loss: a small band either side, judged on the 7-day mean.
    GoalPhase.maintain => (
      low: -0.15,
      high: 0.15,
      proteinLow: 1.6,
      proteinHigh: 2.2,
    ),
    // Lean gain (Iraki 2019; practitioner guidance by training age): the
    // less trained, the faster muscle can be added.
    GoalPhase.leanGain => switch (trainingAge) {
      TrainingAge.novice => (
        low: 0.25,
        high: 0.5,
        proteinLow: 1.6,
        proteinHigh: 2.2,
      ),
      TrainingAge.intermediate => (
        low: 0.15,
        high: 0.3,
        proteinLow: 1.6,
        proteinHigh: 2.2,
      ),
      TrainingAge.advanced => (
        low: 0.05,
        high: 0.15,
        proteinLow: 1.6,
        proteinHigh: 2.2,
      ),
    },
    GoalPhase.strength => (
      low: -0.15,
      high: 0.15,
      proteinLow: 1.6,
      proteinHigh: 2.2,
    ),
  };

  Map<String, Object?> toJson() => {
    'phase': phase.name,
    'pace': pace.name,
    'trainingAge': trainingAge.name,
    'since': ?since,
    'holdKg': ?holdKg,
  };

  static GoalPlan? fromJson(Map m) {
    try {
      return GoalPlan(
        phase: GoalPhase.values.byName(m['phase'] as String),
        pace: GoalPace.values.byName(m['pace'] as String? ?? 'moderate'),
        trainingAge: TrainingAge.values.byName(
          m['trainingAge'] as String? ?? 'intermediate',
        ),
        since: m['since'] as String?,
        holdKg: (m['holdKg'] as num?)?.toDouble(),
      );
    } catch (_) {
      return null;
    }
  }

  /// The saved goal; recomposition (the goal Akshat started with) until one
  /// is chosen.
  static Future<GoalPlan> read() async {
    try {
      final raw = await CalculationStore.read(key);
      if (raw != null) {
        final g = fromJson(jsonDecode(raw) as Map);
        if (g != null) return g;
      }
    } catch (_) {}
    return const GoalPlan(phase: GoalPhase.recomp);
  }

  static Future<bool> isChosen() async =>
      await CalculationStore.read(key) != null;

  static Future<void> save(GoalPlan g) =>
      CalculationStore.write(key, jsonEncode(g.toJson()));
}

// ── the suggestion ──────────────────────────────────────────────────────────

enum GoalVerdict {
  /// Not enough data yet: says which.
  needMore,

  /// Inside the band, with lifts holding or better.
  onTrack,

  /// Faster than the band in the goal's direction (losing too fast, gaining
  /// too fast), or moving the wrong way.
  adjust,

  /// Lifts slipping across comparable sessions: food, sleep and training
  /// together come before any calorie change.
  reviewRecovery,
}

typedef GoalAdvice = ({
  GoalVerdict verdict,
  String headline,
  List<String> because,

  /// A suggested change to the daily calorie goal (kcal, signed), or null.
  /// Never applied by the app.
  int? kcalChange,
  String? next,
});

/// Steps of 100–250 kcal a day: big enough to move the weekly rate, small
/// enough not to overshoot (practitioner convention, MacroFactor/SBS).
int _step(double gapPctPerWeek, double kg) {
  // ~7,700 kcal per kg of weight change is the textbook approximation; it is
  // used only to size a step, never as a promise about tissue.
  final kcal = (gapPctPerWeek.abs() / 100 * kg * 7700 / 7).round();
  final clamped = kcal.clamp(100, 250);
  return (clamped / 25).round() * 25;
}

/// Judge [weeklyPct] (the change in the 7-day average, % of body weight per
/// week, over two closed weeks) against [plan]. [kg] is the latest 7-day
/// average, [currentGoal] the calorie goal, [restingKcal] the estimated
/// resting energy (the floor), [liftsBetter]/[liftsWorse] the comparable
/// lifts, [proteinPerKg] the logged average on complete-protein days.
GoalAdvice goalAdvice({
  required GoalPlan plan,
  required double? weeklyPct,

  /// The fewer of the two weeks' weigh-ins, and of their fully logged days.
  required int weighIns,
  required int foodDays,
  required double? kg,
  required double? currentGoal,
  required double? restingKcal,
  required int liftsBetter,
  required int liftsWorse,
  required double? proteinPerKg,
  double? waistChange,
}) {
  final b = plan.band;
  final missing = <String>[
    if (weighIns < 4) 'four or more weigh-ins in each of two weeks',
    if (foodDays < 5) 'five fully logged food days in each of two weeks',
  ];
  if (missing.isNotEmpty || weeklyPct == null || kg == null) {
    return (
      verdict: GoalVerdict.needMore,
      headline:
          'Not enough to judge your ${plan.phase.title.toLowerCase()} pace yet',
      because: [
        'Needs ${missing.isEmpty ? 'two weeks of weigh-ins' : missing.join(' and ')}.',
      ],
      kcalChange: null,
      next: 'Weigh in most mornings and mark food days complete.',
    );
  }
  String pct(double v) => '${v >= 0 ? '+' : '−'}${v.abs().toStringAsFixed(2)}%';
  final because = <String>[
    'Weight ${pct(weeklyPct)} a week; your ${plan.phase.title.toLowerCase()} '
        'aim is ${pct(b.low)} to ${pct(b.high)}.',
    if (waistChange != null)
      'Waist ${waistChange == 0 ? 'unchanged' : '${waistChange > 0 ? 'up' : 'down'} ${waistChange.abs().toStringAsFixed(2)} in'}.',
    '$liftsBetter comparable lifts better, $liftsWorse worse.',
    if (proteinPerKg != null)
      'Protein ${proteinPerKg.toStringAsFixed(1)} g/kg; aim ${b.proteinLow}–${b.proteinHigh}.',
  ];
  // Lifts falling across sessions come first: a calorie change is not the
  // first answer to that.
  if (liftsWorse >= 2 && liftsWorse > liftsBetter) {
    return (
      verdict: GoalVerdict.reviewRecovery,
      headline: 'Lifts are slipping — check sleep, protein and training first',
      because: because,
      kcalChange: plan.phase == GoalPhase.fatLoss && weeklyPct < b.low
          ? 150
          : null,
      next: plan.phase == GoalPhase.fatLoss && weeklyPct < b.low
          ? 'You are losing faster than planned; eating a little more may help your lifts.'
          : 'Look at sleep and protein before changing calories.',
    );
  }
  final proteinLow = proteinPerKg != null && proteinPerKg < b.proteinLow;
  if (weeklyPct >= b.low && weeklyPct <= b.high) {
    return (
      verdict: GoalVerdict.onTrack,
      headline: 'On track for ${plan.phase.title.toLowerCase()}',
      because: because,
      kcalChange: null,
      next: proteinLow
          ? 'Protein is below the aim; that is the one thing to raise.'
          : 'Keep going.',
    );
  }
  // Outside the band: suggest moving the calorie goal toward it.
  final target = weeklyPct < b.low ? b.low : b.high;
  final gap = target - weeklyPct; // positive: eat more; negative: eat less
  var change = _step(gap, kg) * (gap > 0 ? 1 : -1);
  String? floorNote;
  if (change < 0 &&
      currentGoal != null &&
      restingKcal != null &&
      currentGoal + change < restingKcal) {
    change = (restingKcal - currentGoal).round();
    floorNote =
        'A larger cut would take you below your estimated resting energy.';
    if (change >= 0) change = 0;
  }
  final direction = gap > 0
      ? (plan.phase == GoalPhase.fatLoss
            ? 'losing faster than planned'
            : 'below your aim')
      : (plan.phase == GoalPhase.leanGain
            ? 'gaining faster than planned'
            : 'above your aim');
  return (
    verdict: GoalVerdict.adjust,
    headline: change == 0
        ? 'Outside your aim, and the calorie goal is already at its floor'
        : 'Consider ${change > 0 ? 'raising' : 'lowering'} your calorie goal by ${change.abs()} kcal',
    because: [...because, 'You are $direction.', ?floorNote],
    kcalChange: change == 0 ? null : change,
    next:
        'Change it yourself in Food → Goals. Check again after two more weeks.',
  );
}
