// Refused temporary writes preserve the data that export and import read.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whoop_companion/compute/derivation_engine.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/data/analysis_export.dart';
import 'package:whoop_companion/data/body_log.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/import/import_container.dart';
import 'package:whoop_companion/import/noop_backup_import.dart';

import '../support/coverage_store.dart';

final class RefusedExport extends IOOverrides {
  String? target;
  @override
  File createFile(String path) {
    if (path.contains('whoop_analysis') && path.endsWith('.md')) {
      target = path;
      return RefusedReport(path);
    }
    return super.createFile(path);
  }
}

class RefusedReport implements File {
  RefusedReport(this.path);
  @override
  final String path;
  @override
  Future<File> writeAsString(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) async => throw FileSystemException('Authored report write refusal', path);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class RefusedRepair extends IOOverrides {
  RefusedRepair(this.source);
  final String source;
  String? target;

  @override
  File createFile(String path) {
    final file = super.createFile(path);
    return path == source ? RefusedCopy(this, file) : file;
  }
}

class RefusedCopy implements File {
  RefusedCopy(this.owner, this.file);
  final RefusedRepair owner;
  final File file;
  @override
  Future<bool> exists() => file.exists();
  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) =>
      file.open(mode: mode);
  @override
  Future<File> copy(String newPath) async {
    owner.target = newPath;
    throw FileSystemException('Authored repair copy refusal', newPath);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('temporary-write-refusals', fresh: true));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  test(
    'refused report writing removes its temporary directory and can retry',
    () async {
      final day = todayLabel();
      await BodyLogDb.putWeight(day, 72.5, 'kg', historyOnly: true);
      final db = await LocalDb.instance;
      final readings = await db.query('body_weight_reading');
      final repo = LocalRepositoryImpl(getProfileMap: () => {});
      Future<String> export() => writeAnalysisExport(
        range: AnalysisRange.twoWeeks,
        repo: repo,
        user: const {},
      );

      final refusal = RefusedExport();
      await expectLater(
        IOOverrides.runWithIOOverrides(export, refusal),
        throwsA(
          isA<FileSystemException>().having(
            (e) => e.message,
            'write refusal',
            'Authored report write refusal',
          ),
        ),
      );
      expect(refusal.target, isNotNull);
      expect(await File(refusal.target!).parent.exists(), isFalse);
      expect(await db.query('body_weight_reading'), readings);
      final valid = File(await export());
      expect(await valid.readAsString(), contains('72.50'));
      expect(await db.query('body_weight_reading'), readings);
      await valid.delete();
      await valid.parent.delete();
    },
  );

  test(
    'failed repair copy removes its scratch directory and preserves the input',
    () async {
      final dir = File(LocalDb.dbName).parent;
      final file = File('${dir.path}/authored-noop.sqlite');
      final source = await databaseFactory.openDatabase(file.path);
      try {
        await source.execute('CREATE TABLE hrSample(ts INTEGER, bpm INTEGER)');
      } finally {
        await source.close();
      }
      final bytes = await file.readAsBytes();
      final header = ByteData.sublistView(bytes);
      final stored = header.getUint32(28, Endian.big);
      expect(stored, greaterThan(1));
      header.setUint32(28, stored - 1, Endian.big);
      await file.writeAsBytes(bytes);
      final original = await file.readAsBytes();
      final refusal = RefusedRepair(file.path);
      final engine = DerivationEngine();
      final db = await LocalDb.instance;
      final before = await db.query('decoded_onehz');

      Future<void> restore() =>
          NoopBackupImporter.importDatabase(file.path, const Profile(), engine);
      await expectLater(
        IOOverrides.runWithIOOverrides(restore, refusal),
        throwsA(
          isA<FileSystemException>().having(
            (e) => e.message,
            'copy refusal',
            'Authored repair copy refusal',
          ),
        ),
      );
      expect(refusal.target, isNotNull);
      expect(await File(refusal.target!).parent.exists(), isFalse);
      expect(await file.readAsBytes(), original);
      await expectLater(
        restore(),
        throwsA(
          isA<ImportFormatException>().having(
            (e) => e.toString(),
            'empty repaired backup',
            contains('no samples'),
          ),
        ),
      );
      expect(await file.readAsBytes(), original);
      expect(await db.query('decoded_onehz'), before);
    },
  );
}
