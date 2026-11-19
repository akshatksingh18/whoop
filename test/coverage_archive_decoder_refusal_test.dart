// A well-framed ZIP with an invalid UTF-8 Unix link target reaches the actual
// decoder error, unlike a magic-only blob that simply decodes to an empty ZIP.
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/import/import_container.dart';

Uint8List brokenLinkArchive() {
  final archive = Archive()
    ..addFile(ArchiveFile('authored-link.csv', 1, [0xff]));
  final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
  var central = -1;
  for (var i = 0; i + 46 <= bytes.length; i++) {
    if (bytes[i] == 0x50 &&
        bytes[i + 1] == 0x4b &&
        bytes[i + 2] == 1 &&
        bytes[i + 3] == 2) {
      central = i;
      break;
    }
  }
  expect(central, greaterThanOrEqualTo(0));
  // ZIP central header: Unix creator,then symlink type in external attributes.
  bytes[central + 5] = 3;
  ByteData.sublistView(
    bytes,
  ).setUint32(central + 38, 0xa1ff0000, Endian.little);
  return bytes;
}

void main() {
  for (final database in [false, true]) {
    for (final extension in ['zip', 'noopbak']) {
      test('${database ? 'database' : 'CSV'} resolver names a malformed '
          '$extension decoder error and releases its exact source', () async {
        final root = await (await Directory(
          'build/coverage-remainder/archive-decoder-refusal',
        ).absolute.create(recursive: true)).createTemp('authored-');
        final bytes = brokenLinkArchive();
        expect(() => ZipDecoder().decodeBytes(bytes), throwsFormatException);
        final source = await File(
          '${root.path}/authored.$extension',
        ).writeAsBytes(bytes);
        final retained = await File(
          '${root.path}/retained.csv',
        ).writeAsString('id,value\n1,kept\n');
        final retainedBytes = await retained.readAsBytes();
        late ImportFormatException error;
        try {
          if (database) {
            await resolveNoopDatabase(source.path);
          } else {
            await resolveImportCsvPaths([
              retained.path,
              source.path,
            ], flavor: 'WHOOP');
          }
          fail(
            'The actual decoder failure must not become a successful empty import',
          );
        } on ImportFormatException catch (e) {
          error = e;
        }
        expect(error.message, contains('Could not read'));
        expect(error.message, contains('authored.$extension'));
        expect(error.message, contains('as an archive'));
        expect(error.toString(), error.message);
        expect(await retained.readAsBytes(), retainedBytes);
        expect(await source.readAsBytes(), bytes);
        final renamed = await source.rename('${source.path}.retained');
        expect(
          await renamed.readAsBytes(),
          bytes,
          reason: 'Both decoder-refusal paths must close the real file handle',
        );
      });
    }
  }
}
