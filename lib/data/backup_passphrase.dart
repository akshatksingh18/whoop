// The automatic backup's passphrase, kept in the platform keychain/keystore.
//
// Automatic backups are encrypted (`auto_backup.dart`), and a scheduled job
// cannot ask anyone for a passphrase — so the one the user chose is stored
// here, never in preferences, a file or a log. The same passphrase is what a
// restore on another phone asks for; the keychain copy is a convenience for
// the schedule, NOT a recovery mechanism, and the user still has to keep it
// somewhere of their own.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class BackupPassphrase {
  BackupPassphrase._();

  static const _key = 'backup.auto_passphrase.v1';

  /// Readable from the first unlock after boot, like the coach key: a backup
  /// only runs in the foreground, but a keychain item that turns unreadable the
  /// moment the screen locks would fail a long-running backup halfway.
  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  /// The stored passphrase, or null when none is set OR the keychain could not
  /// be read. Callers treat both as "cannot back up now" and say so; neither is
  /// a reason to write anything unencrypted.
  static Future<String?> read() async {
    try {
      final v = await _storage.read(key: _key);
      return (v == null || v.isEmpty) ? null : v;
    } catch (_) {
      return null;
    }
  }

  /// Store [passphrase]. Returns false when the keychain refused it, so the
  /// caller can tell the user the setting did not stick.
  static Future<bool> write(String passphrase) async {
    try {
      await _storage.write(key: _key, value: passphrase);
      return await read() == passphrase;
    } catch (_) {
      return false;
    }
  }

  static Future<void> clear() async {
    try {
      await _storage.delete(key: _key);
    } catch (_) {}
  }
}
