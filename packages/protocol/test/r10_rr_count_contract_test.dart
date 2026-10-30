// Authored bytes: the R10 slot contract is independent of the four-slot forms.
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:whoop_protocol/whoop_protocol.dart' as p;

Uint8List authoredR10(int count, {int length = 1920, List<int>? values}) {
  final b = Uint8List(length);
  b[0] = p.PacketType.historicalData;
  b[1] = 10;
  final v = ByteData.sublistView(b)
    ..setUint32(3, 7, Endian.little)
    ..setUint32(7, 1700000000, Endian.little);
  b[17] = 60;
  if (length > 18) b[18] = count;
  for (var i = 0; i < 8 && 19 + 2 * i + 2 <= length; i++) {
    v.setInt16(19 + 2 * i, values?[i] ?? 800 + i, Endian.little);
  }
  return b;
}

String hex(Uint8List b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  for (var count = 0; count <= 8; count++) {
    test('R10 count $count agrees across historical and realtime decoding', () {
      final b = authoredR10(count);
      final historical = p.parseR10Lite(b)!;
      final expected = [for (var i = 0; i < count; i++) 800 + i];
      expect(historical.rrIntervalsMs, expected);
      expect(p.realtimeRr(hex(b))?.rrMs ?? [], expected);
      expect(historical.tsEpoch, 1700000000);
      expect(historical.counter, 7);
      expect(historical.hr, 60);
    });
  }
  for (final count in [9, 16, 255]) {
    test('R10 count $count refuses the complete untrusted beat block', () {
      final b = authoredR10(count);
      expect(p.parseR10Lite(b)!.rrIntervalsMs, isEmpty);
      expect(p.realtimeRr(hex(b)), isNull);
      expect(p.parseR10Lite(b)!.hr, 60);
    });
  }
  for (final length in [18, 19, 20, 21, 22, 33, 34, 35]) {
    test('R10 length $length only reads complete declared slots', () {
      final b = authoredR10(8, length: length);
      final n = ((length - 19) ~/ 2).clamp(0, 8);
      final expected = [for (var i = 0; i < n; i++) 800 + i];
      expect(p.parseR10Lite(b)!.rrIntervalsMs, expected);
      expect(p.realtimeRr(hex(b))?.rrMs ?? [], expected);
    });
  }
  test('R10 retains the existing signed plausible-value boundaries', () {
    final b = authoredR10(8, values: [199, 200, 2500, 2501, -1, 800, 0, 900]);
    expect(p.parseR10Lite(b)!.rrIntervalsMs, [200, 2500, 800, 900]);
    expect(p.realtimeRr(hex(b))!.rrMs, [200, 2500, 800, 900]);
  });
  test('R10 never consumes valid-looking slots beyond the declared count', () {
    final b = authoredR10(4);
    expect(p.parseR10Lite(b)!.rrIntervalsMs, [800, 801, 802, 803]);
  });
  for (final revision in [12, 24]) {
    test('revision $revision keeps the independent four-slot limit', () {
      for (final count in [4, 5]) {
        final b = authoredR10(count, length: 89)..[1] = revision;
        final decoded = p.parseR24(b)!;
        expect(
            decoded.rrIntervalsMs, count == 4 ? [800, 801, 802, 803] : isEmpty);
      }
    });
  }
  test('compact realtime retains four slots before its wearing byte', () {
    final b = Uint8List(20)..[0] = 0x28;
    final v = ByteData.sublistView(b)..setUint32(2, 1700000000, Endian.little);
    b[9] = 4;
    b[18] = 1;
    for (var i = 0; i < 4; i++) {
      v.setInt16(10 + 2 * i, 800 + i, Endian.little);
    }
    expect(p.realtimeRr(hex(b))!.rrMs, [800, 801, 802, 803]);
    b[9] = 5;
    expect(p.realtimeRr(hex(b)), isNull);
  });
  test('shared live frame DTO retains all eight accepted R10 intervals', () {
    final decoded =
        p.decodeFrame(p.Frame(authoredR10(8, length: 35), true, true));
    expect(decoded.kind, 'realtime_hr');
    expect(decoded.fields['rr_ms'], [800, 801, 802, 803, 804, 805, 806, 807]);
    expect(decoded.fields['ts_epoch'], 1700000000);
    expect(decoded.fields['hr'], 60);
    expect(decoded.fields['wearing'], true);
  });
}
