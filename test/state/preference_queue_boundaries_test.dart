// Retain accepted preferences and release the queue after a late refusal.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/state/prefs.dart';

import '../support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('preference-queue-boundaries'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  for (final invalid in <Object>[
    <int>[1],
    <String, int>{'value': 1},
  ]) {
    test(
      'rolls back prior updates before the next queued write: ${invalid.runtimeType}',
      () async {
        await Prefs.saveValues({'authored-count': 7, 'authored-note': 'keep'});
        final refused = expectLater(
          Prefs.saveValues({
            'authored-count': 8,
            'authored-note': null,
            'authored-invalid': invalid,
          }),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'preference error',
              'Unsupported preference',
            ),
          ),
        );
        final next = Prefs.saveValues({'authored-new-setting': true});
        await refused;
        await next;

        final saved = await SharedPreferences.getInstance();
        await saved.reload();
        expect(saved.getInt('authored-count'), 7);
        expect(saved.getString('authored-note'), 'keep');
        expect(saved.containsKey('authored-invalid'), isFalse);
        expect(saved.getBool('authored-new-setting'), isTrue);
      },
    );
  }

  for (final cadence in ['daily', 'weekly']) {
    test(
      'automatic $cadence backup defers a malformed timestamp and retries the repaired schedule',
      () async {
        final app = AppState.forTesting();
        addTearDown(app.dispose);
        await Prefs.saveValues({
          Prefs.backupCadence: cadence,
          Prefs.backupLastRunMs: 'authored malformed timestamp',
          Prefs.backupLastError: 'Authored retained status',
        });
        await LocalDb.setCursor('authored-backup-owner', 'keep');

        await app.runBackupIfDue();
        expect(
          app.logLines.where((line) => line.contains('Backup failed:')),
          hasLength(1),
        );
        expect(app.lastBackupError, 'Authored retained status');
        expect(await LocalDb.getCursor('authored-backup-owner'), 'keep');

        // An accepted recent backup timestamp should skip the next run.
        final stamp = DateTime.now().millisecondsSinceEpoch;
        await Prefs.saveValues({Prefs.backupLastRunMs: stamp});
        await app.runBackupIfDue();
        expect(app.lastBackupAt?.millisecondsSinceEpoch, stamp);
        expect(app.lastBackupError, 'Authored retained status');
        expect(
          app.logLines.where((line) => line.contains('Backup failed:')),
          hasLength(1),
        );
        expect(await LocalDb.getCursor('authored-backup-owner'), 'keep');
      },
    );
  }
}
