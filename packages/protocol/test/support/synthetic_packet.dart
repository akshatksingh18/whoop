import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

// Authored by the independent Python fixture encoder, never from a recording.
final _packets = jsonDecode(([
  File('test/fixtures/synthetic_packets.json'),
  File('packages/protocol/test/fixtures/synthetic_packets.json'),
].firstWhere((file) => file.existsSync())).readAsStringSync())
    as Map<String, dynamic>;

String syntheticHex(String name) => _packets[name] as String;

Uint8List syntheticPacket(String name) {
  final hex = syntheticHex(name);
  return Uint8List.fromList([
    for (var i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ]);
}
