// Build 90: the Progress overview's one review.
//
// Everything the overview shows comes from ONE window: the goal's own closed
// weeks (one against the one before for fat loss and lean gain, two against
// two otherwise; `GoalPlan.windowWeeks`). The verdict, the Weight / Waist /
// Strength rows and the inputs line all read it, so the page can never back a
// conclusion with figures from a different period. The History range on the
// detail pages explores; it never produces a verdict.
//
// Missing evidence is named exactly: which closed week fell short, by how
// much, and what can still fix it. A closed week cannot be repaired by
// weighing in today, so the copy never says it can.

import 'dart:math' as math;

import '../compute/profile.dart' show isLiftType;
import '../gps/run_history.dart' show isRunType, isWalkType;
import 'body_log.dart';
import 'day_label.dart';
import 'goal_plan.dart';
import 'lift_log.dart';
import 'lift_progress.dart' show SetVerdict;
import 'progress_review.dart';

/// The fewest weigh-ins and fully logged food days a review week needs
/// (the same five `goalAdvice` asks for).
const int kReviewWeekMinimum = 5;

/// One closed Monday–Sunday week of the review, with what it holds.
typedef ReviewWeek = ({String from, String to, int weighIns, int foodDays});

typedef GoalReview = ({
  GoalPlan plan,

  /// Calendar days since the goal started, or null without a start date.
  int? daysOnGoal,

  /// The later and earlier halves of the review, each `windowWeeks` weeks.
  DayWindow after,
  DayWindow before,

  /// Every review week, newest first.
  List<ReviewWeek> weeks,

  /// The goal check (`goalAdvice`), with exact missing evidence when it
  /// cannot judge yet.
  GoalAdvice advice,

  /// Build 90: the earliest Monday the check can judge, assuming every week
  /// from now meets its minimum; null once it can judge (or when the reason
  /// it cannot is not the evidence count).
  String? firstCheck,

  /// Weigh-ins in each half (kg), and the change between their means.
  WeightWindow weightBefore,
  WeightWindow weightAfter,
  double? weightChangeKg,

  /// The newest waist reading on or before today — shown even when there is
  /// nothing to compare it with — and the change across the review when a
  /// reading sits near its start (within 7 days) and one in its last week.
  DatedValue? waistLatest,
  DatedValue? waistFrom,
  DatedValue? waistTo,

  /// Same-setup best sets compared across the two halves.
  List<LiftComparison> lifts,

  /// Inputs over the later half, each with its own measured count.
  FoodWindow food,
  StepsSummary steps,
  ({double? minutes, int nights}) sleep,
  ({double? pct, int days}) recovery,
  ({int total, int lift, int run, int walk, int other}) workouts,
});

typedef FoodDay = ({
  String date,
  double? kcal,
  bool counts,
  double? protein,
  bool proteinComplete,
});

String _md(String day) {
  const m = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final d = DateTime.parse(day);
  return '${m[d.month - 1]} ${d.day}';
}

/// "Oct 6–12" for a week.
String reviewWeekLabel(String from, String to) {
  final a = DateTime.parse(from), b = DateTime.parse(to);
  return a.month == b.month
      ? '${_md(from)}–${b.day}'
      : '${_md(from)}–${_md(to)}';
}

DayWindow _week(DateTime monday, int back) {
  final m = DateTime(monday.year, monday.month, monday.day - 7 * back);
  return (
    from: dayLabelOf(m),
    to: dayLabelOf(DateTime(m.year, m.month, m.day + 6)),
    days: 7,
    partial: false,
  );
}

