// Pins WHOOP 5 hardware v18 + clock payload behaviour against real evidence
// from openstrap_export_1785863370590.db / openstrap_sync.log (fw 50.40.1.0).

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ble/ble_engine.dart';
import 'package:openstrap_protocol/openstrap_protocol.dart';

Uint8List hex(String s) {
  final clean = s.replaceAll(' ', '');
  final out = Uint8List(clean.length ~/ 2);
  for (int i = 0; i < out.length; i++) {
    out[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

void main() {
  group('gen5 clock payloads — fw 50.40.1.0 Invalid revision evidence', () {
    test('SET_CLOCK prepends revision1 before the 8-byte time', () {
      final p = gen5SetClockPayload(sec: 1785710096, subsec: 16351);
      expect(p, hasLength(9));
      expect(p[0], revision1);
      // Seconds LE start at body[1] — not body[0] (that was read as "revision").
      expect(p[1], 1785710096 & 0xff);
      expect(p[2], (1785710096 >> 8) & 0xff);
      expect(p[3], (1785710096 >> 16) & 0xff);
      expect(p[4], (1785710096 >> 24) & 0xff);
      expect(p[5], 16351 & 0xff);
      expect(p[6], (16351 >> 8) & 0xff);
      expect(p[7], 0);
      expect(p[8], 0);
    });

    test('GET_CLOCK sends revision1 (empty body logged revision 0)', () {
      expect(gen5GetClockPayload(), [revision1]);
    });
  });

  group('gen5V18UnixFromInner — no fabricated misaligned unix', () {
    // Real archive blob #1: unix@7 is garbage; offset-6 is a year-plausible
    // false positive that is NOT monotonic with recordIndex.
    final inner = hex(
      '2f1280540df701737c6a915c2f004d0000000000000000000021fb608c4d0000'
      'c330ebf63ecd4ad43f854b653e5298863da3017400000000000000000039014401'
      '040d6003010c020c3100000000000000000000000000000000000000000000011f'
      'bed68080000000a80372c0000000',
    );

    test('strict protocol decode returns null (gravity/dyn gate)', () {
      expect(parseGen5Historical(inner), isNull);
    });

    test('unix@7 garbage → abstain (do not invent offset-6 time)', () {
      expect(gen5V18UnixFromInner(inner), isNull);
      expect(sampleFromGen5V18Lenient(inner), isNull);
      expect(decodeGen5HistoricalSample(inner), isNull);
    });
  });

  group('sampleFromGen5V18Lenient — gravity-only abstention needs good unix', () {
    // Synthetic: valid shared header unix@7 + HR, gravity out of gate range.
    // Layout matches Gen5HistoricalHeader + HR @14.
    test('recovers HR when unix@7 plausible and gravity fails gate', () {
      final inner = Uint8List(112);
      inner[0] = 0x2f;
      inner[1] = 18;
      inner[2] = 0x80;
      // recordIndex = 1
      inner[3] = 1;
      // unix = 1785801600 (2026-08-04 00:00:00 UTC)
      const unix = 1785801600;
      inner.buffer.asByteData().setUint32(7, unix, Endian.little);
      inner[14] = 72; // HR
      inner[15] = 0; // no RR
      // dynAccel = 0.5 (ok), gravity magnitude ~0.1 (fails 0.5..1.5 gate)
      inner.buffer.asByteData().setFloat32(33, 0.5, Endian.little);
      inner.buffer.asByteData().setFloat32(37, 0.05, Endian.little);
      inner.buffer.asByteData().setFloat32(41, 0.05, Endian.little);
      inner.buffer.asByteData().setFloat32(45, 0.05, Endian.little);

      expect(parseGen5Historical(inner), isNull);
      final sample = sampleFromGen5V18Lenient(inner);
      expect(sample, isNotNull);
      expect(sample!.tsEpoch, unix);
      expect(sample.hr, 72);
      expect(sample.ax, isNull);
      expect(sample.ay, isNull);
      expect(sample.az, isNull);
    });
  });
}
