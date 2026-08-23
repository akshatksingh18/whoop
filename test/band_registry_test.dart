// The band registry is the ONE place the BLE engine's device-specific facts
// live (change-list D1/D2/D3). Every value here used to be a literal in
// `ble_engine.dart`, so this pins them at exactly what the engine did before —
// a wrong offset does not throw, it silently reads the wrong byte.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ble/adapters/_registry.dart';
import 'package:openstrap_protocol/openstrap_protocol.dart';

void main() {
  test('ids are unique and stable — they are stamped as device_family', () {
    expect(kBandRegistry.map((e) => e.id).toList(), <String>['gen4', 'gen5']);
  });

  test('D1 — the scan service list is exactly the two WHOOP services', () {
    expect(kBandRegistry.map((e) => e.service).toList(), <String>[
      GattProfile.gen4.service,
      GattProfile.gen5.service,
    ]);
    expect(kBandRegistry.map((e) => e.servicePrefix).toList(),
        <String>['61080001', 'fd4b0001']);
  });

  test('D2 — a WHOOP link requires its four command/notify characteristics',
      () {
    for (final e in kBandRegistry) {
      expect(e.requiredCharacteristics, <String>[
        e.gatt.cmdTo,
        e.gatt.cmdFrom,
        e.gatt.events,
        e.gatt.data,
      ]);
    }
  });

  test('D2 — an entry may require fewer (a generic HRS has one notify char)',
      () {
    const one = BandEntry(
      id: 'x',
      label: 'x',
      gatt: GattProfile.gen4,
      wire: BandProfile.gen4,
      innerOpcodeOffset: 2,
      innerVersionOffset: 1,
      innerCounterOffset: 3,
      requiredCharacteristics: <String>['61080005-x'],
    );
    expect(one.requiredCharacteristics, hasLength(1));
  });

  test('D3 — frameOpcodeIndex lands on the opcode of a real built frame', () {
    // This is the byte the dangerous-opcode block reads. If it moves, the
    // block silently stops blocking.
    for (final e in kBandRegistry) {
      final raw = buildCommand(7, Cmd.rebootStrap, const <int>[0x01], e.wire);
      expect(raw[e.frameOpcodeIndex], Cmd.rebootStrap, reason: e.id);
    }
    expect(kWhoopGen4.frameOpcodeIndex, 6); // 4-byte header + 2
    expect(kWhoopGen5.frameOpcodeIndex, 10); // 8-byte header + 2
  });

  test('D3 — historical inner offsets are unchanged from the old literals',
      () {
    for (final e in kBandRegistry) {
      expect(e.innerVersionOffset, 1, reason: e.id); // inner[1]
      expect(e.innerCounterOffset, 3, reason: e.id); // u32(inner, 3)
    }
  });

  test('bandEntryFor maps a wire profile back to its entry', () {
    expect(bandEntryFor(BandProfile.gen4).id, 'gen4');
    expect(bandEntryFor(BandProfile.gen5).id, 'gen5');
  });
}
