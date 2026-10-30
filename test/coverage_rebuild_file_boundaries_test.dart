import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
// sqflite only accepts its own factory base; no public fault-injection adapter
// exists. Keep this test boundary on the installed implementation, not a fake DB.
// ignore: implementation_imports
import 'package:sqflite_common/src/factory_mixin.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whoop_companion/data/db.dart';

// Refuse only the real storage boundary. All allowed opens/queries use FFI;
// every file below is a closed, consistent copy of an authored SQLite WAL set.
class _OpenBoundary extends SqfliteDatabaseFactoryBase {
  _OpenBoundary(this.dir);
  final String dir;
  String? refusedPath;
  int refusals = 0;
  int refusedOpens = 0;

  @override
  Future<T> invokeMethod<T>(String method, [Object? arguments]) =>
      (databaseFactoryFfi as SqfliteDatabaseFactoryMixin).invokeMethod<T>(
        method,
        arguments,
      );

  @override
  Future<Database> openDatabase(
    String path, {
    OpenDatabaseOptions? options,
  }) async {
    if (path == refusedPath && refusals > 0) {
      refusals--;
      refusedOpens++;
      throw FileSystemException('authored open refusal', path);
    }
    return databaseFactoryFfi.openDatabase(path, options: options);
  }

  @override
  Future<String> getDatabasesPath() async => dir;
  @override
  Future<void> setDatabasesPath(String? path) async =>
      throw UnsupportedError('fixed fixture directory');
  @override
  Future<void> deleteDatabase(String path) =>
      databaseFactoryFfi.deleteDatabase(path);
  @override
  Future<bool> databaseExists(String path) =>
      databaseFactoryFfi.databaseExists(path);
  @override
  Future<void> writeDatabaseBytes(String path, Uint8List bytes) =>
      databaseFactoryFfi.writeDatabaseBytes(path, bytes);
  @override
  Future<Uint8List> readDatabaseBytes(String path) =>
      databaseFactoryFfi.readDatabaseBytes(path);
}

class _RenameBoundary implements File {
  _RenameBoundary(this.file, this.onRename);
  final File file;
  final Future<File> Function(File, String) onRename;

  @override
  bool existsSync() => file.existsSync();
  @override
  Future<File> rename(String newPath) => onRename(file, newPath);
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'unexpected file operation: ${invocation.memberName}',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const name = 'whoop_rebuild_boundary.db';
  const suffixes = ['', '-wal', '-shm'];
  late DatabaseFactory previousFactory;
  late String previousName;
  late Directory dir;
  late _OpenBoundary factory;
  late String path;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalDb.close();
    previousFactory = databaseFactory;
    previousName = LocalDb.dbName;
    dir = await Directory.systemTemp.createTemp('whoop_rebuild_boundary_');
    factory = _OpenBoundary(dir.path);
    databaseFactory = factory;
    path = p.join(dir.path, name);
    LocalDb.lastRebuild = null;
  });

  tearDown(() async {
    await LocalDb.close();
    databaseFactory = previousFactory;
    LocalDb.dbName = previousName;
    LocalDb.lastRebuild = null;
    // Retain authored recovery files for diagnosis. CI's temp root is ephemeral;
    // local probe evidence is collected separately, never uploaded as fixtures.
  });

  Future<Map<String, Uint8List>> seedClosedWalSet() async {
    LocalDb.dbName = 'source.db';
    final db = await LocalDb.instance;
    await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    await db.execute('PRAGMA wal_autocheckpoint=0');
    await db.insert('food_entry', {
      'id': 'authored-wal-food',
      'date': '2026-04-06',
      'meal': 'lunch',
      'label': 'Authored recovery input',
      'kcal': 123.0,
      'created_at': 11,
      'updated_at': 12,
    });
    final bytes = <String, Uint8List>{};
    // No writes overlap this snapshot; the copied destination has never had a
    // live handle. Its WAL contains the food row, absent from its main file.
    for (final suffix in suffixes) {
      final source = File(p.join(dir.path, 'source.db$suffix'));
      expect(source.existsSync(), isTrue, reason: suffix);
      bytes[suffix] = await source.readAsBytes();
      await File('$path$suffix').writeAsBytes(bytes[suffix]!, flush: true);
    }
    expect(bytes['-wal'], isNotEmpty);
    await LocalDb.close();
    LocalDb.dbName = name;
    return bytes;
  }

  Future<void> expectRestored(Map<String, Uint8List> bytes) async {
    for (final suffix in suffixes) {
      final original = File('$path$suffix');
      expect(original.existsSync(), isTrue, reason: original.path);
      expect(await original.readAsBytes(), bytes[suffix], reason: suffix);
    }
    expect(LocalDb.lastRebuild, isNull);
    final db = await LocalDb.instance;
    expect(await db.query('food_entry'), [
      containsPair('id', 'authored-wal-food'),
    ]);
    expect((await db.query('food_entry')).single['kcal'], 123.0);
    expect(LocalDb.lastRebuild, isNull, reason: 'retry opens the original WAL');
  }

  test(
    'fresh-open refusal restores original main WAL and SHM before retry',
    () async {
      final bytes = await seedClosedWalSet();
      factory
        ..refusedPath = path
        ..refusals = 2;
      await expectLater(
        LocalDb.instance,
        throwsA(
          isA<FileSystemException>().having(
            (e) => e.message,
            'message',
            'authored open refusal',
          ),
        ),
      );
      expect(factory.refusedOpens, 2);
      await expectRestored(bytes);
    },
  );

  for (final refusedSuffix in suffixes) {
    test(
      'refused $refusedSuffix quarantine restores every original before retry',
      () async {
        final bytes = await seedClosedWalSet();
        factory
          ..refusedPath = path
          ..refusals = 1;
        final outer = Zone.current;
        final moves = <String>[];
        await IOOverrides.runZoned(
          () async {
            await expectLater(
              LocalDb.instance,
              throwsA(
                isA<FileSystemException>().having(
                  (e) => e.message,
                  'message',
                  'authored rename refusal',
                ),
              ),
            );
          },
          createFile: (filePath) {
            final real = outer.run(() => File(filePath));
            if (!filePath.startsWith(path)) return real;
            return _RenameBoundary(real, (file, destination) async {
              moves.add(file.path);
              if (file.path == '$path$refusedSuffix') {
                throw FileSystemException('authored rename refusal', file.path);
              }
              return file.rename(destination);
            });
          },
        );
        expect(moves, contains(path));
        if (refusedSuffix.isNotEmpty) {
          expect(moves.last, startsWith('$path.unopenable-'));
          expect(moves.last.endsWith('-wal'), isFalse);
          expect(moves.last.endsWith('-shm'), isFalse);
        }
        expect(factory.refusedOpens, 1, reason: 'fresh open must not begin');
        await expectRestored(bytes);
      },
    );
  }
}
