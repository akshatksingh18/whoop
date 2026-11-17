// Actual periodic maintenance over the FBP adapter; only peripheral and policy
// wall clock are authored. Full cases run in CI; local probes select one tick.
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart'
    as os;
import 'package:whoop_companion/ble/ble_engine.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/sync/sync_policy.dart';
import 'package:whoop_protocol/whoop_protocol.dart' as p;

import 'coverage_ble_durable_boundary_test.dart' show historyComplete, until;
import 'coverage_gatt_connection_test.dart' show Peripheral;
import 'coverage_gatt_keepalive_journeys_test.dart' show waitForTick;
import 'support/coverage_store.dart';

class _MaintenanceBand extends BleEngine {
  _MaintenanceBand(List<String> logs, DateTime Function() now)
    : super(
        onRecord: (_, _) async {},
        onState: (_) {},
        log: logs.add,
        policyNow: now,
      );
  // Liveness is independently covered by the retained real-timer journeys.
  // Keep it fresh while these cases isolate the maintenance cadence decision.
  @override
  Duration get sinceLastRx => Duration.zero;
  @override
  bool? get linkWristOn => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final peripheral = Peripheral();
  setUpAll(() async {
    os.FlutterBluePlusPlatform.instance = peripheral;
    await coverageStore('gatt-maintenance-cadence');
  });
  setUp(() async {
    await resetCoverageStore();
    BleEngine.resetBandClaimForTest();
    peripheral.trace.clear();
    peripheral.mode = 'ready';
    peripheral.band = p.BandProfile.gen4;
    peripheral.beforeWrite = null;
    peripheral.replyToCommand = null;
  });
  tearDownAll(LocalDb.close);
  Future<void> terminal(_MaintenanceBand band) async {
    final gatt = p.GattProfile.gen4;
    peripheral.incoming.add(
      os.BmCharacteristicData(
        remoteId: Peripheral.id,
        primaryServiceUuid: null,
        serviceUuid: os.Guid(gatt.service),
        characteristicUuid: os.Guid(gatt.data),
        instanceId: 0,
        value: p.buildFrame(historyComplete()),
        success: true,
        errorCode: 0,
        errorString: '',
      ),
    );
    await until(() => !band.offloadActive);
  }

  int writes(int op) => peripheral.trace.where((s) => s == 'write:$op').length;

  for (final (name, offset) in [
    ('just before', -1),
    ('exact boundary', 0),
    ('just after', 1),
  ]) {
    test(
      'real maintenance RTC $name is bounded by the existing six-hour policy',
      () async {
        var now = DateTime.now();
        final logs = <String>[];
        final band = _MaintenanceBand(logs, () => now);
        peripheral.engine = band;
        try {
          expect(
            await band.connectToRemoteId(Peripheral.id.str),
            true,
            reason: logs.join('\n'),
          );
          await terminal(band);
          await band.getBattery();
          final clockBefore = writes(p.Cmd.getClock);
          final batteryBefore = writes(p.Cmd.getBatteryLevel);
          now = now.add(
            Duration(seconds: kRtcReverifyIntervalSeconds + offset),
          );
          await waitForTick(
            () => writes(p.Cmd.getBatteryLevel) > batteryBefore,
          );
          expect(writes(p.Cmd.getClock), clockBefore + (offset < 0 ? 0 : 1));
          expect(
            logs.where((s) => s.contains('Periodic RTC re-verify')),
            hasLength(offset < 0 ? 0 : 1),
          );
          expect(band.isConnected, true);
          final sent = peripheral.trace
              .where((s) => s.startsWith('write:'))
              .map((s) => int.parse(s.split(':').last));
          expect(sent.where(p.dangerousCmds.contains), isEmpty);
          expect(
            await (await LocalDb.instance).query('decoded_onehz'),
            isEmpty,
          );
        } finally {
          await band.disconnect();
          expect(band.holdsBandLink, false);
          expect(BleEngine.bandClaimed, false);
        }
      },
      timeout: const Timeout(Duration(seconds: 65)),
    );
  }
  test(
    'a refused battery poll earns no silence credit and the real tick retries',
    () async {
      var now = DateTime.now();
      final logs = <String>[];
      final band = _MaintenanceBand(logs, () => now);
      peripheral.engine = band;
      var refuse = true;
      try {
        expect(await band.connectToRemoteId(Peripheral.id.str), true);
        await terminal(band);
        peripheral.beforeWrite = (_, inner) async {
          if (inner[2] == p.Cmd.getBatteryLevel && refuse) {
            throw StateError('authored maintenance battery refusal');
          }
        };
        final before = writes(p.Cmd.getBatteryLevel);
        await band.getBattery();
        expect(writes(p.Cmd.getBatteryLevel), before + 1);
        expect(
          logs.any((s) => s.contains('authored maintenance battery refusal')),
          true,
        );
        refuse = false;
        // Even one second later is far inside the five-minute successful-write
        // floor. Only the refused write permits this actual timer retry.
        now = now.add(const Duration(seconds: 1));
        await waitForTick(() => writes(p.Cmd.getBatteryLevel) > before + 1);
        expect(writes(p.Cmd.getBatteryLevel), before + 2);
        expect(band.isConnected, true);
        expect(band.pendingCommandCount, 0);
      } finally {
        await band.disconnect();
        peripheral.beforeWrite = null;
        expect(BleEngine.bandClaimed, false);
      }
    },
    timeout: const Timeout(Duration(seconds: 65)),
  );
}
