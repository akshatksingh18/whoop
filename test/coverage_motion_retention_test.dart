// Retained phone-motion answers and pause boundaries, with a synthetic native channel.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whoop_companion/data/calculation_store.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/gps/motion_window.dart';
import 'package:whoop_companion/gps/workout_clock.dart';
import 'package:whoop_companion/state/prefs.dart';

String key(String id, DateTime a, DateTime b) =>
    'motion.$id.${a.millisecondsSinceEpoch ~/ 1000}-${b.millisecondsSinceEpoch ~/ 1000}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('whoop/phone_steps');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late DateTime start, end;
  late Object? response;
  var calls = <MethodCall>[];
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final root = await Directory(
      'build/coverage-expansion/motion',
    ).create(recursive: true);
    LocalDb.dbName = '${root.absolute.path}/synthetic.sqlite';
    await LocalDb.close();
    await databaseFactory.deleteDatabase(LocalDb.dbName);
    await LocalDb.instance;
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.ensureLoaded();
    await LocalDb.wipeAll();
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    WorkoutClock.current = null;
    start = DateTime.now().subtract(const Duration(days: 3));
    end = start.add(const Duration(seconds: 90));
    response = {
      'chunkSec': 60,
      'steps': [60, 30],
      'meters': [45.0, -1.0],
    };
    calls = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (response is Exception) throw response!;
      return response;
    });
  });
  tearDown(() async {
    await WorkoutClock.flushWrites();
    WorkoutClock.current = null;
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });
  tearDownAll(LocalDb.close);

  test(
    'a complete window persists actual final seconds and absent distance',
    () async {
      final w = (await motionWindow('synthetic', start, end))!;
      expect(w.steps, [60, 30]);
      expect(w.meters, [45, null]);
      expect(w.seconds, [60, 30]);
      expect(w.activeMinutes, 1.5);
      expect(w.cadence, 60);
      expect(w.totalMeters, 45);
      expect(calls.single.arguments, {
        'fromMs': start.millisecondsSinceEpoch,
        'toMs': end.millisecondsSinceEpoch,
        'chunkSec': 60,
      });
      expect(
        await CalculationStore.read(key('synthetic', start, end)),
        isNotNull,
      );
      response = PlatformException(code: 'motion-off');
      expect(
        (await motionWindow('synthetic', start, end))!.toJson(),
        w.toJson(),
      );
      expect(
        calls,
        hasLength(1),
        reason: 'a retained answer survives sensor retention',
      );
    },
  );
  test(
    'live motion grows without freezing a partial answer; explicit completion caches it',
    () async {
      end = DateTime.now();
      start = end.subtract(const Duration(seconds: 90));
      expect((await motionWindow('live', start, end))!.totalSteps, 90);
      expect(await CalculationStore.read(key('live', start, end)), isNull);
      response = {
        'steps': [70, 40],
        'meters': [50.0, 25.0],
      };
      expect(
        (await motionWindow('live', start, end, cacheResult: true))!.totalSteps,
        110,
      );
      expect(await CalculationStore.read(key('live', start, end)), isNotNull);
      expect(calls, hasLength(2));
    },
  );
  test(
    'legacy cached durations are clipped to the actual session end without radio',
    () async {
      final legacy = MotionWindow(start, 60, [60, 30], [45, 20]);
      await CalculationStore.write(
        key('old', start, end),
        jsonEncode(legacy.toJson()),
      );
      final w = (await motionWindow('old', start, end))!;
      expect(w.seconds, [60, 30]);
      expect(w.cadence, 60);
      expect(calls, isEmpty);
    },
  );
  test(
    'old unavailable cache abstains; recent unavailable cache can be retried',
    () async {
      final old = start.subtract(const Duration(days: 10)),
          stop = end.subtract(const Duration(days: 10));
      await CalculationStore.write(key('old', old, stop), 'none');
      expect(await motionWindow('old', old, stop), isNull);
      expect(calls, isEmpty);
      await CalculationStore.write(key('recent', start, end), 'none');
      expect((await motionWindow('recent', start, end))!.totalSteps, 90);
      expect(calls, hasLength(1));
    },
  );
  test(
    'corrupt retained JSON retries the platform rather than presenting zero motion',
    () async {
      await CalculationStore.write(key('bad', start, end), '{not json');
      expect((await motionWindow('bad', start, end))!.totalSteps, 90);
      expect(calls, hasLength(1));
    },
  );
  for (final bad in <Object?>[
    null,
    -1,
    'unavailable',
    {
      'chunkSec': 0,
      'steps': [1],
      'meters': [1],
    },
    {
      'steps': 'not an array',
      'meters': [1],
    },
    {
      'steps': [1],
      'meters': [],
    },
    {
      'steps': [-1],
      'meters': [1],
    },
    {
      'steps': [1],
      'meters': [double.infinity],
    },
    {
      'steps': [1, 2, 3],
      'meters': [1, 2, 3],
    },
    PlatformException(code: 'motion-denied'),
    MissingPluginException(),
  ]) {
    test(
      'unusable native answer ${bad.runtimeType} ${bad is Map ? bad.keys : bad} abstains',
      () async {
        response = bad;
        expect(await motionWindow('bad', start, end), isNull);
        expect(await CalculationStore.read(key('bad', start, end)), isNull);
      },
    );
  }
  test('invalid time windows and non-iOS do not query native motion', () async {
    expect(await motionWindow('', start, end), isNull);
    expect(await motionWindow('id', end, start), isNull);
    expect(await motionWindow('id', start, start), isNull);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(await motionWindow('id', start, end), isNull);
    expect(calls, isEmpty);
  });
  test(
    'measured stationary chunks remain zero with absent cadence and distance',
    () async {
      response = {
        'steps': [0, 0],
        'meters': [-1.0, -1.0],
      };
      final w = (await motionWindow('stationary', start, end))!;
      expect(w.totalSteps, 0);
      expect(w.totalMeters, isNull);
      expect(w.activeMinutes, 0);
      expect(w.cadence, isNull);
      expect(w.splits(), isEmpty);
    },
  );
  test(
    'paused session requests only active windows and keeps their absolute instants',
    () async {
      end = start.add(const Duration(minutes: 3));
      WorkoutClock.current = WorkoutClock(
        'paused',
        start,
        end: end,
        pauses: [
          (
            start: start.add(const Duration(minutes: 1)),
            end: start.add(const Duration(minutes: 2)),
          ),
        ],
      );
      response = {
        'chunkSec': 60,
        'steps': [60],
        'meters': [45.0],
      };
      final w = (await sessionMotionWindow('paused', start, end))!;
      expect(calls, hasLength(2));
      expect(w.steps, [60, 60]);
      expect(w.totalMeters, 90);
      expect(w.timesMs, [
        start.millisecondsSinceEpoch,
        start.add(const Duration(minutes: 2)).millisecondsSinceEpoch,
      ]);
      expect(w.activeMinutes, 2);
    },
  );
  test(
    'session crossing midnight requests separate calendar windows',
    () async {
      final day = DateTime.now().subtract(const Duration(days: 3));
      start = DateTime(day.year, day.month, day.day, 23, 59);
      end = start.add(const Duration(minutes: 2));
      WorkoutClock.current = WorkoutClock('midnight', start, end: end);
      response = {
        'steps': [60],
        'meters': [45.0],
      };
      final w = (await sessionMotionWindow('midnight', start, end))!;
      expect(calls, hasLength(2));
      expect(w.totalSteps, 120);
      expect(w.seconds, [60, 60]);
      expect(w.totalMeters, 90);
    },
  );
  test(
    'one missing active interval prevents a falsely complete session answer',
    () async {
      end = start.add(const Duration(minutes: 3));
      WorkoutClock.current = WorkoutClock(
        'partial',
        start,
        end: end,
        pauses: [
          (
            start: start.add(const Duration(minutes: 1)),
            end: start.add(const Duration(minutes: 2)),
          ),
        ],
      );
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return calls.length == 1
            ? {
                'steps': [60],
                'meters': [45.0],
              }
            : null;
      });
      expect(await sessionMotionWindow('partial', start, end), isNull);
      expect(calls, hasLength(2));
    },
  );
  test(
    'sub-minute clipping apportions measured steps only within measured chunks',
    () {
      final w = MotionWindow(
        start,
        60,
        [61, 30],
        [100, null],
        seconds: [60, 30],
      );
      final clipped = w.within([
        (
          start: start.add(const Duration(seconds: 15)),
          end: start.add(const Duration(seconds: 45)),
        ),
        (
          start: start.add(const Duration(seconds: 70)),
          end: start.add(const Duration(seconds: 90)),
        ),
      ]);
      expect(clipped.steps, [31, 20]);
      expect(clipped.meters, [50, null]);
      expect(clipped.seconds, [30, 20]);
      expect(clipped.totalSteps, 51);
      expect(clipped.totalMeters, 50);
      expect(
        clipped.timeAt(1),
        start.add(const Duration(seconds: 70)).millisecondsSinceEpoch,
      );
    },
  );
  for (final bad in [
    {
      'seconds': [0, 30],
    },
    {
      'seconds': [61, 30],
    },
    {
      'seconds': [60],
    },
    {
      'times': [double.nan, 1],
    },
    {
      'times': [1],
    },
  ]) {
    test('malformed retained optional field $bad is absent', () {
      expect(
        MotionWindow.fromJson({
          's': start.millisecondsSinceEpoch,
          'c': 60,
          'steps': [60, 30],
          'm': [45, null],
          ...bad,
        }),
        isNull,
      );
    });
  }
}
