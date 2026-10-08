// Build 84: lifting as a separate maintenance line (never in the total), and
// the low-end digestion cost (walking_energy_test holds its exact table).

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:openstrap_edge/compute/day_upkeep.dart';
import 'package:openstrap_edge/compute/profile.dart';
import 'package:openstrap_edge/data/db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const me = Profile(ageYears: 23, weightKg: 80.5, heightCm: 186.69, sex: 'm');
  const day = '2026-10-06';
  final nine = DateTime(2026, 10, 6, 9).millisecondsSinceEpoch ~/ 1000;

  setUpAll(() async {
    // Sessions are priced at their dated profile, which reads preferences.
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.dbName = 'build84.db';
    await databaseFactory.deleteDatabase(
      path.join(await databaseFactory.getDatabasesPath(), LocalDb.dbName),
    );
  });
  tearDownAll(() async {
    await LocalDb.close();
    await databaseFactory.deleteDatabase(
      path.join(await databaseFactory.getDatabasesPath(), LocalDb.dbName),
    );
  });

  Future<void> session(String id, String type, int start, int minutes) async {
    final db = await LocalDb.instance;
    await db.insert('sessions', {
      'id': id,
      'start_ts': start,
      'end_ts': start + minutes * 60,
      'type': type,
      'status': 'done',
      'source': 'manual',
      'created_at': 1,
    });
  }

  test('lift types are the strength types conservativeMet prices', () {
    expect(isLiftType('Weight training'), isTrue);
    expect(isLiftType('powerlifting'), isTrue);
    expect(isLiftType('Run'), isFalse);
    expect(isLiftType(null), isFalse);
    expect(conservativeMet('weight_training', 0), 3.5);
  });

  test('no lifting session, no line', () async {
    await session('run', 'Run', nine, 30);
    expect(await liftingOn(day, me), isNull);
  });

  test('a 60-minute lift without heart rate: (3.5 − 1) × 80.5 × 1 h', () async {
    await session('lift', 'Weight training', nine + 3600, 60);
    final l = (await liftingOn(day, me))!;
    expect(l.kcal, closeTo(201.25, 1e-9));
    expect(l.sessions, 1);
    // No phone or band steps recorded for the session: said, not guessed.
    expect(l.approximate, isTrue);
    // Never moves the conservative total.
    final u = DayUpkeep(me, steps: 15000, eaten: 0, lifting: l);
    expect(u.parts!.total, closeTo(1861.8125 + 395.381, 0.001));
  });

  test('a session the next day is not this day\'s', () async {
    final next = DateTime(2026, 10, 7, 9).millisecondsSinceEpoch ~/ 1000;
    await session('lift2', 'Weight training', next, 60);
    expect((await liftingOn(day, me))!.sessions, 1);
    expect((await liftingOn('2026-10-07', me))!.kcal, closeTo(201.25, 1e-9));
  });

  test('no weight, no line', () async {
    expect(await liftingOn(day, const Profile(ageYears: 23)), isNull);
  });
}
