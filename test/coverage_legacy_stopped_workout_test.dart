// Older stopped clocks predate pendingSession. Recover their surviving evidence
// through the actual restart/finish entry points without inventing sample peaks.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/data/calculation_store.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/gps/workout_clock.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('legacy-stopped-workout'));
  setUp(resetCoverageStore);
  tearDown(() async {
    await (await LocalDb.instance).execute(
      'DROP TRIGGER IF EXISTS authored_cleanup_refusal',
    );
    await WorkoutClock.flushWrites();
    WorkoutClock.current = null;
  });
  tearDownAll(LocalDb.close);
  const profile = Profile(ageYears: 30, weightKg: 70, heightCm: 170, sex: 'f');
  for (final zonesKnown in [false, true]) {
    for (final cleanupRefused in [false, true]) {
      test(
        'legacy stopped trace survives restart zones=$zonesKnown cleanup-refused=$cleanupRefused',
        () async {
          const id = 'authored-old-stopped';
          final start = DateTime.now().subtract(
            const Duration(hours: 9, minutes: 4),
          );
          final end = start.add(const Duration(minutes: 4));
          final trace = <double?>[120, null, 145, 130];
          final zones = [0, 1, 2, 1, 0];
          await LocalDb.putSession({
            'id': id,
            'start_ts': start.millisecondsSinceEpoch ~/ 1000,
            'type': 'swimming',
            'status': 'live',
            'created_at': 1,
            'private': 1,
            'rpe': 7,
            'device_family': 'gen4',
          });
          final clock = WorkoutClock(
            id,
            start,
            end: end,
            profile: profile,
            results: {'hr': trace, if (zonesKnown) 'zones': zones},
          );
          await clock.persist();
          expect(clock.pendingSession, isNull);
          WorkoutClock.current = null;
          final app = AppState.forTesting()..user = {'weight_kg': 90};
          app.repo = LocalRepositoryImpl(getProfileMap: () => app.user);
          addTearDown(app.dispose);
          await app.debugReconcileOrphanedLiveWorkout();
          expect(app.workoutAwaitingSave, true);
          expect(WorkoutClock.current!.profile!.weightKg, 70);
          expect(app.activeWorkout!.perMinuteHrDense(), isEmpty);
          final db = await LocalDb.instance;
          if (cleanupRefused) {
            await db.execute(
              "CREATE TRIGGER authored_cleanup_refusal BEFORE INSERT ON baselines "
              "WHEN NEW.key='${CalculationStore.prefix}workout.clock.$id' "
              "AND (SELECT status FROM sessions WHERE id='$id')='done' "
              "BEGIN SELECT RAISE(ABORT,'authored post-commit cleanup refusal'); END",
            );
          }
          final revision = app.insightsRevision.value;
          await app.stopWorkout();
          final row = (await LocalDb.session(id))!;
          expect(row['status'], 'done');
          expect(row['end_ts'], end.millisecondsSinceEpoch ~/ 1000);
          expect(row['duration_min'], 4);
          expect(row['private'], 1);
          expect(row['rpe'], 7);
          expect(row['device_family'], 'gen4');
          expect(
            row['max_hr'],
            isNull,
            reason: 'Minute averages cannot reconstruct a measured sample peak',
          );
          expect(
            row['avg_hr'],
            isNull,
            reason:
                'A cold restart must not invent a duration-weighted average',
          );
          expect(
            jsonDecode(row['zone_min_json'] as String),
            zonesKnown ? zones : isEmpty,
          );
          expect(app.activeWorkout, isNull);
          expect(WorkoutClock.current, isNull);
          expect(app.insightsRevision.value, greaterThan(revision));
          final restored = WorkoutClock.read(id, start);
          expect(restored.results['hr'], trace);
          if (zonesKnown) expect(restored.results['zones'], zones);
          if (cleanupRefused) {
            expect(
              restored.pendingSession,
              isNotNull,
              reason:
                  'The durable pre-commit recovery payload remains when cleanup is refused',
            );
            // The done row is authoritative; stale recovery metadata cannot
            // re-open it or overwrite a later explicit edit on the next launch.
            await LocalDb.putSession({...row, 'rpe': 8});
            await db.execute('DROP TRIGGER authored_cleanup_refusal');
            final fresh = AppState.forTesting();
            addTearDown(fresh.dispose);
            await fresh.debugReconcileOrphanedLiveWorkout();
            expect(fresh.activeWorkout, isNull);
            expect((await LocalDb.session(id))!['rpe'], 8);
          } else {
            expect(restored.pendingSession, isNull);
          }
        },
      );
    }
  }
}
