// Authored ZIP64 headers declare large members while the actual input stays tiny.
// The real parser/resolver must refuse them without allocating that payload.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whoop_companion/import/import_container.dart';

// Independent PKZIP local/central records, with a ZIP64 uncompressed-size field.
// The stored payload is always the same 16-byte authored SQLite magic.
List<int> zip64Member(String name, int declaredSize) {
  final filename = utf8.encode(name);
  final payload = utf8.encode('SQLite format 3\u0000');
  final extra = ByteData(12)
    ..setUint16(0, 1, Endian.little)
    ..setUint16(2, 8, Endian.little)
    ..setUint64(4, declaredSize, Endian.little);
  final local = ByteData(30)
    ..setUint32(0, 0x04034b50, Endian.little)
    ..setUint16(4, 45, Endian.little)
    ..setUint32(14, getCrc32(payload), Endian.little)
    ..setUint32(18, payload.length, Endian.little)
    ..setUint32(22, 0xffffffff, Endian.little)
    ..setUint16(26, filename.length, Endian.little)
    ..setUint16(28, extra.lengthInBytes, Endian.little);
  final central = ByteData(46)
    ..setUint32(0, 0x02014b50, Endian.little)
    ..setUint16(4, 45, Endian.little)
    ..setUint16(6, 45, Endian.little)
    ..setUint32(16, getCrc32(payload), Endian.little)
    ..setUint32(20, payload.length, Endian.little)
    ..setUint32(24, 0xffffffff, Endian.little)
    ..setUint16(28, filename.length, Endian.little)
    ..setUint16(30, extra.lengthInBytes, Endian.little);
  final localBytes = [
    ...local.buffer.asUint8List(),
    ...filename,
    ...extra.buffer.asUint8List(),
    ...payload,
  ];
  final centralBytes = [
    ...central.buffer.asUint8List(),
    ...filename,
    ...extra.buffer.asUint8List(),
  ];
  final end = ByteData(22)
    ..setUint32(0, 0x06054b50, Endian.little)
    ..setUint16(8, 1, Endian.little)
    ..setUint16(10, 1, Endian.little)
    ..setUint32(12, centralBytes.length, Endian.little)
    ..setUint32(16, localBytes.length, Endian.little);
  return [...localBytes, ...centralBytes, ...end.buffer.asUint8List()];
}

void main() {
  late Directory root;
  setUp(() async {
    root = await (await Directory(
      'build/coverage-remainder/import-resource-contract',
    ).absolute.create(recursive: true)).createTemp('authored-');
  });

  Future<Set<String>> copies() async => {
    await for (final entry in Directory.systemTemp.list())
      if (p.basename(entry.path).startsWith('whoop_noopbak_')) entry.path,
  };

  Future<void> preserved(File source, List<int> original) async {
    expect(await source.readAsBytes(), original);
    final renamed = await source.rename('${source.path}.retained');
    expect(
      await renamed.readAsBytes(),
      original,
      reason: 'The resolver must release the picked archive on refusal.',
    );
  }

  for (final declared in [0x100000001, 0x100000000]) {
    test(
      'ZIP64 database $declared refuses safely at the real 4 GiB boundary',
      () async {
        final bytes = zip64Member('noop-backup.sqlite', declared);
        expect(bytes.length, lessThan(300));
        // Confirm the wire field is honored before exercising the real app path.
        final member = ZipDecoder().decodeBytes(bytes).files.single;
        expect(member.size, declared);
        final source = await File(
          p.join(root.path, 'authored.noopbak'),
        ).writeAsBytes(bytes);
        final before = await copies();
        await expectLater(
          resolveNoopDatabase(source.path),
          throwsA(
            isA<ImportFormatException>().having(
              (e) => e.message,
              'refusal',
              contains(
                declared > 0x100000000
                    ? 'unpacks to 4.0 GB'
                    : 'Unpacking that backup stopped',
              ),
            ),
          ),
        );
        expect(
          await copies(),
          before,
          reason: 'No partial database copy may remain.',
        );
        await preserved(source, bytes);
      },
    );
  }

  for (final database in [true, false]) {
    test(
      'malformed ${database ? 'database' : 'CSV'} archive preserves and releases its input',
      () async {
        final bytes = [0x50, 0x4b, 3, 4, ...List.filled(12, 0)];
        final source = await File(
          p.join(root.path, 'malformed.zip'),
        ).writeAsBytes(bytes);
        final before = await copies();
        // The pinned decoder treats a missing central directory as an empty
        // archive. It must never become a claimed/importable database.
        if (database) {
          expect(await resolveNoopDatabase(source.path), isNull);
        } else {
          await expectLater(
            resolveImportCsvPaths([source.path], flavor: 'WHOOP'),
            throwsA(
              isA<ImportFormatException>().having(
                (e) => e.message,
                'format guidance',
                contains('no CSV files inside'),
              ),
            ),
          );
        }
        expect(await copies(), before);
        await preserved(source, bytes);
      },
    );
  }

  test('5001 tiny entries are refused before extracting any CSV', () async {
    final archive = Archive();
    for (var i = 0; i < 5001; i++) {
      archive.addFile(ArchiveFile('authored-$i.csv', 0, <int>[]));
    }
    final bytes = ZipEncoder().encode(archive);
    expect(bytes.length, lessThan(1024 * 1024));
    final source = await File(
      p.join(root.path, 'many-entries.zip'),
    ).writeAsBytes(bytes);
    await expectLater(
      resolveImportCsvPaths([source.path], flavor: 'WHOOP'),
      throwsA(
        isA<ImportFormatException>().having(
          (e) => e.message,
          'bounded member count',
          contains('holds 5001 entries'),
        ),
      ),
    );
    await preserved(source, bytes);
  });
}
