// RR observations can exist between sparse 1 Hz samples. Exercise the real
// half-open slicing path without manufacturing HR, movement or optical values.
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/substrate.dart';
import 'build90_decode_integrity_test.dart' show record, hex;

void main() {
  Uint8List live(int ts, List<int> rr) {
    final bytes = Uint8List(19)..[0] = 0x28;
    bytes[1] = 1;
    bytes[8] = 75;
    bytes[9] = rr.length;
    bytes[18] = 1;
    final v = ByteData.sublistView(bytes)..setUint32(2, ts, Endian.little);
    for (var i = 0; i < rr.length; i++) {
      v.setInt16(10 + 2 * i, rr[i], Endian.little);
    }
    return bytes;
  }

  const ts = 1700000000;
  test(
    'COV-48 loose live beats sort without manufacturing one-hertz sensors',
    () {
      final sub = decodeSubstrate([
        hex(live(ts + 2, [900, 910])),
        hex(live(ts, [700, 710])),
        hex(live(ts + 1, [0, 100, 800, 3000])),
      ]);
      expect(sub.tsSec, isEmpty);
      expect(sub.hr, isEmpty);
      expect(sub.ax, isEmpty);
      expect(sub.spo2Red, isEmpty);
      expect(sub.deviceFamily, isNull);
      expect(sub.rrTsMs, [
        ts * 1000.0,
        ts * 1000.0,
        (ts + 1) * 1000.0,
        (ts + 2) * 1000.0,
        (ts + 2) * 1000.0,
      ]);
      expect(sub.rrMs, [700, 710, 800, 900, 910]);
      final restored = Substrate.fromJson(sub.toJson());
      expect(restored.rrTsMs, sub.rrTsMs);
      expect(restored.rrMs, sub.rrMs);
      expect(restored.isEmpty, true);
    },
  );
  test(
    'COV-48 raw replay interleaves live beats with measured historical anchors',
    () {
      final historical = record(24, 2);
      ByteData.sublistView(historical)
        ..setUint32(7, ts + 2, Endian.little)
        ..setUint16(11, 16384, Endian.little);
      final hexes = [
        hex(live(ts + 3, [920])),
        hex(historical),
        hex(live(ts + 1, [720])),
      ];
      final before = List.of(hexes);
      final sub = decodeSubstrate(hexes);
      expect(sub.tsSec, [ts + 2]);
      expect(sub.hr, [60]);
      expect(sub.rrMs, [720, 800, 801, 920]);
      expect(sub.rrTsMs, [
        (ts + 1) * 1000.0,
        (ts + 2) * 1000.0 + 500 - 801,
        (ts + 2) * 1000.0 + 500,
        (ts + 3) * 1000.0,
      ]);
      final slice = sub.slice(ts + 2, ts + 3);
      expect(slice.tsSec, [ts + 2]);
      expect(slice.rrMs, [801]);
      expect(slice.rrTsMs, [(ts + 2) * 1000.0 + 500]);
      expect(hexes, before);
      expect(decodeSubstrate(hexes.reversed.toList()).toJson(), sub.toJson());
    },
  );
  Substrate source() => Substrate(
    tsSec: [100, 200],
    hr: [60, 70],
    ax: [0, 0],
    ay: [0, 0],
    az: [1, 1],
    spo2Red: [null, null],
    spo2Ir: [null, null],
    skinTemp: [null, null],
    skinContact: [null, null],
    rrTsMs: [149999, 150000, 159999, 160000],
    rrMs: [700, 710, 720, 730],
    deviceFamily: 'gen4',
  );
  test('a 1 Hz gap keeps only RR endpoints inside the half-open window', () {
    final original = source();
    final gap = original.slice(150, 160);
    expect(gap.isEmpty, true);
    expect(gap.firstTs, isNull);
    expect(gap.lastTs, isNull);
    expect(gap.hr, isEmpty);
    expect(gap.ax, isEmpty);
    expect(gap.spo2Red, isEmpty);
    expect(gap.deviceFamily, 'gen4');
    expect(gap.rrTsMs, [150000, 159999]);
    expect(gap.rrMs, [710, 720]);
    expect(original.rrMs, [700, 710, 720, 730]);
    expect(original.firstTs, 100);
    expect(original.lastTs, 200);
  });
  test('an empty gap does not substitute one of its neighboring samples', () {
    final gap = source().slice(170, 180);
    expect(gap.length, 0);
    expect(gap.rrMs, isEmpty);
    expect(gap.rrTsMs, isEmpty);
    expect(gap.deviceFamily, 'gen4');
  });
  test(
    'the next record and RR endpoint enter only when the window includes them',
    () {
      final slice = source().slice(160, 201);
      expect(slice.tsSec, [200]);
      expect(slice.hr, [70]);
      expect(slice.rrTsMs, [160000]);
      expect(slice.rrMs, [730]);
      expect(slice.spo2Ir, [null]);
      expect(slice.deviceFamily, 'gen4');
    },
  );
}
