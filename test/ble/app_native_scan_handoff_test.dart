// Actual public pairing scan delegates to the shared engine and native SDK contract.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart'
    as os;
import 'package:whoop_protocol/whoop_protocol.dart' as p;
import 'package:whoop_companion/ble/ble_engine.dart';
import 'package:whoop_companion/ble/ble_state.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/sync/paired_device.dart';
import 'gatt_connection_test.dart' show Peripheral;
import '../support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final native = Peripheral();
  setUpAll(() async {
    await coverageStore('app-native-scan-handoff');
    os.FlutterBluePlusPlatform.instance = native;
  });
  setUp(() async {
    await resetCoverageStore();
    native.trace.clear();
    native.mode = 'service-scan';
    native.radioState = os.BmAdapterStateEnum.on;
    native.scanError = null;
    BleEngine.resetBandClaimForTest();
  });
  tearDownAll(LocalDb.close);
  for (final outcome in ['gen4', 'gen5', 'off', 'denied']) {
    test(
      'public pairing scan $outcome never claims a band or invents saved data',
      () async {
        native.band = outcome == 'gen5'
            ? p.BandProfile.gen5
            : p.BandProfile.gen4;
        native.radioState = switch (outcome) {
          'off' => os.BmAdapterStateEnum.off,
          'denied' => os.BmAdapterStateEnum.unauthorized,
          _ => os.BmAdapterStateEnum.on,
        };
        native.adapters.add(
          os.BmBluetoothAdapterState(adapterState: native.radioState),
        );
        final app = AppState.forTesting();
        native.engine = app.engine;
        try {
          if (outcome == 'off' || outcome == 'denied') {
            await expectLater(
              app.scanForBand(),
              throwsA(
                isA<BleUnavailableException>().having(
                  (e) => e.blocker,
                  'the actual phone blocker',
                  outcome == 'off'
                      ? BleBlocker.adapterOff
                      : BleBlocker.permissionDenied,
                ),
              ),
            );
            expect(native.trace, isNot(contains('scan')));
          } else {
            final found = await app.scanForBand();
            expect(found?.remoteId.str, Peripheral.id.str);
            expect(native.trace, containsAll(['scan', 'stop-scan']));
          }
          expect(native.trace, isNot(contains('connect')));
          expect(app.paired, isNull);
          expect(app.engine.isConnected, false);
          expect(BleEngine.bandClaimed, false);
          expect(await PairedDevice.load(), isNull);
          final db = await LocalDb.instance;
          expect(await db.query('decoded_onehz'), isEmpty);
          expect(await db.query('day_result'), isEmpty);
        } finally {
          await app.engine.disconnect();
          app.dispose();
        }
      },
    );
  }
}
