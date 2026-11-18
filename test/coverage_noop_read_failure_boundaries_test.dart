// Real authored SQLite rows and paging; only a driver's error response is
// scripted. This is not physical corrupt-page validation. Heavy derivation
// uses its existing capture boundary, so the parser's retained input is visible.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
// The installed driver's exception carries the same error classification as
// its native response; no fake row or fake database query result is returned.
// ignore: implementation_imports
import 'package:sqflite_common/src/exception.dart'
    show SqfliteDatabaseException;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/import/import_container.dart';
import 'package:whoop_companion/import/noop_backup_import.dart';
import 'coverage_noop_container_contract_test.dart' show CaptureEngine;
import 'sleep_correction_import_race_test.dart'
    show SourceReadFactory, SourceReadDatabase;
import 'support/coverage_store.dart';

class FaultFactory extends SourceReadFactory {
  FaultFactory(
    DatabaseFactory base,
    this.phase,
    this.errorText, {
    this.all = false,
  }) : super(base, 'rrInterval', () async {});
  final String phase, errorText;
  final bool all;
  bool enabled = true;
  int closes = 0;
  final faulted = <String>{};
  bool shouldFail(String table, String at) =>
      enabled &&
      phase == at &&
      (table == 'rrInterval' || all) &&
      !faulted.contains(table);
  Never fail(String table) {
    faulted.add(table);
    throw SqfliteDatabaseException(errorText, null);
  }

  @override
  Future<Database> openDatabase(
    String path, {
    OpenDatabaseOptions? options,
  }) async {
    final db = await delegate.openDatabase(path, options: options);
    return options?.readOnly == true ? FaultReader(db, this) : db;
  }
}

class FaultReader extends SourceReadDatabase {
  FaultReader(Database db, this.owner)
    : super(
        db,
        'rrInterval',
        () async {},
        onClose: () async {
          owner.closes++;
        },
      );
  final FaultFactory owner;
  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async {
    if (sql.startsWith('SELECT MIN(ts)')) {
      for (final table in ['hrSample', 'rrInterval']) {
        if (sql.contains('FROM $table ') && owner.shouldFail(table, 'span')) {
          owner.fail(table);
        }
      }
    }
    return super.rawQuery(sql, arguments);
  }

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    final phase = (offset ?? 0) > 0 ? 'tie' : 'page';
    if (owner.shouldFail(table, phase)) {
      owner.fail(table);
    }
    return delegate.query(
      table,
      distinct: distinct,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
      groupBy: groupBy,
      having: having,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DatabaseFactory previous;
  late File input;
  late List<int> bytes;
  late int oldPageRows;
  setUpAll(() => coverageStore('noop-read-failure-boundaries'));
  setUp(() async {
    await resetCoverageStore();
    previous = databaseFactory;
    oldPageRows = kNoopBackupPageRows;
    kNoopBackupPageRows = 2;
    final root = await (await Directory(
      'build/coverage-remainder/noop-read-failure-boundaries',
    ).absolute.create(recursive: true)).createTemp('authored-');
    input = File('${root.path}/authored.sqlite');
    final source = await previous.openDatabase(input.path);
    await source.execute('CREATE TABLE hrSample(ts INTEGER,bpm INTEGER)');
    await source.execute('CREATE TABLE rrInterval(ts INTEGER,rrMs INTEGER)');
    const start = 1617724800;
    for (var i = 0; i < 5; i++) {
      await source.insert('hrSample', {'ts': start + i, 'bpm': 70 + i});
    }
    for (var i = 0; i < 6; i++) {
      await source.insert('rrInterval', {
        'ts': start + 1,
        'rrMs': 800 + i * 10,
      });
    }
    await source.close();
    bytes = await input.readAsBytes();
    await LocalDb.setCursor('authored_recovery', 'keep');
  });
  tearDown(() {
    databaseFactory = previous;
    kNoopBackupPageRows = oldPageRows;
  });
  tearDownAll(LocalDb.close);
  const profile = Profile();

  for (final phase in ['span', 'page', 'tie']) {
    for (final message in [
      'database disk image is malformed',
      'SQLITE_CORRUPT',
      'no such column: authored_refusal',
    ]) {
      test(
        'NOOP $phase error "$message" preserves accepted channels, source bytes and a complete retry',
        () async {
          final factory = FaultFactory(previous, phase, message);
          databaseFactory = factory;
          final engine = CaptureEngine();
          final corrupt = message != 'no such column: authored_refusal';
          if (corrupt) {
            final result = await NoopBackupImporter.importDatabase(
              input.path,
              profile,
              engine,
            );
            expect(result.corruptTables, {'rrInterval'});
            expect(result.days, 1);
            expect(engine.inputs, hasLength(1));
            expect(engine.inputs.single.hr, [70, 71, 72, 73, 74]);
            expect(
              engine.inputs.single.rrMs,
              phase == 'tie' ? [800.0, 810.0] : isEmpty,
            );
            expect(result.rows, phase == 'tie' ? 7 : 5);
            expect(engine.finalizations, 1);
          } else {
            await expectLater(
              NoopBackupImporter.importDatabase(input.path, profile, engine),
              throwsA(
                isA<DatabaseException>().having(
                  (e) => e.toString(),
                  'original read refusal',
                  contains(message),
                ),
              ),
            );
            expect(engine.inputs, isEmpty);
            expect(engine.finalizations, 0);
          }
          expect(factory.faulted, {'rrInterval'});
          expect(factory.closes, 1);
          expect(await input.readAsBytes(), bytes);
          expect(await LocalDb.getCursor('authored_recovery'), 'keep');
          expect(await (await LocalDb.instance).query('day_result'), isEmpty);
          factory.enabled = false;
          final retry = CaptureEngine();
          final result = await NoopBackupImporter.importDatabase(
            input.path,
            profile,
            retry,
          );
          expect(result.corruptTables, isEmpty);
          expect(result.rows, 11);
          expect(result.days, 1);
          expect(retry.inputs.single.rrMs, [
            800.0,
            810.0,
            820.0,
            830.0,
            840.0,
            850.0,
          ]);
          expect(retry.inputs.single.hr, [70, 71, 72, 73, 74]);
          expect(factory.closes, 2);
          expect(await input.readAsBytes(), bytes);
          final renamed = await input.rename('${input.path}.retained');
          expect(
            await renamed.readAsBytes(),
            bytes,
            reason: 'Both read-only readers released the source',
          );
        },
      );
    }
  }
  for (final phase in ['span', 'page']) {
    test(
      'NOOP every-table $phase corruption is a recovery refusal, never an empty successful import',
      () async {
        final factory = FaultFactory(
          previous,
          phase,
          'SQLITE_CORRUPT',
          all: true,
        );
        databaseFactory = factory;
        final engine = CaptureEngine();
        await expectLater(
          NoopBackupImporter.importDatabase(input.path, profile, engine),
          throwsA(
            isA<ImportFormatException>().having(
              (e) => e.message,
              'corrupt-file explanation',
              contains('is corrupted'),
            ),
          ),
        );
        expect(factory.faulted, {'hrSample', 'rrInterval'});
        expect(factory.closes, 1);
        expect(engine.inputs, isEmpty);
        expect(engine.finalizations, 0);
        expect(await input.readAsBytes(), bytes);
        expect(await LocalDb.getCursor('authored_recovery'), 'keep');
        factory.enabled = false;
        expect(
          (await NoopBackupImporter.importDatabase(
            input.path,
            profile,
            CaptureEngine(),
          )).rows,
          11,
        );
        expect(factory.closes, 2);
      },
    );
  }
}
