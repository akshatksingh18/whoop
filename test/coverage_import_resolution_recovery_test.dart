// Small authored archives and real SQLite files. Declared-size refusal is
// checked before extraction; no multi-gigabyte buffer or personal capture.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whoop_companion/import/import_container.dart';

void main() {
  late Directory root;
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    root = await Directory(
      'build/coverage-remainder/import-resolution-recovery',
    ).absolute.create(recursive: true);
    root = await root.createTemp('authored-');
  });
  Future<File> file(String name, List<int> bytes) =>
      File(p.join(root.path, name)).writeAsBytes(bytes);
  Future<List<int>> database(
    String name,
    String marker, {
    bool large = false,
  }) async {
    final path = p.join(root.path, name);
    final db = await databaseFactoryFfiNoIsolate.openDatabase(path);
    try {
      await db.execute('CREATE TABLE marker (value TEXT, padding TEXT)');
      await db.insert('marker', {
        'value': marker,
        'padding': large ? 'x' * 12000 : '',
      });
    } finally {
      await db.close();
    }
    return File(path).readAsBytes();
  }

  List<int> zip(Map<String, List<int>> members) {
    final archive = Archive();
    for (final e in members.entries)
      archive.addFile(ArchiveFile(e.key, e.value.length, e.value));
    return ZipEncoder().encode(archive);
  }

  Future<void> unchangedAndReleased(File input, List<int> original) async {
    expect(await input.readAsBytes(), original);
    final moved = await input.rename('${input.path}.retained');
    expect(await moved.readAsBytes(), original);
  }

  for (final name in ['backup.sqlite.gz', 'BACKUP.GZ', '.gz']) {
    test(
      '$name resolves an authored SQLite backup and disposes only its temporary copy',
      () async {
        final originalDb = await database('source.sqlite', 'kept');
        final compressed = gzip.encode(originalDb);
        final source = await file(name, compressed);
        final resolved = await resolveNoopDatabase(source.path);
        expect(resolved, isNotNull);
        final output = resolved!.path;
        expect(output, isNot(source.path));
        expect(await File(output).readAsBytes(), originalDb);
        if (name == '.gz') expect(p.basename(output), 'inflated');
        await resolved.dispose();
        await resolved.dispose();
        expect(await File(output).exists(), false);
        await unchangedAndReleased(source, compressed);
      },
    );
  }
  test(
    'gzip CSV declines the database route and remains readable through CSV resolution',
    () async {
      final body = utf8.encode('date,value\n2021-04-06,authored\n');
      final original = gzip.encode(body);
      final source = await file('export.csv.gz', original);
      expect(await resolveNoopDatabase(source.path), isNull);
      final resolved = await resolveImportCsvPaths([
        source.path,
      ], flavor: 'WHOOP');
      final paths = [...resolved.paths];
      try {
        expect(paths, hasLength(1));
        expect(await File(paths.single).readAsBytes(), body);
      } finally {
        await resolved.dispose();
      }
      expect(paths.every((x) => !File(x).existsSync()), true);
      await unchangedAndReleased(source, original);
    },
  );
  for (final truncated in [false, true]) {
    test(
      'a ${truncated ? 'truncated' : 'CRC-refused'} gzip falls through without losing the source',
      () async {
        final bytes = List<int>.from(
          gzip.encode(utf8.encode('id,value\n1,authored\n')),
        );
        if (truncated) {
          bytes.removeRange(bytes.length - 6, bytes.length);
        } else {
          bytes[bytes.length - 8] ^= 0x20;
        }
        final source = await file('unreadable.csv.gz', bytes);
        expect(await resolveNoopDatabase(source.path), isNull);
        await expectLater(
          resolveImportCsvPaths([source.path], flavor: 'WHOOP'),
          throwsA(isA<ImportFormatException>()),
        );
        await unchangedAndReleased(source, bytes);
      },
    );
  }
  test(
    'largest database member wins while metadata sidecars cannot replace it',
    () async {
      final small = await database('small.db', 'small');
      final large = await database('large.db', 'kept', large: true);
      final original = zip({
        'first/backup.db': small,
        '__MACOSX/metadata.sqlite': [...large, ...large],
        '._metadata.db': [...large, ...large],
        'second/chosen.sqlite3': large,
        'readme.txt': utf8.encode('authored metadata'),
      });
      final source = await file('backup.zip', original);
      final resolved = await resolveNoopDatabase(source.path);
      expect(resolved, isNotNull);
      final output = resolved!.path;
      final db = await databaseFactoryFfiNoIsolate.openDatabase(
        output,
        options: OpenDatabaseOptions(readOnly: true),
      );
      try {
        expect((await db.query('marker')).single['value'], 'kept');
        expect(p.basename(output), 'chosen.sqlite3');
      } finally {
        await db.close();
        await resolved.dispose();
      }
      expect(await File(output).exists(), false);
      await unchangedAndReleased(source, original);
    },
  );
  test(
    'an ordinary ZIP without a database declines without claiming unrelated members',
    () async {
      final original = zip({'readme.txt': utf8.encode('authored text')});
      final source = await file('not-a-backup.zip', original);
      expect(await resolveNoopDatabase(source.path), isNull);
      await unchangedAndReleased(source, original);
    },
  );
  for (final databaseRoute in [false, true]) {
    test(
      'legacy filename bytes preserve payload and release the ${databaseRoute ? 'database' : 'CSV'} reader',
      () async {
        final original = Uint8List.fromList(
          zip({'payload.csv': utf8.encode('id,value\n1,authored\n')}),
        );
        final view = ByteData.sublistView(original);
        var changed = false;
        for (var i = 0; i + 47 <= original.length; i++) {
          if (view.getUint32(i, Endian.little) == 0x02014b50) {
            // The pinned decoder falls back to legacy byte names after invalid UTF-8.
            original[i + 46] = 0xff;
            changed = true;
            break;
          }
        }
        expect(changed, true);
        final source = await file('broken.zip', original);
        if (databaseRoute) {
          expect(await resolveNoopDatabase(source.path), isNull);
        } else {
          final resolved = await resolveImportCsvPaths([
            source.path,
          ], flavor: 'WHOOP');
          final output = resolved.paths.single;
          try {
            expect(await File(output).readAsString(), 'id,value\n1,authored\n');
          } finally {
            await resolved.dispose();
          }
          expect(await File(output).exists(), false);
        }
        await unchangedAndReleased(source, original);
      },
    );
  }
  test(
    'aggregate ZIP size is refused from small headers before any CSV expands',
    () async {
      final bytes = Uint8List.fromList(
        zip({
          'first.csv': utf8.encode('id,value\n1,first\n'),
          'second.csv': utf8.encode('id,value\n2,second\n'),
        }),
      );
      final view = ByteData.sublistView(bytes);
      var patched = 0;
      for (var i = 0; i + 46 <= bytes.length; i++) {
        if (view.getUint32(i, Endian.little) == 0x02014b50) {
          view.setUint32(i + 24, 3 * 1024 * 1024 * 1024, Endian.little);
          patched++;
        }
      }
      expect(patched, 2);
      expect(bytes.length, lessThan(1024));
      final source = await file('declared-size.zip', bytes);
      await expectLater(
        resolveImportCsvPaths([source.path], flavor: 'WHOOP'),
        throwsA(
          isA<ImportFormatException>().having(
            (e) => e.message,
            'size explanation',
            contains('unpacks to more than'),
          ),
        ),
      );
      await unchangedAndReleased(source, bytes);
    },
  );
  test(
    'a destination write refusal preserves the gzip and the existing directory',
    () async {
      final original = gzip.encode(utf8.encode('id,value\n1,authored\n'));
      final source = await file('blocked.csv.gz', original);
      final destination = await Directory(p.join(root.path, 'output')).create();
      final obstruction = await Directory(
        p.join(destination.path, 'blocked.csv'),
      ).create();
      await expectLater(
        inflateGzip(source.path, destination),
        throwsA(
          isA<ImportFormatException>().having(
            (e) => e.message,
            'write explanation',
            contains('as a gzip archive'),
          ),
        ),
      );
      expect(await obstruction.exists(), true);
      await unchangedAndReleased(source, original);
    },
  );
}
