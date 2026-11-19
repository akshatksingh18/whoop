// Lifting's existing calorie line subtracts measured steps in the same window.
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/day_upkeep.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';

import 'support/coverage_store.dart';

const profile = Profile(ageYears: 30, sex: 'f', weightKg: 72, heightCm: 170);

Future<void> session(int start, int? end) {
  return LocalDb.putSession({
    'id': 'authored-lifting-credit',
    'type': 'weight_training',
    'start_ts': start,
    'end_ts': end,
    'status': end != null ? 'done' : 'live',
    'source': 'manual',
    'created_at': 1,
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('lifting-steps-credit'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  for (final steps in [0, 240]) {
    test(
      'lifting disclosure recognizes $steps measured overlapping steps',
      () async {
        const day = '2021-04-06';
        final start = localDayStartSec(day)! + 12 * 3600;
        final end = start + 1800;
        await session(start, end);
        final before = (await liftingOn(day, profile))!;
        expect(before.approximate, isTrue);
        expect(before.sessions, 1);

        await LocalDb.replacePhoneCoverageForDay(day, [
          (startTs: start, endTs: end, steps: steps),
          (startTs: end, endTs: end + 1800, steps: 1500),
        ]);
        final after = (await liftingOn(day, profile))!;
        expect(after.approximate, isFalse);
        expect(after.sessions, 1);
        expect(
          after.kcal,
          closeTo(before.kcal - stepCalories(steps, profile.weightKg)!, 1e-8),
        );
        final stored = await (await LocalDb.instance).query('live_coverage');
        expect(stored.map((r) => r['steps']), unorderedEquals([steps, 1500]));
      },
    );
  }

  test(
    'an active lift uses observed elapsed time without filling its saved end',
    () async {
      final start = DateTime.now().subtract(const Duration(minutes: 30));
      final ts = start.millisecondsSinceEpoch ~/ 1000;
      await session(ts, null);
      final priced = (await liftingOn(dayLabelOf(start), profile))!;
      expect(priced.sessions, 1);
      expect(priced.approximate, isTrue);
      expect(priced.kcal, closeTo(90, 2));
      final retained = (await LocalDb.session('authored-lifting-credit'))!;
      expect(retained['end_ts'], isNull);
      expect(retained['start_ts'], ts);
    },
  );
}
