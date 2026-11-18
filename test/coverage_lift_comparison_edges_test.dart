// Exercise-local comparisons preserve load meaning and explicitly name mixed evidence.
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/lift_log.dart';
import 'package:whoop_companion/data/lift_progress.dart';

LiftExercise exercise(List<(double, int)> values) => LiftExercise(
  name: 'Synthetic press',
  sets: [for (final v in values) LiftSet(load: v.$1, reps: v.$2, completedAt: DateTime(2021, 4, 6, 8))],
);
ExerciseSession session(int day, double load, int reps) {
  final e = exercise([(load, reps)]);
  return (
    date: DateTime(2021, 4, day),
    exercise: e,
    best: e.sets.single,
    score: setScore(e.sets.single),
    reps: reps,
  );
}

void main() {
  test('high-rep history compares reps only at the same load', () {
    final h = [
      session(4, 20, 15),
      session(3, 30, 20),
      session(2, 20, 18),
      session(1, 10, 20),
    ];
    final d = liftTrend(h);
    expect(d.trend, LiftTrend.down);
    expect(d.text, contains('down 3 reps'));
    expect(d.text, contains('2 sessions'));
    expect(
      liftTrend([session(2, 20, 15), session(1, 30, 20)]).trend,
      LiftTrend.incomparable,
    );
  });
  test(
    'small and negative comparable changes keep the established trend thresholds',
    () {
      expect(
        liftTrend([session(2, 100.4, 8), session(1, 100, 8)]).text,
        contains('About level'),
      );
      final down = liftTrend([session(2, 90, 8), session(1, 100, 8)]);
      expect(down.trend, LiftTrend.down);
      expect(down.text, contains('down 10%'));
    },
  );
  test('a stalled rep-only history uses older comparable sessions only', () {
    final h = [
      session(6, 20, 15),
      session(5, 20, 15),
      session(4, 20, 16),
      session(3, 20, 20),
      session(2, 30, 25),
    ];
    expect(liftTrend(h).trend, LiftTrend.flat);
    expect(liftTrend(h).text, contains('No new best in your last 3 sessions'));
  });
  test(
    'different weight and reps is incomparable and extra sets stay descriptive',
    () {
      final a = exercise([(30, 15), (10, 12)]), b = exercise([(20, 20)]);
      final d = versusLast(a, b)!;
      expect(d.verdict, SetVerdict.incomparable);
      expect(d.text, contains('different weight and reps'));
      expect(d.text, contains('1 more set than last time'));
    },
  );
  test(
    'matching and mixed sets do not collapse missing comparability into improvement',
    () {
      final same = versusLast(
        exercise([(20, 8), (30, 15)]),
        exercise([(20, 8), (20, 20)]),
      )!;
      expect(same.verdict, SetVerdict.same);
      expect(same.text, contains('Matching last time'));
      expect(same.text, contains('1 not comparable'));
      final mixed = versusLast(
        exercise([(30, 8), (10, 8), (20, 8), (20, 8)]),
        exercise([(20, 8), (20, 8)]),
      )!;
      expect(mixed.verdict, SetVerdict.same);
      expect(mixed.text, contains('Mixed: 1 ahead, 1 behind'));
      expect(mixed.text, contains('2 more sets than last time'));
    },
  );
}
