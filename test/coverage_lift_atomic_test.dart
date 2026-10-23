// Fail the second half of a linked split/workout edit, not its first write.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/lift_log.dart';
import 'package:openstrap_edge/state/prefs.dart';
import 'package:openstrap_edge/ui2/activity/lift_log_ui.dart';

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
}
