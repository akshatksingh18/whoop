import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_analytics/onehz.dart' as ana;
import 'package:openstrap_edge/data/db.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The movement floor must be estimated ONCE and then FROZEN.
///
/// PROVEN on 4 days of real substrate: a floor recomputed from the same signal
/// it thresholds reports 37 active minutes at 1x, 1.5x, 2x AND 3x activity,
/// while a frozen floor reports 23 -> 254. A tracking threshold is a metric
/// that cannot see change, so persistence here is correctness, not caching.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.dbName = 'openstrap_movement_floor_test.db';
  });

  setUp(() async {
    await LocalDb.close();
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  tearDownAll(() async {
    await LocalDb.close();
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  test('no floor before enrollment — abstain, never a constant', () async {
    expect(await LocalDb.getMovementFloor(), isNull);
  });

  test('a frozen floor round-trips exactly', () async {
    await LocalDb.putMovementFloor(
        floorG: 0.4442, frozenOn: '2026-08-03', days: 18);
    final got = await LocalDb.getMovementFloor();
    expect(got, isNotNull);
    expect(got!.floorG, closeTo(0.4442, 1e-9));
    expect(got.frozenOn, '2026-08-03');
    expect(got.days, 18);
  });

  test('re-freezing overwrites rather than accumulating', () async {
    await LocalDb.putMovementFloor(
        floorG: 0.40, frozenOn: '2026-07-01', days: 14);
    await LocalDb.putMovementFloor(
        floorG: 0.47, frozenOn: '2026-08-03', days: 30);
    final got = await LocalDb.getMovementFloor();
    expect(got!.floorG, closeTo(0.47, 1e-9));
    expect(got.frozenOn, '2026-08-03');
  });

  test('a degenerate persisted floor is rejected, not served', () async {
    // A zero/negative floor would pass EVERY minute. Reading it back as null
    // makes the estimator abstain, which is the honest failure mode.
    await LocalDb.putMovementFloor(
        floorG: 0.0, frozenOn: '2026-08-03', days: 20);
    expect(await LocalDb.getMovementFloor(), isNull);
    await LocalDb.putMovementFloor(
        floorG: -1.0, frozenOn: '2026-08-03', days: 20);
    expect(await LocalDb.getMovementFloor(), isNull);
  });

  test('the thaw policy only fires on a real change of scale', () {
    // Time passing and behaviour changing must NOT thaw it — that is exactly
    // the tracking behaviour freezing exists to prevent.
    expect(ana.shouldRefreezeFloor(daysSinceFrozen: 200), isFalse);
    expect(ana.shouldRefreezeFloor(daysSinceFrozen: 29, wearGapDays: 10),
        isFalse);
    // These genuinely change the signal's scale.
    expect(ana.shouldRefreezeFloor(daysSinceFrozen: 1, deviceChanged: true),
        isTrue);
    expect(
        ana.shouldRefreezeFloor(daysSinceFrozen: 1, wristChanged: true), isTrue);
    expect(ana.shouldRefreezeFloor(daysSinceFrozen: 1, wearGapDays: 30), isTrue);
    expect(ana.shouldRefreezeFloor(daysSinceFrozen: 365), isTrue);
  });

  test('enrollment needs more days than the bare estimator minimum', () {
    expect(ana.enrollmentDaysForFrozenFloor,
        greaterThan(ana.personalDynFloorMinDays));
  });
}
