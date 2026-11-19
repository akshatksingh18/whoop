// Real FBP/AppState refusal regressions; authored peripheral, no radio acceptance claim.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart'
    as os;
import 'package:whoop_companion/ble/ble_engine.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/sync/band_ownership.dart';
import 'package:whoop_protocol/whoop_protocol.dart' as p;
import 'coverage_gatt_connection_test.dart' show Peripheral;
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('alarm-write-refusal-negative'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  final peripheral = Peripheral();
  os.FlutterBluePlusPlatform.instance = peripheral;
  for (final action in ['pulse', 'cancel']) {
    test(
      'a refused actual alarm $action must preserve honest state',
      () async {
        peripheral.mode = 'ready';
        peripheral.trace.clear();
        BandOwnership.resetForTest();
        BleEngine.resetBandClaimForTest();
        final app = AppState.forTesting();
        peripheral.engine = app.engine;
        try {
          expect(await app.engine.connectToRemoteId(Peripheral.id.str), true);
          expect(app.isConnected, true);
          expect(app.engine.isConnected, true);
          if (action == 'cancel') {
            await app.setAlarm(DateTime.now().add(const Duration(hours: 8)));
            app.debugHandleAlarmEvent(56);
            expect(app.alarmConfirmed, true);
          }
          final oldEpoch = app.alarmEpoch;
          final prefs = await SharedPreferences.getInstance();
          final savedEpoch = prefs.getInt('alarm_epoch');
          peripheral.trace.clear();
          peripheral.mode = 'write-refused';
          if (action == 'pulse') {
            await expectLater(
              app.testAlarmBuzz(),
              throwsException,
              reason: 'A refused write must reach the existing UI error path',
            );
          } else {
            await expectLater(
              app.disableAlarm(),
              throwsA(
                isA<Exception>().having(
                  (e) => e.toString(),
                  'message',
                  contains('Cancel not sent. Reconnect and retry.'),
                ),
              ),
            );
            expect(
              app.alarmEpoch,
              oldEpoch,
              reason:
                  'A refused hardware cancel must not erase the armed alarm',
            );
            expect(app.alarmConfirmed, true);
            expect(prefs.getInt('alarm_epoch'), savedEpoch);
          }
          expect(
            peripheral.trace.where(
              (s) =>
                  s ==
                  'write:${action == 'pulse' ? p.Cmd.runAlarm : p.Cmd.disableAlarm}',
            ),
            hasLength(1),
          );
        } finally {
          await app.engine.disconnect();
          app.dispose();
          await Future<void>.delayed(const Duration(milliseconds: 50));
          BandOwnership.resetForTest();
          BleEngine.resetBandClaimForTest();
        }
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  }
}
