import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Steps now come ONLY from a source that can actually resolve gait, and the
/// two such sources must never be summed: the phone (pocket, sees trunk motion)
/// and the band (wrist, documented emitting 22-27 false steps/min during
/// dishes/driving) both count the same walk. Adding them roughly doubles a day.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const day = '2026-08-03';
  const otherDay = '2026-08-02';

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.dbName = 'openstrap_phone_step_source_test.db';
  });

  setUp(() async {
    // Fresh DB per test — `live_coverage` is append-only, so leakage between
    // tests would look exactly like the double-counting these tests exist to
    // rule out.
    await LocalDb.close();
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  tearDownAll(() async {
    await LocalDb.close();
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  test('band-only day sums the band rows', () async {
    await LocalDb.addLiveCoverage(1000, 1600, 120, day);
    await LocalDb.addLiveCoverage(2000, 2600, 80, day);
    expect(await LocalDb.liveStepsForDay(day), 200);
  });

  test('phone WINS outright when present — the two are never added', () async {
    await LocalDb.addLiveCoverage(1000, 1600, 120, day); // wrist
    await LocalDb.replacePhoneCoverageForDay(
      day,
      [(startTs: 1000, endTs: 4600, steps: 350)],
    );
    // NOT 470. The phone measured the same walking from a better place.
    expect(await LocalDb.liveStepsForDay(day), 350);
  });

  test('phone sync is idempotent — re-syncing a day never accumulates',
      () async {
    for (var i = 0; i < 3; i++) {
      await LocalDb.replacePhoneCoverageForDay(
        day,
        [
          (startTs: 1000, endTs: 4600, steps: 350),
          (startTs: 4600, endTs: 8200, steps: 120),
        ],
      );
    }
    expect(await LocalDb.liveStepsForDay(day), 470);
  });

  test('a later sync REPLACES an earlier partial one rather than adding',
      () async {
    await LocalDb.replacePhoneCoverageForDay(
      day,
      [(startTs: 1000, endTs: 4600, steps: 100)],
    );
    // The day filled in; the same hour now reads higher.
    await LocalDb.replacePhoneCoverageForDay(
      day,
      [(startTs: 1000, endTs: 4600, steps: 900)],
    );
    expect(await LocalDb.liveStepsForDay(day), 900);
  });

  test('phone replace is scoped to its day and never touches band rows',
      () async {
    await LocalDb.addLiveCoverage(1000, 1600, 55, otherDay);
    await LocalDb.replacePhoneCoverageForDay(
      otherDay,
      [(startTs: 1000, endTs: 4600, steps: 700)],
    );
    await LocalDb.replacePhoneCoverageForDay(day, const []);

    // Clearing today's phone rows must not disturb yesterday.
    expect(await LocalDb.liveStepsForDay(otherDay), 700);
    // And with today's phone rows gone, the band fallback returns.
    await LocalDb.addLiveCoverage(9000, 9600, 42, day);
    expect(await LocalDb.liveStepsForDay(day), 42);
  });

  test('an empty phone sync leaves the day with no steps, not a zero row',
      () async {
    await LocalDb.replacePhoneCoverageForDay(day, const []);
    expect(await LocalDb.liveStepsForDay(day), 0);
  });

  test('zero/negative/inverted phone windows are dropped, not stored',
      () async {
    await LocalDb.replacePhoneCoverageForDay(
      day,
      [
        (startTs: 1000, endTs: 4600, steps: 0), // no steps that hour
        (startTs: 5000, endTs: 4000, steps: 50), // inverted
        (startTs: 6000, endTs: 9600, steps: 75), // the only real one
      ],
    );
    expect(await LocalDb.liveStepsForDay(day), 75);
  });

  test('clearing phone coverage falls back to the band, not to zero', () async {
    await LocalDb.addLiveCoverage(1000, 1600, 64, day); // band
    await LocalDb.replacePhoneCoverageForDay(
      day,
      [(startTs: 1000, endTs: 4600, steps: 900)],
    );
    expect(await LocalDb.liveStepsForDay(day), 900, reason: 'phone preferred');

    // User turns phone steps off: the phone rows must go, or they would keep
    // overriding the band forever from a source no longer being read.
    await LocalDb.clearPhoneCoverage();
    expect(await LocalDb.liveStepsForDay(day), 64);
  });
}
