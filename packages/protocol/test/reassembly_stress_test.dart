// Feed independently authored synthetic command-response frames (HELLO + GET_ADVERTISING_NAME)
// through the actual FrameReassembler + decodeFrame under adversarial BLE
// chunking — whole-frame, one giant chunk, byte-by-byte, and split-across-frames.
// Reproduces the "first read correct, second read garbled (esp. name)" report if
// the reassembler carries state between reads.

import 'package:whoop_protocol/whoop_protocol.dart';
import 'package:test/test.dart';
import 'support/synthetic_packet.dart';

// Independently CRC-encoded fictional replies, in HELLO/HELLO/name/HELLO order.
final frames = <String>[
  syntheticHex('hello-frame-1'),
  syntheticHex('hello-frame-2'),
  syntheticHex('name-frame'),
  syntheticHex('hello-frame-4'),
];
const expectedSerial = 'TEST00001';
const expectedName = 'Sample WHOOP';

// Run all frame bytes through one reassembler using [chunker] to split the byte
// stream, then decode every valid frame and collect serials + names.
({List<String> serials, List<String> names}) run(
    List<List<int>> Function(List<int>) chunker) {
  final asm = FrameReassembler();
  final serials = <String>[];
  final names = <String>[];
  final stream = <int>[];
  for (final f in frames) {
    stream.addAll(hexToBytes(f));
  }
  for (final chunk in chunker(stream)) {
    for (final frame in asm.feed(chunk)) {
      if (!frame.valid) continue;
      final d = decodeFrame(frame);
      if (d.kind != 'cmd_response') continue;
      final hello = d.fields['hello'];
      if (hello is HelloInfo && hello.serial != null)
        serials.add(hello.serial!);
      final nm = d.fields['strap_name'];
      if (nm is String && nm.isNotEmpty) names.add(nm);
    }
  }
  return (serials: serials, names: names);
}

void main() {
  final chunkers = <String, List<List<int>> Function(List<int>)>{
    'one big chunk': (s) => [s],
    'byte by byte': (s) => [
          for (final b in s) [b]
        ],
    'mtu 20': (s) => [
          for (var i = 0; i < s.length; i += 20)
            s.sublist(i, (i + 20).clamp(0, s.length))
        ],
    'mtu 23 (split frames)': (s) => [
          for (var i = 0; i < s.length; i += 23)
            s.sublist(i, (i + 23).clamp(0, s.length))
        ],
  };

  chunkers.forEach((name, chunker) {
    test('every read is clean under chunking: $name', () {
      final r = run(chunker);
      expect(r.serials.length, greaterThanOrEqualTo(3),
          reason: 'all 3 HELLOs should decode');
      for (final s in r.serials) {
        expect(s, expectedSerial,
            reason: 'serial must never garble on a repeat');
      }
      expect(r.names, isNotEmpty);
      for (final n in r.names) {
        expect(n, expectedName, reason: 'name must never garble on a repeat');
      }
    });
  });
}
