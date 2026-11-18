// Actual workout start/pause/resume boundaries with authored native cadence replies.
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/gps/screen_wake.dart';
import 'package:whoop_companion/gps/workout_clock.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'support/coverage_store.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('whoop/phone_cadence');
  late AppState app;
  late List<int> starts;
  late int stops;
  setUpAll(() => coverageStore('workout-phone-cadence'));
  setUp(() async {
    await resetCoverageStore();
    ScreenWake.resetForTest();
    starts = [];
    stops = 0;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'start') {
        starts.add((call.arguments as Map)['generation'] as int);
      } else if (call.method == 'stop') {
        stops++;
      }
      return true;
    });
    app = AppState.forTesting()
      ..phoneStepsEnabled = true
      ..user = const Profile(
        ageYears: 30,
        sex: 'f',
        weightKg: 70,
        heightCm: 170,
      ).toMap();
    app.repo = LocalRepositoryImpl(getProfileMap: () => app.user);
  });
  tearDown(() async {
    app.dispose();
    await WorkoutClock.flushWrites();
    WorkoutClock.current = null;
    await ScreenWake.release();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });
  tearDownAll(LocalDb.close);

  Future<void> sample(int generation, double rate, {int ageMs = 0}) async {
    final done = Completer<void>();
    binding.channelBuffers.push(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('cadence', {
          'generation': generation,
          'stepsPerSecond': rate,
          'atMs': DateTime.now().millisecondsSinceEpoch - ageMs,
        }),
      ),
      (_) => done.complete(),
    );
    await done.future;
  }

  for (final type in ['indoor_walking', 'treadmill']) {
    test(
      'COV-48 $type phone cadence cannot cross a real pause or session',
      () async {
        final id = 'authored-cadence-$type';
        expect(await app.startWorkout(workoutId: id, type: type), true);
        expect(starts, hasLength(1));
        final first = starts.single;
        expect(app.workoutCadence, isNull);
        await sample(first, 2.5);
        expect(app.workoutCadence, (spm: 150.0, source: 'Your phone'));
        final clock = WorkoutClock.current!;
        clock.setPaused(true);
        expect(app.workoutCadence, isNull);
        expect(stops, 1);
        clock.setPaused(false);
        expect(starts, hasLength(2));
        expect(starts.last, isNot(first));
        await sample(first, 3);
        expect(app.workoutCadence, isNull);
        await sample(starts.last, 1);
        expect(app.workoutCadence, (spm: 60.0, source: 'Your phone'));
        await app.stopWorkout();
        expect(app.workoutCadence, isNull);
        expect(stops, 2);
        expect((await LocalDb.session(id))!['status'], 'done');
        expect(
          (await LocalDb.session(id))!['steps'],
          isNull,
          reason: 'A rate reply alone is not a measured session step count',
        );
        expect(await app.startWorkout(workoutId: '$id-next', type: type), true);
        await sample(first, 3);
        expect(app.workoutCadence, isNull);
        await sample(starts.last, 2);
        expect(app.workoutCadence, (spm: 120.0, source: 'Your phone'));
        await app.stopWorkout();
      },
    );
  }

  test(
    'COV-48 live cadence keeps measured zero distinct from invalid or stale input',
    () async {
      expect(
        await app.startWorkout(
          workoutId: 'authored-cadence-quality',
          type: 'indoor_walking',
        ),
        true,
      );
      final generation = starts.single;
      await sample(generation, 0);
      expect(app.workoutCadence, (spm: 0.0, source: 'Your phone'));
      await sample(generation, 2, ageMs: 30000);
      expect(app.workoutCadence, isNull);
      await sample(generation, 2, ageMs: -10000);
      expect(app.workoutCadence, isNull);
      await sample(generation, -1);
      expect(app.workoutCadence, isNull);
      await sample(generation, 2);
      expect(app.workoutCadence, (spm: 120.0, source: 'Your phone'));
      await app.stopWorkout();
      expect(
        (await LocalDb.session('authored-cadence-quality'))!['steps'],
        isNull,
      );
    },
  );

  for (final phoneEnabled in [false, true]) {
    test(
      'COV-48 phone option $phoneEnabled starts cadence only for a gait workout',
      () async {
        app.phoneStepsEnabled = phoneEnabled;
        expect(
          await app.startWorkout(
            workoutId: 'authored-cadence-other',
            type: 'general_workout',
            met: 3,
          ),
          true,
        );
        expect(starts, isEmpty);
        expect(app.workoutCadence, isNull);
        await app.stopWorkout();
        expect(
          await app.startWorkout(
            workoutId: 'authored-cadence-gait',
            type: 'indoor_walking',
          ),
          true,
        );
        expect(starts, hasLength(phoneEnabled ? 1 : 0));
        expect(app.workoutCadence, isNull);
        await app.stopWorkout();
      },
    );
  }
}
