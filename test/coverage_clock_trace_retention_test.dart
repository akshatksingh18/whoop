// Saved workout clock results survive substrate improvement and later pruning.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/data/calculation_store.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/data/models.dart';
import 'package:whoop_companion/gps/motion_window.dart';
import 'package:whoop_companion/gps/workout_clock.dart';
import 'support/coverage_store.dart';

const profile = Profile(ageYears: 30, sex: 'f', heightCm: 170, weightKg: 70);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LocalRepositoryImpl repo;
  late DateTime start, end;
  setUpAll(() => coverageStore('clock-trace-retention'));
  setUp(() async {
    await resetCoverageStore();
    start = DateTime(2021, 4, 6, 8);
    end = start.add(const Duration(minutes: 4));
    repo = LocalRepositoryImpl(getProfileMap: profile.toMap);
  });
  tearDown(() async {
    await WorkoutClock.flushWrites();
    WorkoutClock.current = null;
  });
  tearDownAll(LocalDb.close);

  Future<void> row(String type, {double? calories}) => LocalDb.putSession({
    'id': 'synthetic-clock',
    'type': type,
    'start_ts': start.millisecondsSinceEpoch ~/ 1000,
    'end_ts': end.millisecondsSinceEpoch ~/ 1000,
    'status': 'done',
    'source': 'manual',
    'created_at': 1,
    if (calories != null) 'calories': calories,
  });
  for (final fuller in [false, true]) {
    test(
      'a ${fuller ? 'fuller' : 'thinner'} saved clock trace is handled without losing retained results',
      () async {
        await row('weight_training');
        final previous = fuller ? <double?>[90, 91, 92, 93] : <double?>[90];
        await WorkoutClock(
          'synthetic-clock',
          start,
          end: end,
          profile: profile,
          results: {'hr': previous, 'synthetic-evidence': 'retained'},
        ).persist();
        final ts = start.millisecondsSinceEpoch ~/ 1000;
        await LocalDb.commitSyncBatch(
          [
            for (var i = 0; i < 180; i++)
              RawRecord(
                counter: i,
                packetType: 47,
                hex: 'authored-clock-$i',
                capturedAt: (ts + i) * 1000,
                recTs: ts + i,
              ),
          ],
          [
            for (var i = 0; i < 180; i++)
              Sample(
                tsEpoch: ts + i,
                counter: i,
                hr: 100 + i ~/ 60 * 20,
                rrIntervalsMs: const [],
                ax: 0,
                ay: 0,
                az: 0,
              ),
          ],
          deviceFamily: 'gen4',
        );
        await repo.getWorkout('synthetic-clock');
        final saved = WorkoutClock.read('synthetic-clock', start, end: end);
        expect(saved.profile!.weightKg, 70);
        expect(saved.results['synthetic-evidence'], 'retained');
        expect(saved.results['hr'], fuller ? previous : [100, 120, 140, null]);
        expect(saved.results['zones'], hasLength(5));
        expect(
          (await LocalDb.session('synthetic-clock'))!['trace_samples'],
          180,
        );
        final db = await LocalDb.instance;
        await db.delete('decoded_onehz');
        await repo.getWorkout('synthetic-clock');
        expect(
          WorkoutClock.read('synthetic-clock', start).results['hr'],
          saved.results['hr'],
        );
        expect(
          (await LocalDb.session('synthetic-clock'))!['trace_samples'],
          180,
        );
      },
    );
  }
  for (final type in ['running', 'walking']) {
    test(
      'legacy $type repair uses retained movement once without changing its dated profile',
      () async {
        end = start.add(const Duration(minutes: 5));
        await row(type, calories: 999);
        await WorkoutClock(
          'synthetic-clock',
          start,
          end: end,
          profile: profile,
        ).persist();
        final motion = MotionWindow(
          start,
          60,
          List.filled(5, 240),
          List.filled(5, 200),
        );
        final key =
            'motion.synthetic-clock.${start.millisecondsSinceEpoch ~/ 1000}-${end.millisecondsSinceEpoch ~/ 1000}';
        await CalculationStore.write(key, jsonEncode(motion.toJson()));
        expect(await repo.repairSessionCalorieBasis(), 1);
        final saved = (await LocalDb.session('synthetic-clock'))!;
        expect(saved['calories_basis'], 'active');
        expect(
          saved['calories'],
          closeTo(type == 'running' ? 59.5 : 2.74 * 1200 * 70 / 8368, 1e-8),
        );
        expect(await repo.repairSessionCalorieBasis(), 0);
        expect(
          (await LocalDb.session('synthetic-clock'))!['calories'],
          saved['calories'],
        );
        expect(
          WorkoutClock.read('synthetic-clock', start).profile!.weightKg,
          70,
        );
      },
    );
  }
}
