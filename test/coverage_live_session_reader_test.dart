// A running/restored session is projected without persisting a finished score.
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/data/calculation_store.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/data/models.dart';
import 'package:whoop_companion/gps/workout_clock.dart';
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('live-session-reader', fresh: true));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  for (final paused in [false, true]) {
    for (final measured in [false, true]) {
      test(
        'live detail paused=$paused measured=$measured preserves the ongoing row and clock',
        () async {
          const id = 'authored-live-reader';
          const profile = Profile(
            ageYears: 30,
            sex: 'f',
            weightKg: 70,
            heightCm: 170,
          );
          final startSec =
              (DateTime.now().millisecondsSinceEpoch ~/ 60000 - 5) * 60;
          final start = DateTime.fromMillisecondsSinceEpoch(startSec * 1000);
          await LocalDb.putSession({
            'id': id,
            'start_ts': startSec,
            'status': 'live',
            'type': 'other',
            'source': 'manual',
            'device_family': 'gen4',
            'created_at': 1,
            'private': 1,
            'rpe': 6,
            'avg_hr': measured ? 99 : null,
            'steps': null,
            'calories': null,
            'strain': null,
          });
          final clock = WorkoutClock(
            id,
            start,
            profile: profile,
            pauses: paused
                ? [
                    (
                      start: start.add(const Duration(minutes: 1)),
                      end: start.add(const Duration(minutes: 2)),
                    ),
                  ]
                : [],
            pausedAt: paused ? start.add(const Duration(minutes: 3)) : null,
            results: {'authored-recovery': 'retain', 'hr': <num>[]},
          );
          await clock.persist();
          final seconds = measured
              ? <int>[for (var i = 0; i < 180; i++) i]
              : <int>[0];
          await LocalDb.commitSyncBatch(
            [
              for (final i in seconds)
                RawRecord(
                  counter: i,
                  packetType: 47,
                  hex: 'authored-live-$i',
                  capturedAt: (startSec + i) * 1000,
                  recTs: startSec + i,
                ),
            ],
            [
              for (final i in seconds)
                Sample(
                  tsEpoch: startSec + i,
                  counter: i,
                  hr: measured ? [90, 180, 120][i ~/ 60] : 0,
                  rrIntervalsMs: const [],
                  ax: 0,
                  ay: 0,
                  az: 0,
                ),
            ],
            deviceFamily: 'gen4',
          );
          final db = await LocalDb.instance;
          final before = await LocalDb.session(id);
          final storedClock = await CalculationStore.read('workout.clock.$id');
          final decoded = await db.query('decoded_onehz');
          var changes = 0;
          final repo = LocalRepositoryImpl(
            getProfileMap: profile.toMap,
            onSessionChanged: () => changes++,
          );
          for (var reopening = 0; reopening < 2; reopening++) {
            final detail = await repo.getWorkout(id);
            expect(detail['status'], 'live');
            expect(detail['end_ts'], isNull);
            expect(detail['private'], true);
            expect(detail['steps'], isNull);
            expect(detail['calories'], isNull);
            expect(detail['strain'], isNull);
            expect(detail['hrr60'], isNull);
            expect(detail['recovery_curve'], isNull);
            if (measured) {
              expect(detail['avg_hr'], paused ? 105 : 130);
              expect(detail['trace_samples'], paused ? 120 : 180);
              final hr = detail['hr'] as List;
              expect(hr, hasLength(paused ? 2 : 3));
              expect([
                for (final e in hr) (e as Map)['v'],
              ], paused ? [90, 120] : [90, 180, 120]);
              expect(
                [for (final e in hr) (e as Map)['t']],
                [
                  for (var minute = 0; minute < hr.length; minute++)
                    startSec + minute * 60,
                ],
              );
            } else {
              expect(detail['avg_hr'], isNull);
              expect(detail['hr'], isNull);
              expect(detail['trace_samples'], isNull);
            }
            expect(await LocalDb.session(id), before);
            expect(
              await CalculationStore.read('workout.clock.$id'),
              storedClock,
            );
            expect(await db.query('decoded_onehz'), decoded);
            expect(changes, 0);
          }
          expect(WorkoutClock.read(id, start).profile!.weightKg, 70);
          expect(
            WorkoutClock.read(id, start).results['authored-recovery'],
            'retain',
          );
        },
      );
    }
  }
}
