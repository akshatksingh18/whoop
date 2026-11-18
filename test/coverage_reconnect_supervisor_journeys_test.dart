// Real one-minute supervisor timer, with only band operations substituted.
// Run these bounded journeys in full Linux CI, never as a long local probe.
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/ble/ble_engine.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/sync/band_ownership.dart';
import 'package:whoop_companion/sync/file_log.dart';
import 'package:whoop_companion/sync/paired_device.dart';
import 'coverage_connection_lifecycle_test.dart' show LifecycleBand;
import 'coverage_ble_durable_boundary_test.dart' show until;
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LifecycleBand band;
  late AppState app;
  setUpAll(() async {
    await coverageStore('reconnect-supervisor');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_timezone'),
          (_) async => 'UTC',
        );
  });
  setUp(() async {
    await resetCoverageStore();
    BandOwnership.resetForTest();
    band = LifecycleBand()..delay = Duration.zero;
    app = AppState.forTesting(engine: band)
      ..paired = PairedDevice(
        'authored-supervised-band',
        null,
        generation: 'gen4',
      );
  });
  tearDown(() async {
    await app.endSession();
    app.dispose();
    BandOwnership.resetForTest();
    await FileLog.write('Authored supervisor test barrier');
  });
  tearDownAll(LocalDb.close);
  int connects() => band.calls.where((s) => s.startsWith('connect:')).length;

  test(
    'the real supervisor retries a failed initial reach without another user action',
    () async {
      var attempts = 0;
      band.connecting = (_) async => ++attempts > 1;
      // Retire through the public action before the unrelated historical derive.
      band.command = (name) async {
        if (name == 'live') await app.endSession();
      };
      await app.openSession();
      expect(connects(), 1);
      expect(app.busy, false);
      await Future<void>.delayed(const Duration(seconds: 61));
      await until(() => band.calls.contains('live'));
      expect(connects(), 2);
      expect(
        app.logLines.any(
          (s) => s.contains('supervisor: disconnected with no loop'),
        ),
        true,
      );
      expect(BandOwnership.foregroundIntent, false);
      expect(app.busy, false);
    },
    timeout: const Timeout(Duration(seconds: 95)),
  );

  test(
    'the real supervisor preserves a healthy connection while its drain is in flight',
    () async {
      final drain = Completer<SyncReport>();
      band.connecting = (_) async => true;
      band.syncing = () => drain.future;
      try {
        await app.openSession();
        await until(() => band.calls.contains('sync'));
        final before = connects();
        await Future<void>.delayed(const Duration(seconds: 61));
        expect(connects(), before);
        expect(band.connected, true);
        expect(
          app.logLines.any((s) => s.contains('supervisor: disconnected')),
          false,
        );
      } finally {
        await app.endSession();
        drain.complete(SyncReport(0, 0, false));
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }
    },
    timeout: const Timeout(Duration(seconds: 95)),
  );

  test(
    'the real supervisor cannot overlap a pending user connection',
    () async {
      final reached = Completer<void>(), connect = Completer<bool>();
      band.connecting = (_) {
        reached.complete();
        return connect.future;
      };
      final opening = app.openSession();
      try {
        await reached.future;
        expect(app.busy, true);
        await Future<void>.delayed(const Duration(seconds: 61));
        expect(connects(), 1);
        expect(app.busy, true);
        expect(
          app.logLines.any((s) => s.contains('supervisor: disconnected')),
          false,
        );
      } finally {
        connect.complete(false);
        await opening;
      }
      expect(app.busy, false);
    },
    timeout: const Timeout(Duration(seconds: 95)),
  );
}
