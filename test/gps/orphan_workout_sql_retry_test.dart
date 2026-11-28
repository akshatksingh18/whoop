// Startup's actual orphan coordinator over transient SQLite refusal and retry.
// The existing debug entry calls the same coordinator as initialization; no fake rows reader.
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/gps/screen_wake.dart';
import 'package:whoop_companion/gps/workout_clock.dart';
import '../support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState app;
  setUpAll(() => coverageStore('orphan-sql-retry'));
  setUp(() async {
    await resetCoverageStore();
    app = AppState.forTesting();
    ScreenWake.resetForTest();
  });
  tearDown(() async {
    app.dispose();
    await WorkoutClock.flushWrites();
    WorkoutClock.current = null;
    ScreenWake.resetForTest();
    final db = await LocalDb.instance;
    await db.execute('DROP TRIGGER IF EXISTS authored_orphan_refusal');
    if ((await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE name='authored_hidden_sessions'",
    )).isNotEmpty) {
      await db.execute(
        'ALTER TABLE authored_hidden_sessions RENAME TO sessions',
      );
    }
  });
  tearDownAll(LocalDb.close);
  Future<Map<String, Object?>> seed(String id, int hours) async {
    final start =
        DateTime.now()
            .subtract(Duration(hours: hours))
            .millisecondsSinceEpoch ~/
        1000;
    await SessionStore.put({
      'id': id,
      'start_ts': start,
      'type': 'yoga',
      'status': 'live',
      'source': 'manual',
      'created_at': start * 1000,
    });
    return Map<String, Object?>.from((await SessionStore.byId(id))!);
  }

  for (final age in [1, 8]) {
    test(
      'orphan read refusal keeps $age-hour row and retry respects its age',
      () async {
        final db = await LocalDb.instance;
        final original = await seed('authored-read-orphan', age);
        await db.execute(
          'ALTER TABLE sessions RENAME TO authored_hidden_sessions',
        );
        await app.debugReconcileOrphanedLiveWorkout();
        expect(app.activeWorkout, isNull);
        expect((await db.query('authored_hidden_sessions')).single, original);
        await db.execute(
          'ALTER TABLE authored_hidden_sessions RENAME TO sessions',
        );
        await app.debugReconcileOrphanedLiveWorkout();
        final saved = (await SessionStore.byId('authored-read-orphan'))!;
        expect(saved['id'], original['id']);
        expect(saved['start_ts'], original['start_ts']);
        if (age == 1) {
          expect(app.activeWorkout!.workoutId, original['id']);
          expect(saved, original);
        } else {
          expect(app.activeWorkout, isNull);
          expect(saved['status'], 'done');
          expect(saved['end_ts_fabricated'], 1);
          expect(saved['duration_min'], isNull);
          expect(saved['calories'], isNull);
          expect(saved['strain'], isNull);
        }
        await app.debugReconcileOrphanedLiveWorkout();
        expect(await SessionStore.byId('authored-read-orphan'), saved);
      },
    );
  }
  for (final attempts in [1, 2]) {
    test(
      'stale orphan survives $attempts refused finalize writes before safe retry',
      () async {
        final db = await LocalDb.instance;
        final original = await seed('authored-write-orphan', 8);
        await SessionStore.put({
          'id': 'authored-unrelated',
          'start_ts': 1617724800,
          'end_ts': 1617726600,
          'type': 'yoga',
          'status': 'done',
          'created_at': 1,
        });
        final unrelated = await SessionStore.byId('authored-unrelated');
        await db.execute(
          "CREATE TRIGGER authored_orphan_refusal BEFORE INSERT ON sessions WHEN NEW.id='authored-write-orphan' BEGIN SELECT RAISE(ABORT,'authored finalize refusal'); END",
        );
        for (var i = 0; i < attempts; i++) {
          await app.debugReconcileOrphanedLiveWorkout();
          expect(app.activeWorkout, isNull);
          expect(await SessionStore.byId('authored-write-orphan'), original);
          expect(await SessionStore.byId('authored-unrelated'), unrelated);
        }
        await db.execute('DROP TRIGGER authored_orphan_refusal');
        final before = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        await app.debugReconcileOrphanedLiveWorkout();
        final saved = (await SessionStore.byId('authored-write-orphan'))!;
        expect(saved['status'], 'done');
        expect(saved['end_ts_fabricated'], 1);
        expect(saved['start_ts'], original['start_ts']);
        expect(saved['end_ts'], greaterThanOrEqualTo(before));
        expect(saved['duration_min'], isNull);
        expect(saved['calories'], isNull);
        expect(saved['strain'], isNull);
        expect(await SessionStore.byId('authored-unrelated'), unrelated);
        await app.debugReconcileOrphanedLiveWorkout();
        expect(await SessionStore.byId('authored-write-orphan'), saved);
        expect(await db.query('sessions'), hasLength(2));
      },
    );
  }
}
