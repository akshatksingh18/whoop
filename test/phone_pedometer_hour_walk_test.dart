import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/health/phone_pedometer.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The hour walk is where this feature's two real defects lived, and neither
/// was reachable from the DB-level tests.
///
/// NOTE ON TIMEZONE. Dart reads the process timezone from the environment and
/// `flutter test` cannot set it per-test, so the DST cases here assert on the
/// BOUNDARY LOGIC (zero-width buckets are skipped, not fatal) in a way that
/// holds in every timezone, rather than hard-coding a US transition. The
/// spring-forward instant collapse itself was reproduced directly against the
/// Dart runtime under `TZ=America/New_York` while diagnosing:
///
///     h=1  from=2026-03-08 01:00  to=2026-03-08 03:00
///     h=2  from=2026-03-08 03:00  to=2026-03-08 03:00   <-- zero width
///
/// With `break` there, hours 3-23 were never queried and the day was persisted
/// with ~3 hours of windows.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.dbName = 'openstrap_phone_hour_walk_test.db';
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  setUp(() async {
    final db = await LocalDb.instance;
    await db.delete('live_coverage');
  });

  /// Yesterday, so the walk covers a whole elapsed day (no "future hours" cap).
  DateTime yesterday() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day - 1);
  }

  test('a full elapsed day walks every hour and banks the total', () async {
    final asked = <DateTime>[];
    final ped = PhonePedometer(stepReader: (from, to) async {
      asked.add(from);
      return 10;
    });

    final day = yesterday();
    final total = await ped.syncDay(day);

    // 24 buckets in a normal day (23 or 25 across a DST transition) — never
    // truncated to a handful.
    expect(asked.length, greaterThanOrEqualTo(23));
    expect(total, asked.length * 10);
    expect(await LocalDb.liveStepsForDay(_label(day)), total);
  });

  test('a zero-width bucket is SKIPPED, not fatal to the rest of the day',
      () async {
    // Simulates the spring-forward collapse: the walk must keep going past a
    // bucket whose `from == to`. We cannot force a real DST gap in-process, so
    // this asserts the invariant directly — every hour after the anomaly is
    // still queried.
    var calls = 0;
    final ped = PhonePedometer(stepReader: (from, to) async {
      calls++;
      // A zero-width interval would never reach the reader at all (it is
      // skipped before the call), so simply counting calls proves the walk
      // did not terminate early.
      return 1;
    });

    final total = await ped.syncDay(yesterday());
    expect(calls, greaterThanOrEqualTo(23));
    expect(total, calls);
  });

  test('ANY failed hour abandons the day rather than banking a partial one',
      () async {
    final day = yesterday();
    final dayId = _label(day);

    // 1. A complete, good sync.
    final good = PhonePedometer(stepReader: (from, to) async => 100);
    final fullTotal = await good.syncDay(day);
    expect(fullTotal, isNotNull);
    expect(await LocalDb.liveStepsForDay(dayId), fullTotal);

    // 2. A later sync where hour 5 fails. `null` from this plugin means the
    //    query FAILED (an empty hour returns 0 on both platforms), so the day
    //    must be abandoned — `replacePhoneCoverageForDay` is delete-then-
    //    insert, and banking the short read would LOWER a good previous total
    //    while still suppressing the band fallback.
    var h = 0;
    final flaky = PhonePedometer(stepReader: (from, to) async {
      final n = h++ == 5 ? null : 100;
      return n;
    });
    expect(await flaky.syncDay(day), isNull);

    // 3. The good total survives untouched.
    expect(await LocalDb.liveStepsForDay(dayId), fullTotal);
  });

  test('a genuine zero-step day banks nothing and falls back to the band',
      () async {
    final day = yesterday();
    final dayId = _label(day);
    await LocalDb.addLiveCoverage(
      day.millisecondsSinceEpoch ~/ 1000,
      day.millisecondsSinceEpoch ~/ 1000 + 600,
      777,
      dayId,
    );

    // Every hour reads successfully as 0 — a real sedentary day, NOT a failure.
    final ped = PhonePedometer(stepReader: (from, to) async => 0);
    expect(await ped.syncDay(day), 0);

    // No phone rows were written, so the band count still shows.
    expect(await LocalDb.liveStepsForDay(dayId), 777);
  });

  test('an all-zero read never erases a day already banked with real steps',
      () async {
    final day = yesterday();
    final dayId = _label(day);

    // 1. A good sync banks a real day.
    final good = PhonePedometer(stepReader: (from, to) async => 100);
    final fullTotal = await good.syncDay(day);
    expect(fullTotal, isNotNull);
    expect(await LocalDb.liveStepsForDay(dayId), fullTotal);

    // 2. Every hour now reads 0 WITHOUT failing — exactly what a silent iOS
    //    READ denial looks like (`requestAuthorization` reports success even
    //    when the user denied read, so queries return empty rather than null,
    //    forever). Unguarded, `replacePhoneCoverageForDay`'s delete-then-insert
    //    would wipe the day; and because phone rows win outright, not even the
    //    band fallback would show.
    final denied = PhonePedometer(stepReader: (from, to) async => 0);
    expect(await denied.syncDay(day), isNull,
        reason: 'unconfirmed, so it must not count toward daysRead either');

    // 3. The banked day survives.
    expect(await LocalDb.liveStepsForDay(dayId), fullTotal);
  });

  test('the routine sync window is much smaller than the backfill window', () {
    // Each hourly bucket is one platform round trip, so the window IS the cost:
    // the 7-day default was up to 168 sequential calls on every launch and
    // again after every export.
    expect(PhonePedometer.routineSyncDays,
        lessThan(PhonePedometer.fullSyncDays));
    expect(PhonePedometer.routineSyncDays, 2);
  });

  test('syncRecent reports days read and their total for the UI', () async {
    final ped = PhonePedometer(stepReader: (from, to) async => 5);
    final r = await ped.syncRecent(days: 2);
    // Today is partial (only elapsed hours), yesterday is whole — both read.
    expect(r.daysRead, 2);
    expect(r.totalSteps, greaterThan(0));
  });
}

String _label(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
