// Small authored files exercise the public CSV resolver, without importing
// personal captures or allocating a large declared-size archive.
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whoop_companion/import/import_container.dart';

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory(
      'build/coverage-remainder/import-container-boundaries',
    ).absolute.create(recursive: true);
    root = await root.createTemp('authored-');
  });
  for (final utf16 in [true, false]) {
    test(
      '${utf16 ? 'UTF-16' : 'binary'} input reports its actual format and preserves the source',
      () async {
        final bytes = utf16 ? [0xff, 0xfe, 65, 0, 10, 0] : [0, 1, 2, 3, 4, 5];
        final file = await File(
          p.join(root.path, 'authored-input.csv'),
        ).writeAsBytes(bytes);
        late ImportFormatException error;
        try {
          await resolveImportCsvPaths([file.path], flavor: 'WHOOP');
          fail('A non-UTF-8 input must not be handed to the CSV parser.');
        } on ImportFormatException catch (e) {
          error = e;
        }
        expect(error.message, contains(utf16 ? 'UTF-16' : 'not a text file'));
        expect(error.message, contains('authored-input.csv'));
        expect(error.toString(), error.message);
        expect(await file.readAsBytes(), bytes);
        // The resolver releases its source handle even after refusing the input.
        final renamed = await file.rename(
          p.join(root.path, 'retained-input.csv'),
        );
        expect(await renamed.readAsBytes(), bytes);
      },
    );
  }

  test(
    'a third colliding basename preserves all CSVs and an existing numbered name',
    () async {
      final members = {
        'first/data.csv': 'id,value\n1,first\n',
        'second/data-2.csv': 'id,value\n2,numbered\n',
        'third/data.csv': 'id,value\n3,third\n',
      };
      final archive = Archive();
      for (final member in members.entries) {
        final bytes = utf8.encode(member.value);
        archive.addFile(ArchiveFile(member.key, bytes.length, bytes));
      }
      final original = ZipEncoder().encode(archive);
      final file = await File(
        p.join(root.path, 'authored-export.zip'),
      ).writeAsBytes(original);
      final result = await resolveImportCsvPaths([file.path], flavor: 'WHOOP');
      final extracted = [...result.paths];
      try {
        expect(extracted.map(p.basename).toSet(), {
          'data.csv',
          'data-2.csv',
          'data-3.csv',
        });
        expect(extracted.toSet(), hasLength(3));
        expect(
          await Future.wait(extracted.map((path) => File(path).readAsString())),
          members.values.toList(),
        );
        expect(await file.readAsBytes(), original);
      } finally {
        await result.dispose();
      }
      expect(extracted.every((path) => !File(path).existsSync()), true);
      expect(await file.readAsBytes(), original);
    },
  );
}
