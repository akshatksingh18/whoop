// Every table the schema creates must be carried by backup import, and every
// imported table that holds an only copy must also be carried by the
// damaged-file salvage (B86-13: salvage dropped body_weight and meal_template).
// A new table fails here until it is placed in both lists or explicitly
// listed below as regenerable.

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:openstrap_edge/data/db.dart';

/// Rebuilt from the ledger/raw data or pure scheduling state: losing them
/// costs recomputation, never a user's record.
const _regenerable = {
  'band_backlog',
  'compute_freshness',
  'compute_jobs',
  'derived_day',
  'notif_fired',
  'raw_records',
  'sleep_session_candidates',
  'sync_ledger',
  'sync_quarantine',
  'wake_day_features',
  'workout_suggestions',
};

/// Imported by a restore but deliberately not by salvage: the primary device
/// row is re-established by pairing, and notification history is not data.
const _importOnly = {'notifications', 'device'};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.dbName = 'openstrap_table_coverage_test.db';
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  tearDownAll(() async {
    await LocalDb.close();
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  test('every schema table is carried by import or marked regenerable', () async {
    final tables = await LocalDb.tableNames();
    final missing = [
      for (final t in tables)
        if (!LocalDb.importTablesForTest.contains(t) && !_regenerable.contains(t))
          t,
    ];
    expect(missing, isEmpty, reason: 'add these to _importTables in db.dart');
  });

  test('salvage carries every imported only-copy table', () {
    final missing = [
      for (final t in LocalDb.importTablesForTest)
        if (!LocalDb.salvageTablesForTest.contains(t) && !_importOnly.contains(t))
          t,
    ];
    expect(missing, isEmpty, reason: 'add these to _salvageTables in db.dart');
  });
}
