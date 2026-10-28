// The strength-set store. Sets are no longer typed during a workout (a lift is
// a timed session with its Lift Log), but rows from earlier builds stay: the
// ladder still lands the tables on an existing install, and deleting a
// session still takes its old sets with it.

import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<String> _dbPath(String name) async =>
    p.join(await databaseFactory.getDatabasesPath(), name);

/// Build a database file at [version] with nothing but a marker table, then
/// close it — the strength step is a pure create, so it needs no predecessor.
Future<void> _seedOldDb(String name, int version) async {
  final path = await _dbPath(name);
  await databaseFactory.deleteDatabase(path);
  final db = await databaseFactory.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: version,
      onCreate: (db, _) async {
        await db.execute('CREATE TABLE marker (id INTEGER PRIMARY KEY)');
        await db.insert('marker', {'id': 1});
      },
    ),
  );
  await db.close();
}

Future<Database> _openThroughLocalDb(String name) async {
  await LocalDb.close();
  LocalDb.dbName = name;
  return LocalDb.instance;
}

Future<bool> _hasTable(Database db, String table) async =>
    (await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",
      [table],
    ))
        .isNotEmpty;

void main() {
  final created = <String>[];

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDownAll(() async {
    await LocalDb.close();
    for (final n in created) {
      await databaseFactory.deleteDatabase(await _dbPath(n));
    }
  });

  Future<Database> upgradeFrom(int version, String name) async {
    created.add(name);
    await _seedOldDb(name, version);
    return _openThroughLocalDb(name);
  }

  test('v34 upgrades to the current version and gains the strength tables',
      () async {
    final db = await upgradeFrom(34, 'strength_from_34.db');

    final rows = await db.rawQuery('PRAGMA user_version');
    expect((rows.first.values.first as num).toInt(), LocalDb.schemaVersion);
    expect(LocalDb.schemaVersion, greaterThanOrEqualTo(38));

    expect(await _hasTable(db, 'strength_set'), isTrue);
    expect(await _hasTable(db, 'exercise_def'), isTrue);
    // The pre-existing data is untouched — this step creates, never rewrites.
    expect(await db.query('marker'), hasLength(1));
  });

  test('a fresh database has the tables too', () async {
    created.add('strength_fresh.db');
    await databaseFactory.deleteDatabase(await _dbPath('strength_fresh.db'));
    final db = await _openThroughLocalDb('strength_fresh.db');
    expect(await _hasTable(db, 'strength_set'), isTrue);
    expect(await _hasTable(db, 'exercise_def'), isTrue);
  });

  test('deleting a session takes its sets with it', () async {
    created.add('strength_cascade.db');
    await databaseFactory.deleteDatabase(await _dbPath('strength_cascade.db'));
    await _openThroughLocalDb('strength_cascade.db');

    await LocalDb.putSession({
      'id': 'sess-del',
      'start_ts': 1770100000,
      'end_ts': 1770103600,
      'type': 'strength',
      'status': 'done',
      'created_at': 1770100000,
    });
    final db = await LocalDb.instance;
    await db.insert('strength_set', {
      'session_id': 'sess-del',
      'seq': 0,
      'exercise_key': 'bench_press',
      'set_index': 1,
      'reps': 1,
      'load_kg': 200.0,
      'at_ts': 1770100100,
    });

    await LocalDb.deleteSession('sess-del');

    // A set on a deleted workout would otherwise keep exporting under a
    // session_id that no longer exists.
    expect(await db.query('strength_set'), isEmpty);
  });

  test('sessions carries the private flag, defaulting to not-private',
      () async {
    final db = await upgradeFrom(39, 'sessions_private_from_39.db');
    final cols = await db.rawQuery('PRAGMA table_info(sessions)');
    final private = cols.firstWhere((c) => c['name'] == 'private');
    expect(private['notnull'], 1);
    expect(private['dflt_value'], '0');

    await LocalDb.putSession({
      'id': 'sess-priv',
      'start_ts': 1770200000,
      'end_ts': 1770203600,
      'type': 'run',
      'status': 'done',
      'created_at': 1770200000,
    });
    expect((await LocalDb.session('sess-priv'))!['private'], 0);
    await LocalDb.setSessionPrivate('sess-priv', true);
    expect((await LocalDb.session('sess-priv'))!['private'], 1);
    await LocalDb.setSessionPrivate('sess-priv', false);
    expect((await LocalDb.session('sess-priv'))!['private'], 0);
  });
}
