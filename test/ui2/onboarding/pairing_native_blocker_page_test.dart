// Real peripheral -> engine -> AppState -> pairing page;no radio/phone claim.
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart'
    as os;
import 'package:whoop_companion/ble/ble_engine.dart';
import 'package:whoop_companion/ble/ble_state.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/l10n/app_localizations.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/onboarding/pairing.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import '../../ble/gatt_connection_test.dart' show Peripheral;
import '../../support/audit_visual.dart' show loadAuditFonts;
import '../../support/coverage_store.dart';
import '../../support/localized_coverage.dart';

// Change only the existing scan's time budget;all transport/state/page code runs.
class _BoundedScanApp extends AppState {
  _BoundedScanApp() : super.forTesting();
  @override
  Future<BluetoothDevice?> scanForBand() =>
      engine.scan(timeout: const Duration(milliseconds: 100));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final peripheral = Peripheral();
  late _BoundedScanApp app;
  setUpAll(() async {
    os.FlutterBluePlusPlatform.instance = peripheral;
    await loadAuditFonts();
    await coverageStore('pairing-native-blocker-page');
  });
  setUp(() async {
    await resetCoverageStore();
    BleEngine.resetBandClaimForTest();
    peripheral.trace.clear();
    peripheral.scanError = null;
    peripheral.mode = 'empty-scan';
    app = _BoundedScanApp();
    peripheral.engine = app.engine;
  });
  tearDown(() async {
    await app.engine.disconnect();
    app.dispose();
    peripheral.radioState = os.BmAdapterStateEnum.on;
    peripheral.adapters.add(
      os.BmBluetoothAdapterState(adapterState: os.BmAdapterStateEnum.on),
    );
  });
  tearDownAll(LocalDb.close);

  for (final state in [
    os.BmAdapterStateEnum.off,
    os.BmAdapterStateEnum.unauthorized,
    os.BmAdapterStateEnum.unavailable,
  ]) {
    for (final scale in [1.0, 3.1]) {
      testWidgets(
        'pairing shows the native $state blocker and genuinely retries after it clears at ${scale}x',
        (t) async {
          await t.runAsync(() async {
            peripheral.radioState = state;
            peripheral.adapters.add(
              os.BmBluetoothAdapterState(adapterState: state),
            );
            await Future<void>.delayed(const Duration(milliseconds: 10));
            await FlutterBluePlus.adapterState.firstWhere(
              (s) => s != BluetoothAdapterState.unknown,
            );
          });
          await localizedPage(t, const PairingScreen(), app: app, scale: scale);
          final l = AppLocalizations.of(t.element(find.byType(PairingScreen)))!;
          final db = await LocalDb.instance;
          final identity = await db.query('device');
          final cursor = await db.query('sync_cursor');
          final blocker = switch (state) {
            os.BmAdapterStateEnum.off => BleBlocker.adapterOff,
            os.BmAdapterStateEnum.unauthorized => BleBlocker.permissionDenied,
            _ => BleBlocker.unsupported,
          };
          Finder button(String label) =>
              find.byWidgetPredicate((w) => w is BigButton && w.label == label);
          await invokeControl(
            t,
            t.widget<BigButton>(button(l.pairingFindMyBand)).onTap,
          );
          final blocked = t.widget<PairingView>(find.byType(PairingView));
          expect(blocked.phase, PairPhase.bluetoothBlocked);
          expect(blocked.blocker, blocker);
          expect(blocked.detail, 'BleUnavailableException(${blocker.name})');
          expect(peripheral.trace, isNot(contains('scan')));
          expect(app.paired, isNull);
          expect(await db.query('device'), identity);
          expect(await db.query('sync_cursor'), cursor);
          await t.runAsync(() async {
            peripheral.radioState = os.BmAdapterStateEnum.on;
            peripheral.adapters.add(
              os.BmBluetoothAdapterState(
                adapterState: os.BmAdapterStateEnum.on,
              ),
            );
            await Future<void>.delayed(const Duration(milliseconds: 20));
          });
          await reveal(t, button(l.pairingTryAgain));
          await invokeControl(
            t,
            t.widget<BigButton>(button(l.pairingTryAgain)).onTap,
          );
          final retried = t.widget<PairingView>(find.byType(PairingView));
          expect(
            retried.phase,
            PairPhase.notFound,
            reason: 'A real empty scan is distinct from an OS refusal',
          );
          expect(retried.blocker, isNull);
          expect(retried.detail, isEmpty);
          expect(peripheral.trace, contains('scan'));
          expect(peripheral.trace, isNot(contains('connect')));
          expect(app.paired, isNull);
          expect(await db.query('device'), identity);
          expect(await db.query('sync_cursor'), cursor);
          expect(await db.query('decoded_onehz'), isEmpty);
          expect(BleEngine.bandClaimed, false);
          expect(FlutterBluePlus.isScanningNow, false);
          expect(t.takeException(), isNull);
        },
        timeout: const Timeout(Duration(seconds: 30)),
      );
    }
  }
}