GoalReview goalReview({
  required GoalPlan plan,
  required String today,
  required List<BodyWeightRow> weights,
  required List<BodyMeasure> measures,
  required List<LiftWorkout> lifts,
  required List<FoodDay> food,
  required List<DatedValue> steps,
  required List<DatedValue> sleepMin,
  required List<DatedValue> recovery,
  required List<({String date, String type})> sessions,
  double? currentGoal,
  double? restingKcal,
  bool female = false,
}) {
  final n = plan.windowWeeks;
  final t = DateTime.parse(today);
  final monday = DateTime(t.year, t.month, t.day - (t.weekday - 1));
  final weekWindows = [for (var i = 1; i <= 2 * n; i++) _week(monday, i)];
  final after = (
    from: weekWindows[n - 1].from,
    to: weekWindows[0].to,
    days: 7 * n,
    partial: false,
  );
  final before = (
    from: weekWindows[2 * n - 1].from,
    to: weekWindows[n].to,
    days: 7 * n,
    partial: false,
  );
  final ws = weightSeries(weights, unit: 'kg');
  final a = weightWindow(ws, after), b = weightWindow(ws, before);
  final weeks = <ReviewWeek>[
    for (final w in weekWindows)
      (
        from: w.from,
        to: w.to,
        weighIns: weightWindow(ws, w).count,
        foodDays: foodWindow(food, w).kcalDays,
      ),
  ];
  final weekly = a.mean == null || b.mean == null || b.mean == 0
      ? null
      : (a.mean! - b.mean!) / b.mean! * 100 / n;
  final fl = foodWindow(food, after);
  final kg = BodyLogDb.sevenDayMean(weights, today)?.kg;
  final cmp = liftComparisons(lifts, before, after);
  final waist = siteSeries(measures, BodySite.waistNavel);
  final waistLatest = inRange(waist, '0000-00-00', today).lastOrNull;
  // B88-08: the earlier reading within 7 days of the review's start, the
  // later one in its last week; any older reading is not this review's change.
  final wb = readingNear(waist, before.from);
  final wa = inRange(waist, weekWindows[0].from, weekWindows[0].to).lastOrNull;
  final waistPair = wa != null && wb != null && wa.date != wb.date;
  final since = plan.since == null ? null : DateTime.tryParse(plan.since!);
  final daysOnGoal = since == null
      ? null
      : DateTime.utc(
          t.year,
          t.month,
          t.day,
        ).difference(DateTime.utc(since.year, since.month, since.day)).inDays;
  var advice = goalAdvice(
    plan: plan,
    weeklyPct: weekly,
    weighIns: weeks.map((w) => w.weighIns).reduce(math.min),
    foodDays: weeks.map((w) => w.foodDays).reduce(math.min),
    kg: kg,
    currentGoal: currentGoal,
    restingKcal: restingKcal,
    liftsBetter: cmp.where((x) => x.change == SetVerdict.better).length,
    liftsWorse: cmp.where((x) => x.change == SetVerdict.worse).length,
    liftsComparable: cmp
        .where((x) => x.change != SetVerdict.incomparable)
        .length,
    proteinPerKg: fl.protein == null || kg == null ? null : fl.protein! / kg,
    proteinDays: fl.proteinDays,
    waistChange: waistPair ? wa.value - wb.value : null,
    waistFrom: waistPair ? _md(wb.date) : null,
    waistTo: waistPair ? _md(wa.date) : null,
    kgChange: a.mean == null || b.mean == null ? null : a.mean! - b.mean!,
    daysOnGoal: daysOnGoal,
    female: female,
  );
  final firstCheck = advice.verdict == GoalVerdict.needMore
      ? firstCheckDate(
          weeks: weeks,
          today: today,
          windowWeeks: n,
          since: plan.since,
          thisWeekCanQualify: thisWeekCanQualify(
            today: today,
            weights: weights,
            food: food,
          ),
        )
      : null;
  if (advice.verdict == GoalVerdict.needMore) {
    advice = _exactMissing(
      advice,
      plan: plan,
      weeks: weeks,
      firstCheck: firstCheck,
      daysOnGoal: daysOnGoal,
      waistPair: waistPair,
      before: before,
      lastWeek: weekWindows[0],
      liftsComparable: cmp
          .where((x) => x.change != SetVerdict.incomparable)
          .length,
    );
  }
  final inputs = periodInputs(
    after,
    food: food,
    steps: steps,
    sleepMin: sleepMin,
    recovery: recovery,
    sessions: sessions,
  );
  return (
    plan: plan,
    daysOnGoal: daysOnGoal,
    after: after,
    before: before,
    weeks: weeks,
    advice: advice,
    firstCheck: firstCheck,
    weightBefore: b,
    weightAfter: a,
    weightChangeKg: a.mean == null || b.mean == null ? null : a.mean! - b.mean!,
    waistLatest: waistLatest,
    waistFrom: waistPair ? wb : null,
    waistTo: waistPair ? wa : null,
    lifts: cmp,
    food: fl,
    steps: inputs.steps,
    sleep: inputs.sleep,
    recovery: inputs.recovery,
    workouts: inputs.workouts,
  );
}

