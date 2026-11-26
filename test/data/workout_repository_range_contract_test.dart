// The reusable workout history reader still accepts its legacy range labels.
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';

import '../support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('workout-repository-range-contract'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  for (final range in ['week', 'quarter', '3m']) {
    test(
      'workout history range $range preserves stored evidence and summary admission',
      () async {
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final expectedDays = range == 'week' ? [6] : [6, 8, 89];
        for (final age in [6, 8, 89, 91]) {
          final start = now - age * 86400;
          await LocalDb.putSession({
            'id': 'authored-range-$age',
            'start_ts': start,
            'end_ts': start + 20 * 60,
            'type': 'yoga',
            'source': 'manual',
            'status': 'done',
            'private': age == 8 ? 1 : 0,
            'end_ts_fabricated': age == 89 ? 1 : 0,
            'duration_min': 20,
            'calories': 50,
            'created_at': start * 1000,
          });
        }
        final db = await LocalDb.instance;
        final original = await db.query('sessions', orderBy: 'start_ts');
        final repository = LocalRepositoryImpl(getProfileMap: () => {});
        final result = await repository.getWorkouts(range: range);
        final workouts = (result['workouts'] as List)
            .cast<Map<String, dynamic>>();
        expect(
          workouts.map((row) => row['id']),
          unorderedEquals([for (final d in expectedDays) 'authored-range-$d']),
        );
        expect(result['summary'], {
          'count': 1,
          'total_min': 20,
          'total_calories': 50,
          'zone_min': [],
        });
        final retained = await db.query('sessions', orderBy: 'start_ts');
        expect(retained, original);
      },
    );
  }
}
