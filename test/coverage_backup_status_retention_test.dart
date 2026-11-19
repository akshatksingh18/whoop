// Real AppState and backup queue, stopping at a missing passphrase before any
// snapshot or encryption. Preference refusal must not erase the actual failure.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:path_provider/path_provider.dart';
import 'package:whoop_companion/data/auto_backup.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/state/prefs.dart';
import 'coverage_data_export_handoff_test.dart' show Keychain;
import 'coverage_settings_controls_test.dart' show Store;
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferencesStorePlatform oldStore;
  late FlutterSecureStoragePlatform oldKeys;
  late Store store;
  setUpAll(() => coverageStore('backup-status-retention'));
  setUp(() async {
    await resetCoverageStore();
    oldStore = SharedPreferencesStorePlatform.instance;
    oldKeys = FlutterSecureStoragePlatform.instance;
    store = Store();
    SharedPreferencesStorePlatform.instance = store;
    FlutterSecureStoragePlatform.instance = Keychain();
    SharedPreferences.resetStatic();
    await Prefs.ensureLoaded();
    await Prefs.saveValues({'authored-unrelated-setting': 'keep'});
  });
  tearDown(() async {
    SharedPreferencesStorePlatform.instance = oldStore;
    FlutterSecureStoragePlatform.instance = oldKeys;
    SharedPreferences.resetStatic();
    await Prefs.ensureLoaded();
  });
  tearDownAll(LocalDb.close);
  Future<void> noBackupWritten() async {
    final documents = await getApplicationDocumentsDirectory();
    expect(
      await Directory('${documents.path}/$kBackupDirName').exists(),
      false,
    );
    expect(Prefs.getString('authored-unrelated-setting', ''), 'keep');
  }

  test(
    'a refused failure-status write preserves the missing-key outcome and retries bookkeeping',
    () async {
      final app = AppState.forTesting();
      addTearDown(app.dispose);
      store.refuse = 'flutter.${Prefs.backupLastError}';
      final refused = await app.runBackupNow();
      expect(refused.succeeded, false);
      expect(refused.needsPassphrase, true);
      expect(refused.error, kBackupNeedsPassphrase);
      expect(refused.warning, contains('backup status could not be saved'));
      expect(app.lastBackupWarning, refused.warning);
      expect(app.lastBackupError, isNull);
      expect(app.lastBackupAt, isNull);
      await noBackupWritten();
      store.refuse = null;
      final retried = await app.runBackupNow();
      expect(retried.needsPassphrase, true);
      expect(retried.warning, isNull);
      expect(app.lastBackupWarning, isNull);
      expect(app.lastBackupError, kBackupNeedsPassphrase);
      expect(app.lastBackupAt, isNull);
      await noBackupWritten();
    },
  );
  test(
    'refused cadence changes retain Off, then an acknowledged choice reports the missing key honestly',
    () async {
      final app = AppState.forTesting();
      addTearDown(app.dispose);
      store.refuse = 'flutter.${Prefs.backupCadence}';
      await expectLater(
        app.setBackupCadence(BackupCadence.daily),
        throwsStateError,
      );
      expect(app.backupCadence, BackupCadence.off);
      expect(app.lastBackupError, isNull);
      await noBackupWritten();
      store.refuse = null;
      final result = (await app.setBackupCadence(BackupCadence.daily))!;
      expect(app.backupCadence, BackupCadence.daily);
      expect(result.succeeded, false);
      expect(result.needsPassphrase, true);
      expect(app.lastBackupError, kBackupNeedsPassphrase);
      await noBackupWritten();
      expect(await app.setBackupCadence(BackupCadence.off), isNull);
      expect(app.backupCadence, BackupCadence.off);
      expect(app.lastBackupError, kBackupNeedsPassphrase);
      await noBackupWritten();
    },
  );
}
