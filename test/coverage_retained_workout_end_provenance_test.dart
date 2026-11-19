// Keep older end-time evidence when startup closes a retained live row.
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/gps/workout_clock.dart';
import 'package:whoop_companion/state/app_state.dart';

import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('retained-workout-end-provenance'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  for (final fabricated in [0, 1]) {
    test(
      'stale live row retains its stored end and provenance flag: $fabricated',
      () async {
        const id = 'authored-retained-workout';
        final start =
            DateTime.now()
                .subtract(const Duration(hours: 9))
                .millisecondsSinceEpoch ~/
            1000;
        final end = start + 45 * 60;
        await LocalDb.putSession({
          'id': id,
          'type': 'yoga',
          'status': 'live',
          'source': 'manual',
          'start_ts': start,
          'end_ts': end,
          'end_ts_fabricated': fabricated,
          'created_at': start * 1000,
        });
        final stored = (await LocalDb.session(id))!;
        final db = await LocalDb.instance;
        final app = AppState.forTesting();
        try {
          await db.execute(
            "CREATE TRIGGER authored_end_refusal BEFORE INSERT ON sessions "
            "WHEN NEW.id='authored-retained-workout' "
            "BEGIN SELECT RAISE(ABORT,'authored retained-end refusal'); END",
          );
          await app.debugReconcileOrphanedLiveWorkout();
          expect(await LocalDb.session(id), stored);
          expect(
            app.logLines,
            contains(contains('authored retained-end refusal')),
          );
          expect(app.activeWorkout, isNull);

          await db.execute('DROP TRIGGER authored_end_refusal');
          await app.debugReconcileOrphanedLiveWorkout();
          expect(app.activeWorkout, isNull);
          expect(WorkoutClock.current, isNull);
          final saved = (await LocalDb.session(id))!;
          expect(saved, {...stored, 'status': 'done'});
          expect(saved['end_ts'], end);
          expect(saved['end_ts_fabricated'], fabricated);
          expect(saved['duration_min'], isNull);
          await app.debugReconcileOrphanedLiveWorkout();
          expect(await LocalDb.session(id), saved);
        } finally {
          await db.execute('DROP TRIGGER IF EXISTS authored_end_refusal');
          app.dispose();
        }
      },
    );
  }
}
