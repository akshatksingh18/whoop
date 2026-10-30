// Real workout lifecycle and SQLite read failure; no production timer seam.
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/gps/screen_wake.dart';
import 'package:whoop_companion/gps/workout_clock.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('live-movement-read-retry'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  test(
    'COV-48 periodic movement read failure is throttled and recovers without ending the live workout',
    () async {
      final app = AppState.forTesting()
        ..user = const Profile(
          ageYears: 30,
          sex: 'f',
          weightKg: 70,
          heightCm: 170,
        ).toMap();
      app.repo = LocalRepositoryImpl(getProfileMap: () => app.user);
      addTearDown(() async {
        app.dispose();
        await WorkoutClock.flushWrites();
        WorkoutClock.current = null;
        await ScreenWake.release();
      });
      const id = 'authored-periodic-movement';
      expect(
        await app.startWorkout(workoutId: id, type: 'general_workout', met: 3),
        true,
      );
      await WorkoutClock.flushWrites();
      final clock = WorkoutClock.current!;
      final active = app.activeWorkout;
      final db = await LocalDb.instance;
      final row = await LocalDb.session(id);
      final routes = await db.query('workout_route');
      var restored = false;
      await db.execute(
        'ALTER TABLE workout_route RENAME TO authored_route_retained',
      );
      Future<void> until(bool Function() ready) async {
        for (var i = 0; i < 100 && !ready(); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(ready(), true, reason: app.logLines.join('\n'));
      }

      int failures() => app.logLines
          .where((s) => s.contains('[workout] movement refresh failed:'))
          .length;
      try {
        app.debugTickWorkout();
        await until(() => failures() == 1);
        expect(app.activeWorkout, same(active));
        expect(clock.end, isNull);
        expect(await LocalDb.session(id), row);
        expect(await db.query('authored_route_retained'), routes);
        app.debugTickWorkout();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(
          failures(),
          1,
          reason: 'a refused read must not be retried every tick',
        );
        await db.execute(
          'ALTER TABLE authored_route_retained RENAME TO workout_route',
        );
        restored = true;
        final revision = app.insightsRevision.value;
        clock.setPaused(true);
        await until(() => app.insightsRevision.value > revision);
        expect(app.activeWorkout, same(active));
        expect(clock.pausedAt, isNotNull);
        expect((await LocalDb.session(id))!['status'], 'live');
        expect(failures(), 1);
        clock.setPaused(false);
        await WorkoutClock.flushWrites();
        await app.stopWorkout();
        expect(app.activeWorkout, isNull);
        final saved = (await LocalDb.session(id))!;
        expect(saved['status'], 'done');
        expect(saved['steps'], isNull);
        expect(saved['type'], 'general_workout');
        expect(saved['start_ts'], row!['start_ts']);
        expect(await db.query('workout_route'), routes);
        expect(failures(), 1);
      } finally {
        if (!restored) {
          await db.execute(
            'ALTER TABLE authored_route_retained RENAME TO workout_route',
          );
        }
      }
    },
  );
}
