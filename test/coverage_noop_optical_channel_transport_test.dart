// A real read-only SQLite backup through paging and the shared import buffer.
// Heavy derivation is captured at its existing seam;raw optical values are
// never asserted to be an oxygen percentage or a calibrated device family.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/import/import_container.dart';
import 'package:whoop_companion/import/noop_backup_import.dart';

import 'coverage_noop_container_contract_test.dart' show CaptureEngine;
import 'sleep_correction_import_race_test.dart' show SourceReadFactory;
import 'support/coverage_store.dart';

class _RefusedSourceOpen extends SourceReadFactory {
  _RefusedSourceOpen(DatabaseFactory base) : super(base, '', () async {});
  bool refuse = true;
  int sourceOpens = 0;
  @override
  Future<Database> openDatabase(
    String path, {
    OpenDatabaseOptions? options,
  }) async {
    if (options?.readOnly == true) {
      sourceOpens++;
      if (refuse) {
        throw const FileSystemException('authored read-only open refusal');
      }
    }
    return delegate.openDatabase(path, options: options);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('noop-optical-channel-transport'));
  setUp(resetCoverageStore);
  tearDown(() => kNoopBackupPageRows = 20000);
  tearDownAll(LocalDb.close);
  test(
    'a refused read-only source open preserves original data and permits a repaired retry',
    () async {
      final root = await (await Directory(
        'build/coverage-remainder/noop-optical-channel-transport',
      ).absolute.create(recursive: true)).createTemp('authored-open-');
      final source = File('${root.path}/authored.sqlite');
      final db = await databaseFactory.openDatabase(source.path);
      await db.execute('CREATE TABLE hrSample(ts INTEGER,bpm INTEGER)');
      final ts = localDayStartSec('2021-04-06')! + 43200;
      await db.insert('hrSample', {'ts': ts, 'bpm': 61});
      await db.close();
      final bytes = await source.readAsBytes();
      await LocalDb.putJournal(
        '2021-04-06',
        '["authored"]',
        'keep before refused import',
      );
      final saved = await (await LocalDb.instance).query('journal');
      final previous = databaseFactory;
      final factory = _RefusedSourceOpen(previous);
      final engine = CaptureEngine();
      databaseFactory = factory;
      try {
        await expectLater(
          NoopBackupImporter.importDatabase(
            source.path,
            const Profile(),
            engine,
          ),
          throwsA(
            isA<ImportFormatException>().having(
              (e) => e.message,
              'actionable source failure',
              allOf(
                contains('database could not be opened'),
                contains('authored read-only open refusal'),
              ),
            ),
          ),
        );
        expect(factory.sourceOpens, 1);
        expect(engine.inputs, isEmpty);
        expect(engine.finalizations, 0);
        expect(await source.readAsBytes(), bytes);
        expect(await (await LocalDb.instance).query('journal'), saved);
        factory.refuse = false;
        final result = await NoopBackupImporter.importDatabase(
          source.path,
          const Profile(),
          engine,
        );
        expect(factory.sourceOpens, 2);
        expect(result.rows, 1);
        expect(result.days, 1);
        expect(engine.inputs.single.hr, [61]);
        expect(engine.finalizations, 1);
        expect(await source.readAsBytes(), bytes);
        expect(await (await LocalDb.instance).query('journal'), saved);
      } finally {
        databaseFactory = previous;
      }
      final retained = await source.rename('${source.path}.retained');
      expect(await retained.readAsBytes(), bytes);
    },
  );
  for (final pageRows in [1, 20000]) {
    for (final mode in ['paired', 'raw-zero', 'red-only', 'infrared-only']) {
      test(
        'NOOP $mode optical samples retain independent channels on $pageRows-row pages',
        () async {
          final root = await (await Directory(
            'build/coverage-remainder/noop-optical-channel-transport',
          ).absolute.create(recursive: true)).createTemp('authored-');
          final source = File('${root.path}/authored.sqlite');
          final db = await databaseFactory.openDatabase(source.path);
          await db.execute(
            'CREATE TABLE hrSample(deviceId TEXT,ts INTEGER,bpm INTEGER,PRIMARY KEY(deviceId,ts))',
          );
          await db.execute(
            'CREATE TABLE spo2Sample(deviceId TEXT,ts INTEGER,red INTEGER,ir INTEGER,PRIMARY KEY(deviceId,ts))',
          );
          final ts = localDayStartSec('2021-04-06')! + 43200;
          for (var i = 0; i < 3; i++) {
            await db.insert('hrSample', {
              'deviceId': 'authored-hr',
              'ts': ts + i,
              'bpm': 60 + i,
            });
          }
          final red = mode == 'infrared-only'
              ? null
              : mode == 'raw-zero'
              ? 0
              : 12345;
          final ir = mode == 'red-only'
              ? null
              : mode == 'raw-zero'
              ? 0
              : 23456;
          for (final i in [0, 2]) {
            await db.insert('spo2Sample', {
              'deviceId': 'authored-optical',
              'ts': ts + i,
              'red': red == null ? null : red + i,
              'ir': ir == null ? null : ir + i,
            });
          }
          await db.close();
          final bytes = await source.readAsBytes();
          await LocalDb.putJournal(
            '2021-04-06',
            '["authored"]',
            'retain unrelated note',
          );
          final saved = await (await LocalDb.instance).query('journal');
          kNoopBackupPageRows = pageRows;
          final engine = CaptureEngine();
          final progress = <int>[];
          final result = await NoopBackupImporter.importDatabase(
            source.path,
            const Profile(),
            engine,
            onProgress: progress.add,
          );
          expect(result.rows, 5);
          expect(result.days, 1);
          expect(result.corruptTables, isEmpty);
          expect(progress, [1]);
          expect(engine.inputs, hasLength(1));
          final sub = engine.inputs.single;
          expect(sub.tsSec, [ts, ts + 1, ts + 2]);
          expect(sub.hr, [60, 61, 62]);
          expect(sub.spo2Red, red == null ? [0, 0, 0] : [red, red, red + 2]);
          expect(sub.spo2Ir, ir == null ? [0, 0, 0] : [ir, ir, ir + 2]);
          expect(sub.deviceFamily, isNull);
          expect(engine.dates.single, {'2021-04-06'});
          expect(engine.finalizations, 1);
          expect(await (await LocalDb.instance).query('journal'), saved);
          expect(await (await LocalDb.instance).query('day_result'), isEmpty);
          expect(await source.readAsBytes(), bytes);
          // The read-only connection must have closed before the original can move.
          final retained = await source.rename('${source.path}.retained');
          expect(await retained.readAsBytes(), bytes);
        },
      );
    }
  }
}
