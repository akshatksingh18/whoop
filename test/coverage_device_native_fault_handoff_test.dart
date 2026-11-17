// Real engine preflight/native replies -> AppState -> DeviceDetail fault and recovery.
// The OS adapter replaces radio delivery;no hardware acceptance claim.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart'
    as os;
import 'package:whoop_companion/ble/ble_engine.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/sync/paired_device.dart';
import 'package:whoop_companion/ui2/profile/devices.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'coverage_gatt_connection_test.dart' show Peripheral;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  final peripheral = Peripheral();
  setUpAll(() async {
    os.FlutterBluePlusPlatform.instance = peripheral;
    await loadAuditFonts();
    await coverageStore('device-native-fault', fresh: true);
  });
  setUp(() async {
    await resetCoverageStore();
    BleEngine.resetBandClaimForTest();
    peripheral.trace.clear();
  });
  tearDownAll(LocalDb.close);
  for (final state in [
    os.BmAdapterStateEnum.off,
    os.BmAdapterStateEnum.unauthorized,
    os.BmAdapterStateEnum.unavailable,
  ]) {
    for (final scale in [1.0, 3.1]) {
      testWidgets(
        'band detail native $state blocker at ${scale}x clears only after healthy reconnect',
        (t) async {
          await LocalDb.putSession({
            'id': 'authored-retained-device',
            'start_ts': 1617714000,
            'type': 'running',
            'status': 'finished',
            'source': 'manual',
            'created_at': 1,
          });
          final retained = await LocalDb.session('authored-retained-device');
          final app = AppState.forTesting()
            ..paired = PairedDevice(Peripheral.id.str, 'Authored band');
          peripheral.engine = app.engine;
          Future<T> drive<T>(Future<T> Function() start) async {
            var done = false;
            T? value;
            Object? failure;
            StackTrace? stack;
            start().then(
              (v) {
                value = v;
                done = true;
              },
              onError: (Object e, StackTrace s) {
                failure = e;
                stack = s;
                done = true;
              },
            );
            for (var i = 0; i < 1500 && !done; i++) {
              await t.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 10)),
              );
              await t.pump(const Duration(milliseconds: 20));
            }
            expect(done, true, reason: peripheral.trace.join(' '));
            if (failure != null) Error.throwWithStackTrace(failure!, stack!);
            return value as T;
          }

          try {
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
            expect(
              await drive(
                () => app.engine.connectToRemoteId(Peripheral.id.str),
              ),
              false,
            );
            final fault = app.engine.bandStatus;
            expect(fault.isFault, true);
            expect(peripheral.trace, isNot(contains('connect')));
            expect(BleEngine.bandClaimed, false);
            final source = liveSources(app).single;
            await localizedPage(
              t,
              DeviceDetail(source),
              app: app,
              scale: scale,
              push: true,
            );
            await reveal(t, find.text(fault.reason));
            expect(find.text(fault.title), findsOneWidget);
            expect(find.text(fault.reason), findsOneWidget);
            if (fault.fix != null) {
              await reveal(t, find.text(fault.fix!));
              expect(find.text(fault.fix!), findsOneWidget);
            }
            expect(app.isPaired, true);
            expect(app.isConnected, false);
            await t.runAsync(() async {
              peripheral.radioState = os.BmAdapterStateEnum.on;
              peripheral.adapters.add(
                os.BmBluetoothAdapterState(
                  adapterState: os.BmAdapterStateEnum.on,
                ),
              );
              await Future<void>.delayed(const Duration(milliseconds: 10));
            });
            expect(
              await drive(
                () => app.engine.connectToRemoteId(Peripheral.id.str),
              ),
              true,
            );
            await t.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 100)),
            );
            await t.pumpAndSettle();
            expect(app.engine.bandStatus.isFault, false);
            expect(app.isConnected, true);
            expect(find.text(fault.reason), findsNothing);
            expect(app.paired!.remoteId, Peripheral.id.str);
            expect(
              await t.runAsync(
                () => LocalDb.session('authored-retained-device'),
              ),
              retained,
            );
            final db = (await t.runAsync(() => LocalDb.instance))!;
            expect(await t.runAsync(() => db.query('decoded_onehz')), isEmpty);
            expect(await t.runAsync(() => db.query('day_result')), isEmpty);
            final back = find.byWidgetPredicate(
              (w) => w is Pressable && w.semanticLabel == 'Back',
            );
            await reveal(t, back);
            await t.tap(back);
            await t.pumpAndSettle();
            expect(find.byType(DeviceDetail), findsNothing);
            expect(app.isPaired, true);
          } finally {
            await drive(() => app.engine.disconnect());
            app.dispose();
            await t.pumpWidget(const SizedBox());
            await t.pumpAndSettle();
          }
        },
      );
    }
  }
}
