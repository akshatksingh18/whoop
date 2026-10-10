// Your goal, chosen and changed by you (build 86, Akshat's request): the
// review judges progress against the phase you are in — losing fat,
// recomposition, keeping it off, gaining muscle, or strength at maintenance
// — and the pace you picked, instead of one goal written into the code.
//
// Every number here is a rate of change in the 7-day average weight, as a
// percentage of body weight per week, with the evidence it comes from in
// `fitness-goal-research.md`. The review only ever SUGGESTS; it never
// changes the calorie goal, and never suggests one below the floor (the
// larger of estimated resting energy and 1,500 kcal for men / 1,200 kcal for
// women, AHA/ACC/TOS 2013). It needs enough data first: two weeks since the
// goal last changed, and in each week of the window five or more weigh-ins
// and five fully logged food days.

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

  /// How many closed weeks each side of the comparison: fat loss and lean
  /// gain move fast enough to judge on one week against the one before;
  /// recomposition, holding and strength change slowly, so two against two
  /// (four weeks; Aragon 2017 treats four as the minimum).
  int get windowWeeks => switch (phase) {
    GoalPhase.fatLoss || GoalPhase.leanGain => 1,
    _ => 2,
  };

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
      high: 0.05,
      proteinLow: 1.6,
      proteinHigh: 2.2,
    ),
    // Holding a loss is judged against the held weight (±1.5%, inside the
    // ±3% that counts as maintenance; Stevens 2006); this rate band is only
    // what the drift should stay within.
    GoalPhase.maintain => (
      low: -0.375,
      high: 0.375,
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
        high: 0.33,
        proteinLow: 1.6,
        proteinHigh: 2.2,
      ),
      TrainingAge.advanced => (
        low: 0.1,
        high: 0.2,
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
/// enough not to overshoot. The size is convention (no trial sets it); the
/// closest anchor is Helms 2014's 25–50 g carbohydrate step.
int _step(double gapPctPerWeek, double kg) {
  // ~7,700 kcal per kg is the textbook figure (Hall 2008: it overstates the
  // deficit lean people need); it only sizes a step, never promises tissue.
  final kcal = (gapPctPerWeek.abs() / 100 * kg * 7700 / 7).round();
  final clamped = kcal.clamp(100, 250);
  return (clamped / 25).round() * 25;
}

/// A rate this far outside the band before a calorie change is suggested,
/// so one noisy fortnight does not trigger one.
const double kGoalMargin = 0.1;

/// Judge [weeklyPct] (the change in the 7-day average, % of body weight per
/// week, over the goal's window) against [plan]. [kg] is the latest 7-day
/// average, [currentGoal] the calorie goal, [restingKcal] the estimated
/// resting energy, [female] picks the minimum-intake floor,
/// [liftsBetter]/[liftsWorse] the comparable lifts, [proteinPerKg] the
/// logged average on complete-protein days, [daysOnGoal] how long since the
/// goal was set, [waistChange] inches and [kgChange] the weight change over
/// the window.
GoalAdvice goalAdvice({
  required GoalPlan plan,
  required double? weeklyPct,

  /// The fewest weigh-ins and fully logged food days in any week of the
  /// window.
  required int weighIns,
  required int foodDays,
  required double? kg,
  required double? currentGoal,
  required double? restingKcal,
  required int liftsBetter,
  required int liftsWorse,
  required double? proteinPerKg,
  double? waistChange,
  double? kgChange,
  int? daysOnGoal,
  bool female = false,
}) {
  final b = plan.band;
  final weeks = plan.windowWeeks * 2;
  final missing = <String>[
    if (daysOnGoal != null && daysOnGoal < 14)
      'two weeks on this goal (${14 - daysOnGoal} more days)',
    if (weighIns < 5) 'five or more weigh-ins in each of the last $weeks weeks',
    if (foodDays < 5)
      'five fully logged food days in each of the last $weeks weeks',
  ];
  if (missing.isNotEmpty || weeklyPct == null || kg == null) {
    return (
      verdict: GoalVerdict.needMore,
      headline:
          'Not enough to judge your ${plan.phase.title.toLowerCase()} pace yet',
      because: [
        'Needs ${missing.isEmpty ? '$weeks weeks of weigh-ins' : missing.join(' and ')}.',
      ],
      kcalChange: null,
      next: 'Weigh in most mornings and mark food days complete.',
    );
  }
  String pct(double v) => '${v >= 0 ? '+' : '−'}${v.abs().toStringAsFixed(2)}%';
  final held = plan.phase == GoalPhase.maintain ? plan.holdKg : null;
  final off = held == null ? null : (kg - held) / held * 100;
  final because = <String>[
    'Weight ${pct(weeklyPct)} a week over $weeks weeks; your '
        '${plan.phase.title.toLowerCase()} aim is ${pct(b.low)} to ${pct(b.high)}.',
    if (off != null)
      '${pct(off)} from the ${held!.toStringAsFixed(1)} kg you are holding (aim within ±1.5%).',
    if (waistChange != null)
      'Waist ${waistChange == 0 ? 'unchanged' : '${waistChange > 0 ? 'up' : 'down'} ${waistChange.abs().toStringAsFixed(2)} in'}.',
    '$liftsBetter comparable lifts better, $liftsWorse worse.',
    if (proteinPerKg != null)
      'Protein ${proteinPerKg.toStringAsFixed(1)} g/kg; aim ${b.proteinLow}–${b.proteinHigh}.',
  ];
  final proteinLow = proteinPerKg != null && proteinPerKg < b.proteinLow;
  // Lifts falling across sessions come first: a calorie cut is not the
  // answer to that, and during a cut a short break at maintenance is.
  if (liftsWorse >= 2 && liftsWorse > liftsBetter) {
    final cutting = plan.phase == GoalPhase.fatLoss;
    return (
      verdict: GoalVerdict.reviewRecovery,
      headline: 'Lifts are slipping — check sleep, protein and training first',
      because: because,
      kcalChange: cutting && weeklyPct < b.low ? 150 : null,
      next: cutting
          ? 'Eating a little more, or one to two weeks at maintenance, may help '
                'your lifts; a break does not speed fat loss but eases hunger.'
          : 'Look at sleep and protein before changing calories.',
    );
  }
  // Holding a weight: inside ±1.5% of it is on track whatever the drift.
  final inside = off != null
      ? off.abs() <= 1.5
      : weeklyPct >= b.low - kGoalMargin && weeklyPct <= b.high + kGoalMargin;
  // Gaining: a waist rising faster than about 1 cm per 2 kg is fat, not
  // muscle (convention; no validated ratio exists).
  final waistFast =
      plan.phase == GoalPhase.leanGain &&
      waistChange != null &&
      kgChange != null &&
      kgChange > 0 &&
      waistChange * 2.54 > kgChange * 0.5;
  if (inside && !waistFast) {
    final stalled =
        plan.phase == GoalPhase.recomp &&
        (daysOnGoal ?? 0) >= 56 &&
        liftsBetter == 0 &&
        (waistChange == null || waistChange >= 0);
    return (
      verdict: GoalVerdict.onTrack,
      headline: stalled
          ? 'Steady, but eight weeks without stronger lifts or a smaller waist'
          : 'On track for ${plan.phase.title.toLowerCase()}',
      because: because,
      kcalChange: null,
      next: stalled
          ? 'A dedicated fat-loss or muscle-gain phase may move things more.'
          : proteinLow
          ? 'Protein is below the aim; that is the one thing to raise.'
          : 'Keep going.',
    );
  }
  // Outside the aim. Toward the band (or the held weight).
  final double gap = off != null
      ? (off > 0 ? -1.0 : 1.0) *
            (off.abs() - 1.5) /
            4 // a month to come back
      : waistFast
      ? -(weeklyPct - b.low).abs().clamp(0.1, 1.0).toDouble()
      : (weeklyPct < b.low ? b.low : b.high) - weeklyPct;
  // Eating less while protein is short: protein first.
  if (gap < 0 && proteinLow) {
    return (
      verdict: GoalVerdict.adjust,
      headline: 'Raise protein before cutting calories',
      because: [
        ...because,
        'You are above your aim, and protein is below its range.',
      ],
      kcalChange: null,
      next:
          'Reach ${b.proteinLow} g/kg on most days, then check again in two weeks.',
    );
  }
  var change = _step(gap, kg) * (gap > 0 ? 1 : -1);
  final floor = [
    ?restingKcal,
    female ? 1200.0 : 1500.0,
  ].reduce((a, c) => a > c ? a : c);
  String? floorNote;
  if (change < 0 && currentGoal != null && currentGoal + change < floor) {
    change = (floor - currentGoal).round();
    floorNote =
        'A larger cut would go below ${floor.round()} kcal, your floor (resting energy or the minimum intake).';
    if (change >= 0) change = 0;
  }
  final direction = waistFast
      ? 'gaining waist faster than muscle explains'
      : off != null
      ? (off > 0
            ? 'above the weight you are holding'
            : 'below the weight you are holding')
      : gap > 0
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
    next: change == 0
        ? 'More steps, a break at maintenance, or ending this phase are the options left.'
        : 'Change it yourself in Food → Goals. Check again after two more weeks.',
  );
}
