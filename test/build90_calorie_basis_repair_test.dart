// Build 90 (algorithm 96): older workouts get an honest `calories_basis`.
//
// Before Build 90 a manual entry or heart-rate re-score could store the legacy
// bout scorer's GROSS kcal (resting energy included) while every screen showed
// ACTIVE kcal. `repairSessionCalorieBasis` recalculates a row only where the
// shown method's inputs are known, keeps everything else as recorded under
// 'legacy', and never touches a vendor import. Synthetic rows only.

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:whoop_companion/compute/manual_session.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';

Map<String, dynamic> _profile() => {
  'age': 30,
  'weight_kg': 75.0,
  'height_cm': 180.0,
  'sex': 'm',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final start = DateTime(2026, 9, 1, 7).millisecondsSinceEpoch ~/ 1000;

  Map<String, dynamic> row(
    String id, {
    required String type,
    required double? calories,
    int offsetHours = 0,
    String source = 'manual',
    String? basis,
    int? avgHr,
  }) {
    final s = start + offsetHours * 3600;
    return {
      'id': id,
      'start_ts': s,
      'end_ts': s + 3600,
      'type': type,
      'status': 'done',
      'calories': calories,
      'calories_basis': basis,
      'avg_hr': avgHr,
      'duration_min': 60,
      'source': source,
      'created_at': 1,
    };
  }

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.dbName = 'whoop_calorie_basis_repair_test.db';
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  tearDownAll(() async {
    await LocalDb.close();
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  test('recalculates only known inputs, keeps the rest, skips vendors', () async {
    final repo = LocalRepositoryImpl(getProfileMap: _profile);
    // A gross pre-Build 90 lift: MET-only active energy is (3.5 − 1) × 75 × 1 h.
    await LocalDb.putSession(
      row('lift', type: 'weight_training', calories: 400, avgHr: 120),
    );
    // No MET and no heart rate: nothing to recalculate from.
    await LocalDb.putSession(
      row('unknown', type: 'general_workout', calories: 300, offsetHours: 2),
    );
    // A vendor's own figure is never replaced by ours.
    await LocalDb.putSession(
      row(
        'whoop_1',
        type: 'weight_training',
        calories: 500,
        offsetHours: 4,
        source: 'whoop',
      ),
    );
    // Already active: left exactly as it is.
    await LocalDb.putSession(
      row(
        'done',
        type: 'weight_training',
        calories: 123,
        offsetHours: 6,
        basis: kCaloriesBasisActive,
      ),
    );

    expect(await repo.repairSessionCalorieBasis(), 1);

    final lift = (await LocalDb.session('lift'))!;
    expect(lift['calories'], closeTo(187.5, 1e-9));
    expect(lift['calories_basis'], kCaloriesBasisActive);

    final unknown = (await LocalDb.session('unknown'))!;
    expect(unknown['calories'], 300, reason: 'kept as recorded, not guessed');
    expect(unknown['calories_basis'], kCaloriesBasisLegacy);

    final vendor = (await LocalDb.session('whoop_1'))!;
    expect(vendor['calories'], 500);
    expect(vendor['calories_basis'], isNull);

    final active = (await LocalDb.session('done'))!;
    expect(active['calories'], 123);

    // Idempotent: every examined row now has a basis.
    expect(await repo.repairSessionCalorieBasis(), 0);
    expect((await LocalDb.session('unknown'))!['calories'], 300);
  });
}
