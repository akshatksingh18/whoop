// Build 90 (D5): milestones are dated facts from recorded readings, compared
// only with the same exercise, load meaning and setup.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/body_log.dart';
import 'package:openstrap_edge/data/lift_log.dart';
import 'package:openstrap_edge/data/progress_milestones.dart';

BodyMeasure _waist(String date, double v) => BodyMeasure(
  date: date,
  recordedAt: DateTime.parse(date),
  inches: {BodySite.waistNavel.name: v},
);

LiftWorkout _w(String date, List<LiftExercise> ex) => LiftWorkout(
  startedAt: DateTime.parse('${date}T18:00:00'),
  endedAt: DateTime.parse('${date}T19:00:00'),
  exercises: ex,
);

LiftExercise _bench(double load, int reps, {String note = ''}) => LiftExercise(
  name: 'Bench press',
  loadMode: LiftLoadMode.platesPerSide,
  equipmentNote: note,
  sets: [
    LiftSet(reps: reps, load: load, completedAt: DateTime(2026, 10, 1)),
  ],
);

void main() {
  test('a waist reading lower than every earlier one is a dated milestone', () {
    final notes = bodyMilestones(
      [
        _waist('2026-09-02', 34.0),
        _waist('2026-09-16', 34.25),
        _waist('2026-10-09', 33.1),
      ],
      '2026-09-01',
      '2026-10-14',
    );
    expect(notes, hasLength(1));
    expect(notes.single, contains('33.1 in on Oct 9'));
    expect(notes.single, contains('lowest of 3 readings since Sep 2'));
    expect(notes.single, contains('previous lowest 34 in, Sep 2'));
  });

  test('a better best set on the same setup is a milestone; another setup is not', () {
    final notes = liftMilestones(
      [
        _w('2026-09-20', [_bench(60, 8)]),
        _w('2026-10-08', [_bench(62.5, 8)]),
        // Same name, different setup: compared only with itself.
        _w('2026-10-10', [_bench(90, 8, note: 'Smith machine')]),
      ],
      '2026-09-01',
      '2026-10-14',
    );
    expect(notes, hasLength(1));
    expect(notes.single, startsWith('Bench press 62.5'));
    expect(notes.single, contains('on Oct 8'));
  });

  test('outside the range nothing is listed, but earlier sessions still count', () {
    final notes = liftMilestones(
      [
        _w('2026-08-01', [_bench(70, 8)]),
        _w('2026-10-08', [_bench(62.5, 8)]),
      ],
      '2026-10-01',
      '2026-10-14',
    );
    expect(notes, isEmpty);
  });
}
