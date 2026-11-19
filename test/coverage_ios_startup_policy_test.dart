// Actual empty-store startup and background cold-connect through authored FBP.
// Dart owner/command contracts only; native delivery remains a phone gate.
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
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
import 'coverage_gatt_connection_test.dart' show Peripheral;
import 'support/coverage_store.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final peripheral = Peripheral();
  final native = <MethodCall>[];
  final service = NotificationService.instance;
  const channel = MethodChannel('whoop/ble_restore');
  String? state;
  var refuseState = false;
  setUpAll(() async {
    await coverageStore('ios-startup-policy', fresh: true);
    os.FlutterBluePlusPlatform.instance = peripheral;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (c) async {
      native.add(c);
      if (c.method == 'appState') {
        if (refuseState) {
          throw PlatformException(code: 'authored-state-refusal');
        }
        return state;
      }
      return null;
    });
  });
  setUp(() async {
    await resetCoverageStore();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    native.clear();
    state = null;
    refuseState = false;
    peripheral.mode = 'ready';
    peripheral.trace.clear();
    BandOwnership.resetForTest();
    BleEngine.resetBandClaimForTest();
    IosBleRestore.foregroundActive = false;
    service.debugProbePermission = () async => false;
    service.debugRequestPermission = () async => false;
    service.debugCancel = (_) async {};
    service.invalidatePermissionCache();
  });
  tearDown(() async {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    service.debugProbePermission = null;
    service.debugRequestPermission = null;
    service.debugCancel = null;
    service.invalidatePermissionCache();
    IosBleRestore.onWake = null;
    IosBleRestore.foregroundActive = false;
    IosBgTask.foregroundPull = null;
    BandOwnership.resetForTest();
    BleEngine.resetBandClaimForTest();
  });
  tearDownAll(() async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    await LocalDb.close();
  });
  Future<void> settled(bool Function() ready) async {
    for (var i = 0; i < 1000 && !ready(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(ready(), true, reason: 'Authored startup must settle');
  }

  for (final result in ['background', 'active', 'absent', 'refused']) {
    test(
      'real unpaired iOS startup with $result reply preserves empty measurements',
      () async {
        state = result == 'active' || result == 'background' ? result : null;
        refuseState = result == 'refused';
        final app = AppState(isIOS: true);
        peripheral.engine = app.engine;
        try {
          await settled(() => app.initialized || app.initError != null);
          expect(app.initialized, true, reason: app.initError);
          expect(app.initError, isNull);
          expect(app.isPaired, false);
          expect(app.engine.isForegroundActive(), result != 'background');
          expect(native.where((c) => c.method == 'appState'), hasLength(1));
          expect(peripheral.trace.where((s) => s == 'connect'), isEmpty);
          expect(await (await LocalDb.instance).query('day_result'), isEmpty);
          expect(
            await (await LocalDb.instance).query('decoded_onehz'),
            isEmpty,
          );
        } finally {
          app.dispose();
          await app.engine.disconnect();
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      },
    );
  }
  for (final refused in [false, true]) {
    test(
      'real paired iOS background cold-start connected=${!refused} keeps one owner and no calculations',
      () async {
        state = 'background';
        peripheral.mode = refused ? 'connect-refused' : 'ready';
        await PairedDevice.save(Peripheral.id.str, null, generation: 'gen4');
        final paired = await PairedDevice.load();
        final app = AppState(isIOS: true);
        peripheral.engine = app.engine;
        try {
          await settled(() => app.initialized || app.initError != null);
          await settled(
            () => refused
                ? native.any((c) => c.method == 'armRecoveryNow')
                : app.engine.liveEnabled,
          );
          expect(app.initError, isNull);
          expect(app.initialized, true);
          expect(app.engine.isConnected, !refused);
          expect(app.engine.isForegroundActive(), false);
          expect(native.where((c) => c.method == 'arm'), hasLength(1));
          expect(
            native.firstWhere((c) => c.method == 'arm').arguments,
            Peripheral.id.str,
          );
          if (refused) {
            expect(IosBleRestore.foregroundActive, false);
            expect(
              native.where((c) => c.method == 'armRecoveryNow'),
              hasLength(1),
            );
          } else {
            expect(IosBleRestore.foregroundActive, true);
            expect(app.engine.liveEnabled, true);
            expect(native.where((c) => c.method == 'armRecoveryNow'), isEmpty);
          }
          expect((await PairedDevice.load())!.remoteId, paired!.remoteId);
          expect(await (await LocalDb.instance).query('day_result'), isEmpty);
          expect(
            await (await LocalDb.instance).query('decoded_onehz'),
            isEmpty,
          );
        } finally {
          app.dispose();
          await app.engine.disconnect();
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  }
}
