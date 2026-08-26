// Info.plist's AccessorySetupKit block is DERIVED from the band registry —
// from [kFramedBands], not the whole of it. ASK provisions the PRIMARY band,
// the one that holds a link and gets its flash trimmed. A notify-only sensor
// is connected straight from its stored remote id during a workout and needs
// no ASK descriptor, so declaring its service here would only put chest straps
// in the WHOOP pairing picker.
//
// Apple requires every criterion an ASK discovery descriptor matches on to be
// declared in Info.plist under NSAccessorySetupBluetoothServices. On iOS 18+
// that picker IS our pairing path, so a band missing from that array cannot be
// paired on iPhone at all — and per TN3115 note 5 it also gives up the iOS 26
// relaunch-after-force-quit / Control-Centre-toggle case. A hand-maintained
// second copy of `kBandRegistry` is exactly the drift nobody notices until a
// user's band silently stops pairing.
//
//   dart run tool/gen_ios_ask_plist.dart           # rewrite the block
//   dart run tool/gen_ios_ask_plist.dart --check   # verify, exit 1 on drift
//
// The check is also a unit test (`test/ios_ask_plist_test.dart`), which is
// what actually enforces it: `flutter test` runs on every PR, so drift fails
// CI loudly. Deliberately NOT an Xcode script phase — the registry is a Dart
// `const`, so only the Dart VM can evaluate it, and a phase that regenerates a
// tracked source file mid-build is the fail-open mode we are trying to avoid
// (a stale plist that still builds).
//
// Both keys must already exist in the plist; this rewrites their bodies and
// never invents structure.

import 'dart:io';

import 'package:openstrap_edge/ble/adapters/_registry.dart';

const String kPlistPath = 'ios/Runner/Info.plist';

/// Apple's required list of service UUIDs the ASK picker may match on.
const String kServicesKey = 'NSAccessorySetupBluetoothServices';

/// Our own key: service UUID -> picker row label. Cosmetic only — the Swift
/// falls back to a generic name — so a stale label degrades the picker text
/// rather than hiding a band.
const String kLabelsKey = 'OSBandLabels';

/// Extra ASK match criterion NOT tied to any one [BandEntry]: the 16-bit SIG
/// member UUID `0xFD4B`, a fallback for gen5's 128-bit vendor UUID being
/// hidden in the scan-response overflow area (see AccessorySetup.swift's
/// `whoopMemberUUID16`). Apple requires every descriptor criterion used in
/// Swift to be declared here too, so this stays a fixed, always-appended
/// tail rather than something a band entry could ever express — it is a
/// platform-encoding fact, not a band.
const String kFd4bMemberUuid16 = 'FD4B';

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

String _servicesBody(List<BandEntry> registry) => registry
        .map((e) => '\t\t<string>${e.service.toUpperCase()}</string>\n')
        .join() +
    '\t\t<!-- 16-bit SIG member UUID. Distinct from the 128-bit vendor '
        'service\n'
        '\t\t     above, and NOT the Bluetooth-base expansion\n'
        '\t\t     0000FD4B-0000-1000-8000-00805F9B34FB (no band advertises '
        'that).\n'
        '\t\t     A 128-bit UUID often does not fit the 31-byte '
        'advertisement. -->\n'
        '\t\t<string>$kFd4bMemberUuid16</string>\n';

String _labelsBody(List<BandEntry> registry) => registry
    .map((e) => '\t\t<key>${e.service.toUpperCase()}</key>\n'
        '\t\t<string>${_esc(e.label)}</string>\n')
    .join();

String _replaceBody(String plist, String key, String tag, String body) {
  final re = RegExp(
    '(\\t<key>$key</key>\\n\\t<$tag>\\n).*?(\\t</$tag>\\n)',
    dotAll: true,
  );
  final m = re.firstMatch(plist);
  if (m == null) {
    throw StateError(
        '$kPlistPath has no <$tag> block for <key>$key</key> — add one '
        '(with at least one child) before running this.');
  }
  return plist.replaceRange(m.start, m.end, '${m[1]}$body${m[2]}');
}

/// [plist] with both generated blocks rebuilt from [registry].
String applyBlocks(String plist, List<BandEntry> registry) {
  var out = _replaceBody(plist, kServicesKey, 'array', _servicesBody(registry));
  out = _replaceBody(out, kLabelsKey, 'dict', _labelsBody(registry));
  return out;
}

void main(List<String> args) {
  final file = File(kPlistPath);
  if (!file.existsSync()) {
    stderr.writeln('$kPlistPath not found — run from the edge/ package root.');
    exit(2);
  }
  final current = file.readAsStringSync();
  final wanted = applyBlocks(current, kFramedBands);
  if (current == wanted) {
    stdout.writeln('$kPlistPath is in sync with kFramedBands.');
    return;
  }
  if (args.contains('--check')) {
    stderr.writeln('$kPlistPath is STALE. Expected:\n'
        '\t<key>$kServicesKey</key>\n\t<array>\n${_servicesBody(kFramedBands)}'
        '\t</array>\n'
        '\t<key>$kLabelsKey</key>\n\t<dict>\n${_labelsBody(kFramedBands)}'
        '\t</dict>\n'
        'Run: dart run tool/gen_ios_ask_plist.dart');
    exit(1);
  }
  file.writeAsStringSync(wanted);
  stdout.writeln('$kPlistPath updated from kFramedBands '
      '(${kFramedBands.length} band(s)).');
}
