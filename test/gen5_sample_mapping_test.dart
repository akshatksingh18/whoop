// Tests for BleEngine's gen5 -> band-agnostic Sample mapping
// (sampleFromGen5Historical) — the seam that turns protocol's typed gen5
// historical-record decode into the same `Sample` shape gen4 records
// produce, so the derivation pipeline / analytics stay band-agnostic.
//
// The v18 fixture is the same real, independently byte-verified capture used
// by protocol's own gen5_historical_test.dart (CRC16-modbus header + CRC32
// payload both check out; see that file's header comment for provenance) —
// reused here rather than re-typed, so a transcription slip can't silently
// diverge the two test suites' expectations.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ble/ble_engine.dart';
import 'package:openstrap_edge/data/models.dart';
import 'package:openstrap_protocol/openstrap_protocol.dart';

Uint8List hex(String s) {
  final clean = s.replaceAll(' ', '');
  final out = Uint8List(clean.length ~/ 2);
  for (int i = 0; i < out.length; i++) {
    out[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

/// A synthetic v18 inner that `Gen5V18Decoder` actually accepts: valid header,
/// an HR inside 25..230, a dynamic-accel inside 0..8 g and a gravity vector
/// inside the 0.5..1.8 g magnitude gate. Only the three bytes these tests care
/// about — the skin-temp i16 and the two disproven flag bytes — are parameters.
Uint8List v18Inner({
  required int skinTempRaw,
  int hrQualityFlags = 0,
  int sleepStateByte = 0,
}) {
  final inner = Uint8List(kGen5V18InnerLen);
  final v = inner.buffer.asByteData();
  inner[0] = PacketType.historicalData;
  inner[1] = 18;
  inner[2] = 0x80;
  v.setUint32(3, 4242, Endian.little); // record index
  v.setUint32(7, 1780916150, Endian.little); // unix
  inner[14] = 64; // heart rate
  inner[15] = 0; // no RR slots declared
  inner[28] = hrQualityFlags; // body 15 — bit7 is the disproven "HR valid"
  v.setFloat32(33, 0.5, Endian.little); // dynamic acceleration
  v.setFloat32(37, 0.0, Endian.little); // gravity x
  v.setFloat32(41, 0.0, Endian.little); // gravity y
  v.setFloat32(45, 1.0, Endian.little); // gravity z — magSq 1.0
  v.setInt16(65, skinTempRaw, Endian.little); // AS6221 skin temp, °C = raw/100
  inner[73] = sleepStateByte; // body 60 — bits 0-1 are the disproven "on wrist"
  return inner;
}

void main() {
  group('sampleFromGen5Historical — v18 (real fixture)', () {
    // "worn" capture, unix=1780916150 — CRC16+CRC32 both verified. Same
    // bytes as protocol/test/gen5_historical_test.dart's v18 real fixture.
    final frame = hex(
      'aa01740001003fb12f1280733d8401b69f266a66460066025a0265020000000'
      '000007b0a8d656463ff0012163cf6a439bf2924fd3ed763fe3e3200aa000000'
      '000000000000f7000901f10b0007010c020c000000000000000000000000000'
      '00000000000000000000100656f1e1e0000009d61a7c00000003e862817',
    );

    late Sample? sample;

    setUp(() {
      final parsed = parseFrame(frame, profile: BandProfile.gen5)!;
      expect(parsed.valid, isTrue, reason: 'both gen5 CRCs must check out');
      sample = sampleFromGen5Historical(parseGen5Historical(parsed.inner));
    });

    test('maps ts/counter/hr straight through', () {
      expect(sample, isNotNull);
      expect(sample!.tsEpoch, 1780916150);
      expect(sample!.counter, 25443699);
      expect(sample!.hr, 102);
    });

    test('maps RR intervals straight through (band-agnostic HRV kernel)', () {
      expect(sample!.rrIntervalsMs, [602, 613]);
    });

    test('maps the gravity vector onto ax/ay/az (shared g-units)', () {
      expect(sample!.ax, closeTo(-0.7252, 1e-3));
      expect(sample!.ay, closeTo(0.4944, 1e-3));
      expect(sample!.az, closeTo(0.4969, 1e-3));
    });

    test(
      'does NOT populate skinTempRaw/spo2 — gen5-specific scale/absence',
      () {
        // See gen5_v18_decode's (now removed, folded into protocol) original
        // caution and Gen5HistorySample's field docs: gen5's skin_temp is
        // already °C-scaled (raw/100), a DIFFERENT transfer function from
        // gen4's per-device affine ADC calibration that `skinTempRaw` feeds —
        // reusing that field here would silently corrupt the skin-temp-z
        // metric. gen5 v18 has no real dual-wavelength SpO2 at all.
        expect(sample!.skinTempRaw, isNull);
        expect(sample!.spo2RedRaw, isNull);
        expect(sample!.spo2IrRaw, isNull);
      },
    );

    test('maps the calibrated °C skin temperature through', () {
      expect(sample!.skinTempC, closeTo(30.57, 1e-9));
    });

    test('claims NO wear state and NO HR-validity for this second', () {
      // This capture is the counter-example in the flesh. Its body-15 byte is
      // 0x8D — bit7 SET — and its body-60 bits 0-1 are 0, so the mapping that
      // used to read those bits recorded "HR is valid" AND "on-wrist code 0"
      // for a second the band was plainly worn for (HR 102, a gravity vector
      // at 1 g). bit7 is not validity (disproven on 1,587,671 records; it
      // toggles ~50/50 independently of HR presence) and bits 0-1 are the
      // primary-flags bit-8 snapshot, not wear. Absence is the honest answer.
      expect(sample!.hr, 102, reason: 'the wearer definitely had a pulse');
      expect(
        sample!.onWrist,
        isNull,
        reason: 'body 60 bits 0-1 are the primary-flags bit-8 snapshot, '
            'not a wear determination',
      );
      expect(
        sample!.hrValid,
        isNull,
        reason: 'body 15 bit7 is not HR/RR validity — HR presence is `hr`',
      );
    });
  });

  group('sampleFromGen5Historical — v18 skin-temp sentinel', () {
    test('-50.00 °C is the unavailable code and maps to null, not a reading',
        () {
      final s = sampleFromGen5Historical(
        parseGen5Historical(v18Inner(skinTempRaw: -5000)),
      );
      expect(s, isNotNull);
      expect(
        s!.skinTempC,
        isNull,
        reason: 'raw -5000 is the AS6221 unavailable/error sentinel',
      );
      // Abstaining on one field never costs the rest of the second.
      expect(s.hr, 64);
      expect(s.tsEpoch, 1780916150);
    });

    test('a real reading just below the sentinel is NOT swallowed', () {
      // The gate is the exact sentinel, not "negative means absent" — an i16
      // skin temp is signed and -12.34 °C is a value, not an error code.
      final s = sampleFromGen5Historical(
        parseGen5Historical(v18Inner(skinTempRaw: -1234)),
      );
      expect(s!.skinTempC, closeTo(-12.34, 1e-9));
    });
  });

  group('sampleFromGen5Historical — the disproven bits are never read', () {
    test('flipping both of them changes nothing in the mapped Sample', () {
      Sample map(int quality, int sleepState) => sampleFromGen5Historical(
            parseGen5Historical(
              v18Inner(
                skinTempRaw: 3000,
                hrQualityFlags: quality,
                sleepStateByte: sleepState,
              ),
            ),
          )!;

      // All bits set vs all bits clear: if either byte were still feeding a
      // column, these two seconds would disagree about wear and validity.
      final allSet = map(0xFF, 0x03);
      final allClear = map(0x00, 0x00);
      for (final s in [allSet, allClear]) {
        expect(s.onWrist, isNull);
        expect(s.hrValid, isNull);
      }
      expect(allSet.skinTempC, closeTo(30.0, 1e-9));
      expect(allClear.skinTempC, closeTo(30.0, 1e-9));
    });
  });

  group('sampleFromGen5Historical — non-Sample record kinds', () {
    test('a null decode (unrecognised version/garbage) maps to null', () {
      expect(sampleFromGen5Historical(null), isNull);
    });

    test('a v21 IMU deep buffer (no Sample equivalent) maps to null', () {
      // Synthetic-but-shape-correct v21 buffer: countA/countB both 100 (the
      // buffer's actual identity gate, per Gen5V21Decoder — hist_version is
      // not trusted for this kind at all).
      final inner = Uint8List(kGen5V21InnerLen);
      inner[0] = 0x2F;
      inner[1] = 21;
      final view = inner.buffer.asByteData();
      view.setUint16(16, 100, Endian.little); // countA offset
      view.setUint16(622, 100, Endian.little); // countB offset
      final decoded = parseGen5Historical(inner);
      expect(decoded, isA<Gen5ImuBuffer>());
      expect(sampleFromGen5Historical(decoded), isNull);
    });
  });
}
