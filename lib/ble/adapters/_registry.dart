// The const table of bands this build can see.
//
// Dart AOT has no runtime code loading, no `dart:mirrors`, and lazy static
// initialisation defeats import-for-side-effects registration (ASSUMPTIONS
// E4), so this is a hand-maintained `const` list. Adding a band is a source
// edit here and nothing else. Revisit past ~50 entries.
//
// SCOPE — this is the MINIMUM registry, not the adapter seam. It holds only
// the facts `ble_engine.dart` used to hardcode:
//
//   • which service UUIDs the scan filters on            (D1)
//   • which characteristics a link must expose to connect (D2)
//   • where the inner-record fields sit                   (D3)
//
// There is deliberately NO `run(BandLink)`, no `BandEvent`, no `InputSignal`
// and — per MULTIBAND_PLAN §3.1 — no capability booleans, ever. Declare the
// INPUT signals a device physically emits when that lands (D9); never a
// `supportsX()` claim about our own features.
//
// ponytail: every entry here is a framed WHOOP-family band, because
// [BandProfile]/[GattProfile] cannot yet express anything else — a u8 length,
// no CRC, or three characteristics (change-list D7). This file is the place
// that stops being true in; nothing above it needs to change again.

import 'package:openstrap_protocol/openstrap_protocol.dart';

/// One band the app can discover and connect to.
///
/// The wire format itself stays in `protocol` ([BandProfile] = header length,
/// size-field offset, direction markers; [GattProfile] = the UUID map). This
/// type carries the edge-side facts that live above the codec — discovery and
/// the inner-record field offsets — following the same "it is data, not a
/// branch" pattern rather than inventing a parallel one.
class BandEntry {
  /// Stable identifier. Stamped into `DeviceState.generation` and, downstream,
  /// `device_family` — so it is a storage key: never rename a shipped one.
  final String id;

  /// Human label for logs and (later) the pairing UI.
  final String label;

  /// GATT UUID map for this band, straight from `protocol`.
  final GattProfile gatt;

  /// Frame envelope profile — header length, size-field offset, header CRC.
  final BandProfile wire;

  /// The characteristics a link MUST expose or the connect aborts.
  ///
  /// Defaults to this entry's own four command/notify characteristics, which
  /// is what a WHOOP link genuinely needs. It is a FIELD and not a constant
  /// because demanding four unconditionally is why a second, parallel BLE
  /// stack (`hr_sensor.dart`) had to exist at all: a generic HRS device
  /// exposes one notify characteristic and nothing else.
  final List<String>? _requiredCharacteristics;

  /// Offset of the opcode byte within the inner payload
  /// (`[pktType, seq, opcode, body…]`).
  final int innerOpcodeOffset;

  /// Offset of the record-version byte within a historical record's inner
  /// payload.
  final int innerVersionOffset;

  /// Offset of the u32-LE record counter within a historical record's inner
  /// payload.
  final int innerCounterOffset;

  const BandEntry({
    required this.id,
    required this.label,
    required this.gatt,
    required this.wire,
    required this.innerOpcodeOffset,
    required this.innerVersionOffset,
    required this.innerCounterOffset,
    List<String>? requiredCharacteristics,
  }) : _requiredCharacteristics = requiredCharacteristics;

  /// Service UUID to advertise-filter the scan on.
  String get service => gatt.service;

  /// 32-bit prefix used to match this band's service from a scan result or a
  /// discovered service list (case-insensitive `startsWith`).
  String get servicePrefix => gatt.servicePrefix;

  List<String> get requiredCharacteristics =>
      _requiredCharacteristics ??
      <String>[gatt.cmdTo, gatt.cmdFrom, gatt.events, gatt.data];

  /// Index of the opcode byte in a fully-framed packet.
  int get frameOpcodeIndex => wire.headerLen + innerOpcodeOffset;
}

/// WHOOP 4 ("Harvard", 6108xxxx).
const BandEntry kWhoopGen4 = BandEntry(
  id: 'gen4',
  label: 'WHOOP 4',
  gatt: GattProfile.gen4,
  wire: BandProfile.gen4,
  innerOpcodeOffset: 2,
  innerVersionOffset: 1,
  innerCounterOffset: 3,
);

/// WHOOP 5 / MG ("fd4b"). Same inner payload layout as gen4 — only the
/// envelope differs, which is exactly what [BandProfile] models.
const BandEntry kWhoopGen5 = BandEntry(
  id: 'gen5',
  label: 'WHOOP 5',
  gatt: GattProfile.gen5,
  wire: BandProfile.gen5,
  innerOpcodeOffset: 2,
  innerVersionOffset: 1,
  innerCounterOffset: 3,
);

/// Every band this build can see. Order is match order during discovery.
const List<BandEntry> kBandRegistry = <BandEntry>[kWhoopGen4, kWhoopGen5];

/// The entry speaking [wire]. Used by the engine's test seam, which is handed
/// a [BandProfile] rather than an entry.
BandEntry bandEntryFor(BandProfile wire) =>
    kBandRegistry.firstWhere((e) => e.wire.type == wire.type);
