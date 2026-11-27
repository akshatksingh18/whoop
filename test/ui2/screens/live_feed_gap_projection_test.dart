// The live host must preserve the minute positions of observed HR and silence.
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/gps/workout_clock.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/screens/workout_screen.dart';
import '../../support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('live-feed-gap-projection'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  for (final anchored in [false, true]) {
    for (final scenario in [
      'silent',
      'tail',
      'internal-and-tail',
      'current-minute',
    ]) {
      test(
        'live host $scenario preserves observation positions with anchors=$anchored',
        () async {
          final app = AppState.forTesting();
          addTearDown(app.dispose);
          final start = DateTime.utc(2021, 4, 6, 12);
          const id = 'authored-feed-projection';
          const profile = Profile(
            ageYears: 30,
            sex: 'f',
            heightCm: 170,
            weightKg: 70,
          );
          final live = LiveWorkoutState(
            startTime: start,
            targetKcal: 0,
            workoutId: id,
            type: 'general_workout',
            profile: anchored ? profile : const Profile(),
            hrMax: anchored ? 190 : null,
            restingHr: anchored ? 60 : null,
          );
          app.activeWorkout = live;
          await LocalDb.putSession({
            'id': id,
            'type': live.type,
            'start_ts': start.millisecondsSinceEpoch ~/ 1000,
            'created_at': 1,
            'status': 'live',
            'source': 'manual',
            'private': 1,
          });
          await WorkoutClock(id, start).persist();
          if (scenario != 'silent') {
            live.accrueHr(100);
            if (scenario == 'internal-and-tail') {
              live.elapsed = const Duration(minutes: 3);
              live.accrueHr(140);
            }
          }
          live.elapsed = Duration(
            minutes: scenario == 'current-minute' ? 0 : 5,
          );
          final ownCurve = live.perMinuteHrDense();
          final calories = live.calories;
          final strain = live.strain;
          final saved = await LocalDb.session(id);
          final clock = await LocalDb.baseline('calculation:workout.clock.$id');
          final host = activityHost(app);
          for (var redraw = 0; redraw < 2; redraw++) {
            final feed = host.feed!();
            expect(feed.hrCurve, switch (scenario) {
              'silent' => <double?>[],
              'tail' => <double?>[100, null, null, null, null, null],
              'internal-and-tail' => <double?>[
                100,
                null,
                null,
                140,
                null,
                null,
              ],
              _ => <double?>[100],
            });
            expect(
              feed.hr,
              isNull,
              reason: 'Old session samples are not fresh live HR',
            );
            expect(feed.strain, strain);
            expect(live.calories, calories);
            expect(live.perMinuteHrDense(), ownCurve);
            expect(app.activeWorkout, same(live));
            expect(await LocalDb.session(id), saved);
            expect(
              await LocalDb.baseline('calculation:workout.clock.$id'),
              clock,
            );
          }
        },
      );
    }
  }
}
