// Banked session totals remain useful after recordings expire. No new scoring.
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('workout-summary-filters'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  test(
    'COV-68 multiple saved workouts accumulate zones while private/live/unknown ends remain excluded',
    () async {
      final now = DateTime.now();
      Future<void> seed(
        String id,
        Duration ago,
        int minutes,
        int kcal,
        String zones, {
        bool private = false,
        bool live = false,
        bool unknownEnd = false,
      }) async {
        final start = now.subtract(ago).millisecondsSinceEpoch ~/ 1000;
        await LocalDb.putSession({
          'id': id,
          'start_ts': start,
          'end_ts': live ? null : start + minutes * 60,
          'type': 'weight_training',
          'status': live ? 'live' : 'done',
          'source': 'manual',
          'created_at': 1,
          'duration_min': minutes,
          'calories': kcal,
          'zone_min_json': zones,
          'private': private ? 1 : 0,
          'end_ts_fabricated': unknownEnd ? 1 : 0,
        });
      }

      await seed('authored-a', const Duration(hours: 2), 30, 150, '[2,3]');
      await seed('authored-b', const Duration(days: 1), 45, 225, '[4,5,6]');
      await seed(
        'authored-private',
        const Duration(hours: 3),
        50,
        999,
        '[900]',
        private: true,
      );
      await seed(
        'authored-live',
        const Duration(hours: 1),
        40,
        888,
        '[800]',
        live: true,
      );
      await seed(
        'authored-unknown-end',
        const Duration(hours: 4),
        60,
        777,
        '[700]',
        unknownEnd: true,
      );
      await seed('authored-older', const Duration(days: 45), 20, 80, '[9]');
      final db = await LocalDb.instance;
      final before = await db.query('sessions', orderBy: 'id');
      final repo = LocalRepositoryImpl(getProfileMap: () => {'age': 30});
      for (final range in ['month', 'all', 'month']) {
        final result = await repo.getWorkouts(range: range);
        final all = range == 'all';
        expect(result['summary'], {
          'count': all ? 3 : 2,
          'total_min': all ? 95 : 75,
          'total_calories': all ? 455 : 375,
          'zone_min': all ? [15, 8, 6] : [6, 8, 6],
        });
        final workouts = result['workouts'] as List;
        expect(workouts.map((w) => w['id']).toSet(), {
          'authored-a',
          'authored-b',
          'authored-private',
          'authored-live',
          'authored-unknown-end',
          if (all) 'authored-older',
        });
        final unknown =
            workouts.singleWhere((w) => w['id'] == 'authored-unknown-end')
                as Map;
        expect(unknown['duration_min'], isNull);
        expect(unknown['calories'], isNull);
        expect(unknown['zone_min'], isEmpty);
        expect(
          workouts.singleWhere((w) => w['id'] == 'authored-private')['private'],
          true,
        );
        expect(
          workouts.singleWhere((w) => w['id'] == 'authored-live')['status'],
          'live',
        );
        expect(await db.query('sessions', orderBy: 'id'), before);
        expect(await db.query('decoded_onehz'), isEmpty);
      }
    },
  );
}
