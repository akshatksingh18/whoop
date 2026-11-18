// Existing maintenance methods with a real live clock/store and authored motion.
// No calorie rule changes, new proposals, or phone sensor acceptance are implied.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/day_upkeep.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/gps/run_history.dart';
import 'package:whoop_companion/gps/route_models.dart';
import 'package:whoop_companion/gps/workout_clock.dart';

import 'support/coverage_store.dart';

class _HeldRead extends LocalRepositoryImpl {
  _HeldRead() : super(getProfileMap: () => const Profile(weightKg: 70).toMap());
  final reached = Completer<void>(), release = Completer<void>();
  var hold = true;
  @override
  Future<Map<String, dynamic>> getWorkouts({String range = 'month'}) async {
    final result = await super.getWorkouts(range: range);
    if (hold) {
      hold = false;
      reached.complete();
      await release.future;
    }
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('live-upkeep-reader'));
  setUp(() async {
    await resetCoverageStore();
    runsChanged();
  });
  tearDown(() async {
    await WorkoutClock.flushWrites();
    WorkoutClock.current = null;
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('whoop/phone_steps'),
          null,
        );
  });
  tearDownAll(LocalDb.close);
  const profile = Profile(ageYears: 30, sex: 'f', weightKg: 70, heightCm: 170);
  const day = '2021-04-06', id = 'authored-live-upkeep';
  final start = DateTime.fromMillisecondsSinceEpoch(
    (localDayStartSec(day)! + 12 * 3600) * 1000,
  );
  for (final kind in [
    'paused-run',
    'finished-run',
    'paused-other',
    'motion-only-run',
  ]) {
    test(
      '$kind retains active-time ownership in the existing daily estimate',
      () async {
        final isRun = kind != 'paused-other';
        final finished = kind == 'finished-run';
        final hasDayCoverage = kind != 'motion-only-run';
        final end = start.add(const Duration(minutes: 5));
        final calls = <MethodCall>[];
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('whoop/phone_steps'),
              (call) async {
                calls.add(call);
                if (call.method != 'motionWindow') return null;
                final args = call.arguments as Map;
                final from = args['fromMs'] as int, to = args['toMs'] as int;
                final chunks = (to - from) ~/ 60000;
                return {
                  'steps': List.filled(chunks, 100),
                  'meters': List.filled(chunks, 200.0),
                };
              },
            );
        await LocalDb.putSession({
          'id': id,
          'type': isRun ? 'running' : 'swimming',
          'start_ts': start.millisecondsSinceEpoch ~/ 1000,
          'end_ts': finished ? end.millisecondsSinceEpoch ~/ 1000 : null,
          'status': finished ? 'done' : 'live',
          'created_at': start.millisecondsSinceEpoch,
          'source': 'manual',
        });
        if (hasDayCoverage) {
          await LocalDb.replacePhoneCoverageForDay(day, [
            (
              startTs: start.millisecondsSinceEpoch ~/ 1000,
              endTs: end.millisecondsSinceEpoch ~/ 1000,
              steps: 500,
            ),
          ]);
        }
        final clock = WorkoutClock.begin(id, start, profile);
        clock.setPaused(true, start.add(const Duration(minutes: 3)));
        if (finished) {
          clock.setPaused(false, start.add(const Duration(minutes: 4)));
          clock.finish(end);
        }
        await WorkoutClock.flushWrites();
        final repo = LocalRepositoryImpl(getProfileMap: () => profile.toMap());
        final saved = await loadRuns(repo);
        expect(saved, finished ? hasLength(1) : isEmpty);
        final result = await DayUpkeep.read(
          repo,
          day,
          profile,
          eaten: 0,
          runs: saved,
        );
        expect(result.steps, hasDayCoverage ? 500 : isNull);
        expect(result.eaten, 0);
        expect(
          result.runs.count,
          isRun ? 1 : 0,
          reason:
              'a finished current clock cannot duplicate its saved history row',
        );
        expect(result.runs.steps, isRun ? (finished ? 400 : 300) : 0);
        expect(result.runs.km, closeTo(isRun ? (finished ? .8 : .6) : 0, 1e-9));
        expect(
          result.walkedSteps,
          !hasDayCoverage
              ? isNull
              : isRun
              ? (finished ? 100 : 200)
              : 500,
        );
        expect(result.overlapUnknown, false);
        expect(
          result.runWindows,
          isRun ? hasLength(finished ? 2 : 1) : isEmpty,
        );
        if (isRun) {
          expect(result.runs.kcal, greaterThan(0));
          expect(result.parts!.run, result.runs.kcal);
          if (!hasDayCoverage) {
            expect(
              result.parts!.steps,
              0,
              reason:
                  'the approved conservative estimate retains known running while daily walking remains unmeasured',
            );
          }
          expect(
            result.runWindows.first.end,
            start.add(const Duration(minutes: 3)),
          );
          expect(calls.where((c) => c.method == 'motionWindow'), isNotEmpty);
        } else {
          expect(result.runs.kcal, 0);
          expect(calls.where((c) => c.method == 'motionWindow'), isEmpty);
        }
        final row = (await LocalDb.session(id))!;
        expect(row['status'], finished ? 'done' : 'live');
        expect(WorkoutClock.current, same(clock));
        expect(
          clock.pausedAt,
          finished ? isNull : start.add(const Duration(minutes: 3)),
        );
      },
    );
  }
  test(
    'GPS running with unknown step overlap retains the approved conservative maximum',
    () async {
      await LocalDb.putSession({
        'id': id,
        'type': 'running',
        'start_ts': start.millisecondsSinceEpoch ~/ 1000,
        'status': 'live',
        'created_at': start.millisecondsSinceEpoch,
        'source': 'manual',
      });
      final morning =
          start.subtract(const Duration(hours: 1)).millisecondsSinceEpoch ~/
          1000;
      await LocalDb.replacePhoneCoverageForDay(
        day,
        [(startTs: morning, endTs: morning + 300, steps: 500)],
        distances: {'$morning-${morning + 300}': 500},
      );
      await LocalDb.appendRoutePoints(id, [
        for (var i = 0; i < 7; i++)
          RoutePoint(
            seq: i,
            tsMs: start.add(Duration(seconds: i * 30)).millisecondsSinceEpoch,
            lat: 0,
            lng: i * 90 / 111195,
            speed: 3,
          ).toRow(id),
      ]);
      final clock = WorkoutClock.begin(id, start, profile);
      clock.setPaused(true, start.add(const Duration(minutes: 3)));
      await WorkoutClock.flushWrites();
      final repo = LocalRepositoryImpl(getProfileMap: () => profile.toMap());
      final result = await DayUpkeep.read(repo, day, profile, eaten: 0);
      expect(result.overlapUnknown, true);
      expect(result.steps, 500);
      expect(
        result.walkedSteps,
        500,
        reason: 'unmeasured run steps are not subtracted as if known',
      );
      expect(result.runs.count, 1);
      expect(result.runs.steps, 0);
      expect(result.runs.km, closeTo(.54, .001));
      expect(result.runs.kcal, greaterThan(30));
      expect(
        result.parts!.steps,
        0,
        reason: 'the approved maximum does not add both movement estimates',
      );
      expect(result.acsmParts!.steps, 0);
      expect(result.parts!.total, result.parts!.bmr + result.parts!.run);
      expect(result.walkingMeters, 500);
      expect((await LocalDb.session(id))!['status'], 'live');
      expect(WorkoutClock.current, same(clock));
    },
  );
  for (final replacedRepo in [false, true]) {
    test(
      'a held run-history read cannot poison a newer ${replacedRepo ? 'repository' : 'revision'}',
      () async {
        final repo = _HeldRead();
        final current = replacedRepo
            ? LocalRepositoryImpl(getProfileMap: () => profile.toMap())
            : repo;
        Future<void> seed(String sessionId) => LocalDb.putSession({
          'id': sessionId,
          'type': 'running',
          'start_ts': start.millisecondsSinceEpoch ~/ 1000,
          'end_ts':
              start.add(const Duration(minutes: 5)).millisecondsSinceEpoch ~/
              1000,
          'status': 'done',
          'source': 'manual',
          'created_at': start.millisecondsSinceEpoch,
        });
        await seed('authored-old-run');
        final pending = loadRuns(repo);
        await repo.reached.future;
        try {
          await (await LocalDb.instance).update(
            'sessions',
            {'status': 'live'},
            where: 'id=?',
            whereArgs: ['authored-old-run'],
          );
          await seed('authored-new-run');
          runsChanged();
          expect((await loadRuns(current)).map((r) => r.id), [
            'authored-new-run',
          ]);
        } finally {
          repo.release.complete();
        }
        expect((await pending).map((r) => r.id), [
          replacedRepo ? 'authored-old-run' : 'authored-new-run',
        ]);
        expect((await loadRuns(current)).map((r) => r.id), [
          'authored-new-run',
        ]);
        expect((await LocalDb.session('authored-old-run'))!['status'], 'live');
        expect((await LocalDb.session('authored-new-run'))!['status'], 'done');
      },
    );
  }
}
