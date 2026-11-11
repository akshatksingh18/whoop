// A refused new start must not prevent finishing an older recovered clock.
// Startup reconciliation awaits SQLite and can finish after that failed tap.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' show DatabaseException;
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/gps/screen_wake.dart';
import 'package:whoop_companion/gps/workout_clock.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('recovered-start-refusal', fresh: true));
  setUp(() async {
    await resetCoverageStore();
    ScreenWake.resetForTest();
  });
  tearDown(() async {
    final db = await LocalDb.instance;
    await db.execute('DROP TRIGGER IF EXISTS authored_start_refusal');
    await db.execute('DROP TRIGGER IF EXISTS authored_finish_refusal');
    await WorkoutClock.flushWrites();
    WorkoutClock.current = null;
    await ScreenWake.release();
  });
  tearDownAll(LocalDb.close);
  for (final type in ['other', 'weight_training']) {
    for (final anchored in [false, true]) {
      for (final refuseFinish in [false, true]) {
        test(
          'Recovered $type anchored=$anchored finish-refused=$refuseFinish survives a refused competing start',
          () async {
            const id = 'authored-recovered',
                attempted = 'authored-refused-start';
            final profile = anchored
                ? const Profile(
                    ageYears: 30,
                    sex: 'f',
                    weightKg: 70,
                    heightCm: 170,
                  )
                : const Profile();
            final from = DateTime.now().subtract(const Duration(minutes: 20));
            await LocalDb.putSession({
              'id': id,
              'start_ts': from.millisecondsSinceEpoch ~/ 1000,
              'type': type,
              'status': 'live',
              'private': 1,
              'rpe': 7,
              'source': 'manual',
              'device_family': 'gen4',
              'created_at': 1,
            });
            await WorkoutClock(id, from, profile: profile).persist();
            await LocalDb.putSession({
              'id': 'authored-history',
              'start_ts': 1617724800,
              'end_ts': 1617726600,
              'status': 'done',
              'type': 'yoga',
              'source': 'manual',
              'created_at': 2,
              'private': 1,
              'calories': 123,
              'strain': 4.2,
              'avg_hr': 110,
            });
            await LocalDb.setCursor('authored-recovery', 'retain');
            final db = await LocalDb.instance;
            final history = await db.query(
              'sessions',
              where: 'id=?',
              whereArgs: ['authored-history'],
            );
            final cursors = await db.query('sync_cursor');
            final original = await LocalDb.session(id);
            final app = AppState.forTesting()..user = profile.toMap();
            app.repo = LocalRepositoryImpl(getProfileMap: () => app.user);
            addTearDown(app.dispose);
            await db.execute(
              "CREATE TRIGGER authored_start_refusal BEFORE INSERT ON sessions "
              "WHEN NEW.id='$attempted' BEGIN SELECT RAISE(ABORT,'authored start refusal'); END",
            );
            await expectLater(
              app.startWorkout(workoutId: attempted, type: type),
              throwsA(isA<DatabaseException>()),
            );
            expect(app.activeWorkout, isNull);
            expect(await LocalDb.session(attempted), isNull);
            expect(await LocalDb.session(id), original);

            // Run the actual startup continuation from the surviving stored row
            // and clock. No private failed-future or active-workout field is set.
            await app.debugReconcileOrphanedLiveWorkout();
            expect(app.activeWorkout!.workoutId, id);
            expect(app.activeWorkout!.type, type);
            expect(WorkoutClock.current!.profile!.weightKg, profile.weightKg);
            expect(
              await app.startWorkout(
                workoutId: 'must-not-replace',
                type: 'other',
              ),
              false,
            );
            expect(await LocalDb.session('must-not-replace'), isNull);
            if (refuseFinish) {
              await db.execute(
                "CREATE TRIGGER authored_finish_refusal BEFORE INSERT ON sessions "
                "WHEN NEW.id='$id' AND NEW.status='done' BEGIN SELECT RAISE(ABORT,'authored finish refusal'); END",
              );
              await expectLater(
                app.stopWorkout(),
                throwsA(isA<DatabaseException>()),
              );
              expect(app.activeWorkout!.workoutId, id);
              expect(WorkoutClock.current!.end, isNotNull);
              expect(WorkoutClock.current!.pendingSession, isNotNull);
              expect(await LocalDb.session(id), original);
              await db.execute('DROP TRIGGER authored_finish_refusal');
            }
            final pending = WorkoutClock.current!.pendingSession == null
                ? null
                : Map.of(WorkoutClock.current!.pendingSession!);
            await app.stopWorkout();
            expect(app.activeWorkout, isNull);
            expect(WorkoutClock.current, isNull);
            expect(
              app.logLines.any(
                (s) => s.contains(
                  'retrying the complete session write after start failure',
                ),
              ),
              true,
            );
            final saved = (await LocalDb.session(id))!;
            expect(saved['status'], 'done');
            expect(saved['start_ts'], original!['start_ts']);
            expect(
              saved['end_ts'] as int,
              greaterThanOrEqualTo(saved['start_ts'] as int),
            );
            expect(saved['duration_min'], greaterThanOrEqualTo(20));
            expect(saved['private'], 1);
            expect(saved['rpe'], 7);
            expect(saved['device_family'], 'gen4');
            expect(saved['source'], 'manual');
            expect(saved['type'], type);
            expect(saved['avg_hr'], isNull);
            expect(saved['max_hr'], isNull);
            expect(saved['steps'], isNull);
            if (pending != null) {
              for (final key in pending.keys) {
                expect(
                  saved[key],
                  pending[key],
                  reason: 'Retry must retain staged $key',
                );
              }
            }
            await app.stopWorkout();
            expect(await LocalDb.session(id), saved);
            expect(
              await db.query(
                'sessions',
                where: 'id=?',
                whereArgs: ['authored-history'],
              ),
              history,
            );
            expect(await db.query('sync_cursor'), cursors);
            expect(await LocalDb.session(attempted), isNull);
            expect(await db.query('sessions'), hasLength(2));
          },
        );
      }
    }
  }
}
