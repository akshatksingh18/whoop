// Real constructor and atomic store;deliver its existing post-commit callback.
// This is the AppState callback boundary,not a radio/debouncer/OS-delivery claim.
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_protocol/whoop_protocol.dart' as p;
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/models.dart';
import 'package:whoop_companion/notify/notification_service.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/sync/ios_bg_task.dart';
import 'package:whoop_companion/ble/ios_ble_restore.dart';
import '../compute/prepare_handoff_test.dart' show raw;
import '../support/coverage_store.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final service = NotificationService.instance;
  const channel = MethodChannel('whoop/ble_restore');
  setUpAll(() => coverageStore('recorded-publication-handoff'));
  setUp(() async {
    await resetCoverageStore();
    service.debugProbePermission = () async => false;
    service.debugRequestPermission = () async => false;
    service.debugCancel = (_) async {};
    service.invalidatePermissionCache();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'appState' ? 'background' : null,
    );
  });
  tearDown(() {
    service.debugProbePermission = null;
    service.debugRequestPermission = null;
    service.debugCancel = null;
    service.invalidatePermissionCache();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    IosBgTask.foregroundPull = null;
    IosBleRestore.onWake = null;
    IosBleRestore.foregroundActive = false;
  });
  tearDownAll(LocalDb.close);
  for (final beginBackground in [false, true]) {
    test(
      'durable callbacks from background=$beginBackground retain newest data without duplicate revisions',
      () async {
        final app = AppState(isIOS: true);
        var disposed = false;
        try {
          for (
            var i = 0;
            i < 300 && !app.initialized && app.initError == null;
            i++
          ) {
            await Future<void>.delayed(const Duration(milliseconds: 5));
          }
          expect(app.initError, isNull);
          expect(app.initialized, true);
          if (!beginBackground) await app.openSession();
          final before = app.insightsRevision.value;
          final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 10;
          Future<void> bank(int i) async {
            final bytes = p.hexToBytes(raw(ts + i, 70 + i));
            ByteData.sublistView(bytes).setUint32(3, i + 1, Endian.little);
            final decoded = p.parseR24(bytes)!;
            await app.engine.onCommitBatch!(
              [
                RawRecord(
                  counter: decoded.counter,
                  packetType: 47,
                  hex: bytes
                      .map((b) => b.toRadixString(16).padLeft(2, '0'))
                      .join(),
                  capturedAt: (ts + i) * 1000,
                  recTs: ts + i,
                ),
              ],
              [
                Sample(
                  tsEpoch: decoded.tsEpoch,
                  counter: decoded.counter,
                  hr: decoded.hr,
                  ax: decoded.accelG[0],
                  ay: decoded.accelG[1],
                  az: decoded.accelG[2],
                ),
              ],
              null,
              deviceFamily: 'gen4',
            );
            app.engine.onDataStored!();
            for (var n = 0; n < 100; n++) {
              if (app.lastRecordAt?.millisecondsSinceEpoch == (ts + i) * 1000 &&
                  (await ComputeJobStore.jobs()).isNotEmpty) {
                break;
              }
              await Future<void>.delayed(const Duration(milliseconds: 2));
            }
            expect(app.lastRecordAt?.millisecondsSinceEpoch, (ts + i) * 1000);
          }

          await bank(0);
          expect(
            app.insightsRevision.value,
            before + (beginBackground ? 0 : 1),
          );
          if (beginBackground) await app.openSession();
          await bank(1);
          expect(app.insightsRevision.value, before + 1);
          await bank(2);
          expect(app.insightsRevision.value, before + 1);
          await app.pauseForBackground();
          await bank(3);
          expect(app.insightsRevision.value, before + 1);
          final db = await LocalDb.instance;
          final rows = await db.query('decoded_onehz', orderBy: 'rec_ts');
          expect(rows.map((r) => r['rec_ts']), [
            for (var i = 0; i < 4; i++) ts + i,
          ]);
          expect(rows.map((r) => r['hr']), [70, 71, 72, 73]);
          final jobs = await ComputeJobStore.jobs();
          expect(jobs, hasLength(1));
          expect(jobs.single['state'], 'queued');
          expect(app.deriving, false);
          expect(await db.query('day_result'), isEmpty);
          app.dispose();
          disposed = true;
          expect(await ComputeJobStore.jobs(), jobs);
          expect(await db.query('decoded_onehz', orderBy: 'rec_ts'), rows);
        } finally {
          if (!disposed) app.dispose();
          await app.engine.disconnect();
        }
      },
    );
  }
}
