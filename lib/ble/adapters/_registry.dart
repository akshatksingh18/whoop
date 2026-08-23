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
// WHAT THE FIRST NON-WHOOP ENTRY PROVED (D10, the `0x180D` strap below).
// The identity half of this type held: id, label, service UUID and
// `requiredCharacteristics` describe a generic heart-rate strap exactly, and
// `requiredCharacteristics` had already been made a field for precisely this.
// Two halves did NOT hold, and both are recorded here rather than papered over:
//
//   1. The WIRE half is WHOOP-shaped by construction. [GattProfile] is six
//      named command/notify characteristics and [BandProfile] is a framed
//      envelope over a CLOSED `DeviceType {gen4, gen5}` enum — neither can
//      express one service with one notify characteristic and no envelope, and
//      `protocol` is SEALED so neither can be widened there. So both are
//      NULLABLE now: null means "not a framed WHOOP-family band", and
//      [isFramed] is the predicate every WHOOP-only consumer filters on.
//   2. There is no SESSION half at all. A [BandEntry] DESCRIBES a band; it
//      cannot DRIVE one. Everything a session does — SET_CLOCK, INIT, the
//      drain, `RecordGate`, the batch ACK, the liveness fuse — is hardcoded in
//      `ble_engine._doConnect`, so a band that does not speak that sequence
//      still needs its own code path (`hrs_link.dart`). That is the gap
//      MULTIBAND_PLAN §3.1's `Stream<BandEvent> run(BandLink)` closes, and
//      until it lands "third registry entry" buys shared IDENTITY, not shared
//      PLUMBING.

import 'package:openstrap_protocol/openstrap_protocol.dart';

/// GATT Heart Rate Service and its Heart Rate Measurement characteristic.
/// Written out in full 128-bit form rather than the 16-bit shorthand: the
/// shorthand's expansion is a platform detail we should not depend on.
const String kHeartRateServiceUuid = '0000180d-0000-1000-8000-00805f9b34fb';
const String kHeartRateMeasurementUuid = '00002a37-0000-1000-8000-00805f9b34fb';

/// What a stored timestamp actually IS for a given band.
///
/// The distinction is load-bearing and it is not cosmetic. A WHOOP record
/// carries the instant the band itself stamped on the reading; a `0x2A37`
/// strap carries beat-to-beat DURATIONS and no clock at all, so the only time
/// we can attach is the moment the notification reached this phone — which
/// BLE delivery jitter and stack batching move by tens of milliseconds.
///
/// RMSSD, pNN50 and everything else computed off the durations stay correct on
/// [arrival]. Lomb-Scargle, `cvhr_per_hour`, `spanSec` and anything else that
/// reads the time AXIS must refuse on it (MULTIBAND_PLAN §3.2, §5.3). This
/// enum is what lets that refusal be code instead of a doc note.
enum TimeAnchor {
  /// The source stamped the reading itself. Every WHOOP record.
  measured,

  /// The instant the sample reached the phone. Approximate, and never to be
  /// written into a column that means "where the beat was".
  arrival,
}

/// One band the app can discover and connect to.
///
/// The wire format itself stays in `protocol` ([BandProfile] = header length,
/// size-field offset, direction markers; [GattProfile] = the UUID map). This
/// type carries the edge-side facts that live above the codec — discovery and
/// the inner-record field offsets — following the same "it is data, not a
/// branch" pattern rather than inventing a parallel one.
class BandEntry {
  /// Stable identifier. Stamped into `DeviceState.generation` and, downstream,
  /// `device_family` and `decoded_*.source` — so it is a storage key: never
  /// rename a shipped one.
  final String id;

  /// Human label for logs and (later) the pairing UI.
  final String label;

  /// GATT UUID map for this band. NULL for a band that is not a WHOOP-family
  /// six-characteristic link — see the header note.
  final GattProfile? gatt;

  /// Frame envelope profile — header length, size-field offset, header CRC.
  /// NULL means this band sends no envelope at all, which is also what
  /// [isFramed] reports and what the offload engine filters on.
  final BandProfile? wire;

  /// What [TimeAnchor] this band's stored timestamps carry.
  final TimeAnchor timeAnchor;

  final String? _service;

  /// The characteristics a link MUST expose or the connect aborts.
  ///
  /// Defaults to this entry's own four command/notify characteristics, which
  /// is what a WHOOP link genuinely needs. It is a FIELD and not a constant
  /// because demanding four unconditionally is why a second, parallel BLE
  /// stack had to exist at all: a generic HRS device exposes one notify
  /// characteristic and nothing else.
  final List<String>? _requiredCharacteristics;

  /// Offset of the opcode byte within the inner payload
  /// (`[pktType, seq, opcode, body…]`). Framed entries only.
  final int innerOpcodeOffset;

