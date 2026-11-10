// Build 90 (D5): a set in a FINISHED lift log can be fixed or deleted. Only
// weight and reps change; the set's logged time and the log's own times stay.

import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/lift_log.dart';

LiftWorkout _finished() {
  final w = LiftWorkout(startedAt: DateTime(2026, 10, 14, 18));
  final bench = w.addExercise(
    name: 'Bench press',
    loadMode: LiftLoadMode.perHand,
  );
  final dip = w.addExercise(
    name: 'Bed-edge dip',
    loadMode: LiftLoadMode.addedWeight,
  );
  w.addSet(bench, reps: 8, load: 80, at: DateTime(2026, 10, 14, 18, 10));
  w.addSet(bench, reps: 8, load: 60, at: DateTime(2026, 10, 14, 18, 14));
  w.addSet(dip, reps: 12, load: 0, at: DateTime(2026, 10, 14, 18, 20));
  w.finish(DateTime(2026, 10, 14, 18, 40));
  return w;
}

void main() {
  test('a typed 80 instead of 60 is corrected; times stay as recorded', () {
    final w = _finished();
    final e = w.exercises.firstWhere((x) => x.name == 'Bench press');
    final s = e.sets.first;
    final at = s.completedAt;
    w.correctFinishedSet(e.id, s.id, reps: 8, load: 60);
    expect(s.load, 60);
    expect(s.completedAt, at);
    expect(w.startedAt, DateTime(2026, 10, 14, 18));
    expect(w.endedAt, DateTime(2026, 10, 14, 18, 40));
    expect(w.isActive, isFalse);
  });

  test('deleting a set keeps the rest; an emptied exercise leaves the log', () {
    final w = _finished();
    final dip = w.exercises.firstWhere((x) => x.name == 'Bed-edge dip');
    w.deleteFinishedSet(dip.id, dip.sets.single.id);
    expect(w.exercises.map((x) => x.name), ['Bench press']);
    expect(w.setCount, 2);
  });

  test('invalid values and unknown sets are refused', () {
    final w = _finished();
    final e = w.exercises.first;
    expect(
      () => w.correctFinishedSet(e.id, e.sets.first.id, reps: 0, load: 60),
      throwsA(isA<LiftLogError>()),
    );
    expect(
      () => w.correctFinishedSet(e.id, e.sets.first.id, reps: 8, load: -1),
      throwsA(isA<LiftLogError>()),
    );
    expect(
      () => w.deleteFinishedSet(e.id, 'nope'),
      throwsA(isA<LiftLogError>()),
    );
  });
}
