// Hold only the native preference mirror after the real clock database commit.
// Concurrent real session commands must own their rows after an older read resumes.
import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/data/calculation_store.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/gps/workout_clock.dart';
import 'package:whoop_companion/state/prefs.dart';
import '../support/refusing_prefs_store.dart';
import '../support/coverage_store.dart';

const id = 'authored-trace-owner';
const key = 'workout.clock.$id';
const profile = Profile(ageYears: 30, sex: 'f', heightCm: 170, weightKg: 70);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferencesStorePlatform original;
  late RefusingPrefsStore store;
  late LocalRepositoryImpl repo;
  Completer<void>? gate;
  setUpAll(() => coverageStore('session-trace-owner-race'));
  setUp(() async {
    await resetCoverageStore();
    original = SharedPreferencesStorePlatform.instance;
    store = RefusingPrefsStore(targetKey: key);
    SharedPreferencesStorePlatform.instance = store;
    SharedPreferences.resetStatic();
    await Prefs.ensureLoaded();
    repo = LocalRepositoryImpl(getProfileMap: profile.toMap);
  });
  tearDown(() async {
    if (gate != null && !gate!.isCompleted) gate!.complete();
    await WorkoutClock.flushWrites();
    gate = null;
    SharedPreferencesStorePlatform.instance = original;
    SharedPreferences.resetStatic();
  });
  tearDownAll(LocalDb.close);

  for (final action in ['delete', 'retime']) {
    for (final paused in [false, true]) {
      test(
        'a ${paused ? 'paused' : 'continuous'} saved trace read cannot overwrite a concurrent $action',
        () async {
          final start = DateTime(2021, 4, 6, 8);
          final end = start.add(const Duration(minutes: 3));
          final startTs = start.millisecondsSinceEpoch ~/ 1000;
          final endTs = end.millisecondsSinceEpoch ~/ 1000;
          await SessionStore.put({
            'id': id,
            'type': 'general_workout',
            'start_ts': startTs,
            'end_ts': endTs,
            'created_at': 1,
            'status': 'done',
            'source': 'manual',
            'private': 1,
            'strain': 7,
            'calories': 80,
            'avg_hr': 120,
            'max_hr': 150,
            'zone_min_json': '[1,2,3,4,5]',
          });
          await SessionStore.put({
            'id': 'authored-unrelated-session',
            'type': 'general_workout',
            'start_ts': startTs - 3600,
            'end_ts': startTs - 3000,
            'created_at': 2,
            'status': 'done',
            'source': 'manual',
            'calories': 0,
          });
          final sibling = await SessionStore.byId('authored-unrelated-session');
          final clock = WorkoutClock(
            id,
            start,
            end: end,
            profile: profile,
            pauses: paused
                ? [
                    (
                      start: start.add(const Duration(minutes: 1)),
                      end: start.add(const Duration(minutes: 2)),
                    ),
                  ]
                : [],
            results: {
              'hr': [100, 110, 120, 130, 140, 150],
              'zones': [1, 2, 3],
            },
          );
          await clock.persist();
          gate = Completer<void>();
          store.held = gate;
          store.reached = Completer<void>();
          final reading = repo.getWorkout(id);
          await store.reached!.future.timeout(const Duration(seconds: 5));
          final bounded =
              jsonDecode(
                    (await MetricSeriesStore.baseline(
                          '${CalculationStore.prefix}$key',
                        ))!['payload_json']
                        as String,
                  )
                  as Map;
          expect((bounded['results'] as Map)['hr'], [
            100,
            110,
            if (!paused) 120,
          ]);
          expect((bounded['results'] as Map)['zones'], isEmpty);

          Map<String, dynamic>? concurrent;
          if (action == 'delete') {
            await repo.deleteWorkout(id);
            expect(await SessionStore.byId(id), isNull);
          } else {
            await repo.setWorkoutWindow(
              id,
              startTs: startTs,
              endTs: endTs + 120,
            );
            concurrent = await SessionStore.byId(id);
            expect(concurrent!['end_ts'], endTs + 120);
          }
          gate!.complete();
          await reading.timeout(const Duration(seconds: 5));
          await WorkoutClock.flushWrites();
          if (action == 'delete') {
            expect(await SessionStore.byId(id), isNull);
            expect(await repo.getWorkout(id), isEmpty);
          } else {
            expect(await SessionStore.byId(id), concurrent);
            final reread = await repo.getWorkout(id);
            expect(reread['end_ts'], endTs + 120);
            expect(await SessionStore.byId(id), concurrent);
          }
          expect(
            await SessionStore.byId('authored-unrelated-session'),
            sibling,
          );
          expect(
            (await MetricSeriesStore.baseline(
              '${CalculationStore.prefix}$key',
            ))!['payload_json'],
            jsonEncode(bounded),
          );
          // Native mirror is now acknowledged; deletion does not promise to erase
          // the independently retained clock anchor. Only row ownership is tested.
          expect(store.values['flutter.$key'], jsonEncode(bounded));
        },
      );
    }
  }
}
