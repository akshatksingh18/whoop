// Progress photos keep no metadata and are never larger than 2048 px.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:openstrap_edge/data/photo_encode.dart';

void main() {
  test('location and other EXIF are gone; the long side is capped', () {
    final src = img.Image(width: 3000, height: 1500);
    src.exif.gpsIfd['GPSLatitude'] = img.IfdValueRational(52, 1);
    src.exif.imageIfd['Model'] = img.IfdValueAscii('Phone');
    final jpeg = img.encodeJpg(src);
    expect(img.decodeJpgExif(jpeg)!.gpsIfd.isEmpty, isFalse,
        reason: 'the fixture really carries a location');
    final out = encodeProgressPhotoSync(Uint8List.fromList(jpeg));
    final back = img.decodeJpg(out)!;
    expect(back.width, kProgressPhotoMaxSide);
    expect(back.height, 1024);
    final exif = img.decodeJpgExif(out);
    expect(exif == null || (exif.gpsIfd.isEmpty && exif.imageIfd.isEmpty), isTrue);
  });

  test('a file that is not an image is refused', () {
    expect(
      () => encodeProgressPhotoSync(Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    );
  });
}
