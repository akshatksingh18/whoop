// Progress-photo re-encoding (build 86): every photo kept by Body is decoded,
// turned upright, scaled to at most 2048 px on its long side and written as a
// fresh JPEG with no metadata — no location, no camera details — on a worker
// isolate. The same treatment AkshatOS Body gives its photos.

import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

const int kProgressPhotoMaxSide = 2048;

/// [bytes] re-encoded for storage; throws FormatException when they are not
/// an image this app can read.
Future<Uint8List> encodeProgressPhoto(Uint8List bytes) =>
    Isolate.run(() => encodeProgressPhotoSync(bytes));

Future<Uint8List> encodeProgressPhotoFile(String path) async =>
    encodeProgressPhoto(await File(path).readAsBytes());

Uint8List encodeProgressPhotoSync(Uint8List bytes) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    decoded = null; // a truncated or foreign file can throw inside a decoder
  }
  if (decoded == null) throw const FormatException('Not a readable image.');
  var out = img.bakeOrientation(decoded);
  final long = out.width > out.height ? out.width : out.height;
  if (long > kProgressPhotoMaxSide) {
    out = out.width >= out.height
        ? img.copyResize(out, width: kProgressPhotoMaxSide)
        : img.copyResize(out, height: kProgressPhotoMaxSide);
  }
  // Nothing of the original's metadata survives: orientation is baked into
  // the pixels above, and the EXIF block (location included) is emptied.
  out.exif = img.ExifData();
  return img.encodeJpg(out, quality: 85);
}
