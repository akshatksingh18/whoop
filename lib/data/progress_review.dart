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
import 'lift_progress.dart' show SetVerdict, bestSet, compareSet;

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

/// B88-08: the reading a period's change starts from — the one nearest
/// [start] within [days] calendar days either side, or null. A tape or waist
/// change never reaches back to an older reading.
DatedValue? readingNear(List<DatedValue> s, String start, {int days = 7}) {
  final t = DateTime.parse(start);
  final anchor = DateTime.utc(t.year, t.month, t.day);
  int gap(String d) {
    final x = DateTime.parse(d);
    return DateTime.utc(x.year, x.month, x.day).difference(anchor).inDays.abs();
  }

  DatedValue? best;
  for (final x in s) {
    final g = gap(x.date);
    if (g > days) continue;
    if (best == null || g < gap(best.date)) best = x;
  }
  return best;
}

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

/// The first week from [start] and the last closed week, for the
/// since-start review. Null until the two no longer overlap, so a short
/// history never compares a week with itself.
(DayWindow, DayWindow)? sinceStartWindows(String start, String today) {
  final (last, _) = closedWeeks(today);
  final s = DateTime.parse(start);
  final first = (
    from: start,
    to: dayLabelOf(DateTime(s.year, s.month, s.day + 6)),
    days: 7,
    partial: false,
  );
  if (first.to.compareTo(last.from) >= 0) return null;
  return (first, last);
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

/// Build 89: ONE period for the whole Progress page. What it compares
/// ([before] → [after]) and the days every section below shows ([shownFrom]
/// → [shownTo]), so no two numbers on the page cover different days:
/// - week / month: the last closed week or month against the one before;
/// - 2 months … 1 year: the last N days against the N days before;
/// - since start / all: your first week against the last closed week, with
///   the sections covering start (or the first record) to today.
/// [before]/[after] are null when the history cannot be compared yet.
typedef ProgressPeriod = ({
  DayWindow? before,
  DayWindow? after,
  String shownFrom,
  String shownTo,
  String words,
});

ProgressPeriod progressPeriod(
  ProgressRange r,
  String today, {
  String? baseline,
  String? earliest,
}) {
  String md(String d) {
    final x = DateTime.parse(d);
    const m = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${x.day} ${m[x.month - 1]}';
  }

  String span(DayWindow w) => '${md(w.from)}–${md(w.to)}';
  switch (r) {
    case ProgressRange.week:
      final (after, before) = closedWeeks(today);
      return (
        before: before,
        after: after,
        shownFrom: after.from,
        shownTo: after.to,
        words: 'Last week (${span(after)}) vs the week before (${span(before)})',
      );
    case ProgressRange.month:
      final (after, before) = closedMonths(today);
      const names = [
        'January', 'February', 'March', 'April', 'May', 'June', 'July', //
        'August', 'September', 'October', 'November', 'December',
      ];
      String name(DayWindow w) => names[DateTime.parse(w.from).month - 1];
      return (
        before: before,
        after: after,
        shownFrom: after.from,
        shownTo: after.to,
        words: '${name(after)} vs ${name(before)}',
      );
    case ProgressRange.sinceStart:
    case ProgressRange.all:
      final start = r == ProgressRange.sinceStart
          ? (baseline ?? earliest)
          : (earliest ?? baseline);
      final w = start == null ? null : sinceStartWindows(start, today);
      final from = r.from(today, baseline: baseline, earliest: earliest);
      return (
        before: w?.$1,
        after: w?.$2,
        shownFrom: from,
        shownTo: today,
        words: w == null
            ? '${r == ProgressRange.all ? 'Everything' : 'Since ${md(from)}'} — '
                  'too early to compare a first and a last week'
            : 'Your first week (${span(w.$1)}) vs last week (${span(w.$2)})',
      );
    case ProgressRange.twoMonths:
    case ProgressRange.threeMonths:
    case ProgressRange.sixMonths:
    case ProgressRange.year:
      final n = r.days!;
      final t = DateTime.parse(today);
      final after = (
        from: dayLabelOf(DateTime(t.year, t.month, t.day - (n - 1))),
        to: today,
        days: n,
        partial: false,
      );
      final before = (
        from: dayLabelOf(DateTime(t.year, t.month, t.day - (2 * n - 1))),
        to: dayLabelOf(DateTime(t.year, t.month, t.day - n)),
        days: n,
        partial: false,
      );
      return (
        before: before,
        after: after,
        shownFrom: after.from,
        shownTo: today,
        words: 'Last ${r.label} (${span(after)}) vs the ${r.label} before',
      );
  }
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

/// One exercise's progress between two windows: each window's best set
/// ([bestSet], the live workout's own choice), only for the same name, load
/// meaning and equipment note, judged by the live workout's comparator
/// ([compareSet], B88-07). Absent when either window lacks it.
typedef LiftComparison = ({
  String exercise,
  LiftLoadMode mode,
  LiftSet before,
  LiftSet after,
  SetVerdict change,
});

List<LiftComparison> liftComparisons(
  List<LiftWorkout> finished,
  DayWindow before,
  DayWindow after,
) {
  Map<String, (LiftExercise, LiftSet)> bestIn(DayWindow w) {
    final ex = <String, LiftExercise>{};
    final sets = <String, List<LiftSet>>{};
    for (final x in finished) {
      final d = dayLabelOf(x.startedAt);
      if (d.compareTo(w.from) < 0 || d.compareTo(w.to) > 0) continue;
      for (final e in x.exercises) {
        if (e.sets.isEmpty) continue;
        final k =
            '${liftNameKey(e.name)}|${e.loadMode.name}|${liftNameKey(e.equipmentNote)}';
        ex[k] ??= e;
        (sets[k] ??= []).addAll(e.sets);
      }
    }
    return {for (final k in ex.keys) k: (ex[k]!, bestSet(sets[k]!))};
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
          change: compareSet(b[k]!.$2, pa.$2),
        ),
  ];
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
  // B88-07: a lift whose best sets cannot be compared is not evidence.
  final comparable = [
    for (final l in lifts)
      if (l.change != SetVerdict.incomparable) l,
  ];
  if (comparable.isEmpty) {
    missing.add('the same lift logged comparably in both periods');
  }
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
  final better = comparable.where((l) => l.change == SetVerdict.better).length;
  final worse = comparable.where((l) => l.change == SetVerdict.worse).length;
  final same = comparable.length - better - worse;
  final apart = lifts.length - comparable.length;
  final dw = weightAfter.mean! - weightBefore.mean!;
  final pct = dw / weightBefore.mean! * 100;
  final because = <String>[
    'Average weight ${dw >= 0 ? 'up' : 'down'} ${dw.abs().toStringAsFixed(1)} '
        '(${pct.abs().toStringAsFixed(1)}%) on ${weightAfter.count} vs '
        '${weightBefore.count} weigh-ins.',
    if (waistChange != null)
      'Waist ${waistChange == 0 ? 'unchanged' : '${waistChange > 0 ? 'up' : 'down'} ${waistChange.abs().toStringAsFixed(2)} in'} between its measured dates.',
    '$better of ${comparable.length} comparable lifts better, $same the same, '
        '$worse worse${apart == 0 ? '' : '; $apart not comparable'}.',
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
    // B88-07: "stronger" needs at least one lift actually better; 0 better
    // and 0 worse is holding steady, not improvement.
    headline: better > 0 && better >= worse
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