// ── Build 90: one time rule for everything except the goal check ─────────

/// The last [days] days up to and including [today], and the same number of
/// days just before them. Progress's one comparison everywhere outside the
/// goal check (Akshat: "last 7 days vs the 7 days before" reads at a glance,
/// matches Trends, and never shrinks to one day on a Monday).
(DayWindow, DayWindow) rollingWindows(String today, int days) {
  final t = DateTime.parse(today);
  final after = (
    from: dayLabelOf(DateTime(t.year, t.month, t.day - (days - 1))),
    to: today,
    days: days,
    partial: false,
  );
  final before = (
    from: dayLabelOf(DateTime(t.year, t.month, t.day - (2 * days - 1))),
    to: dayLabelOf(DateTime(t.year, t.month, t.day - days)),
    days: days,
    partial: false,
  );
  return (after, before);
}

/// What went in over one window, each with its own measured count.
typedef PeriodInputs = ({
  FoodWindow food,
  StepsSummary steps,
  ({double? minutes, int nights}) sleep,
  ({double? pct, int days}) recovery,
  ({int total, int lift, int run, int walk, int other}) workouts,
});

PeriodInputs periodInputs(
  DayWindow w, {
  required List<FoodDay> food,
  required List<DatedValue> steps,
  required List<DatedValue> sleepMin,
  required List<DatedValue> recovery,
  required List<({String date, String type})> sessions,
}) {
  double? mean(List<DatedValue> v) =>
      v.isEmpty ? null : v.fold<double>(0, (s, x) => s + x.value) / v.length;
  final sl = inRange(sleepMin, w.from, w.to);
  final rc = inRange(recovery, w.from, w.to);
  final ss = [
    for (final s in sessions)
      if (s.date.compareTo(w.from) >= 0 && s.date.compareTo(w.to) <= 0) s,
  ];
  final lift = ss.where((s) => isLiftType(s.type)).length;
  final run = ss.where((s) => isRunType(s.type)).length;
  final walk = ss.where((s) => isWalkType(s.type)).length;
  return (
    food: foodWindow(food, w),
    steps: stepsSummary(inRange(steps, w.from, w.to)),
    sleep: (minutes: mean(sl), nights: sl.length),
    recovery: (pct: mean(rc), days: rc.length),
    workouts: (
      total: ss.length,
      lift: lift,
      run: run,
      walk: walk,
      other: ss.length - lift - run - walk,
    ),
  );
}

/// The overview's body and inputs over the last [days] days against the
/// [days] before (the goal check keeps its own full weeks).
typedef RollingReview = ({
  DayWindow after,
  DayWindow before,
  PeriodInputs now,
  PeriodInputs was,
  WeightWindow weightAfter,
  WeightWindow weightBefore,
  double? weightChangeKg,
  DatedValue? waistLatest,
  DatedValue? waistFrom,
  DatedValue? waistTo,
  List<LiftComparison> lifts,
});

