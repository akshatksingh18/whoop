// The band registry is the ONE place the BLE engine's device-specific facts
// live (change-list D1/D2/D3). Every value here used to be a literal in
// `ble_engine.dart`, so this pins them at exactly what the engine did before —
// a wrong offset does not throw, it silently reads the wrong byte.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ble/adapters/_registry.dart';
import 'package:openstrap_protocol/openstrap_protocol.dart';

void main() {
  test('ids are unique and stable — they are stamped as device_family', () {
    expect(kBandRegistry.map((e) => e.id).toList(),
        <String>['gen4', 'gen5', 'ble_hrs']);
  });

  test('D1 — the scan service list is exactly the two WHOOP services', () {
    // [kFramedBands], not the whole registry: the scan filter and the
    // discovery match are about the band the OFFLOAD ENGINE drives. A
    // notify-only sensor matching there would be handed to `_doConnect`.
    expect(kFramedBands.map((e) => e.service).toList(), <String>[
      GattProfile.gen4.service,
      GattProfile.gen5.service,
    ]);
    expect(kFramedBands.map((e) => e.servicePrefix).toList(),
        <String>['61080001', 'fd4b0001']);
  });

  test('D2 — a WHOOP link requires its four command/notify characteristics',
      () {
    for (final e in kFramedBands) {
      expect(e.requiredCharacteristics, <String>[
        e.gatt!.cmdTo,
        e.gatt!.cmdFrom,
        e.gatt!.events,
        e.gatt!.data,
      ]);
    }
  });

  test('D10 — a generic HRS entry has one service and one notify char', () {
    expect(kBleHrs.isFramed, isFalse);
    expect(kBleHrs.service, kHeartRateServiceUuid);
    expect(kBleHrs.servicePrefix, '0000180d');
    expect(kBleHrs.requiredCharacteristics, [kHeartRateMeasurementUuid]);
    // The two halves that could NOT be expressed — see the registry header.
    expect(kBleHrs.gatt, isNull, reason: 'GattProfile is six WHOOP UUIDs');
    expect(kBleHrs.wire, isNull, reason: 'BandProfile is a framed envelope');
  });

  test('D3 — frameOpcodeIndex lands on the opcode of a real built frame', () {
    // This is the byte the dangerous-opcode block reads. If it moves, the
    // block silently stops blocking.
    for (final e in kFramedBands) {
      final raw = buildCommand(7, Cmd.rebootStrap, const <int>[0x01], e.wire!);
      expect(raw[e.frameOpcodeIndex], Cmd.rebootStrap, reason: e.id);
    }
    expect(kWhoopGen4.frameOpcodeIndex, 6); // 4-byte header + 2
    expect(kWhoopGen5.frameOpcodeIndex, 10); // 8-byte header + 2
  });

  test('D3 — historical inner offsets are unchanged from the old literals',
      () {
    for (final e in kFramedBands) {
      expect(e.innerVersionOffset, 1, reason: e.id); // inner[1]
      expect(e.innerCounterOffset, 3, reason: e.id); // u32(inner, 3)
    }
    // A band with no envelope has no inner payload, and -1 throws rather than
    // reading a plausible-looking wrong byte.
    expect(kBleHrs.innerVersionOffset, -1);
    expect(kBleHrs.innerCounterOffset, -1);
  });

  test('a band declares what its timestamps ARE', () {
    // Not cosmetic: the frequency-domain and per-hour metrics have to refuse
    // on an arrival anchor, and this is the fact they refuse on.
    expect(kWhoopGen4.timeAnchor, TimeAnchor.measured);
    expect(kWhoopGen5.timeAnchor, TimeAnchor.measured);
    expect(kBleHrs.timeAnchor, TimeAnchor.arrival);
  });

  test('bandEntryFor maps a wire profile back to its entry', () {
    expect(bandEntryFor(BandProfile.gen4).id, 'gen4');
    expect(bandEntryFor(BandProfile.gen5).id, 'gen5');
  });
}
