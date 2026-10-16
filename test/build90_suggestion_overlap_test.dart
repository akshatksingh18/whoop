// Build 90 (Akshat's phone review): a walk he had started was also offered as
// "1 effort we spotted but did not log". A derive that ran during the live
// workout filed its own effort, and stopping the workout never retired it.
// A suggestion overlapping any logged session, done or live, is not active.
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:openstrap_edge/data/db.dart';

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.dbName = 'build90_suggestion_overlap_test.db';
    await databaseFactory.deleteDatabase(
      p.join(await databaseFactory.getDatabasesPath(), LocalDb.dbName),
    );
  });

  tearDownAll(() async {
    await LocalDb.close();
    await databaseFactory.deleteDatabase(
      p.join(await databaseFactory.getDatabasesPath(), LocalDb.dbName),
    );
  });

  Future<void> suggestion(String id, int start, int end) =>
      LocalDb.putWorkoutSuggestion({
        'id': id,
        'date': '2026-09-01',
        'start_ts': start,
        'end_ts': end,
        'duration_min': (end - start) ~/ 60,
        'created_at': 1,
      });

  Future<void> session(String id, int start, int? end, String status) =>
      LocalDb.putSession({
        'id': id,
        'start_ts': start,
        'end_ts': end,
        'type': 'walking',
        'status': status,
        'source': 'manual',
        'created_at': 1,
      });

  test('a logged or running workout retires the effort inside it', () async {
    const t0 = 1_788_000_000;
    // Inside a finished walk: not offered.
    await session('walk', t0, t0 + 3120, 'done');
    await suggestion('inside', t0 + 120, t0 + 1020);
    // Inside a workout still running (no end): not offered either.
    await session('live', t0 + 20_000, null, 'live');
    await suggestion('during-live', t0 + 20_200, t0 + 21_000);
    // Hours away from both: still offered.
    await suggestion('elsewhere', t0 + 10_000, t0 + 11_000);
    // Back to back with the walk (touching, not overlapping): still offered.
    await suggestion('after', t0 + 3120, t0 + 4000);

    final active = [
      for (final r in await LocalDb.activeWorkoutSuggestions()) r['id'],
    ];
    expect(active, containsAll(['elsewhere', 'after']));
    expect(active, isNot(contains('inside')));
    expect(active, isNot(contains('during-live')));
  });
}
