// The real FBP/engine scan and connection preflight receives authored OS states.
// Refusal copy/retry is verified without changing permissions or using a radio.
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart'
    as os;
import 'package:whoop_companion/ble/ble_engine.dart';
import 'package:whoop_companion/ble/ble_state.dart';

import 'coverage_gatt_connection_test.dart' show Peripheral;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final peripheral = Peripheral();
  final logs = <String>[];
  late BleEngine engine;
  setUpAll(() => os.FlutterBluePlusPlatform.instance = peripheral);
  Future<void> radio(os.BmAdapterStateEnum state) async {
    peripheral.radioState = state;
    peripheral.adapters.add(os.BmBluetoothAdapterState(adapterState: state));
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }

  setUp(() async {
    BleEngine.resetBandClaimForTest();
    peripheral.trace.clear();
    peripheral.scanError = null;
    peripheral.mode = 'service-scan';
    logs.clear();
    engine = BleEngine(
      onRecord: (_, _) async {},
      onState: (_) {},
      log: logs.add,
    );
    peripheral.engine = engine;
    await radio(os.BmAdapterStateEnum.on);
    await FlutterBluePlus.adapterState.firstWhere(
      (s) => s != BluetoothAdapterState.unknown,
    );
  });
  tearDown(() async {
    await engine.disconnect();
    await radio(os.BmAdapterStateEnum.on);
    expect(BleEngine.bandClaimed, false);
    expect(FlutterBluePlus.isScanningNow, false);
  });

  for (final entry in ['scan', 'connect']) {
    for (final state in [
      os.BmAdapterStateEnum.off,
      os.BmAdapterStateEnum.unauthorized,
      os.BmAdapterStateEnum.unavailable,
    ]) {
      test(
        '$entry retains the actual $state blocker until a successful retry',
        () async {
          await radio(state);
          final blocker = switch (state) {
            os.BmAdapterStateEnum.off => BleBlocker.adapterOff,
            os.BmAdapterStateEnum.unauthorized => BleBlocker.permissionDenied,
            _ => BleBlocker.unsupported,
          };
          for (var attempt = 0; attempt < 2; attempt++) {
            if (entry == 'scan') {
              await expectLater(
                engine.scan(timeout: const Duration(milliseconds: 200)),
                throwsA(
                  isA<BleUnavailableException>().having(
                    (e) => e.blocker,
                    'actual blocker',
                    blocker,
                  ),
                ),
              );
            } else {
              expect(await engine.connectToRemoteId(Peripheral.id.str), false);
            }
            expect(engine.bandStatus.isFault, true);
            expect(engine.holdsBandLink, false);
            expect(BleEngine.bandClaimed, false);
          }
          expect(peripheral.trace, isNot(contains('scan')));
          expect(peripheral.trace, isNot(contains('connect')));
          expect(
            logs.where((l) => l.contains('blocked by the phone')),
            hasLength(1),
          );
          expect(engine.bandStatus.condition, switch (blocker) {
            BleBlocker.adapterOff => BandCondition.bluetoothOff,
            BleBlocker.permissionDenied => BandCondition.bluetoothDenied,
            BleBlocker.unsupported => BandCondition.bluetoothUnsupported,
          });
          await radio(os.BmAdapterStateEnum.on);
          if (entry == 'scan') {
            expect(
              (await engine.scan(
                timeout: const Duration(milliseconds: 200),
              ))?.remoteId.str,
              Peripheral.id.str,
            );
          } else {
            expect(await engine.connectToRemoteId(Peripheral.id.str), true);
          }
          expect(engine.bandStatus.isFault, false);
          expect(logs.where((l) => l.contains('block cleared')), hasLength(1));
        },
      );
    }
  }

  for (final (reason, blocker) in [
    ('Bluetooth permission denied', BleBlocker.permissionDenied),
    ('Bluetooth must be turned on', BleBlocker.adapterOff),
    ('Bluetooth not supported', BleBlocker.unsupported),
  ]) {
    test(
      'a late platform scan refusal surfaces $reason and permits retry',
      () async {
        peripheral.scanError = PlatformException(
          code: 'synthetic_scan',
          message: reason,
        );
        await expectLater(
          engine.scan(timeout: const Duration(milliseconds: 200)),
          throwsA(
            isA<BleUnavailableException>().having(
              (e) => e.blocker,
              'late blocker',
              blocker,
            ),
          ),
        );
        expect(engine.bandStatus.isFault, true);
        expect(engine.state.connection, 'disconnected');
        expect(BleEngine.bandClaimed, false);
        peripheral.scanError = null;
        expect(
          (await engine.scan(
            timeout: const Duration(milliseconds: 200),
          ))?.remoteId.str,
          Peripheral.id.str,
        );
        expect(engine.bandStatus.isFault, false);
        expect(logs.where((l) => l.contains('block cleared')), hasLength(1));
      },
    );
  }

  test(
    'a bounded unknown cold adapter can still scan and find the band',
    () async {
      await radio(os.BmAdapterStateEnum.unknown);
      expect(
        (await engine.scan(
          timeout: const Duration(milliseconds: 200),
        ))?.remoteId.str,
        Peripheral.id.str,
      );
      expect(engine.bandStatus.isFault, false);
      expect(peripheral.trace.where((s) => s == 'scan'), hasLength(1));
      expect(logs.where((l) => l.contains('blocked by the phone')), isEmpty);
    },
  );
}
