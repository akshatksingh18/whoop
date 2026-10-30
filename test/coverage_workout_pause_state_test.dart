// App-owned start/pause/resume/finish boundaries. All sensors and rows are authored.
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/ble/ble_engine.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/gps/workout_clock.dart';
import 'package:whoop_companion/gps/screen_wake.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'support/coverage_store.dart';

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
    for (var i = 0; i < 10; i++)
      await Future<void>.delayed(const Duration(milliseconds: 5));
    await WorkoutClock.flushWrites();
  }

  void wave(int atMs, {int frames = 32}) {
    for (var f = 0; f < frames; f++) {
      app.debugFeedLiveAccel(
        [
          for (var i = 0; i < 200; i++)
            1 + .45 * math.sin(2 * math.pi * 2 * (f * 200 + i) / 100),
        ],
        recTs: atMs ~/ 1000 + f * 2,
        atMs: atMs + f * 2000,
      );
    }
  }

  test(
    'the real pause callback retains the session and can resume before a durable finish',
    () async {
      await LocalDb.putMetricSeriesValue(todayLabel(), 'rhr', 55);
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
      expect((await LocalDb.session(clock.id))!['status'], 'live');
      clock.setPaused(false);
      await settle();
      expect(clock.pausedAt, isNull);
      expect(clock.pauses, hasLength(1));
      await app.stopWorkout();
      expect(app.activeWorkout, isNull);
      expect((await LocalDb.session(clock.id))!['status'], 'done');
    },
  );
  test(
    'a partial passive gait minute is not joined across the start of non-gait work',
    () async {
      final at = DateTime.now().millisecondsSinceEpoch - 30000;
      wave(at, frames: 10);
      expect(
        await app.startWorkout(
          workoutId: 'synthetic-nongait',
          type: 'weight_training',
          met: 3.5,
        ),
        true,
      );
      wave(at + 20000, frames: 22);
      expect(app.workoutStepsMeasured, isNull);
      expect(app.workoutCadence, isNull);
      await app.stopWorkout();
      expect((await LocalDb.session('synthetic-nongait'))!['steps'], isNull);
    },
  );
  test(
    'pausing an on-foot session does not bill paused movement into its session count',
    () async {
      expect(
        await app.startWorkout(workoutId: 'synthetic-gait', type: 'walking'),
        true,
      );
      await settle();
      final at = DateTime.now().millisecondsSinceEpoch;
      wave(at);
      final before = app.workoutStepsMeasured;
      expect(before, greaterThan(0));
      expect(app.workoutCadence?.source, 'Wrist · last complete minute');
      final clock = WorkoutClock.current!;
      clock.setPaused(true);
      wave(at + 64000);
      expect(app.workoutStepsMeasured, before);
      clock.setPaused(false);
      await settle();
      // The first resumed chunk spans a pause and is excluded from the median;
      // three complete gait minutes are required by the retained cadence policy.
      wave(at + 128000, frames: 96);
      expect(app.workoutStepsMeasured, greaterThan(before!));
      await app.stopWorkout();
      expect(
        (await LocalDb.session('synthetic-gait'))!['cadence_spm'],
        greaterThan(0),
      );
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
      expect(await LocalDb.baseline('crossday'), isNull);
      await app.stopWorkout();
    },
  );
}
