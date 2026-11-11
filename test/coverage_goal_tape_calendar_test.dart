// The active Goal review calls readingNear with its own closed-week boundary.
// Fixed calendar inputs keep tape admission independent of the suite's weekday.
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/body_log.dart';
import 'package:whoop_companion/data/goal_plan.dart';
import 'package:whoop_companion/data/goal_review.dart';

GoalReview review(
  GoalPhase phase,
  String first, {
  String today = '2026-11-10',
  List<BodyMeasure> extra = const [],
}) => goalReview(
  plan: GoalPlan(phase: phase, since: '2026-01-01'),
  today: today,
  weights: const [],
  measures: [
    BodyMeasure(
      id: 'authored-start',
      date: first,
      recordedAt: DateTime(2026, 1, 1),
      inches: {'waistNavel': 34},
    ),
    ...extra,
    BodyMeasure(
      id: 'authored-latest',
      date: '2026-11-08',
      recordedAt: DateTime(2026, 1, 1),
      inches: {'waistNavel': 33},
    ),
  ],
  lifts: const [],
  food: const [],
  steps: const [],
  sleepMin: const [],
  recovery: const [],
  sessions: const [],
);

void main() {
  for (final phase in GoalPhase.values) {
    final short = phase == GoalPhase.fatLoss || phase == GoalPhase.leanGain;
    final boundary = short ? '2026-10-26' : '2026-10-12';
    for (final (name, first, admitted) in [
      ('seven days before', short ? '2026-10-19' : '2026-10-05', true),
      ('eight days before', short ? '2026-10-18' : '2026-10-04', false),
      ('seven days after', short ? '2026-11-02' : '2026-10-19', true),
      ('eight days after', short ? '2026-11-03' : '2026-10-20', false),
    ]) {
      test('${phase.name} tape $name its actual review start', () {
        final result = review(phase, first);
        expect(result.before.from, boundary);
        expect(result.after.to, '2026-11-08');
        expect(result.waistLatest, (date: '2026-11-08', value: 33.0));
        expect(
          result.waistFrom,
          admitted ? (date: first, value: 34.0) : isNull,
        );
        expect(
          result.waistTo,
          admitted ? (date: '2026-11-08', value: 33.0) : isNull,
        );
        expect(result.weightChangeKg, isNull);
        expect(result.food.kcalDays, 0);
        expect(
          result.advice.verdict,
          GoalVerdict.needMore,
          reason:
              'Tape must never substitute for missing weight/food evidence.',
        );
      });
    }
  }
  for (final today in ['2026-11-09', '2026-11-10', '2026-11-15']) {
    test('the same closed week keeps tape evidence on $today', () {
      final result = review(GoalPhase.fatLoss, '2026-10-26', today: today);
      expect(result.before.from, '2026-10-26');
      expect(result.after.to, '2026-11-08');
      expect(result.waistFrom, (date: '2026-10-26', value: 34.0));
      expect(result.waistTo, (date: '2026-11-08', value: 33.0));
    });
  }
  for (final phase in [GoalPhase.fatLoss, GoalPhase.recomp]) {
    final short = phase == GoalPhase.fatLoss;
    for (final kind in ['nearer', 'tie', 'exact']) {
      test(
        '${phase.name} selects the $kind tape reading among two eligible dates',
        () {
          final first = kind == 'nearer'
              ? (short ? '2026-10-19' : '2026-10-05')
              : kind == 'tie'
              ? (short ? '2026-10-25' : '2026-10-11')
              : (short ? '2026-10-26' : '2026-10-12');
          final second = kind == 'nearer'
              ? (short ? '2026-10-25' : '2026-10-11')
              : kind == 'tie'
              ? (short ? '2026-10-27' : '2026-10-13')
              : (short ? '2026-11-01' : '2026-10-18');
          final result = review(
            phase,
            first,
            extra: [
              BodyMeasure(
                id: 'authored-competing',
                date: second,
                recordedAt: DateTime(2026, 1, 1),
                inches: {'waistNavel': 35},
              ),
            ],
          );
          expect(
            result.waistFrom,
            kind == 'nearer'
                ? (date: second, value: 35.0)
                : (date: first, value: 34.0),
          );
          expect(result.waistTo, (date: '2026-11-08', value: 33.0));
          expect(result.advice.verdict, GoalVerdict.needMore);
          expect(result.weightChangeKg, isNull);
        },
      );
    }
  }
}
