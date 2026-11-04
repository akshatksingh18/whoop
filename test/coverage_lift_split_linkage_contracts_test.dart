// Retained active set/split behavior, including imported ad-hoc exercise names.
// Identity, recorded times and completed history must survive reconciliation.
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/lift_log.dart';

void main() {
  final at = DateTime(2021, 4, 6, 12);
  test(
    'the correction adapter delegates an active set edit without changing its logged time',
    () {
      final original = LiftSet(
        id: 'authored-active-set',
        reps: 8,
        load: 20,
        completedAt: at,
      );
      final w = LiftWorkout(
        id: 'authored-active',
        startedAt: at,
        exercises: [
          LiftExercise(
            id: 'authored-exercise',
            name: 'Authored press',
            sets: [original],
          ),
        ],
      );
      w.correctFinishedSet(
        'authored-exercise',
        original.id,
        reps: 12,
        load: 25,
      );
      expect(w.isActive, true);
      expect(original.reps, 12);
      expect(original.load, 25);
      expect(original.completedAt, at);
      expect(original.id, 'authored-active-set');
    },
  );
  for (final reversed in [false, true]) {
    test(
      'records retain only the best same-context rep/load improvement regardless of set order: $reversed',
      () {
        LiftWorkout workout(
          String id,
          DateTime start,
          List<(int, double)> entries,
        ) => LiftWorkout(
          id: id,
          startedAt: start,
          endedAt: start.add(const Duration(minutes: 30)),
          exercises: [
            LiftExercise(
              id: '$id-exercise',
              name: 'Authored press',
              loadMode: LiftLoadMode.perHand,
              equipmentNote: 'Authored bench',
              sets: [
                for (var i = 0; i < entries.length; i++)
                  LiftSet(
                    id: '$id-$i',
                    reps: entries[i].$1,
                    load: entries[i].$2,
                    completedAt: start,
                  ),
              ],
            ),
          ],
        );
        final before = workout(
          'authored-earlier',
          at.subtract(const Duration(days: 1)),
          [(8, 20), (6, 30)],
        );
        final entries = <(int, double)>[
          (9, 20),
          (12, 20),
          (10, 20),
          (6, 35),
          (6, 40),
          (6, 38),
        ];
        final current = workout(
          'authored-current',
          at,
          reversed ? entries.reversed.toList() : entries,
        );
        final original = current.toJson();
        final records = liftRecords(current, [before]);
        expect(records.map((r) => r.text), [
          '12 reps at 20 lb/hand',
          '40 lb/hand for 6',
        ]);
        expect(records.every((r) => r.exercise == 'Authored press'), true);
        expect(current.toJson(), original);
      },
    );
  }
  test(
    'one set improving both known comparisons produces one record rather than duplicate praise',
    () {
      final earlier = LiftWorkout(
        id: 'authored-earlier',
        startedAt: at.subtract(const Duration(days: 1)),
        endedAt: at.subtract(const Duration(hours: 23)),
        exercises: [
          LiftExercise(
            name: 'Authored press',
            loadMode: LiftLoadMode.perHand,
            sets: [
              LiftSet(
                reps: 8,
                load: 20,
                completedAt: at.subtract(const Duration(days: 1)),
              ),
              LiftSet(
                reps: 12,
                load: 10,
                completedAt: at.subtract(const Duration(days: 1)),
              ),
            ],
          ),
        ],
      );
      final current = LiftWorkout(
        id: 'authored-current',
        startedAt: at,
        exercises: [
          LiftExercise(
            name: 'Authored press',
            loadMode: LiftLoadMode.perHand,
            sets: [LiftSet(reps: 12, load: 20, completedAt: at)],
          ),
        ],
      );
      expect(
        liftRecords(current, [earlier]).single.text,
        '12 reps at 20 lb/hand',
      );
    },
  );
  LiftSet set() =>
      LiftSet(id: 'authored-set', reps: 8, load: 20, completedAt: at);
  LiftSplit split() => LiftSplit(
    id: 'authored-split',
    name: 'Authored split',
    exercises: [
      LiftSplitExercise(
        id: 'authored-press',
        name: 'Authored press',
        loadMode: LiftLoadMode.stack,
        equipmentNote: 'Authored machine',
      ),
      LiftSplitExercise(
        id: 'authored-row',
        name: 'Authored row',
        loadMode: LiftLoadMode.total,
      ),
    ],
  );
  for (final hasSets in [false, true]) {
    test(
      'an unlinked matching ${hasSets ? 'started' : 'unstarted'} exercise takes one split identity without replacing recorded sets',
      () {
        final exercise = LiftExercise(
          id: 'authored-existing',
          name: '  AUTHORED PRESS  ',
          loadMode: LiftLoadMode.perHand,
          equipmentNote: 'Original setup',
          sets: hasSets ? [set()] : [],
        );
        final w = LiftWorkout(
          id: 'authored-workout',
          startedAt: at,
          exercises: [exercise],
        );
        final before = exercise.toJson();
        final s = split();
        w.syncWith(s);
        expect(w.exercises, hasLength(2));
        expect(w.splitId, s.id);
        final linked = w.exercises.singleWhere((e) => e.id == exercise.id);
        expect(linked.splitExerciseId, 'authored-press');
        expect(identical(linked, exercise), true);
        if (hasSets) {
          expect(linked.loadMode, LiftLoadMode.perHand);
          expect(linked.equipmentNote, 'Original setup');
          expect(linked.sets.single.toJson(), (before['sets'] as List).single);
        } else {
          expect(linked.name, 'Authored press');
          expect(linked.loadMode, LiftLoadMode.stack);
          expect(linked.equipmentNote, 'Authored machine');
        }
        final reconciled = w.toJson();
        w.syncWith(s);
        expect(
          w.toJson(),
          reconciled,
          reason: 'A repeated split refresh is idempotent',
        );
      },
    );
  }
  test(
    'an already linked split identity cannot also bind an imported ad-hoc exercise',
    () {
      final linked = LiftExercise(
        id: 'authored-linked',
        name: 'Authored press',
        splitExerciseId: 'authored-press',
        sets: [set()],
      );
      final adHoc = LiftExercise(
        id: 'authored-ad-hoc',
        name: 'Authored press',
        sets: [
          LiftSet(
            id: 'authored-other-set',
            reps: 10,
            load: 15,
            completedAt: at,
          ),
        ],
      );
      final w = LiftWorkout(
        id: 'authored-workout',
        startedAt: at,
        exercises: [linked, adHoc],
      );
      w.syncWith(split());
      expect(
        w.exercises.where((e) => e.splitExerciseId == 'authored-press'),
        hasLength(1),
      );
      expect(adHoc.splitExerciseId, isNull);
      expect(adHoc.sets.single.id, 'authored-other-set');
      expect(
        w.exercises.map((e) => e.id),
        containsAll(['authored-linked', 'authored-ad-hoc']),
      );
    },
  );
  test(
    'removing an exercise from the split retains its completed set as an unlinked ad-hoc exercise',
    () {
      final w = LiftWorkout(id: 'authored-workout', startedAt: at)
        ..syncWith(split());
      final press = w.exercises.singleWhere(
        (e) => e.splitExerciseId == 'authored-press',
      );
      press.sets.add(set());
      final before = press.sets.single.toJson();
      final changed = split()
        ..exercises.removeWhere((e) => e.id == 'authored-press');
      w.syncWith(changed);
      expect(w.exercises, hasLength(2));
      expect(press.splitExerciseId, isNull);
      expect(press.sets.single.toJson(), before);
      expect(press.id, w.exercises.first.id);
    },
  );
  test(
    'a finished log ignores later split changes including renames, modes and deletions',
    () {
      final w = LiftWorkout(id: 'authored-workout', startedAt: at)
        ..syncWith(split());
      w.exercises.first.sets.add(set());
      w.finish(at.add(const Duration(minutes: 30)));
      final before = w.toJson();
      final changed = split()
        ..name = 'Edited split'
        ..exercises.clear();
      w.syncWith(changed);
      expect(w.toJson(), before);
    },
  );
  for (final reps in [0, -1]) {
    test(
      'finished set rejects $reps reps without changing its original identity, load or time',
      () {
        final w = LiftWorkout(
          id: 'authored-workout',
          startedAt: at,
          exercises: [
            LiftExercise(
              id: 'authored-exercise',
              name: 'Authored press',
              sets: [set()],
            ),
          ],
        )..finish(at.add(const Duration(minutes: 30)));
        final before = w.toJson();
        expect(
          () => w.correctFinishedSet(
            'authored-exercise',
            'authored-set',
            reps: reps,
            load: 30,
          ),
          throwsA(LiftLogError.invalidReps),
        );
        expect(w.toJson(), before);
      },
    );
  }
}
