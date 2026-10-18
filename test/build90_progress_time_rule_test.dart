// Build 90 (Akshat's phone review): Progress uses one time rule outside the
// goal check, the last N days up to today against the N days before, and the
// goal card names the real first-check date. Synthetic data only.
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/body_log.dart';
import 'package:openstrap_edge/data/goal_plan.dart';
import 'package:openstrap_edge/data/goal_review.dart';
import 'package:openstrap_edge/data/progress_review.dart';

BodyWeightRow _w(String date) => (
  date: date,
  kg: 80,
  atTs: DateTime.parse(date).millisecondsSinceEpoch ~/ 1000,
  unit: 'kg',
  entered: 80,
  source: 'whoop',
  originId: null,
  historyOnly: false,
);

FoodDay _f(String date, {double? protein}) => (
  date: date,
  kcal: 2200,
  counts: true,
  protein: protein,
  proteinComplete: protein != null,
);

List<String> _days(String from, int n) {
  final d = DateTime.parse(from);
  return [
    for (var i = 0; i < n; i++)
      DateTime(d.year, d.month, d.day + i).toIso8601String().substring(0, 10),
  ];
}

void main() {
  test('every range runs up to today against the same length before', () {
    final (after, before) = rollingWindows('2026-10-16', 7);
    expect(after.from, '2026-10-10');
    expect(after.to, '2026-10-16');
    expect(before.from, '2026-10-03');
    expect(before.to, '2026-10-09');
    final week = progressPeriod(ProgressRange.week, '2026-10-16');
    expect(week.after!.to, '2026-10-16', reason: 'includes today');
    expect(week.words, 'Last 7 days (Oct 10–Oct 16) vs the 7 days before (Oct 3–Oct 9)');
    final month = progressPeriod(ProgressRange.month, '2026-10-16');
    expect(month.after!.days, 30);
    expect(month.before!.to, '2026-09-16');
    expect(ProgressRange.week.label, '7 days');
    expect(ProgressRange.month.label, '30 days');
  });

  test('the overview compares the last 7 days with the 7 before', () {
    final r = rollingReview(
      today: '2026-10-16',
      weights: [for (final d in _days('2026-10-12', 5)) _w(d)],
      measures: const [],
      lifts: const [],
      food: [for (final d in _days('2026-10-01', 16)) _f(d, protein: 150)],
      steps: const [],
      sleepMin: const [],
      recovery: const [],
      sessions: const [(date: '2026-10-15', type: 'walking'), (date: '2026-10-05', type: 'walking')],
    );
    // This week's weigh-ins count; the old overview ignored the open week.
    expect(r.weightAfter.count, 5);
    expect(r.weightBefore.count, 0);
    expect(r.now.food.kcalDays, 7);
    expect(r.was.food.kcalDays, 7);
    expect(r.now.workouts.total, 1);
    expect(r.was.workouts.total, 1);
  });

  test('the first check waits for four qualifying full weeks, not "8 more days"', () {
    // Goal started Oct 10; nothing logged before Oct 12 (Monday).
    final weights = [for (final d in _days('2026-10-12', 5)) _w(d)];
    final food = [for (final d in _days('2026-10-12', 5)) _f(d)];
    final r = goalReview(
      plan: GoalPlan(phase: GoalPhase.recomp, since: '2026-10-10'),
      today: '2026-10-16',
      weights: weights,
      measures: const [],
      lifts: const [],
      food: food,
      steps: const [],
      sleepMin: const [],
      recovery: const [],
      sessions: const [],
    );
    expect(r.advice.verdict, GoalVerdict.needMore);
    // 4 full weeks needed; this week is the first: Oct 12, 19, 26, Nov 2 →
    // the check can first judge on Monday Nov 9.
    expect(r.firstCheck, '2026-11-09');
    expect(r.advice.because.first, startsWith('First check Nov 9'));
    expect(r.advice.because.join(' '), isNot(contains('8 more days')));
    final ev = thisWeekEvidence(today: '2026-10-16', weights: weights, food: food);
    expect(ev.weighIns, 5);
    expect(ev.foodDays, 5);
    expect(ev.proteinDays, 0);
  });

  test('a young goal waits for day 14 even when the weeks qualify', () {
    expect(
      firstCheckDate(
        weeks: [
          for (var i = 0; i < 4; i++)
            (from: '2026-09-01', to: '2026-09-07', weighIns: 7, foodDays: 7),
        ],
        today: '2026-10-16',
        windowWeeks: 2,
        since: '2026-10-10',
      ),
      isNull,
      reason: 'the weeks qualify, so the wait is the goal-age rule, not evidence',
    );
  });
}