RollingReview rollingReview({
  required String today,
  int days = 7,
  required List<BodyWeightRow> weights,
  required List<BodyMeasure> measures,
  required List<LiftWorkout> lifts,
  required List<FoodDay> food,
  required List<DatedValue> steps,
  required List<DatedValue> sleepMin,
  required List<DatedValue> recovery,
  required List<({String date, String type})> sessions,
}) {
  final (after, before) = rollingWindows(today, days);
  final ws = weightSeries(weights, unit: 'kg');
  final a = weightWindow(ws, after), b = weightWindow(ws, before);
  final waist = siteSeries(measures, BodySite.waistNavel);
  final latest = inRange(waist, '0000-00-00', today).lastOrNull;
  final wa = inRange(waist, after.from, after.to).lastOrNull;
  final wb = inRange(waist, before.from, before.to).lastOrNull;
  final pair = wa != null && wb != null && wa.date != wb.date;
  PeriodInputs inputs(DayWindow w) => periodInputs(
    w,
    food: food,
    steps: steps,
    sleepMin: sleepMin,
    recovery: recovery,
    sessions: sessions,
  );
  return (
    after: after,
    before: before,
    now: inputs(after),
    was: inputs(before),
    weightAfter: a,
    weightBefore: b,
    weightChangeKg: a.mean == null || b.mean == null ? null : a.mean! - b.mean!,
    waistLatest: latest,
    waistFrom: pair ? wb : null,
    waistTo: pair ? wa : null,
    lifts: liftComparisons(lifts, before, after),
  );
}

/// The earliest Monday the goal check can judge, if every week from now on
/// meets the minimum: the check needs 2 × [windowWeeks] closed Monday–Sunday
/// weeks that each hold [kReviewWeekMinimum] weigh-ins and fully logged food
/// days, and a goal at least 14 days old. [weeks] is newest first (the
/// review's closed weeks). Null when the closed weeks already qualify (the
/// check is waiting on something else).
///
/// Build 90 phone review: the card said "judged after two weeks (8 more
/// days)" while every one of the four review weeks was short, so no verdict
/// could come for weeks.
String? firstCheckDate({
  required List<ReviewWeek> weeks,
  required String today,
  required int windowWeeks,
  String? since,
  bool thisWeekCanQualify = true,
}) {
  final need = 2 * windowWeeks;
  var good = 0;
  for (final w in weeks) {
    if (w.weighIns < kReviewWeekMinimum || w.foodDays < kReviewWeekMinimum) {
      break;
    }
    good++;
  }
  final t = DateTime.parse(today);
  final nextMonday = DateTime(t.year, t.month, t.day + (8 - t.weekday));
  // The current week is the first of the weeks still needed, unless it can
  // no longer reach the minimum (Build 91, Codex audit F06: on a Sunday with
  // nothing logged the date came a week early). Then the run of qualifying
  // weeks starts again next Monday and needs all of them.
  final stillNeeded = need - good;
  if (stillNeeded <= 0) return null;
  var at = DateTime(
    nextMonday.year,
    nextMonday.month,
    nextMonday.day + 7 * (thisWeekCanQualify ? stillNeeded - 1 : need),
  );
  // And the goal must be 14 days old: the first Monday on or after day 14.
  final start = since == null ? null : DateTime.tryParse(since);
  if (start != null) {
    final old = DateTime(start.year, start.month, start.day + 14);
    final m = DateTime(old.year, old.month, old.day + ((8 - old.weekday) % 7));
    if (m.isAfter(at)) at = m;
  }
  return dayLabelOf(at);
}

/// Whether this Monday-to-Sunday week can still reach [kReviewWeekMinimum]
/// weigh-ins and fully logged food days: what Monday to yesterday holds plus
/// one per day left, today included. Never assumes a back-filled day.
bool thisWeekCanQualify({
  required String today,
  required List<BodyWeightRow> weights,
  required List<FoodDay> food,
}) {
  final t = DateTime.parse(today);
  final left = 8 - t.weekday; // today through Sunday
  if (t.weekday == DateTime.monday) return left >= kReviewWeekMinimum;
  final w = (
    from: dayLabelOf(DateTime(t.year, t.month, t.day - (t.weekday - 1))),
    to: dayLabelOf(DateTime(t.year, t.month, t.day - 1)),
    days: t.weekday - 1,
    partial: false,
  );
  final weighIns = weightWindow(weightSeries(weights, unit: 'kg'), w).count;
  final foodDays = foodWindow(food, w).kcalDays;
  return weighIns + left >= kReviewWeekMinimum &&
      foodDays + left >= kReviewWeekMinimum;
}

