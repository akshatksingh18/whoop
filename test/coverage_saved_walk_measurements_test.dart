// Authored saved walking sessions through the actual route/clock/SQLite readers.
// GPS comparison energy must remain separate from phone-step Budget evidence.
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/data/calculation_store.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/gps/route_models.dart';
import 'package:whoop_companion/gps/motion_window.dart';
import 'package:whoop_companion/gps/workout_clock.dart';
import 'package:whoop_companion/gps/workout_measurements.dart';
import 'package:whoop_companion/platform/phone_pedometer.dart';
import 'support/coverage_store.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  final start = DateTime(2021, 4, 6, 8);
  final end = start.add(const Duration(minutes: 10));
  const id = 'authored-saved-walk';
  const recorded = Profile(ageYears: 30, sex: 'f', heightCm: 170, weightKg: 70);
  const current = Profile(ageYears: 35, sex: 'f', heightCm: 170, weightKg: 110);
  int sec(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

  setUpAll(() async {
    await coverageStore('saved-walk-measurements', fresh: true);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(phoneStepsChannel, (
      call,
    ) async {
      calls.add(call);
      throw PlatformException(code: 'authored-history-has-no-native-sensor');
    });
  });
  setUp(() async {
    await resetCoverageStore();
    calls.clear();
  });
  tearDown(() async {
    await WorkoutClock.flushWrites();
    WorkoutClock.current = null;
  });
  tearDownAll(() async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      phoneStepsChannel,
      null,
    );
    await LocalDb.close();
  });

  for (final shape in ['steady', 'stopped-minute', 'zero']) {
    test(
      'saved phone-only walk $shape retains its measured active time and distance',
      () async {
        await LocalDb.putSession({
          'id': id,
          'type': 'walking',
          'status': 'done',
          'start_ts': sec(start),
          'end_ts': sec(end),
          'created_at': 1,
        });
        await WorkoutClock(id, start, end: end, profile: recorded).persist();
        final counts = [
          for (var i = 0; i < 10; i++)
            shape == 'zero' || (shape == 'stopped-minute' && i == 4) ? 0 : 60,
        ];
        final payload = jsonEncode(
          MotionWindow(start, 60, counts, [
            for (final n in counts) n == 0 ? 0.0 : 84.0,
          ], seconds: List.filled(10, 60)).toJson(),
        );
        final key = 'motion.$id.${sec(start)}-${sec(end)}';
        await CalculationStore.write(key, payload);
        if (shape == 'zero') {
          await LocalDb.replacePhoneCoverageForDay(dayLabelOf(start), [
            (startTs: sec(start), endTs: sec(end), steps: 0),
          ]);
        }
        final before = (await LocalDb.session(id))!;
        final result = await WorkoutMeasurements.read(
          LocalRepositoryImpl(getProfileMap: () => current.toMap()),
          id,
          start,
          end,
          current,
          bandSteps: 9999,
        );
        final active = shape == 'zero'
            ? 0
            : shape == 'steady'
            ? 600
            : 540;
        expect(result.points, isEmpty);
        expect(result.motion, isNotNull);
        expect(result.movingSec, active);
        expect(result.steps, active);
        expect(result.meters, closeTo(active * 1.4, 1e-9));
        expect(
          result.acsm('walking'),
          closeTo(.0005 * 70 * active * 1.4, 1e-9),
        );
        expect(
          result.method1('walking'),
          closeTo(2.74 * active * 70 / 8368, 1e-9),
        );
        expect(result.profile.weightKg, 70);
        expect(calls, isEmpty);
        expect(await CalculationStore.read(key), payload);
        expect(await LocalDb.session(id), before);
        expect(await LocalDb.routePoints(id), isEmpty);
        expect(await (await LocalDb.instance).query('day_result'), isEmpty);
      },
    );
  }

  for (final shape in ['continuous', 'signal-gap', 'paused']) {
    for (final evidence in ['measured', 'zero', 'absent']) {
      test(
        'saved walk $shape with $evidence steps keeps independent evidence',
        () async {
          final paused = shape == 'paused';
          await LocalDb.putSession({
            'id': id,
            'type': 'walking',
            'status': 'done',
            'start_ts': sec(start),
            'end_ts': sec(end),
            'created_at': 1617696000000,
            'source': 'manual',
            'private': 1,
            'rpe': 4,
          });
          await WorkoutClock(
            id,
            start,
            end: end,
            profile: recorded,
            pauses: [
              if (paused)
                (
                  start: start.add(const Duration(minutes: 4)),
                  end: start.add(const Duration(minutes: 6)),
                ),
            ],
          ).persist();
          await LocalDb.appendRoutePoints(id, [
            for (var i = 0; i <= 60; i++)
              if (shape != 'signal-gap' || i <= 20 || i >= 30)
                RoutePoint(
                  seq: i,
                  tsMs: start.millisecondsSinceEpoch + i * 10000,
                  lat: 0,
                  lng: i * 14 / 111319.49079327357,
                  alt: 0,
                  accuracy: 5,
                  speed: 1.4,
                ).toRow(id),
          ]);
          if (evidence != 'absent') {
            await LocalDb.replacePhoneCoverageForDay(dayLabelOf(start), [
              (
                startTs: sec(start),
                endTs: sec(end),
                steps: evidence == 'zero' ? 0 : 600,
              ),
            ]);
          }
          final before = (await LocalDb.session(id))!;
          final route = await LocalDb.routePoints(id);
          final coverage = await (await LocalDb.instance).query(
            'live_coverage',
          );
          final repo = LocalRepositoryImpl(
            getProfileMap: () => current.toMap(),
          );
          final result = await WorkoutMeasurements.read(
            repo,
            id,
            start,
            end,
            current,
            bandSteps: 9999,
          );
          final moving = paused
              ? 480
              : shape == 'signal-gap'
              ? 500
              : 600;
          expect(result.movingSec, moving);
          expect(result.meters, closeTo(moving * 1.4, .001));
          expect(
            result.profile.weightKg,
            70,
            reason: 'The saved session profile owns historical estimates',
          );
          expect(
            result.motion,
            isNull,
            reason:
                'A real GPS track must not be supplemented with phone distance',
          );
          final steps = evidence == 'absent'
              ? null
              : evidence == 'zero'
              ? 0
              : paused
              ? 480
              : 600;
          expect(
            result.steps,
            steps,
            reason: 'Band counts cannot fill unknown phone-step evidence',
          );
          expect(
            result.method1('walking'),
            steps == null ? isNull : closeTo(2.74 * steps * 70 / 8368, 1e-9),
          );
          expect(
            result.acsm('walking'),
            closeTo(.0005 * 70 * moving * 1.4, .001),
          );
          expect(result.movementEstimate('walking'), result.acsm('walking'));
          expect(
            calls,
            isEmpty,
            reason: 'Reading saved GPS must not request phone permission',
          );
          expect(await LocalDb.session(id), before);
          expect(await LocalDb.routePoints(id), route);
          expect(
            await (await LocalDb.instance).query('live_coverage'),
            coverage,
          );
          expect(await (await LocalDb.instance).query('day_result'), isEmpty);
        },
      );
    }
  }
}
