// Dart/native-channel contracts and real authored SQLite; no sensor acceptance claim.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/gps/workout_clock.dart';
import 'package:whoop_companion/platform/phone_pedometer.dart';
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final day = DateTime(2021, 4, 6);
  int sec(DateTime at) => at.millisecondsSinceEpoch ~/ 1000;
  final calls = <MethodCall>[];
  Object? movement;
  bool fail = false;
  setUpAll(() => coverageStore('phone-window-contracts'));
  setUp(() async {
    await resetCoverageStore();
    calls.clear();
    fail = false;
    movement = {'steps': 10, 'distance_m': 5.0};
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    messenger.setMockMethodCallHandler(phoneStepsChannel, (call) async {
      calls.add(call);
      if (fail) throw PlatformException(code: 'authored_sensor_refusal');
      return switch (call.method) {
        'movementInInterval' => movement,
        'stepsInInterval' => 10,
        'authorized' => false,
        _ => null,
      };
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(phoneStepsChannel, null);
    debugDefaultTargetPlatformOverride = null;
    WorkoutClock.current = null;
  });
  tearDownAll(LocalDb.close);

  for (final live in [false, true]) {
    test(
      'phone windows split around ${live ? 'live' : 'saved'} session pauses without duplicating counts',
      () async {
        final start = day.add(const Duration(hours: 8, minutes: 10));
        final pause = day.add(const Duration(hours: 8, minutes: 20));
        final resume = day.add(const Duration(hours: 8, minutes: 30));
        final end = day.add(const Duration(hours: 8, minutes: 40));
        final clock = WorkoutClock(
          'authored-walk',
          start,
          end: end,
          pauses: [(start: pause, end: resume)],
        );
        if (live) {
          WorkoutClock.current = clock;
        } else {
          await clock.persist();
          await LocalDb.putSession({
            'id': clock.id,
            'type': 'walking',
            'start_ts': sec(start),
            'end_ts': sec(end),
            'status': 'done',
            'created_at': sec(start) * 1000,
            'source': 'manual',
          });
        }
        // Return counts proportional to the requested duration, so splitting must
        // leave the daily total unchanged and every second belongs to one row.
        final windows = <(int, int)>[];
        final ped = PhonePedometer(
          stepReader: (from, to) async {
            windows.add((sec(from), sec(to)));
            return to.difference(from).inMinutes;
          },
        );
        expect(await ped.syncDay(day), 1440);
        final cuts = {
          for (final w in windows) w.$1,
          for (final w in windows) w.$2,
        };
        for (final at in [start, pause, resume, end]) {
          expect(cuts, contains(sec(at)));
        }
        expect(windows.first.$1, sec(day));
        expect(windows.last.$2, sec(DateTime(2021, 4, 7)));
        for (var i = 1; i < windows.length; i++) {
          expect(windows[i].$1, windows[i - 1].$2);
        }
        final db = await LocalDb.instance;
        final rows = await db.query('live_coverage');
        expect(rows, hasLength(windows.length));
        expect(await LocalDb.phoneStepsForDay('2021-04-06'), 1440);
      },
    );
  }

  for (final meters in [null, -1.0, double.nan, double.infinity, 0.0, 5.0]) {
    test(
      'iOS movement validates distance $meters independently of measured steps',
      () async {
        movement = {'steps': 10, 'distance_m': meters};
        expect(await PhonePedometer().syncDay(day), 240);
        final db = await LocalDb.instance;
        final rows = await db.query('live_coverage', orderBy: 'start_ts');
        expect(rows, hasLength(24));
        final good = meters != null && meters.isFinite && meters >= 0;
        expect(rows.every((r) => r['steps'] == 10), true);
        expect(
          rows.every(
            (r) => good ? r['distance_m'] == meters : r['distance_m'] == null,
          ),
          true,
        );
        for (final call in calls) {
          final args = call.arguments as Map;
          expect((args['toMs'] as int) - (args['fromMs'] as int), 3600000);
        }
      },
    );
  }
  for (final platform in [TargetPlatform.iOS, TargetPlatform.linux]) {
    for (final distanceKnown in [false, true]) {
      test(
        'old ${platform.name} phone cache is reusable only with required distance=$distanceKnown',
        () async {
          debugDefaultTargetPlatformOverride = platform;
          final windows = [
            for (var h = 0; h < 24; h++)
              (
                startTs: sec(day.add(Duration(hours: h))),
                endTs: sec(day.add(Duration(hours: h + 1))),
                steps: 10,
              ),
          ];
          await LocalDb.replacePhoneCoverageForDay(
            '2021-04-06',
            windows,
            distances: {
              for (final w in windows)
                '${w.startTs}-${w.endTs}': distanceKnown ? 5.0 : null,
            },
          );
          expect(await PhonePedometer().syncDay(day), 240);
          expect(
            calls.length,
            platform == TargetPlatform.iOS && !distanceKnown ? 24 : 0,
          );
          expect(await LocalDb.phoneStepsForDay('2021-04-06'), 240);
        },
      );
    }
  }
  for (final response in ['throws', 'missing_steps']) {
    test(
      'iOS $response abandons the replacement and retains prior measured rows',
      () async {
        await LocalDb.replacePhoneCoverageForDay('2021-04-06', [
          (
            startTs: sec(day),
            endTs: sec(day.add(const Duration(hours: 1))),
            steps: 20,
          ),
        ]);
        final db = await LocalDb.instance;
        final before = await db.query('live_coverage');
        fail = response == 'throws';
        movement = {'distance_m': 15.0};
        expect(await PhonePedometer().syncDay(day), isNull);
        expect(calls, hasLength(1));
        expect(await db.query('live_coverage'), before);
      },
    );
  }
  test(
    'a refused stop is contained and never clears durable coverage',
    () async {
      await LocalDb.replacePhoneCoverageForDay('2021-04-06', [
        (
          startTs: sec(day),
          endTs: sec(day.add(const Duration(hours: 1))),
          steps: 20,
        ),
      ]);
      fail = true;
      await PhonePedometer().stop();
      expect(calls.single.method, 'stop');
      expect(await LocalDb.phoneStepsForDay('2021-04-06'), 20);
    },
  );
  test(
    'a refused legacy purge keeps both original rows and its unfinished marker retryable',
    () async {
      await LocalDb.replacePhoneCoverageForDay('2021-04-06', [
        (
          startTs: sec(day),
          endTs: sec(day.add(const Duration(hours: 1))),
          steps: 20,
        ),
      ]);
      final db = await LocalDb.instance;
      await db.execute(
        "CREATE TRIGGER authored_purge_refusal BEFORE DELETE ON live_coverage BEGIN SELECT RAISE(ABORT,'authored refusal'); END",
      );
      try {
        expect(await PhonePedometer().syncRecent(days: 0), (
          daysRead: 0,
          totalSteps: 0,
        ));
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool('phone_steps_healthstore_purged'), isNot(true));
        expect(await LocalDb.phoneStepsForDay('2021-04-06'), 20);
      } finally {
        await db.execute('DROP TRIGGER authored_purge_refusal');
      }
      expect(await PhonePedometer().syncRecent(days: 0), (
        daysRead: 0,
        totalSteps: 0,
      ));
      expect(
        (await SharedPreferences.getInstance()).getBool(
          'phone_steps_healthstore_purged',
        ),
        true,
      );
      expect(await LocalDb.phoneStepsForDay('2021-04-06'), 0);
    },
  );
}