  /// Offset of the record-version byte within a historical record's inner
  /// payload. Framed entries only.
  final int innerVersionOffset;

  /// Offset of the u32-LE record counter within a historical record's inner
  /// payload. Framed entries only.
  final int innerCounterOffset;

  /// A framed WHOOP-family band: an envelope, a command characteristic, and a
  /// flash the offload engine trims.
  const BandEntry.framed({
    required this.id,
    required this.label,
    required GattProfile this.gatt,
    required BandProfile this.wire,
    required this.innerOpcodeOffset,
    required this.innerVersionOffset,
    required this.innerCounterOffset,
    List<String>? requiredCharacteristics,
  })  : _requiredCharacteristics = requiredCharacteristics,
        _service = null,
        timeAnchor = TimeAnchor.measured;

  /// A notify-only sensor: one service, one or more notify characteristics, no
  /// envelope, no commands, no stored history to offload.
  ///
  /// The record offsets are -1 on purpose. They describe a position inside a
  /// framed payload this band never sends, and a plausible-looking 2/1/3 would
  /// read the wrong byte in silence — which is the exact failure the registry
  /// exists to prevent. -1 throws.
  const BandEntry.notify({
    required this.id,
    required this.label,
    required String service,
    required List<String> characteristics,
    required this.timeAnchor,
  })  : _service = service,
        _requiredCharacteristics = characteristics,
        gatt = null,
        wire = null,
        innerOpcodeOffset = -1,
        innerVersionOffset = -1,
        innerCounterOffset = -1;

  /// True when this band speaks a framed envelope, i.e. the offload engine can
  /// drive it. The one predicate every WHOOP-only consumer filters on.
  bool get isFramed => wire != null;

  /// Service UUID to advertise-filter the scan on.
  String get service => gatt?.service ?? _service!;

  /// 32-bit prefix used to match this band's service from a scan result or a
  /// discovered service list (case-insensitive `startsWith`).
  String get servicePrefix => service.substring(0, 8);

  List<String> get requiredCharacteristics =>
      _requiredCharacteristics ??
      <String>[gatt!.cmdTo, gatt!.cmdFrom, gatt!.events, gatt!.data];

  /// Index of the opcode byte in a fully-framed packet. Framed entries only —
  /// this is the byte the dangerous-opcode block reads, and a band with no
  /// envelope has no such byte to read.
  int get frameOpcodeIndex => wire!.headerLen + innerOpcodeOffset;
}

/// WHOOP 4 ("Harvard", 6108xxxx).
const BandEntry kWhoopGen4 = BandEntry.framed(
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
const BandEntry kWhoopGen5 = BandEntry.framed(
  id: 'gen5',
  label: 'WHOOP 5',
  gatt: GattProfile.gen5,
  wire: BandProfile.gen5,
  innerOpcodeOffset: 2,
  innerVersionOffset: 1,
  innerCounterOffset: 3,
);

/// Any standard Bluetooth heart-rate sensor — the SIG's Heart Rate Service.
/// Chest straps, optical armbands, some rings, and a WHOOP in broadcast mode.
///
/// EXPERIMENTAL and it stays that way: nobody on this project owns one yet, so
/// not a byte of this path has met hardware (ASSUMPTIONS R6). It is also not
/// yet REACHABLE — there is no pairing screen, so nothing writes the `device`
/// row `HrsLink.arm` reads, and arming is a no-op exactly as it was before.
const BandEntry kBleHrs = BandEntry.notify(
  id: 'ble_hrs',
  label: 'Bluetooth heart rate sensor',
  service: kHeartRateServiceUuid,
  characteristics: <String>[kHeartRateMeasurementUuid],
  // The strap reports durations and has no clock. See [TimeAnchor].
  timeAnchor: TimeAnchor.arrival,
);

/// Every band this build can see. Order is match order during discovery.
const List<BandEntry> kBandRegistry = <BandEntry>[
  kWhoopGen4,
  kWhoopGen5,
  kBleHrs,
];

/// The bands the OFFLOAD ENGINE can drive, and the bands iOS provisions
/// through the AccessorySetupKit picker — the same set, for the same reason:
/// both are about the primary band that holds a link, keeps a flash and gets
/// trimmed. A notify-only sensor is connected straight from its stored remote
/// id during a workout, so putting it in the ASK plist would only add chest
/// straps to the WHOOP pairing picker.
final List<BandEntry> kFramedBands =
    kBandRegistry.where((e) => e.isFramed).toList(growable: false);

/// The entry speaking [wire]. Used by the engine's test seam, which is handed
/// a [BandProfile] rather than an entry.
BandEntry bandEntryFor(BandProfile wire) =>
    kBandRegistry.firstWhere((e) => e.wire?.type == wire.type);
