// A cold-open paired app enters its existing foreground connection path.
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart'
    as os;
import 'package:whoop_companion/ble/ble_engine.dart';
import 'package:whoop_companion/ble/ios_ble_restore.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/notify/notification_service.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/sync/band_ownership.dart';
import 'package:whoop_companion/sync/ios_bg_task.dart';
import 'package:whoop_companion/sync/paired_device.dart';

import '../ble/durable_boundary_test.dart' show until;
import '../ble/gatt_connection_test.dart' show Peripheral;
import '../support/coverage_store.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const restore = MethodChannel('whoop/ble_restore');
  final peripheral = Peripheral();
  final service = NotificationService.instance;
  final seen = <MethodCall>[];
  setUpAll(() async {
    await coverageStore('foreground-pairing-startup', fresh: true);
    os.FlutterBluePlusPlatform.instance = peripheral;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(restore, (
      call,
    ) async {
      seen.add(call);
      return call.method == 'appState' ? 'active' : null;
    });
  });
  setUp(() async {
    await resetCoverageStore();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    peripheral.trace.clear();
    seen.clear();
    BandOwnership.resetForTest();
    BleEngine.resetBandClaimForTest();
    service.debugProbePermission = () async => false;
    service.debugRequestPermission = () async => false;
    service.debugCancel = (_) async {};
    service.invalidatePermissionCache();
  });
  tearDown(() {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    IosBleRestore.onWake = null;
    IosBleRestore.foregroundActive = false;
    IosBgTask.foregroundPull = null;
    service.debugProbePermission = null;
    service.debugRequestPermission = null;
    service.debugCancel = null;
    service.invalidatePermissionCache();
    BandOwnership.resetForTest();
    BleEngine.resetBandClaimForTest();
  });
  tearDownAll(() async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(restore, null);
    await LocalDb.close();
  });

  for (final refused in [false, true]) {
    test(
      'cold foreground pairing retains its saved identity through refusal: $refused',
      () async {
        await PairedDevice.save(Peripheral.id.str, null, generation: 'gen4');
        await CursorStore.write('authored-retained-history', 'keep');
        final db = await LocalDb.instance;
        peripheral.mode = refused ? 'connect-refused' : 'ready';
        final app = AppState(isIOS: true);
        peripheral.engine = app.engine;
        try {
          await until(
            () => app.initialized || app.initError != null,
            attempts: 1000,
          );
          await until(
            () => peripheral.trace.contains('connect') && !app.busy,
            attempts: 1200,
          );
          expect(app.initialized, isTrue, reason: app.initError);
          expect(app.engine.isForegroundActive(), isTrue);
          expect(app.engine.isConnected, !refused);
          expect(
            peripheral.trace.where((item) => item == 'connect'),
            hasLength(1),
          );
          if (refused) {
            peripheral.mode = 'ready';
            await app.openSession();
            expect(app.engine.isConnected, isTrue);
            expect(
              peripheral.trace.where((item) => item == 'connect'),
              hasLength(2),
            );
          }
          expect(seen.where((call) => call.method == 'appState'), hasLength(1));
          expect(
            seen
                .where((call) => call.method == 'arm')
                .map((call) => call.arguments),
            [Peripheral.id.str, if (refused) Peripheral.id.str],
          );
          expect((await PairedDevice.load())?.remoteId, Peripheral.id.str);
          expect(await CursorStore.read('authored-retained-history'), 'keep');
          expect(await db.query('day_result'), isEmpty);
          expect(await db.query('decoded_onehz'), isEmpty);
        } finally {
          app.dispose();
          await app.engine.disconnect();
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      },
    );
  }
}
