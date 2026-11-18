// Status reads the authored ledger, retains a previous answer on refusal and
// rereads after actual record publication. No installed-phone state is claimed.
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:whoop_protocol/whoop_protocol.dart' as protocol;
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/auto_backup.dart';
import 'package:whoop_companion/state/prefs.dart';
import 'package:whoop_companion/ui2/profile/data.dart';
import 'package:whoop_companion/data/models.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/profile/status.dart';
import 'coverage_ble_durable_boundary_test.dart' show record;
import 'coverage_body_history_actions_test.dart' show flush;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

class _App extends AppState {
  _App() : super.forTesting();
  // Only these native readers are substituted; sync health remains real SQLite.
  @override
  Future<void> refreshSigningStatus() async {}
  @override
  Future<void> refreshBackupPassphraseState() async {
    hasBackupPassphrase = false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('status-health-recovery');
    PackageInfo.setMockInitialValues(
      appName: 'Authored fixture',
      packageName: 'authored.fixture',
      version: '0.0.0',
      buildNumber: '0',
      buildSignature: '',
    );
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  testWidgets(
    'failed health reads retry and new committed band data refreshes the retained ledger',
    (t) async {
      final db = await LocalDb.instance;
      await LocalDb.noteBackgroundWake('bg_refresh');
      await LocalDb.upsertSyncLedgerEntry(
        chunkId: 'capture',
        kind: 'capture',
        status: 'partial',
      );
      await LocalDb.putComputeFreshness(
        'today',
        jsonEncode({
          'activity_computed_at': DateTime.now().millisecondsSinceEpoch - 60000,
        }),
      );
      final app = _App();
      addTearDown(app.dispose);
      await db.execute(
        'ALTER TABLE sync_ledger RENAME TO authored_held_sync_ledger',
      );
      try {
        await localizedPage(t, const StatusScreen(), app: app);
        await flush(t);
        expect(find.text('Sync health could not be read'), findsOneWidget);
        expect(find.text('Your band data is intact.'), findsOneWidget);
      } finally {
        await t.runAsync(
          () => db.execute(
            'ALTER TABLE authored_held_sync_ledger RENAME TO sync_ledger',
          ),
        );
      }
      await reveal(t, find.text('Retry'));
      await t.tap(find.text('Retry'));
      await flush(t);
      var text = (await readPage(t)).join(' ');
      expect(text, isNot(contains('Sync health could not be read')));
      expect(text, contains('iOS background refresh'));
      expect(text, contains('Stopped part way'));
      expect(text, contains('0.0.0 (0)'));
      await t.runAsync(
        () => db.execute(
          'ALTER TABLE sync_ledger RENAME TO authored_held_sync_ledger',
        ),
      );
      try {
        app.bumpInsights();
        await flush(t);
        text = (await readPage(t)).join(' ');
        expect(text, contains('iOS background refresh'));
        expect(text, contains('Stopped part way'));
      } finally {
        await t.runAsync(
          () => db.execute(
            'ALTER TABLE authored_held_sync_ledger RENAME TO sync_ledger',
          ),
        );
      }
      await t.runAsync(() async {
        await LocalDb.noteBackgroundWake('bg_task');
        await LocalDb.upsertSyncLedgerEntry(
          chunkId: 'capture',
          kind: 'capture',
          status: 'complete',
        );
        final seconds = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 60;
        final bytes = record(protocol.BandProfile.gen4);
        ByteData.sublistView(bytes).setUint32(7, seconds, Endian.little);
        await app.engine.onRecord(
          null,
          RawRecord(
            counter: 1,
            packetType: bytes[0],
            hex: bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join(),
            capturedAt: (seconds + 60) * 1000,
            recTs: seconds,
          ),
        );
        expect(
          app.lastRecordAt,
          DateTime.fromMillisecondsSinceEpoch(seconds * 1000),
        );
      });
      await flush(t);
      text = (await readPage(t)).join(' ');
      expect(text, contains('iOS background task'));
      expect(text, contains('Finished'));
      expect(text, isNot(contains('Stopped part way')));
      expect(text, isNot(contains('Nothing synced from the band yet')));
      expect(
        (await t.runAsync(LocalDb.syncHealth))!.transferStatus,
        'complete',
      );
    },
  );
  for (final expired in [false, true]) {
    testWidgets(
      'authored ${expired ? "expired" : "renewal-window"} profile keeps backup history and its settings door',
      (t) async {
        // This exercises the explanation for an authored profile, not native
        // signing or acceptance of a particular installed build.
        final app = _App()
          ..signingExpiry = DateTime.now().add(
            Duration(minutes: (28 * 60 + 30) * (expired ? -1 : 1)),
          );
        addTearDown(app.dispose);
        await Prefs.saveValues({Prefs.backupCadence: BackupCadence.daily.name});
        await LocalDb.upsertSyncLedgerEntry(
          chunkId: 'capture',
          kind: 'capture',
          status: 'partial',
        );
        await localizedPage(t, const StatusScreen(), app: app);
        await flush(t);
        var text = (await readPage(t)).join(' ');
        expect(
          text,
          contains(expired ? 'Signing has expired' : 'Signing ends in 1 d 4 h'),
        );
        expect(text, contains(expired ? 'Expired' : '1 d 4 h'));
        expect(
          text,
          contains('Install over the existing app; do not delete it first.'),
        );
        expect(text, contains('No backup written yet'));
        expect(text, contains('Stopped part way'));
        final saved = DateTime(2021, 4, 6, 12);
        await t.runAsync(() async {
          await Prefs.saveValues({
            Prefs.backupLastRunMs: saved.millisecondsSinceEpoch,
          });
          await LocalDb.upsertSyncLedgerEntry(
            chunkId: 'capture',
            kind: 'capture',
            status: 'idle',
          );
        });
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await flush(t);
        text = (await readPage(t)).join(' ');
        expect(text, contains('Nothing new to send'));
        expect(text, isNot(contains('Stopped part way')));
        expect(text, contains('Last one 2021-04-06'));
        expect(text, contains('Encrypted, kept on this phone only'));
        await reveal(t, find.text('Automatic backup'));
        await t.tap(find.text('Automatic backup'));
        await flush(t);
        expect(find.byType(DataScreen), findsOneWidget);
        expect(app.lastBackupAt, saved);
        expect(app.backupCadence, BackupCadence.daily);
        expect(app.lastBackupError, isNull);
      },
    );
  }
}
