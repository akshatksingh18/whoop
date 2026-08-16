// Repository-layer P0 regressions, against the REAL LocalRepositoryImpl +
// LocalDb over sqflite_ffi.
//
//  7. getCycle() crashed the whole cycle screen whenever the mean cycle length
//     came out below the 10-day ovulation floor: `(mean - 14).round().clamp(10,
//     mean.round())` THROWS ArgumentError when lowerLimit > upperLimit. Two
//     logged `start` markers 8 days apart is enough (a correction the user
//     made, or a genuinely short cycle).
// 10. getRecords() computes only `workouts_tracked` — the one key its only
//     caller reads. It used to `recentDayResults(3650)` (SELECT r.*, hr_curve
//     + hypnogram + HRV series for TEN YEARS) and jsonDecode every one on the
//     main isolate; then day/night counts from SQL plus a full personal-record
//     sweep; all of it for a screen that wanted an integer.

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/local_repository_impl.dart';

void main() {
  late LocalRepositoryImpl repo;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.dbName = 'openstrap_repo_p0_test.db';
    await databaseFactory.deleteDatabase(
      p.join(await databaseFactory.getDatabasesPath(), LocalDb.dbName),
    );
    repo = LocalRepositoryImpl(getProfileMap: () => {'track_cycle': true});
  });

  tearDownAll(() async {
    await LocalDb.close();
    await databaseFactory.deleteDatabase(
      p.join(await databaseFactory.getDatabasesPath(), LocalDb.dbName),
    );
  });

  setUp(() async {
    final db = await LocalDb.instance;
    await db.delete('cycle_log');
    await db.delete('day_result');
    await db.delete('metric_series');
    await db.delete('sessions');
  });

  // ── fix 7 ────────────────────────────────────────────────────────────────
  test(
    'getCycle degrades to phase "unknown" on a sub-10-day mean cycle instead '
    'of throwing ArgumentError out of clamp()',
    () async {
      // Two starts 8 days apart → meanLength 8 → clamp(10, 8) used to throw.
      await LocalDb.putCycleLog('2026-06-01', 'start');
      await LocalDb.putCycleLog('2026-06-09', 'start');

      final cycle = await repo.getCycle();

      expect(cycle['enabled'], isTrue);
      expect(cycle['phase'], 'unknown', reason: 'honest, not invented');
      expect(cycle['fertile_start'], isNull);
      expect(cycle['fertile_end'], isNull);
      // Everything that IS knowable still comes back.
      expect(cycle['mean_length'], 8);
      expect(cycle['predicted_next'], isNotNull);
      expect(cycle['cycle_day'], isNotNull);
    },
  );

  test('a normal-length cycle still gets a real phase + fertile window',
      () async {
    await LocalDb.putCycleLog('2026-06-01', 'start');
    await LocalDb.putCycleLog('2026-06-29', 'start'); // 28 days

    final cycle = await repo.getCycle();
    expect(cycle['mean_length'], 28);
    expect(cycle['phase'], isNot('unknown'));
    expect(cycle['fertile_start'], isNotNull);
    expect(cycle['fertile_end'], isNotNull);
  });

  test('exactly 10 days — the clamp boundary — does not throw', () async {
    await LocalDb.putCycleLog('2026-06-01', 'start');
    await LocalDb.putCycleLog('2026-06-11', 'start');
    final cycle = await repo.getCycle();
    expect(cycle['mean_length'], 10);
    expect(cycle['phase'], isNotNull);
  });

  // ── fix 10 ───────────────────────────────────────────────────────────────
  test(
    'getRecords answers the ONE key its caller reads, touching no day_result '
    'payload at all',
    () async {
      String bundle(int? tstSec) => tstSec == null
          ? '{"scalars":{}}'
          : '{"sleep":{"accounting":{"value":{"tst_sec":$tstSec}}}}';

      await LocalDb.putDayResult(
        dayId: '2026-01-01',
        algoVersion: 41,
        payloadJson: bundle(21600),
        windowJson: '{}',
        series: const {'rhr': 52.0},
      );
      await LocalDb.putDayResult(
        dayId: '2026-01-02',
        algoVersion: 41,
        payloadJson: '<<truncated write>>', // not JSON at all
        windowJson: '{}',
      );

      final records = await repo.getRecords();
      // workout_screen reads ['workouts_tracked'] and nothing else, so nothing
      // else is computed — the day/night counts, the personal records, the
      // streaks and the resting-HR drift all had zero consumers.
      expect(records.keys, ['workouts_tracked']);
      expect(records['workouts_tracked'], 0);
    },
  );
}
