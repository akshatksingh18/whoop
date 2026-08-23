// The iOS AccessorySetupKit block in Info.plist is DERIVED from kBandRegistry.
//
// This is the enforcement half of tool/gen_ios_ask_plist.dart: `flutter test`
// runs on every PR, so a band added to the registry and forgotten in the plist
// fails CI. It has to fail loudly, because the symptom otherwise is invisible —
// on iOS 18+ the ASK picker is the pairing path, so an undeclared service just
// means that band never appears in the picker.
//
// Same shape as telemetry_consent_default_test.dart, which already asserts
// platform config from Dart.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ble/adapters/_registry.dart';

import '../tool/gen_ios_ask_plist.dart';

void main() {
  final plist = File(kPlistPath).readAsStringSync();

  test('Info.plist ASK block is in sync with kBandRegistry', () {
    expect(
      applyBlocks(plist, kBandRegistry),
      plist,
      reason: 'stale — run `dart run tool/gen_ios_ask_plist.dart`',
    );
  });

  test('every registry service is declared, uppercased', () {
    for (final e in kBandRegistry) {
      expect(plist, contains('<string>${e.service.toUpperCase()}</string>'));
    }
  });

  test('AccessorySetup.swift keeps no second copy of the UUIDs', () {
    // The Swift reads NSAccessorySetupBluetoothServices at runtime. A literal
    // back in the source is the drift this whole thing exists to prevent.
    final swift =
        File('ios/Runner/AccessorySetup.swift').readAsStringSync().toLowerCase();
    for (final e in kBandRegistry) {
      expect(swift, isNot(contains(e.service.toLowerCase())));
    }
  });
}
