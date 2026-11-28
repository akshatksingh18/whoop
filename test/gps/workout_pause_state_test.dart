// App-owned start/pause/resume/finish boundaries. All sensors and rows are authored.
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/ble/ble_engine.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/gps/workout_clock.dart';
import 'package:whoop_companion/gps/screen_wake.dart';
import 'package:whoop_companion/state/app_state.dart';
import '../support/coverage_store.dart';

class Band extends BleEngine {
  Band() : super(onRecord: (_, _) async {}, onState: (_) {});
  var enables = 0;
  @override
  bool get isConnected => true;
  @override
  bool get liveEnabled => false;
  @override
  Future<void> enableLiveStreams() async {
    enables++;
  }
}

const profile = Profile(ageYears: 30, sex: 'f', heightCm: 170, weightKg: 70);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState app;
  late Band band;
  setUpAll(() => coverageStore('workout-pause-state'));
  setUp(() async {
    await resetCoverageStore();
    ScreenWake.resetForTest();
    band = Band();
    band.state
      ..generation = 'gen4'
      ..connection = 'connected';
    app = AppState.forTesting(engine: band)..user = profile.toMap();
    app.repo = LocalRepositoryImpl(getProfileMap: () => app.user);
  });
  tearDown(() async {
    app.dispose();
    await WorkoutClock.flushWrites();
    WorkoutClock.current = null;
    await ScreenWake.release();
  });
  tearDownAll(LocalDb.close);
  Future<void> settle() async {
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    await WorkoutClock.flushWrites();
  }

  test(
    'the real pause callback retains the session and can resume before a durable finish',
    () async {
      await MetricSeriesStore.putValue(todayLabel(), 'rhr', 55);
      expect(
        await app.startWorkout(
          workoutId: 'synthetic-pause',
          type: 'general_workout',
          met: 3,
        ),
        true,
      );
      await settle();
      expect(band.enables, 1);
      expect(app.activeWorkout!.profile.weightKg, 70);
      expect(app.activeWorkout!.restingHr, 55);
      final clock = WorkoutClock.current!;
      clock.setPaused(true);
      await settle();
      app.debugTickWorkout();
      expect(WorkoutClock.read(clock.id, clock.start).pausedAt, isNotNull);
      expect(app.activeWorkout!.workoutId, clock.id);
      expect((await SessionStore.byId(clock.id))!['status'], 'live');
      clock.setPaused(false);
      await settle();
      expect(clock.pausedAt, isNull);
      expect(clock.pauses, hasLength(1));
      await app.stopWorkout();
      expect(app.activeWorkout, isNull);
      expect((await SessionStore.byId(clock.id))!['status'], 'done');
    },
  );
  test(
    'an active workout defers insight rebuilding without changing saved evidence',
    () async {
      expect(
        await app.startWorkout(
          workoutId: 'synthetic-defer',
          type: 'general_workout',
        ),
        true,
      );
      await app.rebuildInsights();
      expect(app.insightsRebuilding, false);
      expect(app.insightsRebuildMessage, startsWith('Finish the workout'));
      expect(await MetricSeriesStore.baseline('crossday'), isNull);
      await app.stopWorkout();
    },
  );
}
