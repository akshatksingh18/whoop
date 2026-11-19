// Real SDK/native-operation timeout boundary;host contract,not hardware acceptance.
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart'
    as os;
import 'package:whoop_companion/ble/ble_engine.dart';
import 'coverage_gatt_connection_test.dart' show Peripheral;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final p = Peripheral();
  setUpAll(() => os.FlutterBluePlusPlatform.instance = p);
  test(
    'late old native disconnect after bounded ownership wait cannot kill the new owner',
    () async {
      BleEngine.resetBandClaimForTest();
      final entered = Completer<void>(), release = Completer<void>();
      final old = BleEngine(onRecord: (_, _) async {}, onState: (_) {});
      final fresh = BleEngine(onRecord: (_, _) async {}, onState: (_) {});
      p.engine = old;
      try {
        expect(await old.connectToRemoteId(Peripheral.id.str), true);
        p.beforeDisconnect = () async {
          if (!entered.isCompleted) {
            entered.complete();
          }
          await release.future;
        };
        p.link(false);
        await entered.future.timeout(const Duration(seconds: 3));
        p.engine = fresh;
        final opening = fresh.connectToRemoteId(Peripheral.id.str);
        await Future<void>.delayed(const Duration(milliseconds: 10200));
        expect(p.trace.where((s) => s == 'connect'), hasLength(1));
        expect(fresh.isConnected, false);
        p.beforeDisconnect = null;
        release.complete();
        expect(await opening.timeout(const Duration(seconds: 15)), true);
        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect(fresh.isConnected, true);
        expect(fresh.holdsBandLink, true);
        expect(BleEngine.bandClaimed, true);
      } finally {
        p.beforeDisconnect = null;
        if (!release.isCompleted) {
          release.complete();
        }
        await old.disconnect();
        await fresh.disconnect();
      }
    },
    timeout: const Timeout(Duration(seconds: 40)),
  );
}
