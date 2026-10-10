// Media-inclusive encrypted backups (build 86). An exported encrypted backup
// that has progress photos to carry is a ZIP of the database snapshot plus
// `body_photos/<id>.jpg`, sealed as OSBK format version 2. Builds before 86
// refuse version 2 with "written by a newer version" instead of misreading it,
// and every version-1 (database-only) backup still restores here.
//
// The automatic in-app backup stays database-only: it lives in the same app
// container as the photo files and protects against a damaged database, not
// against losing the app. Getting photos off the phone is what the exported
// encrypted backup is for.

import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

const kMediaBackupDbName = 'openstrap.db';
const kMediaBackupPhotoDir = 'body_photos';
final _photoName = RegExp(r'^[0-9A-Za-z-]{8,64}\.jpg$');

/// Zip [dbPath] and every JPEG in [photoDir] into `[dbPath].zip`.
Future<String> packMediaBackup(String dbPath, String photoDir) =>
    Isolate.run(() async {
      final out = '$dbPath.zip';
      final enc = ZipFileEncoder()..create(out, level: 0);
      await enc.addFile(File(dbPath), kMediaBackupDbName);
      final dir = Directory(photoDir);
      if (await dir.exists()) {
        for (final f in dir.listSync().whereType<File>()) {
          final name = p.basename(f.path);
          if (_photoName.hasMatch(name)) {
            await enc.addFile(f, '$kMediaBackupPhotoDir/$name');
          }
        }
      }
      await enc.close();
      return out;
    });

/// Unpack a decrypted version-2 payload: the database to [dbDest], and each
/// photo into [photoDir] unless a file of that name is already there. Only
/// the two expected kinds of entry are read; anything else (a path escaping
/// the folder, an unexpected name) is ignored. Returns photos written.
Future<int> unpackMediaBackup(String zipPath, String dbDest, String photoDir) =>
    Isolate.run(() async {
      final input = InputFileStream(zipPath);
      var photos = 0;
      var db = false;
      try {
        final archive = ZipDecoder().decodeStream(input);
        for (final f in archive.files) {
          if (!f.isFile) continue;
          if (f.name == kMediaBackupDbName) {
            final o = OutputFileStream(dbDest);
            f.writeContent(o);
            await o.close();
            db = true;
            continue;
          }
          final parts = f.name.split('/');
          if (parts.length != 2 ||
              parts[0] != kMediaBackupPhotoDir ||
              !_photoName.hasMatch(parts[1])) {
            continue;
          }
          final dest = File(p.join(photoDir, parts[1]));
          if (await dest.exists()) continue;
          await dest.parent.create(recursive: true);
          final o = OutputFileStream(dest.path);
          f.writeContent(o);
          await o.close();
          photos++;
        }
      } finally {
        await input.close();
      }
      if (!db) throw const FormatException('The backup has no database in it.');
      return photos;
    });
