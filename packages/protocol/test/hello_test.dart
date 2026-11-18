// Authored HELLO identity/commit boundaries. Original captured examples are
// retained locally; synthetic cases do not prove observations on hardware.
import 'dart:typed_data';
import 'package:whoop_protocol/whoop_protocol.dart';
import 'package:test/test.dart';
import 'support/synthetic_packet.dart';

void main() {
  // Volatile sequence/header bytes cannot displace the fixed identity token.
  final helloBodies = [
    for (final seq in [1, 2, 7])
      Uint8List.fromList(syntheticPacket('hello-payload'))
        ..[0] = seq
        ..[12] = 0x50
        ..[13] = 0x46,
  ];

  test('serial is read at the fixed offset for each authored header', () {
    for (final body in helloBodies) {
      final h = parseHello(body);
      expect(h.serial, 'TEST00001',
          reason: 'serial must be the offset-16 NUL-terminated token');
    }
  });

  test('charging and wristOn are absent, not a fabricated false', () {
    // payload[5] is the zero high byte of the battery u32 and payload[116] sits
    // in the all-zero tail, so both used to report a confident "no" on every
    // earlier builds — wristOn then overwrote a true from the WRIST_ON event.
    for (final body in helloBodies) {
      final h = parseHello(body);
      expect(h.charging, isNull);
      expect(h.wristOn, isNull);
      expect(h.batteryPct, isNotNull, reason: 'battery still decodes');
    }
  });

  test('commit hex follows the serial', () {
    final h = parseHello(helloBodies.first);
    expect(h.commit, isNotNull);
    expect(h.commit!.startsWith('aaaaaaaa'), isTrue);
    expect(h.commit!.length >= 16, isTrue);
  });

  test('no serial = no junk (short HELLO body returns null, never "?*")', () {
    final h = parseHello(Uint8List(12));
    expect(h.serial, isNull);
  });

  test('renamed-band advertised name is irrelevant to serial parsing', () {
    // Sanity: a body whose header bytes happen to be printable must NOT be
    // mistaken for the serial — only the offset-16 token counts.
    final h = parseHello(helloBodies[1]); // header has "PF" @12
    expect(h.serial, 'TEST00001');
  });

  group('advertising name decode', () {
    // inner = [0x24, seq=0x65, 0x4C(opcode)] + body
    String? name(String bodyHex) {
      final inner = hexToBytes('24654c$bodyHex');
      return parseCommandResponse(inner)?.decoded['strap_name'] as String?;
    }

    test('independent name frame decodes its fictional label', () {
      final frame = parseFrame(syntheticPacket('name-frame'))!;
      expect(parseCommandResponse(frame.inner)!.decoded['strap_name'],
          'Sample WHOOP');
    });

    test('no NUL terminator + trailing high bytes → no junk', () {
      // header + len=05 + "PROBE" + high bytes (no NUL). Bounded by len; high
      // bytes dropped → must not leak "?*".
      expect(name('0101010105' '50524f4245' 'fffe2a3f'), 'PROBE');
    });

    test('embedded high byte inside name is dropped, not rendered as "?"', () {
      // len=06, name bytes "AB"+0xFF+"CDE" → printable-only keeps "ABCDE".
      expect(name('0101010106' '4142ff434445' '00'), 'ABCDE');
    });
  });
}
