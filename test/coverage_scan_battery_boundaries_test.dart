// Authored OS scan and framed battery failures; no physical radio acceptance.
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart'
    as os;
import 'package:whoop_companion/ble/ble_engine.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_protocol/whoop_protocol.dart' as p;
import 'coverage_gatt_connection_test.dart' show Peripheral;
import 'coverage_ble_durable_boundary_test.dart' show until;
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final peripheral = Peripheral();
  final logs = <String>[];
  final published = <double?>[];
  late BleEngine engine;
  setUpAll(() async {
    await coverageStore('scan-battery-boundaries');
    os.FlutterBluePlusPlatform.instance = peripheral;
  });
  setUp(() async {
    await resetCoverageStore();
    BleEngine.resetBandClaimForTest();
    peripheral
      ..mode = 'service-scan'
      ..scanError = null
      ..stopError = null;
    peripheral.trace.clear();
    logs.clear();
    published.clear();
    engine = BleEngine(
      onRecord: (_, _) async {},
      onState: (s) => published.add(s.batteryPct),
      log: logs.add,
    );
    peripheral.engine = engine;
    peripheral.radioState = os.BmAdapterStateEnum.on;
    peripheral.adapters.add(
      os.BmBluetoothAdapterState(adapterState: os.BmAdapterStateEnum.on),
    );
    await FlutterBluePlus.adapterState.firstWhere(
      (state) => state != BluetoothAdapterState.unknown,
    );
  });
  tearDown(() async {
    peripheral.stopError = null;
    await FlutterBluePlus.stopScan();
    await engine.disconnect();
    expect(BleEngine.bandClaimed, isFalse);
    expect(engine.pendingCommandCount, 0);
  });
  tearDownAll(LocalDb.close);

  test(
    'COV-48 finding a band survives refused OS stop and a later scan retries',
    () async {
      peripheral.stopError = PlatformException(code: 'authored-stop-refusal');
      final found = await engine.scan(
        timeout: const Duration(milliseconds: 200),
      );
      await until(
        () => logs.any((s) => s.contains('stopScan after match failed')),
      );
      expect(found?.remoteId, Peripheral.id);
      expect(FlutterBluePlus.isScanningNow, isFalse);
      expect(peripheral.trace.where((s) => s == 'scan'), hasLength(1));
      expect(peripheral.trace, isNot(contains('connect')));
      peripheral.stopError = null;
      final retry = await engine.scan(
        timeout: const Duration(milliseconds: 200),
      );
      expect(retry?.remoteId, Peripheral.id);
      expect(peripheral.trace.where((s) => s == 'scan'), hasLength(2));
      expect(FlutterBluePlus.isScanningNow, isFalse);
    },
  );

  test(
    'COV-48 an existing OS scan stops before the engine starts its own scan',
    () async {
      peripheral.mode = 'empty-scan';
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 1));
      expect(FlutterBluePlus.isScanningNow, isTrue);
      peripheral.trace.clear();
      peripheral.mode = 'service-scan';
      final found = await engine.scan(
        timeout: const Duration(milliseconds: 200),
      );
      expect(found?.remoteId, Peripheral.id);
      expect(peripheral.trace.indexOf('stop-scan'), 0);
      expect(peripheral.trace.indexOf('scan'), greaterThan(0));
      expect(FlutterBluePlus.isScanningNow, isFalse);
      expect(peripheral.trace, isNot(contains('connect')));
    },
  );

  for (final band in [p.BandProfile.gen4, p.BandProfile.gen5]) {
    test(
      'COV-48 ${band.type.name} battery refusal and silence preserve measurement until explicit retry',
      () async {
        final requests = <Uint8List>[];
        var refused = true, answer = false;
        engine.debugInstallFakeLink(
          band: band,
          onWrite: (frame) async {
            final request = p.parseFrame(frame, profile: band)!.inner;
            requests.add(request);
            if (refused) return false;
            if (answer) {
              final inner = Uint8List.fromList([
                p.PacketType.commandResponse,
                31,
                p.Cmd.getBatteryLevel,
                request[1],
                1,
                if (band.isGen5) 65 else ...[650 & 255, 650 >> 8],
              ]);
              engine.debugReceiveFrame(p.Frame(inner, true, true));
            }
            return true;
          },
        );
        engine.debugAbsorbDecoded(
          p.Decoded('event', {
            'battery_pct': 72.0,
            'ts_epoch': DateTime.now().millisecondsSinceEpoch ~/ 1000,
          }),
        );
        final publications = published.length;
        await engine.getBattery();
        expect(engine.state.batteryPct, 72);
        expect(engine.pendingCommandCount, 0);
        refused = false;
        await engine.getBattery();
        expect(
          engine.pendingCommandCount,
          1,
          reason: 'caller returns after write, before the response timeout',
        );
        await until(() => engine.pendingCommandCount == 0, attempts: 1400);
        await until(
          () =>
              logs.any((s) => s.contains('GET_BATTERY_LEVEL went unanswered')),
        );
        expect(engine.state.batteryPct, 72);
        expect(published, hasLength(publications));
        answer = true;
        await engine.getBattery();
        await until(() => engine.state.batteryPct == 65);
        expect(engine.pendingCommandCount, 0);
        expect(requests, hasLength(3));
        expect(requests.every((r) => r[2] == p.Cmd.getBatteryLevel), isTrue);
        expect(requests.map((r) => r[1]).toSet(), hasLength(3));
        expect(
          logs.where((s) => s.contains('GET_BATTERY_LEVEL went unanswered')),
          hasLength(1),
        );
      },
    );
  }
}
