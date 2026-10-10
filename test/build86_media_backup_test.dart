// Encrypted backups carry progress photos from build 86 (format 2) while
// database-only backups (format 1) still restore, and unpacking never writes
// outside the photo folder or over a photo already there.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/media_backup.dart';
import 'package:openstrap_edge/import/backup_crypto.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('mediabk'));
  tearDown(() async => tmp.delete(recursive: true));

  test('database and photos round-trip through an encrypted format-2 file', () async {
    final db = File(p.join(tmp.path, 'snap.db'))..writeAsStringSync('SQLITE');
    final photos = Directory(p.join(tmp.path, 'photos'))..createSync();
    File(p.join(photos.path, 'A1B2C3D4-0000-4000-8000-000000000001.jpg'))
        .writeAsBytesSync([1, 2, 3]);
    File(p.join(photos.path, 'notes.txt')).writeAsStringSync('ignored');
    final zip = await packMediaBackup(db.path, photos.path);
    final sealed = File(p.join(tmp.path, 'b.osbk'));
    await encryptBackupFile(File(zip), sealed, 'pass phrase', iterations: 1000,
        version: kBackupFormatVersionMedia);
    final payload = File(p.join(tmp.path, 'out.payload'));
    expect(await decryptBackupFile(sealed, payload, 'pass phrase'), kBackupFormatVersionMedia);

    final restoredPhotos = Directory(p.join(tmp.path, 'restored'))..createSync();
    // A photo already on the phone is kept, not replaced.
    File(p.join(restoredPhotos.path, 'A1B2C3D4-0000-4000-8000-000000000001.jpg'))
        .writeAsBytesSync([9]);
    final dbOut = p.join(tmp.path, 'restored.db');
    final n = await unpackMediaBackup(payload.path, dbOut, restoredPhotos.path);
    expect(File(dbOut).readAsStringSync(), 'SQLITE');
    expect(n, 0);
    expect(File(p.join(restoredPhotos.path, 'A1B2C3D4-0000-4000-8000-000000000001.jpg')).readAsBytesSync(), [9]);
    expect(File(p.join(restoredPhotos.path, 'notes.txt')).existsSync(), isFalse);
  });

  test('a database-only backup is still format 1', () async {
    final db = File(p.join(tmp.path, 'snap.db'))..writeAsStringSync('SQLITE');
    final sealed = File(p.join(tmp.path, 'b.osbk'));
    await encryptBackupFile(db, sealed, 'pw', iterations: 1000);
    final out = File(p.join(tmp.path, 'o.db'));
    expect(await decryptBackupFile(sealed, out, 'pw'), kBackupFormatVersion);
    expect(out.readAsStringSync(), 'SQLITE');
  });
}
