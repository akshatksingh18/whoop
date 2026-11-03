// Heavy security boundary: the two 2 GiB cases run only on GitHub Actions.
// A named tiny case validates the same streaming authoring path locally.
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/import/import_container.dart';

Future<File> authoredGzip(Directory root, int size) async {
  final file = File('${root.path}/authored-$size.gz');
  final output = file.openWrite();
  final encoder = GZipCodec(
    level: 1,
  ).encoder.startChunkedConversion(output);
  final block = Uint8List(64 * 1024);
  for (var left = size; left > 0;) {
    final count = left < block.length ? left : block.length;
    encoder.add(
      count == block.length ? block : Uint8List.sublistView(block, 0, count),
    );
    left -= count;
  }
  encoder.close();
  await output.done;
  return file;
}

Future<Directory> work() async => (await Directory(
  'build/coverage-remainder/gzip-resource-ceiling',
).absolute.create(recursive: true)).createTemp('authored-');

Future<String> fingerprint(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

void main() {
  test(
    'tiny streaming gzip retains its bytes, trailer and released input',
    () async {
      final root = await work();
      final file = await authoredGzip(root, 17);
      final before = await fingerprint(file);
      final dest = await Directory('${root.path}/output').create();
      final result = await inflateGzip(file.path, dest);
      expect(result, isNotNull);
      expect(await File(result!).readAsBytes(), List.filled(17, 0));
      expect(await fingerprint(file), before);
      final retained = await file.rename('${file.path}.retained');
      expect(await fingerprint(retained), before);
    },
  );

  const limit = 2 * 1024 * 1024 * 1024;
  for (final size in [limit, limit + 1]) {
    test(
      'streamed gzip $size honors the real inclusive 2 GiB ceiling',
      () async {
        // Fail before creating a large fixture if someone accidentally selects
        // this test locally. Full suites are cloud-only; this introduces no skip.
        if (Platform.environment['GITHUB_ACTIONS'] != 'true') {
          throw StateError('Run the 2 GiB gzip cases on GitHub Actions only.');
        }
        final root = await work();
        final file = await authoredGzip(root, size);
        expect(await file.length(), lessThan(16 * 1024 * 1024));
        final before = await fingerprint(file);
        final dest = await Directory('${root.path}/output').create();
        if (size > limit) {
          await expectLater(
            inflateGzip(file.path, dest),
            throwsA(
              isA<ImportFormatException>().having(
                (e) => e.message,
                'ceiling guidance',
                contains('unpacks to more than 2 GB'),
              ),
            ),
          );
          expect(
            await dest.list().toList(),
            isEmpty,
            reason:
                'A refused large restore must not leave a partial inflated copy.',
          );
        } else {
          final result = await inflateGzip(file.path, dest);
          expect(result, isNotNull);
          final inflated = File(result!);
          expect(await inflated.length(), limit);
          expect(inflated.absolute.parent.path, dest.absolute.path);
          // Regenerable authored zeros are not recovery evidence. Release the
          // runner's disk after proving the accepted boundary, with no recursion.
          await inflated.delete();
          expect(await dest.list().toList(), isEmpty);
        }
        expect(await fingerprint(file), before);
        final retained = await file.rename('${file.path}.retained');
        expect(await fingerprint(retained), before);
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  }
}
