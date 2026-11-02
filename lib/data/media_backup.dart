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

import 'package:whoop_companion/migration/legacy_names.dart';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'body_photo_file.dart';

const kMediaBackupDbName = '${LegacyNames.databaseFile}';
const kMediaBackupPhotoDir = 'body_photos';

/// Count exactly the filename family the media packer carries, not DB references.
Future<int> mediaBackupPhotoCount(String photoDir) => Isolate.run(() async {
  final dir = Directory(photoDir);
  if (!await dir.exists()) return 0;
  return (await dir.list().toList())
      .whereType<File>()
      .where((f) => isBodyPhotoFileName(p.basename(f.path)))
      .length;
});

/// Zip [dbPath] and every JPEG in [photoDir] into `[dbPath].zip`.
Future<String> packMediaBackup(String dbPath, String photoDir) async =>
    (await packMediaBackupWithCount(dbPath, photoDir)).path;

Future<({String path, int photos})> packMediaBackupWithCount(
  String dbPath,
  String photoDir, {
  List<String> requiredPhotoNames = const [],
}) => Isolate.run(() async {
  await validateMediaPhotoFiles(photoDir, requiredPhotoNames);
  final out = '$dbPath.zip';
  final enc = ZipFileEncoder()..create(out, level: 0);
  var photos = 0;
  try {
    try {
      await enc.addFile(File(dbPath), kMediaBackupDbName);
      final dir = Directory(photoDir);
      if (await dir.exists()) {
        for (final f in dir.listSync().whereType<File>()) {
          final name = p.basename(f.path);
          if (isBodyPhotoFileName(name)) {
            await enc.addFile(f, '$kMediaBackupPhotoDir/$name');
            photos++;
          }
        }
      }
    } finally {
      await enc.close();
    }
  } catch (_) {
    try {
      if (await File(out).exists()) await File(out).delete();
    } catch (_) {}
    rethrow;
  }
  return (path: out, photos: photos);
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
              !isBodyPhotoFileName(parts[1])) {
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

/// Missing or unsupported referenced media must fail explicitly, never become
/// a seemingly complete database-only backup. Also used before restore commit.
Future<void> validateMediaPhotoFiles(
  String photoDir,
  List<String> names,
) async {
  for (final name in names) {
    if (!isBodyPhotoFileName(name) ||
        !await File(p.join(photoDir, name)).exists()) {
      throw const FormatException(
        'A referenced Body photo is missing or has an unsupported name. '
        'The complete photo backup cannot be made or restored.',
      );
    }
  }
}

/// Read the exported/imported snapshot, rather than a racing live-library list.
Future<List<String>> mediaSnapshotPhotoNames(String dbPath) async {
  final db = await openDatabase(dbPath, readOnly: true, singleInstance: false);
  try {
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='body_photo'",
    );
    if (tables.isEmpty) return [];
    return [
      for (final row in await db.query('body_photo', columns: ['id']))
        bodyPhotoFileName(row['id'] as String),
    ];
  } finally {
    await db.close();
  }
}
