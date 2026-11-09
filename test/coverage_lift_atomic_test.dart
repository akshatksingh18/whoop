// Fail the second half of a linked split/workout edit, not its first write.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/calculation_store.dart';
import 'package:whoop_companion/data/lift_log.dart';
import 'package:whoop_companion/state/prefs.dart';
import 'package:whoop_companion/ui2/activity/lift_log_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late LiftLogController controller;
  late LiftSplit split;
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final dir = await Directory(
      'build/coverage-audit/lift',
    ).create(recursive: true);
    LocalDb.dbName = '${dir.absolute.path}/synthetic.sqlite';
    await LocalDb.close();
    await databaseFactory.deleteDatabase(LocalDb.dbName);
    db = await LocalDb.instance;
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.ensureLoaded();
    await LocalDb.wipeAll();
    split = LiftSplit(
      id: 'synthetic-split',
      name: 'Synthetic',
      exercises: [
        LiftSplitExercise(
          name: 'Synthetic press',
          loadMode: LiftLoadMode.total,
        ),
      ],
    );
    await LiftLogDb.saveSplits([split]);
    final workout = LiftWorkout(
      startedAt: DateTime.now(),
      sessionId: 'synthetic-session',
    )..syncWith(split);
    await LiftLogDb.save(workout);
    controller = LiftLogController('synthetic-session')
      ..workout = workout
      ..splits = [split];
    await db.execute(
      "CREATE TRIGGER synthetic_lift_refusal BEFORE INSERT ON lift_log BEGIN SELECT RAISE(ABORT,'synthetic refusal'); END",
    );
  });
  tearDown(() async {
    controller.dispose();
    await db.execute('DROP TRIGGER IF EXISTS synthetic_lift_refusal');
  });
  tearDownAll(LocalDb.close);

  test(
    'a post-commit cache read failure preserves the saved outcome',
    () async {
      await db.execute('ALTER TABLE baselines RENAME TO synthetic_baselines');
      try {
        await expectLater(
          CalculationStore.hydrate(),
          throwsA(isA<DatabaseException>()),
        );
        await CalculationStore.hydrate(afterCommit: true);
        expect(await LiftLogDb.forSession('synthetic-session'), isNotNull);
      } finally {
        await db.execute('ALTER TABLE synthetic_baselines RENAME TO baselines');
      }
      await CalculationStore.hydrate();
      expect((await LiftLogDb.splits()).single.id, split.id);
    },
  );

  test('adding an exercise cannot partially change its split', () async {
    await controller.addExercise('Synthetic row', LiftLoadMode.total, '');
    expect(controller.message, isNotNull);
    expect(
      (await LiftLogDb.splits()).firstWhere((s) => s.id == split.id).exercises,
      hasLength(1),
    );
    expect(controller.workout!.exercises, hasLength(1));
  });
  test('removing an exercise cannot partially change its split', () async {
    await controller.removeExercise(
      controller.workout!.exercises.single.id,
      fromSplit: true,
    );
    expect(controller.message, isNotNull);
    expect(
      (await LiftLogDb.splits()).firstWhere((s) => s.id == split.id).exercises,
      hasLength(1),
    );
    expect(controller.workout!.exercises, hasLength(1));
  });
  test(
    'split synchronization rolls back if its workout write is refused',
    () async {
      final next = split.copy()..name = 'Renamed synthetic';
      await controller.saveSplits([next]);
      expect(controller.message, isNotNull);
      expect(
        (await LiftLogDb.splits()).firstWhere((s) => s.id == split.id).name,
        'Synthetic',
      );
      expect(controller.workout!.splitName, 'Synthetic');
    },
  );
  test(
    'a failed history refresh cannot report a committed set as unsaved',
    () async {
      await db.execute('DROP TRIGGER synthetic_lift_refusal');
      await RestTimer.setDefault(60);
      await db.insert('lift_log', {
        'id': 'synthetic-unreadable-history',
        'started_at': 1,
        'ended_at': 2,
        'origin': 'whoop',
        'json': '{unreadable',
        'updated_at': 1,
      });
      await controller.logSet(
        controller.workout!.exercises.single.id,
        reps: 8,
        load: 10,
      );
      expect((await LiftLogDb.forSession('synthetic-session'))!.setCount, 1);
      expect(controller.message, startsWith('Saved.'));
      expect(controller.message, isNot(contains('not saved')));
      expect(await RestTimer.deadline(), isNotNull);
      await db.delete(
        'lift_log',
        where: 'id=?',
        whereArgs: ['synthetic-unreadable-history'],
      );
      await controller.logSet(
        controller.workout!.exercises.single.id,
        reps: 9,
        load: 10,
      );
      expect((await LiftLogDb.forSession('synthetic-session'))!.setCount, 2);
      expect(controller.message, isNull);
      await RestTimer.skip();
    },
  );
  test(
    'an unreadable initial history remains an explicit read failure',
    () async {
      await db.execute('DROP TRIGGER synthetic_lift_refusal');
      await db.insert('lift_log', {
        'id': 'synthetic-unreadable-history',
        'started_at': 1,
        'ended_at': 2,
        'origin': 'whoop',
        'json': '{unreadable',
        'updated_at': 1,
      });
      await controller.load();
      expect(controller.message, startsWith('Your sets could not be read:'));
      expect((await LiftLogDb.forSession('synthetic-session'))!.setCount, 0);
    },
  );
}
