// The Progress page's numbers (build 86): one local review model over dated
// records the app already keeps — weigh-ins, tape sessions, lift logs, food
// days, steps, sleep and recovery. Every figure carries its own dates and
// counts; a missing family is reported missing, never zero, and nothing here
// claims muscle gained, fat lost or a cause.
//
// The review answers "what does the evidence suggest?" with deterministic
// templates: gather more evidence, continue, or review fueling/recovery/
// training together. A numeric intake adjustment is NOT suggested: its size,
// window and coverage rules need Akshat's approval first (fitness-app-plan.md).

import 'dart:math' as math;

import 'body_log.dart';
import 'day_label.dart';
import 'lift_log.dart';

/// The range menu on Progress.
enum ProgressRange {
  week('1 week', 7),
  month('1 month', 30),
  twoMonths('2 months', 61),
  threeMonths('3 months', 91),
  sixMonths('6 months', 182),
  year('1 year', 365),
  sinceStart('Since start', null),
  all('All', null);

  const ProgressRange(this.label, this.days);
  final String label;
  final int? days;

  /// Inclusive first day for [today], given the journey [baseline] and the
  /// [earliest] record. Explicit calendar boundaries, one policy everywhere.
  String from(String today, {String? baseline, String? earliest}) {
    if (this == sinceStart) return baseline ?? earliest ?? today;
    if (this == all) return earliest ?? today;
    final t = DateTime.parse(today);
    return dayLabelOf(DateTime(t.year, t.month, t.day - (days! - 1)));
  }
}

/// What the measurement menu can show.
sealed class ProgressMetric {
  const ProgressMetric();
  String get label;
  String get unit;
}

class WeightMetric extends ProgressMetric {
  const WeightMetric(this.unit);
  @override
  final String unit;
  @override
  String get label => 'Weight';
}

class StepsMetric extends ProgressMetric {
  const StepsMetric();
  @override
  String get label => 'Steps';
  @override
  String get unit => 'steps';
}

class SiteMetric extends ProgressMetric {
  const SiteMetric(this.site);
  final BodySite site;
  @override
  String get label => site.title;
  @override
  String get unit => 'in';
}

/// One dated observation for a chart or summary.
typedef DatedValue = ({String date, double value});

/// Start / Latest / Change for a body metric over a range, each with its
/// actual date. Null when the range holds no reading.
typedef BodySummary = ({
  DatedValue start,
  DatedValue latest,
  double change,
  int count,
});

BodySummary? bodySummary(List<DatedValue> inRange) {
  if (inRange.isEmpty) return null;
  final s = [...inRange]..sort((a, b) => a.date.compareTo(b.date));
  return (
    start: s.first,
    latest: s.last,
    change: s.last.value - s.first.value,
    count: s.length,
  );
}

/// Steps over a range: total, days measured and their average. A day with no
/// measurement is not a zero-step day.
typedef StepsSummary = ({double total, int days, double? average});

StepsSummary stepsSummary(List<DatedValue> inRange) {
  final measured = inRange.where((d) => d.value.isFinite).toList();
  final total = measured.fold<double>(0, (a, d) => a + d.value);
  return (
    total: total,
    days: measured.length,
    average: measured.isEmpty ? null : total / measured.length,
  );
}

List<DatedValue> weightSeries(List<BodyWeightRow> all, {String unit = 'kg'}) =>
    [
      for (final w in all)
        (date: w.date, value: unit == 'lb' ? w.kg * kLbPerKg : w.kg),
    ];

List<DatedValue> siteSeries(List<BodyMeasure> all, BodySite site) => [
  for (final m in all)
    if (m.value(site) != null) (date: m.date, value: m.value(site)!),
]..sort((a, b) => a.date.compareTo(b.date));

List<DatedValue> inRange(List<DatedValue> s, String from, String to) => [
  for (final d in s)
    if (d.date.compareTo(from) >= 0 && d.date.compareTo(to) <= 0) d,
];

// ── windows ────────────────────────────────────────────────────────────────

typedef DayWindow = ({String from, String to, int days, bool partial});

/// The last CLOSED Monday–Sunday week before [today] (any weekday), and the
/// one before it.
(DayWindow, DayWindow) closedWeeks(String today) {
  final t = DateTime.parse(today);
  final thisMonday = DateTime(t.year, t.month, t.day - (t.weekday - 1));
  DayWindow week(int back) {
    final m = DateTime(
      thisMonday.year,
      thisMonday.month,
      thisMonday.day - 7 * back,
    );
    final s = DateTime(m.year, m.month, m.day + 6);
    return (from: dayLabelOf(m), to: dayLabelOf(s), days: 7, partial: false);
  }

  return (week(1), week(2));
}

