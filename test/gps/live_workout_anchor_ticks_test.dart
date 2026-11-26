// Real workout start/tick/stop with authored current/stale HR and saved profile.
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/gps/workout_clock.dart';
import 'package:whoop_companion/gps/screen_wake.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'workout_pause_state_test.dart' show Band;
import '../support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('live-workout-anchor-ticks', fresh: true));
  setUp(() async {
    await resetCoverageStore();
    ScreenWake.resetForTest();
  });
  tearDownAll(LocalDb.close);
  for (final sex in ['f', 'm']) {
    for (final input in ['absent', 'resting', 'effort', 'expired']) {
      test(
        '$sex real live tick with $input HR preserves session anchors and no stale accrual',
        () async {
          final band = Band();
          band.state
            ..generation = 'gen4'
            ..connection = 'connected';
          final app = AppState.forTesting(engine: band)
            ..user = {
              'age': 30,
              'sex': sex,
              'height_cm': 170.0,
              'weight_kg': 70.0,
              'resting_hr': 55,
            };
          app.repo = LocalRepositoryImpl(getProfileMap: () => app.user);
          final id = 'authored-$sex-$input';
          try {
            expect(
              await app.startWorkout(
                workoutId: id,
                type: 'general_workout',
                met: 3,
              ),
              true,
            );
            await WorkoutClock.flushWrites();
            final workout = app.activeWorkout!;
            expect(workout.restingHr, 55);
            expect(workout.hrMax, isNotNull);
            final before = (await LocalDb.session(id))!;
            final maxHr = workout.hrMax;
            app.user = {...app.user!, 'age': 65, 'weight_kg': 110.0};
            band.state
              ..liveHr = input == 'absent'
                  ? null
                  : input == 'resting'
                  ? 55
                  : 160
              ..liveHrAt = input == 'absent'
                  ? null
                  : DateTime.now().millisecondsSinceEpoch -
                        (input == 'expired'
                            ? AppState.liveHrMaxAge.inMilliseconds + 1000
                            : 0);
            final zoneBefore = workout.zoneSeconds.fold<double>(
              0,
              (a, b) => a + b,
            );
            app.debugTickWorkout();
            final measured = input == 'resting' || input == 'effort';
            expect(
              workout.currentHr,
              measured ? (input == 'resting' ? 55 : 160) : null,
            );
            expect(
              workout.zoneSeconds.fold<double>(0, (a, b) => a + b),
              zoneBefore + (measured ? 1 : 0),
            );
            expect(workout.profile.weightKg, 70);
            expect(workout.profile.sex, sex);
            expect(workout.restingHr, 55);
            expect(workout.hrMax, maxHr);
            expect(app.activeWorkout, same(workout));
            expect((await LocalDb.session(id))!['status'], 'live');
            expect(
              (await LocalDb.session(id))!['start_ts'],
              before['start_ts'],
            );
            expect(await (await LocalDb.instance).query('day_result'), isEmpty);
            await app.stopWorkout();
            expect(app.activeWorkout, isNull);
            final saved = (await LocalDb.session(id))!;
            expect(saved['status'], 'done');
            expect(saved['start_ts'], before['start_ts']);
            expect(saved['type'], 'general_workout');
            expect(await (await LocalDb.instance).query('day_result'), isEmpty);
          } finally {
            app.dispose();
            await WorkoutClock.flushWrites();
            WorkoutClock.current = null;
            await ScreenWake.release();
          }
        },
      );
    }
  }
}
