// A real AppState receives the durable-write callback and later emits quiet.
import 'dart:async';
import 'dart:typed_data' show Endian;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/ble/ble_state.dart' show SyncActivityWindow;
import 'package:whoop_companion/ble/ios_ble_restore.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/models.dart';
import 'package:whoop_companion/notify/notification_service.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/sync/ios_bg_task.dart';
import 'package:whoop_protocol/whoop_protocol.dart' as protocol;

import '../compute/prepare_handoff_test.dart' show raw;
import '../support/coverage_store.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final service = NotificationService.instance;
  const channel = MethodChannel('whoop/ble_restore');
  setUpAll(() => coverageStore('durable-sync-quiet-publication'));
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

  test(
    'two real durable batches extend activity and publish one quiet boundary',
    () async {
      final app = AppState(isIOS: true);
      addTearDown(() async {
        app.dispose();
        await app.engine.disconnect();
      });
      for (
        var i = 0;
        i < 300 && !app.initialized && app.initError == null;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(app.initError, isNull);
      expect(app.initialized, isTrue);
      await app.openSession();
      // Like an ongoing offload, let records become visible while deriving waits.
      app.engine.onOffloadState!(true);
      expect(app.syncingNow, isFalse);

      final first = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 10;
      Future<void> bank(int i) async {
        final ts = first + i;
        final bytes = protocol.hexToBytes(raw(ts, 70 + i));
        ByteData.sublistView(bytes).setUint32(3, i + 1, Endian.little);
        final decoded = protocol.parseR24(bytes)!;
        await app.engine.onCommitBatch!(
          [
            RawRecord(
              counter: i + 1,
              packetType: protocol.PacketType.historicalData,
              hex: bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join(),
              capturedAt: DateTime.now().millisecondsSinceEpoch,
              recTs: ts,
            ),
          ],
          [Sample(tsEpoch: ts, counter: i + 1, hr: decoded.hr)],
          null,
          deviceFamily: 'gen4',
        );
        app.engine.onDataStored!();
        expect(app.syncingNow, isTrue);
        for (var n = 0; n < 150; n++) {
          if (app.lastRecordAt?.millisecondsSinceEpoch == ts * 1000) break;
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        expect(app.lastRecordAt?.millisecondsSinceEpoch, ts * 1000);
      }

      await bank(0);
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await bank(1);
      final quiet = Completer<void>();
      var quietNotices = 0;
      void observe() {
        if (!app.syncingNow) {
          quietNotices++;
          if (!quiet.isCompleted) quiet.complete();
        }
      }

      app.addListener(observe);
      await quiet.future.timeout(
        Duration(milliseconds: SyncActivityWindow().windowMs + 1800),
      );
      app.removeListener(observe);
      expect(quietNotices, 1);
      expect(app.syncingNow, isFalse);
      expect(app.lastRecordAt?.millisecondsSinceEpoch, (first + 1) * 1000);
      final db = await LocalDb.instance;
      final rows = await db.query('decoded_onehz', orderBy: 'rec_ts');
      expect(rows.map((row) => row['rec_ts']), [first, first + 1]);
      expect(await db.query('day_result'), isEmpty);
    },
  );
}
