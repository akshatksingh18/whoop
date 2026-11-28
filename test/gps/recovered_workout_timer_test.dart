import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/gps/workout_clock.dart';
import 'package:whoop_companion/state/app_state.dart';

import '../support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('recovered-workout-timer', fresh: true));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  for (final paused in [false, true]) {
    test('restored yoga timer respects a persisted pause: $paused', () async {
      const id = 'authored-resumed-yoga';
      final startSec =
          DateTime.now()
              .subtract(const Duration(minutes: 10))
              .millisecondsSinceEpoch ~/
          1000;
      final start = DateTime.fromMillisecondsSinceEpoch(startSec * 1000);
      final pause = paused ? start.add(const Duration(minutes: 2)) : null;
      await SessionStore.put({
        'id': id,
        'type': 'yoga',
        'status': 'live',
        'start_ts': startSec,
        'end_ts': null,
        'source': 'manual',
        'created_at': startSec * 1000,
      });
      await WorkoutClock(id, start, pausedAt: pause).persist();
      expect(WorkoutClock.current, isNull);
      final original = await SessionStore.byId(id);
      final app = AppState.forTesting();
      try {
        await app.debugReconcileOrphanedLiveWorkout();
        final live = app.activeWorkout!;
        expect(live.workoutId, id);
        expect(WorkoutClock.current?.pausedAt, pause);
        // Wait for the coordinator's own timer rather than calling the test
        // tick seam. The retained SQL row must not acquire synthetic samples.
        for (
          var attempt = 0;
          attempt < 60 && live.elapsed == Duration.zero;
          attempt++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 40));
        }
        expect(live.elapsed, greaterThan(Duration.zero));
        if (paused) {
          expect(live.elapsed, const Duration(minutes: 2));
        } else {
          expect(live.elapsed.inSeconds, greaterThanOrEqualTo(600));
          expect(
            live.elapsed,
            lessThanOrEqualTo(DateTime.now().difference(start)),
          );
        }
        expect(live.currentHr, isNull);
        expect(await SessionStore.byId(id), original);
        await app.debugReconcileOrphanedLiveWorkout();
        expect(identical(app.activeWorkout, live), isTrue);
        expect(await SessionStore.byId(id), original);
      } finally {
        app.dispose();
        await WorkoutClock.flushWrites();
      }
    });
  }
}
