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
      : DateTime.utc(t.year, t.month, t.day)
            .difference(DateTime.utc(since.year, since.month, since.day))
            .inDays;
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
  if (advice.verdict == GoalVerdict.needMore) {
    advice = _exactMissing(
      advice,
      plan: plan,
      weeks: weeks,
      daysOnGoal: daysOnGoal,
      waistPair: waistPair,
      before: before,
      lastWeek: weekWindows[0],
      liftsComparable:
          cmp.where((x) => x.change != SetVerdict.incomparable).length,
    );
  }
  double? mean(List<DatedValue> v) =>
      v.isEmpty ? null : v.fold<double>(0, (s, x) => s + x.value) / v.length;
  final sl = inRange(sleepMin, after.from, after.to);
  final rc = inRange(recovery, after.from, after.to);
  final ss = [
    for (final s in sessions)
      if (s.date.compareTo(after.from) >= 0 && s.date.compareTo(after.to) <= 0)
        s,
  ];
  final lift = ss.where((s) => isLiftType(s.type)).length;
  final run = ss.where((s) => isRunType(s.type)).length;
  final walk = ss.where((s) => isWalkType(s.type)).length;
  return (
    plan: plan,
    daysOnGoal: daysOnGoal,
    after: after,
    before: before,
    weeks: weeks,
    advice: advice,
    weightBefore: b,
    weightAfter: a,
    weightChangeKg: a.mean == null || b.mean == null ? null : a.mean! - b.mean!,
    waistLatest: waistLatest,
    waistFrom: waistPair ? wb : null,
    waistTo: waistPair ? wa : null,
    lifts: cmp,
    food: fl,
    steps: stepsSummary(inRange(steps, after.from, after.to)),
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

/// The goal check's "not enough yet", rewritten to name each short week and
/// what can still fix it. The verdict and its rules are unchanged.
GoalAdvice _exactMissing(
  GoalAdvice advice, {
  required GoalPlan plan,
  required List<ReviewWeek> weeks,
  required int? daysOnGoal,
  required bool waistPair,
  required DayWindow before,
  required DayWindow lastWeek,
  required int liftsComparable,
}) {
  final lines = <String>[];
  if (daysOnGoal != null && daysOnGoal < 14) {
    final left = 14 - daysOnGoal;
    lines.add(
      'This goal is $daysOnGoal ${daysOnGoal == 1 ? 'day' : 'days'} old; '
      'it is judged after two weeks ($left more ${left == 1 ? 'day' : 'days'}).',
    );
  }
  for (final w in weeks.reversed) {
    final label = reviewWeekLabel(w.from, w.to);
    if (w.weighIns < kReviewWeekMinimum) {
      lines.add(
        '$label: ${w.weighIns} of $kReviewWeekMinimum weigh-ins.',
      );
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
  return (
    verdict: advice.verdict,
    headline: advice.headline,
    because: lines,
    kcalChange: null,
    next: shortWeeks
        ? 'Those weeks are closed. If you weighed in or ate and did not log '
              'it, add the real entry for that day; otherwise the review '
              'judges again once the coming weeks are complete.'
        : advice.next,
  );
}
