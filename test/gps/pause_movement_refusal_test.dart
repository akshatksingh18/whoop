// A pause can request a movement refresh before the next timer tick.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/gps/screen_wake.dart';
import 'package:whoop_companion/gps/workout_clock.dart';
import 'package:whoop_companion/state/app_state.dart';

import '../ble/durable_boundary_test.dart' show until;
import '../support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('pause-movement-read-refusal'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  test(
    'pausing keeps its confirmed boundary through a refused movement refresh',
    () async {
      final app = AppState.forTesting()
        ..user = {'age': 30, 'sex': 'f', 'weight_kg': 70, 'height_cm': 170};
      app.repo = LocalRepositoryImpl(getProfileMap: () => app.user);
      addTearDown(() async {
        app.dispose();
        await WorkoutClock.flushWrites();
        WorkoutClock.current = null;
        await ScreenWake.release();
      });
      const id = 'authored-pause-route-refusal';
      expect(
        await app.startWorkout(workoutId: id, type: 'general_workout'),
        isTrue,
      );
      final active = app.activeWorkout!;
      final clock = WorkoutClock.current!;
      final db = await LocalDb.instance;
      final saved = await SessionStore.byId(id);
      final route = await db.query('workout_route');

      await db.execute(
        'ALTER TABLE workout_route RENAME TO authored_retained_route',
      );
      DateTime? pausedAt;
      try {
        clock.setPaused(true);
        pausedAt = clock.pausedAt;
        expect(pausedAt, isNotNull);
        await until(
          () => app.logLines.any(
            (line) => line.contains('[workout] movement refresh failed:'),
          ),
        );
        await WorkoutClock.flushWrites();
        final timing = await MetricSeriesStore.baseline(
          'calculation:workout.clock.$id',
        );
        final persisted = jsonDecode(timing!['payload_json'] as String) as Map;
        expect(persisted['paused'], pausedAt!.millisecondsSinceEpoch);
        expect(persisted['end'], isNull);
        expect(app.activeWorkout, same(active));
        expect(await SessionStore.byId(id), saved);
        expect(await db.query('authored_retained_route'), route);
      } finally {
        await db.execute(
          'ALTER TABLE authored_retained_route RENAME TO workout_route',
        );
      }

      final revision = app.insightsRevision.value;
      clock.setPaused(false);
      await until(() => app.insightsRevision.value > revision);
      await WorkoutClock.flushWrites();
      expect(clock.pauses.single.start, pausedAt);
      expect(clock.pausedAt, isNull);
      expect(app.activeWorkout, same(active));
      expect(await SessionStore.byId(id), saved);

      await app.stopWorkout();
      expect(app.activeWorkout, isNull);
      final done = (await SessionStore.byId(id))!;
      expect(done['status'], 'done');
      expect(done['start_ts'], saved!['start_ts']);
      expect(done['steps'], isNull);
      expect(await db.query('workout_route'), route);
    },
  );
}
