// Decoded control publication contracts: synthetic values, no BLE/OS acceptance.
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/ble/ble_engine.dart';
import 'package:whoop_protocol/whoop_protocol.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BleEngine engine;
  var changes = 0;
  setUp(() {
    changes = 0;
    engine = BleEngine(onRecord: (_, _) async {}, onState: (_) => changes++);
    engine.debugInstallFakeLink(onWrite: (_) async => true);
  });
  tearDown(() => engine.disconnect());
  test(
    'alarm readback is diagnostic and never becomes a new local set command',
    () {
      engine.debugAbsorbDecoded(
        p.Decoded('cmd_response', {
          'alarm_epoch': 1760000000,
          'alarm_active': true,
        }),
      );
      expect(engine.offloadSnapshot['strap_alarm_epoch'], 1760000000);
      expect(engine.offloadSnapshot['strap_alarm_active'], isTrue);
      engine.debugAbsorbDecoded(
        p.Decoded('cmd_response', {'alarm_epoch': 0, 'alarm_active': false}),
      );
      expect(engine.offloadSnapshot['strap_alarm_epoch'], 0);
      expect(engine.offloadSnapshot['strap_alarm_active'], isFalse);
      expect(engine.isConnected, isFalse);
    },
  );
  test('a garbled name cannot overwrite the last published clean label', () {
    engine.debugAbsorbDecoded(
      p.Decoded('cmd_response', {'strap_name': 'Synthetic band'}),
    );
    expect(engine.state.strapName, 'Synthetic band');
    final before = changes;
    for (final name in <String?>['?*', '', null]) {
      engine.debugAbsorbDecoded(
        p.Decoded('cmd_response', {'strap_name': name}),
      );
      expect(engine.state.strapName, 'Synthetic band');
    }
    expect(changes, before);
  });
  test(
    'charge event provenance survives and stale battery does not become current',
    () {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      engine.debugAbsorbDecoded(
        p.Decoded('event', {'battery_pct': 60, 'ts_epoch': now}),
      );
      engine.debugAbsorbDecoded(
        p.Decoded('event', {
          'battery_pct': 10,
          'charging': true,
          'on_wrist': false,
          'ts_epoch': now - 86400,
        }),
      );
      expect(engine.state.batteryPct, 60);
      expect(engine.state.charging, isTrue);
      expect(engine.state.chargingTs, now - 86400);
      // A buffered wear event does not establish the present link's wrist state.
      expect(engine.linkWristOn, isNot(false));
      engine.debugAbsorbDecoded(
        p.Decoded('event', {'on_wrist': true, 'ts_epoch': now}),
      );
      expect(engine.linkWristOn, isTrue);
      expect(changes, greaterThanOrEqualTo(3));
    },
  );
  test(
    'gen4 HELLO publishes known fields and preserves good state when fields are absent',
    () {
      engine.debugAbsorbDecoded(
        p.Decoded('cmd_response', {
          'hello': p.HelloInfo(
            serial: 'SYNTH00001',
            batteryPct: 72,
            wristOn: true,
          ),
        }),
      );
      expect(engine.state.serial, 'SYNTH00001');
      expect(engine.state.batteryPct, 72);
      expect(engine.linkWristOn, isTrue);
      engine.debugAbsorbDecoded(
        p.Decoded('cmd_response', {'hello': p.HelloInfo(serial: '?*')}),
      );
      expect(engine.state.serial, 'SYNTH00001');
      expect(engine.state.batteryPct, 72);
      expect(engine.linkWristOn, isTrue);
      expect(changes, 2);
    },
  );
}
