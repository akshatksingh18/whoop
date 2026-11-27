// Store-name migration over real SQLite files in a fresh directory per test.
// Every store here is synthetic: one table of numbered placeholder rows.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' show Sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/migration/legacy_names.dart';
import 'package:whoop_companion/migration/store_migration.dart';

const _current = LocalDb.kStoreFileName;
const _legacy = LegacyNames.databaseFile;

Future<void> _store(String path, {int rows = 3, int version = 7}) async {
  final db = await openDatabase(path, singleInstance: false);
  await db.execute('CREATE TABLE IF NOT EXISTS t (id INTEGER PRIMARY KEY, v)');
  for (var i = 0; i < rows; i++) {
    await db.insert('t', {'v': 'synthetic $i'});
  }
  await db.execute('PRAGMA user_version = $version');
  await db.close();
}

Future<(int?, int?)> _read(String path) async {
  final db = await openDatabase(path, singleInstance: false);
  try {
    return (
      Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM t')),
      Sqflite.firstIntValue(await db.rawQuery('PRAGMA user_version')),
    );
  } finally {
    await db.close();
  }
}

List<String> _names(Directory dir) =>
    [for (final f in dir.listSync()) p.basename(f.path)]..sort();

void main() {
  late Directory dir;
  String at(String name) => p.join(dir.path, name);
  Future<StoreResolution> resolve() =>
      StoreMigration.resolve(dir.path, current: _current, legacy: _legacy);

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('store-migration-');
    StoreMigration.debugStep = null;
  });
  tearDown(() async {
    StoreMigration.debugStep = null;
    await LocalDb.close();
    LocalDb.dbName = LocalDb.kStoreFileName;
    await dir.delete(recursive: true);
  });

  test('no store under either name starts the owned name empty', () async {
    final r = await resolve();
    expect(
      (r.name, r.move, r.retainedAs, r.error),
      (_current, StoreMove.fresh, null, null),
    );
    expect(_names(dir), isEmpty);
  });

  test('an owned store alone is opened as it is', () async {
    await _store(at(_current));
    final r = await resolve();
    expect((r.name, r.move), (_current, StoreMove.current));
    expect(await _read(at(_current)), (3, 7));
  });

  test('the original is copied, checked, published and kept aside', () async {
    await _store(at(_legacy), rows: 40);
    final r = await resolve();
    expect((r.name, r.move, r.error), (_current, StoreMove.migrated, null));
    expect(await _read(at(_current)), (40, 7));
    expect(p.basename(r.retainedAs!), startsWith('$_legacy.migrated-'));
    expect(await _read(r.retainedAs!), (40, 7));
    expect(File(at(_legacy)).existsSync(), false);
    expect(_names(dir), [_current, p.basename(r.retainedAs!)]..sort());
  });

  test('rows still in the original write-ahead log are copied', () async {
    final live = await Directory(at('live')).create();
    final src = p.join(live.path, 'src.db');
    final db = await openDatabase(src, singleInstance: false);
    await db.rawQuery('PRAGMA journal_mode=WAL');
    await db.rawQuery('PRAGMA wal_autocheckpoint=0');
    await db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY, v)');
    for (var i = 0; i < 25; i++) {
      await db.insert('t', {'v': 'synthetic $i'});
    }
    expect(File('$src-wal').lengthSync(), greaterThan(0));
    await File(src).copy(at(_legacy));
    await File('$src-wal').copy(at('$_legacy-wal'));
    await db.close();
    await live.delete(recursive: true);

    final r = await resolve();
    expect(r.move, StoreMove.migrated);
    expect((await _read(at(_current))).$1, 25);
  });

  test('an interrupted earlier copy is discarded and redone', () async {
    await _store(at(_legacy));
    await File(at('$_current.migrating')).writeAsString('partial copy');
    await File(at('$_current.migrating-journal')).writeAsString('partial');
    final r = await resolve();
    expect(r.move, StoreMove.migrated);
    expect(await _read(at(_current)), (3, 7));
    expect(_names(dir).where((n) => n.contains('migrating')), isEmpty);
  });

  test('both names: the owned store stays and the original is set aside '
      'without merging', () async {
    await _store(at(_current), rows: 2);
    await _store(at(_legacy), rows: 9);
    await File(at('$_legacy-wal')).writeAsString('synthetic journal');
    final r = await resolve();
    expect(
      (r.name, r.move, r.error),
      (_current, StoreMove.retainedLegacy, null),
    );
    expect(await _read(at(_current)), (2, 7));
    expect(p.basename(r.retainedAs!), startsWith('$_legacy.retained-'));
    expect(
      await File('${r.retainedAs}-wal').readAsString(),
      'synthetic journal',
    );
    expect(await _read(r.retainedAs!), (9, 7));
    expect(File(at(_legacy)).existsSync(), false);
  });

  test('an unreadable original keeps serving under its own name', () async {
    await File(at(_legacy)).writeAsString('not a database');
    final r = await resolve();
    expect(
      (r.name, r.move, r.retainedAs),
      (_legacy, StoreMove.keptLegacy, null),
    );
    expect(r.error, isNotNull);
    expect(await File(at(_legacy)).readAsString(), 'not a database');
    expect(_names(dir), [_legacy]);
  });

  test('a copy that does not match the original is never published', () async {
    await _store(at(_legacy));
    StoreMigration.debugStep = (step) async {
      if (step != 'check') return;
      final copy = await openDatabase(
        at('$_current.migrating'),
        singleInstance: false,
      );
      await copy.insert('t', {'v': 'extra'});
      await copy.close();
    };
    final r = await resolve();
    expect(r.move, StoreMove.keptLegacy);
    expect(r.error, contains('did not match'));
    expect(_names(dir), [_legacy]);
    expect(await _read(at(_legacy)), (3, 7));
  });

  test('a refused publication leaves only the original', () async {
    await _store(at(_legacy));
    StoreMigration.debugStep = (step) async {
      if (step == 'publish') throw const FileSystemException('no space');
    };
    final r = await resolve();
    expect((r.name, r.move), (_legacy, StoreMove.keptLegacy));
    expect(r.error, contains('no space'));
    expect(_names(dir), [_legacy]);
  });

  test('a published store whose original cannot move stays published; '
      'the next open sets the original aside', () async {
    await _store(at(_legacy));
    StoreMigration.debugStep = (step) async {
      if (step == 'aside') throw const FileSystemException('refused');
    };
    final first = await resolve();
    expect(
      (first.name, first.move, first.retainedAs),
      (_current, StoreMove.migrated, null),
    );
    expect(first.error, contains('refused'));
    expect(_names(dir), [_current, _legacy]..sort());

    StoreMigration.debugStep = null;
    final next = await resolve();
    expect(next.move, StoreMove.retainedLegacy);
    expect(await _read(at(_current)), (3, 7));
    expect(await _read(next.retainedAs!), (3, 7));
  });

  test(
    'a refused move aside puts the journals back with their store',
    () async {
      await _store(at(_current));
      await _store(at(_legacy));
      await File(at('$_legacy-wal')).writeAsString('w');
      await File(at('$_legacy-shm')).writeAsString('s');
      final steps = <String>[];
      StoreMigration.debugStep = (step) async {
        steps.add(step);
        if (step == 'aside') throw const FileSystemException('refused');
      };
      final r = await resolve();
      expect((r.move, r.retainedAs), (StoreMove.retainedLegacy, null));
      expect(steps, [
        'aside-wal',
        'aside-shm',
        'aside',
        'restore-shm',
        'restore-wal',
      ]);
      expect(
        _names(dir),
        [_current, _legacy, '$_legacy-shm', '$_legacy-wal']..sort(),
      );
    },
  );

  test('a refused put-back is reported and nothing is deleted', () async {
    await _store(at(_current));
    await _store(at(_legacy));
    await File(at('$_legacy-wal')).writeAsString('w');
    StoreMigration.debugStep = (step) async {
      if (step == 'aside' || step == 'restore-wal') {
        throw FileSystemException(step);
      }
    };
    final r = await resolve();
    expect(r.retainedAs, null);
    expect(r.error, contains('putting the original back failed'));
    expect(_names(dir).length, 3);
    expect(await _read(at(_legacy)), (3, 7));
  });

  test(
    'LocalDb migrates the installed store once for concurrent first opens',
    () async {
      databaseFactoryFfi.setDatabasesPath(dir.path);
      LocalDb.dbName = _legacy;
      await LocalDb.putJournal('2026-01-02', '["synthetic"]', 'placeholder');
      await LocalDb.close();

      LocalDb.dbName = LocalDb.kStoreFileName;
      final opened = await Future.wait([LocalDb.instance, LocalDb.instance]);
      expect(identical(opened.first, opened.last), true);
      expect(LocalDb.lastStoreMove!.move, StoreMove.migrated);
      expect(opened.first.path, at(_current));
      final rows = await opened.first.query('journal');
      expect([for (final r in rows) r['note']], ['placeholder']);
      expect(
        _names(dir).where((n) => n.startsWith('$_legacy.migrated-')).length,
        1,
      );
    },
  );
}
