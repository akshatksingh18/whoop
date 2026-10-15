// Build 90: the Progress overview reads ONE fixed review window — the goal's
// own closed weeks — and names missing evidence exactly.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/body_log.dart';
import 'package:openstrap_edge/data/goal_plan.dart';
import 'package:openstrap_edge/data/goal_review.dart';
import 'package:openstrap_edge/data/progress_review.dart';

// Wednesday 2026-10-14: the closed weeks are Oct 5–11, Sep 28–Oct 4,
// Sep 21–27 and Sep 14–20.
const _today = '2026-10-14';

BodyWeightRow _w(String date, double kg) => (
  date: date,
  kg: kg,
  atTs: DateTime.parse(date).millisecondsSinceEpoch ~/ 1000,
  unit: 'kg',
  entered: kg,
  source: 'whoop',
  originId: null,
  historyOnly: false,
);

FoodDay _f(String date, double kcal, {double? protein}) => (
  date: date,
  kcal: kcal,
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

GoalReview _review({
  GoalPhase phase = GoalPhase.recomp,
  List<BodyWeightRow>? weights,
  List<FoodDay>? food,
  List<BodyMeasure> measures = const [],
  List<({String date, String type})> sessions = const [],
  List<DatedValue> sleep = const [],
}) => goalReview(
  plan: GoalPlan(phase: phase, since: '2026-08-01'),
  today: _today,
  weights:
      weights ??
      [for (final d in _days('2026-09-14', 28)) _w(d, 80)],
  measures: measures,
  lifts: const [],
  food: food ?? [for (final d in _days('2026-09-14', 28)) _f(d, 2200)],
  steps: const [],
  sleepMin: sleep,
  recovery: const [],
  sessions: sessions,
);

void main() {
  test('recomposition compares the last two closed weeks with the two before', () {
    final r = _review();
    expect(r.after.from, '2026-09-28');
    expect(r.after.to, '2026-10-11');
    expect(r.before.from, '2026-09-14');
    expect(r.before.to, '2026-09-27');
    expect(r.weeks.map((w) => w.from), [
      '2026-10-05',
      '2026-09-28',
      '2026-09-21',
      '2026-09-14',
    ]);
  });

  test('fat loss compares one closed week with the one before', () {
    final r = _review(phase: GoalPhase.fatLoss);
    expect(r.after.from, '2026-10-05');
    expect(r.before.from, '2026-09-28');
  });

  test('missing evidence names each short week and never says weigh in today', () {
    final weights = [
      for (final d in _days('2026-09-14', 28))
        // Oct 5–11 gets three weigh-ins only.
        if (d.compareTo('2026-10-05') < 0 ||
            ['2026-10-05', '2026-10-07', '2026-10-09'].contains(d))
          _w(d, 80),
    ];
    final r = _review(phase: GoalPhase.fatLoss, weights: weights);
    expect(r.advice.verdict, GoalVerdict.needMore);
    expect(r.advice.because, contains('Oct 5–11: 3 of 5 weigh-ins.'));
    expect(r.advice.next, contains('Those weeks are closed'));
    expect(r.advice.next, isNot(contains('Weigh in most mornings')));
  });

  test('a waist reading shows even with nothing to compare it with', () {
    final r = _review(
      measures: [
        BodyMeasure(
          date: '2026-10-02',
          recordedAt: DateTime(2026, 10, 2),
          inches: {BodySite.waistNavel.name: 33.1},
        ),
      ],
    );
    expect(r.waistLatest?.value, 33.1);
    expect(r.waistFrom, isNull);
    expect(r.advice.because.join(' '), contains('Waist: needs a reading'));
  });

  test('inputs come from the later half only', () {
    final r = _review(
      sessions: const [
        (date: '2026-10-01', type: 'running'),
        (date: '2026-10-08', type: 'weight_training'),
        (date: '2026-09-20', type: 'running'), // before the later half
        (date: '2026-10-13', type: 'running'), // this week: not closed
      ],
      sleep: const [
        (date: '2026-10-03', value: 420),
        (date: '2026-10-04', value: 480),
        (date: '2026-09-15', value: 300),
      ],
    );
    expect(r.workouts.total, 2);
    expect(r.workouts.run, 1);
    expect(r.workouts.lift, 1);
    expect(r.sleep.nights, 2);
    expect(r.sleep.minutes, 450);
    expect(r.food.kcalDays, 14);
  });
}
