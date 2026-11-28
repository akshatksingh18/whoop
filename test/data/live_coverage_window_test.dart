// live_coverage — the persistence guard for imported band step windows.
//
// A `live_coverage` row records a period whose steps were counted outside the
// 1 Hz estimate (an imported band window or a phone row), so derivation can
// exclude those minutes and nothing is counted twice. A zero-width window
// would exclude ~one minute instead of the real period, so:
//   1. StepCoverageStore.add widens or rejects degenerate windows, and
//   2. legacy zero-width rows already on disk stay readable.

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/live_coverage_policy.dart';

void main() {
  // These cover the band ladder, which the app keeps off (phone-only steps).
  setUpAll(() => StepCoverageStore.debugBandSteps = true);
  tearDownAll(() => StepCoverageStore.debugBandSteps = false);

  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.dbName = 'whoop_live_coverage_test.db';
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  tearDownAll(() async {
    await LocalDb.close();
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  // ── 1. the persistence guard ───────────────────────────────────────────────
  group('StepCoverageStore.add', () {
    test('a zero-duration window that claims steps is never persisted as-is — '
        'and its steps are not lost', () async {
      const start = 1786000000;
      await StepCoverageStore.add(start, start, 1657, '2026-08-06');

      final db = await LocalDb.instance;
      final rows = await db.query(
        'live_coverage',
        where: 'day = ?',
        whereArgs: ['2026-08-06'],
      );
      expect(rows, hasLength(1), reason: 'the real 100 Hz count must survive');
      final end = (rows.first['end_ts'] as num).toInt();
      // Pre-fix the row went in verbatim with end_ts == start_ts.
      expect(end, greaterThan(start));
      expect(end - start, minCoverageSecondsForSteps(1657));
      expect((rows.first['steps'] as num).toInt(), 1657);
      expect(
        (await StepCoverageStore.resolvedStepsForDay('2026-08-06')).total,
        1657,
      );
    });

    test(
      'an impossibly short window is widened to what its steps imply',
      () async {
        const start = 1786100000;
        await StepCoverageStore.add(start, start + 3, 600, '2026-08-07');
        final windows = await StepCoverageStore.windowsOverlapping(
          start,
          start + 3600,
        );
        expect(windows, hasLength(1));
        expect(
          windows.first[1] - windows.first[0],
          minCoverageSecondsForSteps(600),
        );
      },
    );

    test(
      'an inverted window is rejected, and a zero-step window is not stored',
      () async {
        const start = 1786200000;
        await StepCoverageStore.add(start, start - 60, 500, '2026-08-08');
        await StepCoverageStore.add(start, start + 600, 0, '2026-08-08');
        final db = await LocalDb.instance;
        final rows = await db.query(
          'live_coverage',
          where: 'day = ?',
          whereArgs: ['2026-08-08'],
        );
        expect(rows, isEmpty);
      },
    );

    test('an honest window is stored exactly as measured', () async {
      const start = 1786300000;
      await StepCoverageStore.add(start, start + 1800, 2000, '2026-08-09');
      final windows = await StepCoverageStore.windowsOverlapping(
        start,
        start + 3600,
      );
      expect(windows.first, [start, start + 1800]);
    });
  });

  // ── 2. historical degenerate rows stay readable ────────────────────────────
  group('legacy zero-width rows already on disk', () {
    test(
      'are tolerated by the coverage readers (left alone, not migrated)',
      () async {
        // Written the way the old code did, bypassing the guard, to prove the
        // readers still behave on the rows real users already have.
        const start = 1786400000;
        final db = await LocalDb.instance;
        await db.insert('live_coverage', {
          'start_ts': start,
          'end_ts': start, // zero width
          'steps': 1230,
          'day': '2026-08-10',
        });
        expect(
          (await StepCoverageStore.resolvedStepsForDay('2026-08-10')).total,
          1230,
        );
        final windows = await StepCoverageStore.windowsOverlapping(
          start,
          start + 3600,
        );
        expect(windows, hasLength(1));
        expect(windows.first, [start, start]);
      },
    );
  });
}