/// This Monday-to-today week's evidence for the goal check.
({int weighIns, int foodDays, int proteinDays}) thisWeekEvidence({
  required String today,
  required List<BodyWeightRow> weights,
  required List<FoodDay> food,
}) {
  final t = DateTime.parse(today);
  final monday = DateTime(t.year, t.month, t.day - (t.weekday - 1));
  final w = (
    from: dayLabelOf(monday),
    to: today,
    days: t.weekday,
    partial: true,
  );
  final f = foodWindow(food, w);
  return (
    weighIns: weightWindow(weightSeries(weights, unit: 'kg'), w).count,
    foodDays: f.kcalDays,
    proteinDays: f.proteinDays,
  );
}

/// The goal check's "not enough yet", rewritten to name each short week and
/// what can still fix it. The verdict and its rules are unchanged.
GoalAdvice _exactMissing(
  GoalAdvice advice, {
  required GoalPlan plan,
  required List<ReviewWeek> weeks,
  required String? firstCheck,
  required int? daysOnGoal,
  required bool waistPair,
  required DayWindow before,
  required DayWindow lastWeek,
  required int liftsComparable,
}) {
  final lines = <String>[];
  // Build 90: the date the check can first judge, worked out from the
  // weeks themselves (it said "judged after two weeks" while every review
  // week was short).
  if (firstCheck != null) {
    lines.add(
      'First check ${_md(firstCheck)}, if every week from now has '
      '$kReviewWeekMinimum weigh-ins and $kReviewWeekMinimum fully logged food days.',
    );
  }
  for (final w in weeks.reversed) {
    final label = reviewWeekLabel(w.from, w.to);
    if (w.weighIns < kReviewWeekMinimum) {
      lines.add('$label: ${w.weighIns} of $kReviewWeekMinimum weigh-ins.');
    }
    if (w.foodDays < kReviewWeekMinimum) {
      lines.add(
        '$label: ${w.foodDays} of $kReviewWeekMinimum fully logged food days.',
      );
    }
  }
  if (plan.phase == GoalPhase.recomp) {
    if (!waistPair) {
      final from = DateTime.parse(before.from);
      String day(int d) =>
          _md(dayLabelOf(DateTime(from.year, from.month, from.day + d)));
      lines.add(
        'Waist: needs a reading between ${day(-7)} and ${day(7)}, and one in '
        '${reviewWeekLabel(lastWeek.from, lastWeek.to)}.',
      );
    }
    if (liftsComparable == 0) {
      lines.add(
        'Strength: needs the same lift, on the same setup, logged in both halves.',
      );
    }
  }
  if (lines.isEmpty) return advice;
  final shortWeeks = weeks.any(
    (w) => w.weighIns < kReviewWeekMinimum || w.foodDays < kReviewWeekMinimum,
  );
  final recomp = plan.phase == GoalPhase.recomp;
  final next = [
    if (shortWeeks)
      'Those weeks are closed. If you weighed in or ate and did not log it, '
          'add the real entry for that day; otherwise the review judges again '
          'once the coming weeks are complete.',
    if (recomp && !waistPair)
      'Measure your waist each week, so every review has a reading near its '
          'start and one in its last week.',
    if (recomp && liftsComparable == 0)
      'Log your lifts on the same setup each week.',
    if (!shortWeeks && daysOnGoal != null && daysOnGoal < 14)
      'Keep logging; the first review comes after two weeks on this goal.',
  ];
  return (
    verdict: advice.verdict,
    headline: advice.headline,
    because: lines,
    kcalChange: null,
    next: next.isEmpty ? advice.next : next.join(' '),
  );
}
