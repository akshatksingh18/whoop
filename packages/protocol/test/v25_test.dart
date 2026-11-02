import 'package:whoop_protocol/whoop_protocol.dart';
import 'package:test/test.dart';
import 'support/synthetic_packet.dart';

String _innerHex(String framed) => framed.substring(8);

void main() {
  group('WHOOP 4 historical v25 auto-routing', () {
    final records = [
      for (var i = 0; i < 3; i++) syntheticHex('g4-v25-frame-$i')
    ];

    test('parseR24 auto-routes v25 and decodes the unix second only', () {
      final parsed = [
        for (final hex in records) parseR24(hexToBytes(_innerHex(hex)))
      ];
      expect(parsed.every((r) => r != null), isTrue);
      final rows = parsed.cast<R24>();
      expect(rows.map((r) => r.histVersion).toSet(), {25});
      expect(rows[0].tsEpoch, 1609459200);
      expect(rows[1].tsEpoch, rows[0].tsEpoch + 1);
      expect(rows[2].tsEpoch, rows[0].tsEpoch + 2);
      for (final r in rows) {
        expect(r.hr, 0);
        expect(r.rrIntervalsMs, isEmpty);
        expect(r.spo2RedRaw, isNull);
        expect(r.spo2IrRaw, isNull);
        // Synthetic payload bytes do not become HR or acceleration. Preserve
        // absence rather than interpreting a waveform as a motion reading.
        expect(r.accelG, isEmpty);
      }
    });

    test('the waveform payload and its timestamp are untouched', () {
      final r = parseR24(hexToBytes(_innerHex(records[0])))!;
      // rawTail is inner[13:], i.e. the PPG burst itself. Compare the WHOLE
      // slice, not `endsWith` — that also passes if the decoder silently drops
      // leading waveform bytes, which is the failure worth catching.
      expect(r.rawTail, isNotEmpty);
      expect(r.rawTail, _innerHex(records[0]).substring(13 * 2));
    });

    test('decodeRecord surfaces v25 timestamps', () {
      final decoded = [for (final hex in records) decodeRecord(_innerHex(hex))];
      expect(decoded.every((r) => r != null), isTrue);
      expect(decoded[0]!.recType, 25);
      expect(decoded[0]!.ts, 1609459200);
      expect(decoded[1]!.ts, decoded[0]!.ts + 1);
      expect(decoded[2]!.ts, decoded[0]!.ts + 2);
    });
  });
}
