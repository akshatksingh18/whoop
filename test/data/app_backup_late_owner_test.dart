// Actual automatic-backup queue and AppState lifetime;no export or encryption.
import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:path_provider/path_provider.dart';
import 'package:whoop_companion/data/auto_backup.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/state/prefs.dart';
import 'export_handoff_test.dart' show Keychain;
import '../support/coverage_store.dart';

class _HeldKeychain extends Keychain {
  final started = Completer<void>();
  final reply = Completer<String?>();
  int reads = 0;
  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) {
    reads++;
    if (!started.isCompleted) started.complete();
    return reply.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FlutterSecureStoragePlatform original;
  late _HeldKeychain keys;
  setUpAll(() => coverageStore('app-backup-late-owner', fresh: true));
  setUp(() async {
    await resetCoverageStore();
    original = FlutterSecureStoragePlatform.instance;
    keys = _HeldKeychain();
    FlutterSecureStoragePlatform.instance = keys;
    await Prefs.saveValues({
      Prefs.backupCadence: 'daily',
      'authored-unrelated-setting': 'keep',
    });
    await CursorStore.write('authored-retained-cursor', 'keep');
  });
  tearDown(() => FlutterSecureStoragePlatform.instance = original);
  tearDownAll(LocalDb.close);
  for (final disposed in [false, true]) {
    test(
      'automatic backup late missing-key reply disposed=$disposed finishes without losing evidence or queue ownership',
      () async {
        final app = AppState.forTesting();
        var notifications = 0;
        app.addListener(() => notifications++);
        var retired = false;
        addTearDown(() {
          if (!retired) app.dispose();
        });
        final work = app.runBackupIfDue();
        await keys.started.future;
        expect(keys.reads, 1);
        if (disposed) {
          app.dispose();
          retired = true;
        }
        keys.reply.complete(null);
        await expectLater(work, completes);
        expect(app.lastBackupError, kBackupNeedsPassphrase);
        expect(app.lastBackupAt, isNull);
        expect(notifications, disposed ? 0 : 1);
        expect(app.logLines.any((s) => s.contains('Backup failed:')), true);
        expect(
          app.logLines.any((s) => s.contains('used after being disposed')),
          false,
        );
        expect(await CursorStore.read('authored-retained-cursor'), 'keep');
        expect(Prefs.getString('authored-unrelated-setting', ''), 'keep');
        expect(Prefs.getString(Prefs.backupCadence, ''), 'daily');
        final documents = await getApplicationDocumentsDirectory();
        expect(
          await Directory('${documents.path}/$kBackupDirName').exists(),
          false,
        );
        final next = AppState.forTesting();
        addTearDown(next.dispose);
        await expectLater(next.runBackupIfDue(), completes);
        expect(keys.reads, 2);
        expect(next.lastBackupError, kBackupNeedsPassphrase);
        expect(next.lastBackupAt, isNull);
        expect(
          next.logLines.any((s) => s.contains('used after being disposed')),
          false,
        );
        expect(await CursorStore.read('authored-retained-cursor'), 'keep');
      },
    );
  }
}
