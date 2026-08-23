// The real [BandLink]: `flutter_blue_plus` on one side, an adapter on the
// other.
//
// This file is HOST PLUMBING that happens to live in `adapters/` because
// MULTIBAND_PLAN §3.6 makes this directory the only place `protocol` may be
// imported, and the dangerous-opcode block below needs protocol's opcode
// tables. A contributor writing an adapter reads `adapter.dart` and their own
// `<id>.dart` and never this.
//
// It deliberately does NOT do: discovery, connect, bond, MTU negotiation,
// connection priority, CoreBluetooth restoration, AccessorySetupKit
// provisioning, or the process-wide band lock. Those are per-PLATFORM and
// per-APP concerns owned above the seam; a link is handed the services of an
// already-connected peripheral and does nothing but move bytes.

import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:openstrap_protocol/openstrap_protocol.dart';

import '_registry.dart';
import 'adapter.dart';

/// A [BandLink] over an already-connected, already-discovered peripheral.
class GattBandLink implements BandLink {
  /// Which band this is, so [write] knows where the opcode byte sits. A band
  /// whose entry gets [BandEntry.frameOpcodeIndex] wrong reads the wrong byte
  /// and the dangerous-opcode block stops protecting it.
  final BandEntry entry;

  /// The peripheral's discovered services. Characteristics are matched on a
  /// 32-bit prefix, the same way `ble_engine` matches them, because the OS
  /// hands back the 16-bit shorthand on some platforms and the full 128-bit
  /// form on others.
  final List<BluetoothService> services;

  final void Function(String message) onLog;

  GattBandLink({
    required this.entry,
    required this.services,
    required this.onLog,
  });

  // Same numbers as the engine's, and for the same reason: an untimed GATT op
  // on a wedged stack hangs the session forever with no failure state to
  // recover from.
  static const Duration _notifyTimeout = Duration(seconds: 15);
  static const Duration _writeTimeout = Duration(seconds: 8);

  /// Which of [uuids] this peripheral does NOT expose. The host aborts the
  /// connect when it is non-empty — WHICH characteristics a link must have is
  /// registry data ([BandEntry.requiredCharacteristics]), and demanding four
  /// unconditionally is why a second parallel BLE stack once had to exist.
  List<String> missingCharacteristics(Iterable<String> uuids) =>
      [for (final u in uuids) if (_find(u) == null) u];

  BluetoothCharacteristic? _find(String uuid) {
    final prefix = uuid.substring(0, 8).toLowerCase();
    for (final s in services) {
      for (final c in s.characteristics) {
        if (c.uuid.str.toLowerCase().startsWith(prefix)) return c;
      }
    }
    return null;
  }

  @override
  Stream<(int, List<int>)> notify(String characteristicUuid) async* {
    final c = _find(characteristicUuid);
    if (c == null) {
      log('notify: no characteristic ${characteristicUuid.substring(0, 8)} on '
          'this peripheral.');
      return;
    }
    await c.setNotifyValue(true).timeout(_notifyTimeout);
    // The arrival second is stamped HERE, at the edge of the radio, and not
    // inside the adapter — it is the closest we can get to when the
    // notification actually landed, and it keeps `DateTime.now()` out of
    // adapter code so a fixture can replay one deterministically.
    yield* c.onValueReceived.map(
      (v) => (DateTime.now().millisecondsSinceEpoch ~/ 1000, v),
    );
  }

  @override
  Future<bool> write(String characteristicUuid, List<int> value) async {
    // THE DANGEROUS-OPCODE BLOCK, at the one place every adapter's writes
    // funnel through. It is here rather than in adapter code precisely so no
    // adapter — including one a contributor wrote — can reach FORCE_TRIM
    // (whose full-erase form is two 0xFEFEFEFE args), REBOOT or POWER_CYCLE by
    // any path. There is no opt-out parameter: the one audited exception in
    // this app (gen5 deep buffers) writes through `ble_engine._write`, which
    // keeps its own carve-out, single and reviewed.
    final opcode = _opcodeOf(value);
    if (opcode != null &&
        (dangerousCmds.contains(opcode) || OpcodeSafety.isDestructive(opcode))) {
      log('REFUSED dangerous opcode 0x${opcode.toRadixString(16)} at BandLink');
      return false;
    }
    final c = _find(characteristicUuid);
    if (c == null) {
      log('write: no characteristic ${characteristicUuid.substring(0, 8)} on '
          'this peripheral.');
      return false;
    }
    try {
      // withoutResponse: false is what triggers bonding AND what gets commands
      // acknowledged; a without-response write is silently dropped by the band.
      // allowLongWrite covers the one frame that exceeds the 20-byte ATT limit
      // of a default MTU (the rich SET_ALARM_TIME), and is a no-op below it.
      await c
          .write(value, withoutResponse: false, allowLongWrite: true)
          .timeout(_writeTimeout);
      return true;
    } on TimeoutException {
      log('write timeout: no GATT response in ${_writeTimeout.inSeconds}s.');
      return false;
    } catch (e) {
      log('write error: $e');
      return false;
    }
  }

  /// The command opcode carried by an already-framed outbound write, or null
  /// when this band has no envelope (nothing to read an opcode out of) or the
  /// frame is too short to carry one.
  int? _opcodeOf(List<int> raw) {
    if (!entry.isFramed) return null;
    final i = entry.frameOpcodeIndex;
    return i < raw.length ? raw[i] : null;
  }

  @override
  void log(String message) => onLog(message);
}