/// The current week so far (partial) and the matching elapsed days of the
/// week before, for a like-for-like partial comparison.
(DayWindow, DayWindow) currentWeekSoFar(String today) {
  final t = DateTime.parse(today);
  final monday = DateTime(t.year, t.month, t.day - (t.weekday - 1));
  final n = t.weekday;
  final prevMonday = DateTime(monday.year, monday.month, monday.day - 7);
  return (
    (from: dayLabelOf(monday), to: today, days: n, partial: true),
    (
      from: dayLabelOf(prevMonday),
      to: dayLabelOf(
        DateTime(prevMonday.year, prevMonday.month, prevMonday.day + n - 1),
      ),
      days: n,
      partial: true,
    ),
  );
}

/// The last complete calendar month before [today] and the one before it,
/// with their real day counts (28–31 are not the same length).
(DayWindow, DayWindow) closedMonths(String today) {
  final t = DateTime.parse(today);
  DayWindow month(int back) {
    final first = DateTime(t.year, t.month - back, 1);
    final last = DateTime(t.year, t.month - back + 1, 0);
    return (
      from: dayLabelOf(first),
      to: dayLabelOf(last),
      days: last.day,
      partial: false,
    );
  }

  return (month(1), month(2));
}

// ── comparisons inside a window ────────────────────────────────────────────

/// The weigh-ins of a window: mean of the actual readings, how many, and the
/// first and last reading with their dates. A single reading is not a trend.
typedef WeightWindow = ({
  double? mean,
  int count,
  DatedValue? first,
  DatedValue? last,
});

WeightWindow weightWindow(List<DatedValue> series, DayWindow w) {
  final r = inRange(series, w.from, w.to);
  return (
    mean: r.isEmpty
        ? null
        : r.fold<double>(0, (a, d) => a + d.value) / r.length,
    count: r.length,
    first: r.isEmpty ? null : r.first,
    last: r.isEmpty ? null : r.last,
  );
}

/// Food inside a window, each with its own denominator: calorie days that
/// count toward averages, complete-protein days, and how many days of the
/// window those are. Unknown food is not zero intake.
typedef FoodWindow = ({
  double? kcal,
  int kcalDays,
  double? protein,
  int proteinDays,
  int windowDays,
});

FoodWindow foodWindow(
  List<
    ({
      String date,
      double? kcal,
      bool counts,
      double? protein,
      bool proteinComplete,
    })
  >
  days,
  DayWindow w,
) {
  final inW = [
    for (final d in days)
      if (d.date.compareTo(w.from) >= 0 && d.date.compareTo(w.to) <= 0) d,
  ];
  final k = [
    for (final d in inW)
      if (d.counts && d.kcal != null) d.kcal!,
  ];
  final pr = [
    for (final d in inW)
      if (d.counts && d.proteinComplete && d.protein != null) d.protein!,
  ];
  double? mean(List<double> v) =>
      v.isEmpty ? null : v.reduce((a, b) => a + b) / v.length;
  return (
    kcal: mean(k),
    kcalDays: k.length,
    protein: mean(pr),
    proteinDays: pr.length,
    windowDays: w.days,
  );
}

/// One exercise's comparable progress between two windows: the best set by
/// load then reps in each, only for the same name, load meaning and
/// equipment note. Absent when either window lacks it.
typedef LiftComparison = ({
  String exercise,
  LiftLoadMode mode,
  LiftSet before,
  LiftSet after,
  int direction, // 1 better, 0 same, -1 worse
});

List<LiftComparison> liftComparisons(
  List<LiftWorkout> finished,
  DayWindow before,
  DayWindow after,
) {
  Map<String, (LiftExercise, LiftSet)> bestIn(DayWindow w) {
    final out = <String, (LiftExercise, LiftSet)>{};
    for (final x in finished) {
      final d = dayLabelOf(x.startedAt);
      if (d.compareTo(w.from) < 0 || d.compareTo(w.to) > 0) continue;
      for (final e in x.exercises) {
        final k =
            '${liftNameKey(e.name)}|${e.loadMode.name}|${liftNameKey(e.equipmentNote)}';
        for (final s in e.sets) {
          final cur = out[k];
          if (cur == null ||
              s.load > cur.$2.load ||
              (s.load == cur.$2.load && s.reps > cur.$2.reps)) {
            out[k] = (e, s);
          }
        }
      }
    }
    return out;
  }

  final a = bestIn(before), b = bestIn(after);
  return [
    for (final k in b.keys)
      if (a[k] case final pa?)
        (
          exercise: b[k]!.$1.name,
          mode: b[k]!.$1.loadMode,
          before: pa.$2,
          after: b[k]!.$2,
          direction: _compare(pa.$2, b[k]!.$2),
        ),
  ];
}

