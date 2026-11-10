// Shared writer: a read-side suggestion failure follows a committed session.
// Authored SQLite state only; the proposed durable-dismissal diagnostic stays
// separate because current overlap filtering already hides that fragment.
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('manual-suggestion-read-refusal'));
  setUp(resetCoverageStore);
  tearDown(() async {
    final db = await LocalDb.instance;
    final hidden = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE name = 'authored_hidden_suggestions'",
    );
    if (hidden.isNotEmpty) {
      await db.execute(
        'ALTER TABLE authored_hidden_suggestions RENAME TO workout_suggestions',
      );
    }
  });
  tearDownAll(LocalDb.close);
  const from = 1617724800, to = from + 1800;
  for (final edit in [false, true]) {
    for (final refuse in [false, true]) {
      test(
        '${edit ? 'retiming' : 'manual save'} preserves its committed unscored session when suggestion read refusal=$refuse',
        () async {
          final db = await LocalDb.instance;
          var published = 0;
          final repo = LocalRepositoryImpl(
            getProfileMap: () => {},
            onSessionChanged: () => published++,
          );
          await LocalDb.putWorkoutSuggestion({
            'id': 'authored-overlap',
            'date': '2021-04-06',
            'start_ts': from + 60,
            'end_ts': to - 60,
            'duration_min': 28,
            'created_at': 1,
          });
          final original = await db.query('workout_suggestions');
          if (edit) {
            await LocalDb.putSession({
              'id': 'authored-existing',
              'start_ts': from,
              'end_ts': to - 300,
              'type': 'yoga',
              'status': 'done',
              'source': 'manual',
              'created_at': 1,
            });
          }
          if (refuse) {
            await db.execute(
              'ALTER TABLE workout_suggestions RENAME TO authored_hidden_suggestions',
            );
          }
          final result = edit
              ? await repo.setWorkoutWindow(
                  'authored-existing',
                  startTs: from,
                  endTs: to,
                )
              : await repo.logManualWorkout(
                  startTs: from,
                  endTs: to,
                  type: 'yoga',
                );
          expect(result['unscored'], true);
          expect(result['hr_samples'], 0);
          final row = (await db.query('sessions')).single;
          expect(row['id'], result['workout_id']);
          if (edit) {
            expect(row['id'], 'authored-existing');
          }
          expect(row['start_ts'], from);
          expect(row['end_ts'], to);
          expect(row['strain'], isNull);
          expect(row['calories'], isNull);
          expect(published, 1);
          if (refuse) {
            expect(await db.query('authored_hidden_suggestions'), original);
            await db.execute(
              'ALTER TABLE authored_hidden_suggestions RENAME TO workout_suggestions',
            );
          }
          expect(
            await LocalDb.activeWorkoutSuggestions(),
            isEmpty,
            reason: 'The committed overlap is suppressed by the shared reader',
          );
          final retry = await repo.setWorkoutWindow(
            row['id'] as String,
            startTs: from,
            endTs: to,
          );
          expect(retry['workout_id'], row['id']);
          expect(await db.query('sessions'), hasLength(1));
          expect(published, 2);
          expect(await db.query('decoded_onehz'), isEmpty);
          expect(await db.query('day_result'), isEmpty);
        },
      );
    }
  }
}
