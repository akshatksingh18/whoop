// The real Body/import callback reads a selected file and preserves its original.
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:whoop_companion/data/photo_encode.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  setUp(() async {
    root = await Directory(
      'build/coverage-remainder/photo-file',
    ).create(recursive: true);
    root = await root.createTemp('authored-');
  });
  for (final portrait in [false, true]) {
    test(
      'file callback strips metadata and caps a ${portrait ? 'portrait' : 'landscape'} without changing source bytes',
      () async {
        final image = img.Image(
          width: portrait ? 2 : 2050,
          height: portrait ? 2050 : 2,
        );
        image.exif.imageIfd['Model'] = img.IfdValueAscii('Authored camera');
        image.exif.gpsIfd['GPSLatitude'] = img.IfdValueRational(0, 1);
        final bytes = img.encodeJpg(image);
        expect(img.decodeJpgExif(bytes)!.gpsIfd.isEmpty, false);
        final source = File('${root.path}/authored.jpg');
        await source.writeAsBytes(bytes);
        final encoded = await encodeProgressPhotoFile(source.path);
        final back = img.decodeJpg(encoded)!;
        expect(back.width, portrait ? 2 : kProgressPhotoMaxSide);
        expect(back.height, portrait ? kProgressPhotoMaxSide : 2);
        final exif = img.decodeJpgExif(encoded);
        expect(
          exif == null || (exif.gpsIfd.isEmpty && exif.imageIfd.isEmpty),
          true,
        );
        expect(await source.readAsBytes(), bytes);
        expect(await root.list().length, 1);
      },
    );
  }
  test(
    'an unreadable selected file is refused without consuming its evidence',
    () async {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final source = File('${root.path}/authored-invalid.bin');
      await source.writeAsBytes(bytes);
      await expectLater(
        encodeProgressPhotoFile(source.path),
        throwsFormatException,
      );
      expect(await source.readAsBytes(), bytes);
      expect(await root.list().length, 1);
    },
  );
  test(
    'a missing selected file reports the read failure without creating a replacement',
    () async {
      final path = '${root.path}/authored-missing.jpg';
      await expectLater(
        encodeProgressPhotoFile(path),
        throwsA(isA<FileSystemException>()),
      );
      expect(await File(path).exists(), false);
      expect(await root.list().length, 0);
    },
  );
}
