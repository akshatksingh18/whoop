// Real engine keep-alive timers and GATT writes over a scripted peripheral.
// These integration cases wait one real timer interval in cloud CI; local probes
// select one journey. Observed age/wrist metadata is controlled, not radio state.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart'
    as os;
import 'package:whoop_protocol/whoop_protocol.dart' as p;
import 'package:whoop_companion/ble/ble_engine.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/sync/sync_policy.dart';

import 'coverage_gatt_connection_test.dart' show Peripheral;
import 'coverage_ble_durable_boundary_test.dart' show historyComplete, until;
import 'support/coverage_store.dart';

class _AgeBand extends BleEngine {
  _AgeBand(List<String> logs, List<String> states)
    : super(
        onRecord: (_, _) async {},
        onState: (s) => states.add(s.connection),
        log: logs.add,
      );
  Duration age = Duration.zero;
  bool? wrist;
  @override
  Duration get sinceLastRx => age;
  @override
  bool? get linkWristOn => wrist;
}

Future<void> waitForTick(bool Function() reached) async {
  await Future<void>.delayed(
    const Duration(seconds: kKeepAliveIntervalSeconds),
  );
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!reached() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  expect(
    reached(),
    true,
    reason: 'the real scheduled keep-alive must reach its observable outcome',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final peripheral = Peripheral();
  setUpAll(() async {
    os.FlutterBluePlusPlatform.instance = peripheral;
    await coverageStore('gatt-keepalive');
  });
  setUp(() async {
    await resetCoverageStore();
    BleEngine.resetBandClaimForTest();
    peripheral.trace.clear();
  });
  tearDownAll(LocalDb.close);
  for (final kind in [
    'silent',
    'off-wrist',
    'no-stream',
    'foreground-hr',
    'hr-only',
    'delivering-hr',
    'transferring',
  ]) {
    test(
      'real GATT keep-alive $kind retains timer and live-mode ownership',
      () async {
        final logs = <String>[], states = <String>[];
        final band = _AgeBand(logs, states);
        peripheral.engine = band;
        try {
          expect(
            await band.connectToRemoteId(Peripheral.id.str),
            true,
            reason: logs.join('\n'),
          );
          void receive(Uint8List inner) {
            peripheral.incoming.add(
              os.BmCharacteristicData(
                remoteId: Peripheral.id,
                primaryServiceUuid: null,
                serviceUuid: os.Guid(p.GattProfile.gen4.service),
                characteristicUuid: os.Guid(p.GattProfile.gen4.data),
                instanceId: 0,
                value: p.buildFrame(inner),
                success: true,
                errorCode: 0,
                errorString: '',
              ),
            );
          }

          final live = !['silent', 'off-wrist', 'no-stream'].contains(kind);
          if (live) {
            if (kind == 'foreground-hr') {
              await band.enableLiveStreams();
            } else {
              await band.enableHrOnlyLive();
            }
            expect(band.liveHrOnly, true);
          }
          if (kind != 'transferring' &&
              kind != 'silent' &&
              kind != 'off-wrist') {
            receive(historyComplete());
            await until(() => !band.offloadActive);
          }
          if (kind == 'delivering-hr') {
            final inner = Uint8List(20);
            inner[0] = 0x28;
            inner[8] = 88;
            inner[18] = 1;
            ByteData.sublistView(inner).setUint32(
              2,
              DateTime.now().millisecondsSinceEpoch ~/ 1000,
              Endian.little,
            );
            receive(inner);
            await until(() => band.state.liveHr == 88);
          }
          if (kind == 'off-wrist') band.wrist = false;
          band.age = Duration(
            seconds: switch (kind) {
              'silent' || 'off-wrist' => kLivenessFuseSeconds + 1,
              'no-stream' => kNoStreamPollSilenceSeconds + 1,
              _ => kLivenessFuseSeconds ~/ 2 + 1,
            },
          );
          int writes(int op) =>
              peripheral.trace.where((s) => s == 'write:$op').length;
          final batteryBefore = writes(p.Cmd.getBatteryLevel);
          final highBefore = writes(p.Cmd.sendR10R11Realtime);
          final hrBefore = writes(p.Cmd.toggleRealtimeHr);
          if (kind == 'off-wrist') {
            await Future<void>.delayed(
              const Duration(seconds: kKeepAliveIntervalSeconds + 1),
            );
            expect(
              band.isConnected,
              true,
              reason: 'off-wrist silence has its longer existing fuse',
            );
            expect(writes(p.Cmd.getBatteryLevel), batteryBefore);
            band.age = const Duration(
              seconds: kLinkFreshnessOffWristSeconds + 1,
            );
          }
          if (kind == 'silent' || kind == 'off-wrist') {
            await waitForTick(
              () =>
                  !band.isConnected &&
                  !band.holdsBandLink &&
                  states.last == 'disconnected',
            );
            expect(band.holdsBandLink, false);
            expect(
              BleEngine.bandClaimed,
              true,
              reason: 'unintentional bounce retains the claim for reconnect',
            );
            expect(states.last, 'disconnected');
            expect(logs.join('\n'), contains('bouncing the link'));
            if (kind == 'off-wrist') {
              expect(logs.join('\n'), contains('(off wrist)'));
            }
          } else if (kind == 'transferring') {
            expect(band.offloadActive, true);
            await Future<void>.delayed(
              const Duration(seconds: kKeepAliveIntervalSeconds + 1),
            );
            expect(band.isConnected, true);
            expect(band.offloadActive, true);
            expect(writes(p.Cmd.getBatteryLevel), batteryBefore);
            expect(writes(p.Cmd.toggleRealtimeHr), hrBefore);
            expect(writes(p.Cmd.sendR10R11Realtime), highBefore);
          } else {
            await waitForTick(
              () => writes(p.Cmd.getBatteryLevel) > batteryBefore,
            );
            expect(band.isConnected, true);
            expect(
              writes(p.Cmd.sendR10R11Realtime),
              highBefore,
              reason:
                  'every public live entry keeps the retired high-rate stream off',
            );
            expect(
              writes(p.Cmd.toggleRealtimeHr),
              kind == 'no-stream' || kind == 'delivering-hr'
                  ? hrBefore
                  : greaterThan(hrBefore),
            );
          }
          final sent = peripheral.trace
              .where((s) => s.startsWith('write:'))
              .map((s) => int.parse(s.split(':').last));
          expect(sent.where(p.dangerousCmds.contains), isEmpty);
        } finally {
          await band.disconnect();
          expect(band.holdsBandLink, false);
          expect(BleEngine.bandClaimed, false);
        }
      },
      timeout: const Timeout(Duration(seconds: 95)),
    );
  }
}