int _compare(LiftSet a, LiftSet b) {
  if (b.load > a.load && b.reps >= a.reps) return 1;
  if (b.load == a.load && b.reps > a.reps) return 1;
  if (b.load == a.load && b.reps == a.reps) return 0;
  if (b.load < a.load && b.reps <= a.reps) return -1;
  if (b.load == a.load && b.reps < a.reps) return -1;
  return 0; // heavier for fewer reps, or lighter for more: not comparable
}

// ── the review ─────────────────────────────────────────────────────────────

enum ReviewState { gatherEvidence, keepGoing, reviewTogether }

typedef Review = ({
  ReviewState state,
  String headline,
  List<String> because,
  String? next,
});

/// The evidence-qualified review of a pair of windows for the stated goal
/// (recomposition: leaner while getting stronger). It never asks for a lower
/// weight every week, never cuts intake by default and never diagnoses.
Review review({
  required WeightWindow weightBefore,
  required WeightWindow weightAfter,
  required double? waistChange,
  required FoodWindow food,
  required List<LiftComparison> lifts,
  required int sessionsAfter,
}) {
  final missing = <String>[];
  if (weightBefore.count < 3 || weightAfter.count < 3) {
    missing.add('at least three weigh-ins in each period');
  }
  if (food.kcalDays < 4) missing.add('food logged on four or more days');
  if (lifts.isEmpty) missing.add('the same lift logged in both periods');
  if (missing.isNotEmpty) {
    return (
      state: ReviewState.gatherEvidence,
      headline: 'Not enough to compare yet',
      because: ['Needs ${missing.join(', ')}.'],
      next: missing.first == 'at least three weigh-ins in each period'
          ? 'Weigh in on more mornings.'
          : missing.first.startsWith('food')
          ? 'Log every meal on more days, or mark the day incomplete.'
          : 'Log your sets in the Lift workout.',
    );
  }
  final better = lifts.where((l) => l.direction > 0).length;
  final worse = lifts.where((l) => l.direction < 0).length;
  final dw = weightAfter.mean! - weightBefore.mean!;
  final pct = dw / weightBefore.mean! * 100;
  final because = <String>[
    'Average weight ${dw >= 0 ? 'up' : 'down'} ${dw.abs().toStringAsFixed(1)} '
        '(${pct.abs().toStringAsFixed(1)}%) on ${weightAfter.count} vs '
        '${weightBefore.count} weigh-ins.',
    if (waistChange != null)
      'Waist ${waistChange == 0 ? 'unchanged' : '${waistChange > 0 ? 'up' : 'down'} ${waistChange.abs().toStringAsFixed(2)} in'} between its measured dates.',
    '$better of ${lifts.length} comparable lifts better, $worse worse.',
    '$sessionsAfter workouts; food on ${food.kcalDays} of ${food.windowDays} days.',
  ];
  if (worse >= 2 && worse > better) {
    return (
      state: ReviewState.reviewTogether,
      headline: 'Lifts slipped — look at food, sleep and training together',
      because: because,
      next: 'Check protein coverage and recent sleep before changing anything.',
    );
  }
  return (
    state: ReviewState.keepGoing,
    headline: better >= worse
        ? 'Consistent with getting stronger'
        : 'Holding steady',
    because: because,
    next: null,
  );
}

/// Seven-calendar-day means at [ends] for a weight trend chart: the mean of
/// the readings in each trailing week, null where it has none.
List<double?> weightTrend(List<BodyWeightRow> all, List<String> ends) => [
  for (final e in ends) BodyLogDb.sevenDayMean(all, e)?.kg,
];

/// Consecutive day labels from [from] to [to], DST-safe.
List<String> daysBetween(String from, String to) {
  final out = <String>[];
  var d = DateTime.parse(from);
  final end = DateTime.parse(to);
  while (!d.isAfter(end) && out.length < 4000) {
    out.add(dayLabelOf(d));
    d = DateTime(d.year, d.month, d.day + 1);
  }
  return out;
}

double roundTo(double v, int places) {
  final f = math.pow(10, places);
  return (v * f).round() / f;
}
