// F-3: `stopWorkout()` ended with `unawaited(LocalDb.putSession(sessionRow))`
// and cleared `activeWorkout` on the very next line. The in-memory session is
// the ONLY other copy — the `status='live'` row written at start carries no
// duration, no zones, no calories and no strain — so a failed write destroyed
// the whole workout while the summary screen rendered it in full, and it was
// gone on the next launch.

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/nutrition_store.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const name = 'workout_stop_durability_test.db';

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await LocalDb.close();
    LocalDb.dbName = name;
    await databaseFactory.deleteDatabase(
      p.join(await databaseFactory.getDatabasesPath(), name),
    );
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  tearDownAll(() async {
    await LocalDb.close();
    await databaseFactory.deleteDatabase(
      p.join(await databaseFactory.getDatabasesPath(), name),
    );
  });

  test(
    'a session that could not be written stays live instead of vanishing',
    () async {
      final app = AppState.forTesting();
      addTearDown(app.dispose);
      app.activeWorkout = LiveWorkoutState(
        startTime: DateTime.now().subtract(const Duration(minutes: 42)),
        targetKcal: 400,
        workoutId: 'w-durability',
        type: 'run',
      );

      // Make the durable write fail the way a real one would.
      final db = await LocalDb.instance;
      final insightsBefore = app.insightsRevision.value;
      final foodBefore = NutritionDb.revision.value;
      await db.execute('ALTER TABLE sessions RENAME TO sessions_hidden');
      await expectLater(app.stopWorkout(), throwsA(anything));

      // Before the fix this was null and the 42 minutes were gone.
      expect(app.insightsRevision.value, insightsBefore);
      expect(NutritionDb.revision.value, foodBefore);
      expect(app.activeWorkout, isNotNull);
      expect(app.activeWorkout!.workoutId, 'w-durability');

      // Every teardown step is idempotent, so calling stop again is a clean
      // retry — which is the only reason keeping it live is useful.
      await db.execute('ALTER TABLE sessions_hidden RENAME TO sessions');
      await app.stopWorkout();
      expect(app.activeWorkout, isNull);
      expect(app.insightsRevision.value, insightsBefore + 1);
      expect(NutritionDb.revision.value, foodBefore + 1);

      final rows = await db.query(
        'sessions',
        where: 'id = ?',
        whereArgs: ['w-durability'],
      );
      expect(rows, hasLength(1));
      expect(rows.first['status'], 'done');
      expect(
        (rows.first['end_ts'] as num).toInt() -
            (rows.first['start_ts'] as num).toInt(),
        greaterThan(2400),
        reason: 'the retry banked the real 42-minute window',
      );
    },
  );
  test('repository mutations publish only after their durable write', () async {
    final app = AppState.forTesting();
    addTearDown(app.dispose);
    final db = await LocalDb.instance;
    var signals = 0;
    final repo = LocalRepositoryImpl(
      getProfileMap: () => null,
      onSessionChanged: () {
        signals++;
        app.publishSessionChange();
      },
    );
    await db.execute('ALTER TABLE sessions RENAME TO sessions_hidden');
    await expectLater(repo.startWorkout('walk'), throwsA(anything));
    expect(signals, 0);
    await db.execute('ALTER TABLE sessions_hidden RENAME TO sessions');
    final result = await repo.startWorkout('walk');
    final id = result['workout_id'] as String;
    expect((await LocalDb.session(id))?['status'], 'live');
    expect(signals, 1);
    await repo.setWorkoutPrivate(id, true);
    expect(signals, 2);
    await repo.endWorkout(id);
    expect((await LocalDb.session(id))?['status'], 'done');
    expect(signals, 3);
    await repo.endWorkout(id);
    expect(signals, 3, reason: 'an unchanged row does not publish again');
  });
}
