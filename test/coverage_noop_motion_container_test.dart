// Authored small databases/archives through the real importer. Derivation is
// captured at its existing handoff; no sensor validity or physical damage claim.
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/import/import_container.dart';
import 'package:whoop_companion/import/noop_backup_import.dart';
import 'package:whoop_companion/import/noop_import.dart';

import 'coverage_noop_container_contract_test.dart' show CaptureEngine;
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  const profile = Profile(ageYears: 30, sex: 'f', weightKg: 70, heightCm: 170);
  setUpAll(() => coverageStore('noop-motion-container'));
  setUp(() async {
    await resetCoverageStore();
    root = await Directory(
      'build/coverage-remainder/noop-motion-container',
    ).absolute.create(recursive: true);
    root = await root.createTemp('authored-');
  });
  tearDown(() => kNoopBackupPageRows = 20000);
  tearDownAll(LocalDb.close);

  for (final hr in [false, true]) {
    for (final oneRowPages in [false, true]) {
      test(
        'NOOP gravity survives real ${oneRowPages ? 'single-row' : 'ordinary'} pages; HR=$hr',
        () async {
          final source = File('${root.path}/authored.sqlite');
          final db = await databaseFactory.openDatabase(source.path);
          await db.execute(
            'CREATE TABLE gravitySample(deviceId TEXT,ts INTEGER,x REAL,y REAL,z REAL,PRIMARY KEY(deviceId,ts))',
          );
          final ts = localDayStartSec('2021-04-06')! + 43200;
          for (final pair in [(ts, .1, .2, .9), (ts + 2, .3, .4, .8)]) {
            await db.insert('gravitySample', {
              'deviceId': 'authored-motion',
              'ts': pair.$1,
              'x': pair.$2,
              'y': pair.$3,
              'z': pair.$4,
            });
          }
          await db.execute(
            'CREATE TABLE hrSample(deviceId TEXT,ts INTEGER,bpm INTEGER,PRIMARY KEY(deviceId,ts))',
          );
          if (hr) {
            for (var i = 0; i < 3; i++) {
              await db.insert('hrSample', {
                'deviceId': 'authored-other-source',
                'ts': ts + i,
                'bpm': 60 + i,
              });
            }
          }
          await db.close();
          final bytes = await source.readAsBytes();
          await LocalDb.putJournal(
            '2021-04-06',
            '["authored"]',
            'Unrelated saved note',
          );
          final saved = await (await LocalDb.instance).query('journal');
          kNoopBackupPageRows = oneRowPages ? 1 : 20000;
          final engine = CaptureEngine();
          final result = await NoopBackupImporter.importDatabase(
            source.path,
            profile,
            engine,
          );
          expect(result.days, 1);
          expect(result.rows, hr ? 5 : 2);
          expect(result.corruptTables, isEmpty);
          expect(engine.inputs, hasLength(1));
          final sub = engine.inputs.single;
          expect(engine.dates.single, {'2021-04-06'});
          expect(sub.tsSec, hr ? [ts, ts + 1, ts + 2] : [ts, ts + 2]);
          expect(sub.hr, hr ? [60, 61, 62] : [0, 0]);
          expect(sub.ax, hr ? [.1, .1, .3] : [.1, .3]);
          expect(sub.ay, hr ? [.2, .2, .4] : [.2, .4]);
          expect(sub.az, hr ? [.9, .9, .8] : [.9, .8]);
          expect(sub.rrMs, isEmpty);
          expect(engine.finalizations, 1);
          expect(await (await LocalDb.instance).query('day_result'), isEmpty);
          expect(await (await LocalDb.instance).query('journal'), saved);
          expect(await source.readAsBytes(), bytes);
          final moved = await source.rename('${source.path}.retained');
          expect(
            await moved.readAsBytes(),
            bytes,
            reason: 'all source handles must close',
          );
        },
      );
    }
  }

  for (final truncate in [true, false]) {
    test(
      'NOOP rejects a recognized but ${truncate ? 'truncated' : 'damaged'} ZIP without importing or holding its source',
      () async {
        final archive = Archive();
        archive.addFile(ArchiveFile('authored.csv', 8, 'a,b\n1,2\n'.codeUnits));
        final original = ZipEncoder().encode(archive);
        final bytes = truncate ? original.sublist(0, 12) : [...original];
        if (!truncate) {
          for (var i = bytes.length - 6; i < bytes.length - 2; i++) {
            bytes[i] = 0xff;
          }
        }
        final source = await File(
          '${root.path}/authored.zip',
        ).writeAsBytes(bytes);
        expect(await sniffFile(source.path), ImportContainer.zip);
        final saved = await (await LocalDb.instance).query('day_result');
        final engine = CaptureEngine();
        await expectLater(
          NoopImporter.importFile(source.path, profile, engine),
          throwsA(
            isA<ImportFormatException>().having(
              (e) => e.message,
              'current archive explanation',
              contains('archive with no CSV files'),
            ),
          ),
        );
        expect(engine.inputs, isEmpty);
        expect(engine.finalizations, 0);
        expect(await (await LocalDb.instance).query('day_result'), saved);
        expect(await source.readAsBytes(), bytes);
        final moved = await source.rename('${source.path}.retained');
        expect(await moved.readAsBytes(), bytes);
      },
    );
  }
}
