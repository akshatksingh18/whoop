// Build 90: the home bodyweight workout. A blank Added weight is a bodyweight
// set; variations live inside one exercise and compare only with themselves;
// the Home split carries Akshat's five exercises.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/lift_log.dart';
import 'package:openstrap_edge/data/lift_progress.dart';

LiftSet _s(double load, int reps) =>
    LiftSet(reps: reps, load: load, completedAt: DateTime(2026, 10, 14));

LiftWorkout _w(String date, List<LiftExercise> ex) => LiftWorkout(
  startedAt: DateTime.parse('${date}T07:00:00'),
  endedAt: DateTime.parse('${date}T07:25:00'),
  exercises: ex,
);

void main() {
  test('a bodyweight set reads as bodyweight, a backpack set as added load', () {
    expect(liftSetText(LiftLoadMode.addedWeight, _s(0, 12)), 'Bodyweight × 12');
    expect(liftSetText(LiftLoadMode.addedWeight, _s(10, 12)), '+10 lb × 12');
    expect(liftSetText(LiftLoadMode.perHand, _s(20, 10)), '20 lb/hand × 10');
  });

  test('bodyweight sets compare by reps; heavier for fewer reps is not comparable', () {
    expect(compareSet(_s(0, 14), _s(0, 12)), SetVerdict.better);
    expect(compareSet(_s(10, 10), _s(0, 15)), SetVerdict.incomparable);
    expect(setScore(_s(0, 8)), isNull, reason: 'no load: no strength estimate');
  });

  test('the Home split has the five exercises with honest load meanings', () {
    final h = LiftSplit.home;
    expect(h.name, 'Home');
    expect([for (final e in h.exercises) e.name], [
      'Push-up',
      'Backpack row',
      'Bed-edge dip',
      'Split squat',
      'Leg raise',
    ]);
    // The backpack is a row's whole load, so it needs the weighed number;
    // the others are bodyweight exercises where a blank means bodyweight.
    expect(h.exercises[1].loadMode, LiftLoadMode.total);
    for (final i in [0, 2, 3, 4]) {
      expect(h.exercises[i].loadMode, LiftLoadMode.addedWeight);
    }
    expect(h.exercises.every((e) => e.equipmentNote.isEmpty), isTrue);
  });

  test('variations of one exercise are listed newest first and never mixed', () {
    final pushup = LiftExercise(
      name: 'Push-up',
      loadMode: LiftLoadMode.addedWeight,
      sets: [_s(0, 15)],
    );
    final raised = LiftExercise(
      name: 'Push-up',
      loadMode: LiftLoadMode.addedWeight,
      equipmentNote: 'Feet raised',
      sets: [_s(0, 9)],
    );
    final close = LiftExercise(
      name: 'Push-up',
      loadMode: LiftLoadMode.addedWeight,
      equipmentNote: 'Close grip',
      sets: [_s(0, 10)],
    );
    final finished = [
      _w('2026-10-12', [raised, pushup]),
      _w('2026-10-05', [close]),
    ];
    expect(LiftLogDb.variationsOf('push-up', finished), [
      'Feet raised',
      'Close grip',
    ]);
    // Same name, different variation: each compares only with itself.
    final todayRaised = LiftExercise(
      name: 'Push-up',
      loadMode: LiftLoadMode.addedWeight,
      equipmentNote: 'Feet raised',
    );
    final h = exerciseHistory(todayRaised, finished);
    expect(h, hasLength(1));
    expect(h.single.best.reps, 9);
  });
}
