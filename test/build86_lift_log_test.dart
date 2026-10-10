// Lift Log inside the WHOOP workout (build 86): the domain keeps AkshatOS
// Lift Log's rules (akshatos/lift-log.md), the store writes whole workouts
// durably, and an AkshatOS backup imports once, idempotently, as history
// with no WHOOP session (so no strain or calories). Synthetic data only.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/lift_log.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.dbName = 'openstrap_lift_log_test.db';
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  tearDownAll(() async {
    await LocalDb.close();
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  final t0 = DateTime(2026, 10, 10, 7);

  group('domain parity', () {
    test('a first set moves the exercise up to the order done', () {
      final w = LiftWorkout(startedAt: t0);
      final a = w.addExercise(name: 'A', loadMode: LiftLoadMode.stack);
      final b = w.addExercise(name: 'B', loadMode: LiftLoadMode.stack);
      final c = w.addExercise(name: 'C', loadMode: LiftLoadMode.perHand);
      w.addSet(c, reps: 10, load: 40, at: t0.add(const Duration(minutes: 5)));
      expect(w.exercises.map((e) => e.name), ['C', 'A', 'B']);
      w.addSet(a, reps: 8, load: 70, at: t0.add(const Duration(minutes: 9)));
      expect(w.exercises.map((e) => e.name), ['C', 'A', 'B']);
      expect(b, isNotEmpty);
    });

    test('invalid sets are refused; finishing drops empty exercises', () {
      final w = LiftWorkout(startedAt: t0);
      final a = w.addExercise(name: 'Row', loadMode: LiftLoadMode.stack);
      w.addExercise(name: 'Unused', loadMode: LiftLoadMode.stack);
      expect(
        () => w.addSet(a, reps: 0, load: 10, at: t0),
        throwsA(isA<LiftLogError>()),
      );
      expect(
        () => w.addSet(a, reps: 5, load: -1, at: t0),
        throwsA(isA<LiftLogError>()),
      );
      w.addSet(a, reps: 10, load: 70, at: t0);
      w.finish(t0.add(const Duration(minutes: 40)));
      expect(w.exercises.map((e) => e.name), ['Row']);
      expect(
        () => w.addSet(a, reps: 1, load: 1, at: t0),
        throwsA(isA<LiftLogError>()),
      );
    });

    test('delete-last-set really deletes, and Undo removes only the last', () {
      final w = LiftWorkout(startedAt: t0);
      final a = w.addExercise(name: 'Curl', loadMode: LiftLoadMode.perHand);
      final s1 = w.addSet(a, reps: 10, load: 30, at: t0);
      w.addSet(a, reps: 9, load: 30, at: t0);
      w.removeLastSet(a);
      expect(w.exercises.single.sets.single.id, s1.id);
      w.removeSet(a, s1.id);
      expect(w.exercises.single.sets, isEmpty);
    });

    test('a split edit updates the open workout as Lift Log does', () {
      final split = LiftSplit(
        name: 'Chest day',
        exercises: [
          LiftSplitExercise(name: 'Bench', loadMode: LiftLoadMode.perHand),
          LiftSplitExercise(name: 'Fly', loadMode: LiftLoadMode.stack),
        ],
      );
      final w = LiftWorkout(startedAt: t0)..syncWith(split);
      expect(w.exercises.map((e) => e.name), ['Bench', 'Fly']);
      final bench = w.exercises.first.id;
      w.addSet(bench, reps: 10, load: 50, at: t0);
      // Remove Bench (logged → stays, unlinked), rename Fly, add Dips.
      split.exercises
        ..removeAt(0)
        ..first.name = 'Pec-deck fly'
        ..add(
          LiftSplitExercise(name: 'Dips', loadMode: LiftLoadMode.addedWeight),
        );
      w.syncWith(split);
      expect(w.exercises.map((e) => e.name), ['Bench', 'Pec-deck fly', 'Dips']);
      expect(w.exercises.first.splitExerciseId, isNull);
    });

    test('a today-only skip stays skipped through a sync', () {
      final split = LiftSplit(
        name: 'Lower',
        exercises: [
          LiftSplitExercise(
            name: 'Squat',
            loadMode: LiftLoadMode.platesPerSide,
          ),
          LiftSplitExercise(name: 'Curl', loadMode: LiftLoadMode.stack),
        ],
      );
      final w = LiftWorkout(startedAt: t0)..syncWith(split);
      final curl = w.removeExercise(w.exercises.last.id);
      w.skipped.add(curl.splitExerciseId!);
      w.syncWith(split);
      expect(w.exercises.map((e) => e.name), ['Squat']);
    });

    test('records need comparable history: same name, mode and equipment', () {
      LiftWorkout done(
        DateTime at,
        double load,
        int reps, {
        LiftLoadMode mode = LiftLoadMode.perHand,
        String note = '',
      }) {
        final w = LiftWorkout(startedAt: at);
        final e = w.addExercise(
          name: 'Bench',
          loadMode: mode,
          equipmentNote: note,
        );
        w.addSet(e, reps: reps, load: load, at: at);
        w.finish(at.add(const Duration(hours: 1)));
        return w;
      }

      final before = done(t0, 40, 8);
      final now = done(t0.add(const Duration(days: 3)), 40, 10);
      expect(liftRecords(now, [before]).single.text, '10 reps at 40 lb/hand');
      // A heavier set for fewer reps than anything at that load is not a rep
      // record; a different mode or machine is not comparable at all.
      expect(
        liftRecords(done(t0.add(const Duration(days: 4)), 45, 6), [before]),
        isEmpty,
      );
      expect(
        liftRecords(
          done(
            t0.add(const Duration(days: 5)),
            90,
            12,
            mode: LiftLoadMode.stack,
          ),
          [before],
        ),
        isEmpty,
      );
      // No history: nothing is claimed.
      expect(liftRecords(before, const []), isEmpty);
    });
  });

  group('store', () {
    test(
      'a workout round-trips, and the last performance uses name and mode',
      () async {
        final w = LiftWorkout(
          startedAt: t0,
          sessionId: 'sess-1',
          splitName: 'Chest day',
        );
        final e = w.addExercise(
          name: 'Dumbbell bench press',
          loadMode: LiftLoadMode.perHand,
        );
        w.addSet(e, reps: 10, load: 50, at: t0.add(const Duration(minutes: 3)));
        await LiftLogDb.save(w);
        expect((await LiftLogDb.active())!.id, w.id);
        w.finish(t0.add(const Duration(minutes: 50)));
        await LiftLogDb.save(w);
        expect(await LiftLogDb.active(), isNull);
        final back = await LiftLogDb.forSession('sess-1');
        expect(back!.exercises.single.sets.single.load, 50);
        final last = await LiftLogDb.lastPerformance(
          ' dumbbell BENCH press ',
          LiftLoadMode.perHand,
        );
        expect(last!.exercise.sets.single.reps, 10);
        expect(
          await LiftLogDb.lastPerformance(
            'Dumbbell bench press',
            LiftLoadMode.total,
          ),
          isNull,
          reason: 'a different load meaning is a different lift',
        );
        final csv = await LiftLogDb.csv();
        expect(csv, contains('perHand,50,10,1'));
      },
    );

    test('deleting a session deletes its log, not imported history', () async {
      final w = LiftWorkout(startedAt: t0, sessionId: 'sess-del');
      w.addSet(
        w.addExercise(name: 'Row', loadMode: LiftLoadMode.stack),
        reps: 8,
        load: 60,
        at: t0,
      );
      await LiftLogDb.save(w);
      await LocalDb.deleteSession('sess-del');
      expect(await LiftLogDb.forSession('sess-del'), isNull);
    });
  });

  test(
    'set marks fall in the minute they were logged, inside the trace only',
    () {
      final start = DateTime(2026, 9, 1, 18);
      expect(
        setMarkMinutes(start, [
          start.add(const Duration(minutes: 3, seconds: 59)),
          start.add(const Duration(minutes: 3, seconds: 10)),
          start.add(const Duration(minutes: 12)),
          start.subtract(const Duration(minutes: 1)),
          start.add(const Duration(minutes: 90)),
        ], 60),
        [3, 12],
        reason:
            'deduped per minute; before the start or past the trace is dropped',
      );
    },
  );

  group('AkshatOS import', () {
    // Swift's default JSON date is seconds since 2001-01-01.
    double apple(DateTime d) => d.millisecondsSinceEpoch / 1000 - 978307200;
    String backup({bool active = false}) => jsonEncode({
      'version': 1,
      'exportedAt': apple(t0),
      'workouts': [
        {
          'id': 'A1B2C3D4-0000-4000-8000-000000000001',
          'startedAt': apple(DateTime(2026, 9, 1, 18)),
          if (!active) 'endedAt': apple(DateTime(2026, 9, 1, 19)),
          'notes': '',
          'splitName': 'Lower day',
          'exercises': [
            {
              'id': 'A1B2C3D4-0000-4000-8000-000000000002',
              'name': 'Smith-machine squat',
              'loadMode': 'platesPerSide',
              'equipmentNote': 'Smith bar resistance excluded',
              'sets': [
                {
                  'id': 'A1B2C3D4-0000-4000-8000-000000000003',
                  'reps': 8,
                  'load': 42.5,
                  'completedAt': apple(DateTime(2026, 9, 1, 18, 10)),
                },
              ],
            },
          ],
        },
      ],
    });

    test(
      'dates, modes and pounds survive; a repeat import is a no-op',
      () async {
        final plan = await planLiftImport(backup());
        expect(plan.add, hasLength(1));
        final w = plan.add.single;
        expect(w.startedAt, DateTime(2026, 9, 1, 18));
        expect(w.exercises.single.sets.single.load, 42.5);
        expect(w.exercises.single.loadMode, LiftLoadMode.platesPerSide);
        expect(await applyLiftImport(plan), 1);
        final again = await planLiftImport(backup());
        expect(again.add, isEmpty);
        expect(again.unchanged, 1);
        // History only: no WHOOP session, so no strain or calories.
        final stored = (await LiftLogDb.finished()).firstWhere(
          (x) => x.id == w.id,
        );
        expect(stored.sessionId, isNull);
        expect(stored.origin, 'akshatos');
      },
    );

    test('an unfinished AkshatOS workout is refused, not half-imported', () {
      expect(planLiftImport(backup(active: true)), throwsFormatException);
    });
  });
}
