// Incomplete profile data cannot invent a maintenance total or erase distance.
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/ui2/screens/day_steps.dart';

import '../../support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('steps-distance-partial-profile'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  for (final weight in <double?>[72, null]) {
    test(
      'recorded walking distance at profile weight $weight keeps its basis',
      () async {
        const day = '2021-04-06';
        final start = localDayStartSec(day)! + 12 * 3600;
        final end = start + 3600;
        await StepCoverageStore.replacePhoneForDay(
          day,
          [(startTs: start, endTs: end, steps: 1200)],
          distances: {'$start-$end': 600},
        );
        final p = Profile(weightKg: weight);
        final reader = LocalRepositoryImpl(getProfileMap: p.toMap);
        final db = await LocalDb.instance;
        final rows = await db.query('live_coverage');
        final summary = await DayStepsData.load(reader, want: day);

        expect(summary.day, day);
        expect(summary.phone, 1200);
        expect(summary.dayTotal, 1200);
        expect(
          summary.walking?.km,
          weight == null ? isNull : closeTo(.6, 1e-9),
        );
        final expected = movementEquationEstimateKcal(
          runMeters: 0,
          walkMeters: 600,
          weightKg: weight,
        );
        expect(summary.acsmWalking, expected);
        expect(await db.query('live_coverage'), rows);
        expect(await db.query('sessions'), isEmpty);
        expect(await db.query('day_result'), isEmpty);
      },
    );
  }
}
