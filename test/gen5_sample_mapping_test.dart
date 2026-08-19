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

    test('MT-12: carries the aux temp channels and signal quality', () {
      // These reach `decoded_onehz.temp_ch2_c` / `temp_ch3_c` /
      // `signal_quality_logvar` and NOTHING reads them. The test exists so the
      // mapper cannot silently drop them again — which is what it did until
      // now, with the columns already in the schema.
      expect(sample!.tempCh2C, 24.7);
      expect(sample!.tempCh3C, 26.5);
      expect(sample!.signalQualityLogVar, isNotNull);
    });

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

  // The band's own wake/sleep envelope: modelled by protocol, polarity already
  // corrected there, and never mapped — `grep sleepState edge/lib` was zero.
  // All four records below are VERBATIM v18 inners out of a real MG export's
  // archive, one per state.
  group('sampleFromGen5Historical — the band\'s own sleep envelope', () {
    // hr -> the inner frame that carried it. Across the whole 1,035-record
    // archive the median heart rate orders wake 119 > up 90 > still 82 >
    // sleep 70, which is why these four are worth trusting as a signal at all:
    // the codes rank the way the physiology does.
    const real = <int, String>{
      0: '2f1280afc24101f25b716af54800580000000000000000000220ec0780580000'
          'e3b4de12419a71ae3ea450763ef6ec443f6c1298000000000000000000'
          '4e015901cd0d6009010c020c0000000000000000000000000000000000'
          '000000000000010083a6808000000044cf89c0000000',
      1: '2f12803fc842014565726a5138005000000000000000000000219a2287500000'
          'ffd8151c3ee17a6c3e48a1c2be3333113ec60b95000000000000000000'
          '54015f01090e500b010c020c1100000000000000000000000000000000'
          '00000000000001005b6780800000004e4473c0000000',
      2: '2f12804ffc41015e96716a5c4f00470000000000000000000031cd4f824f0000'
          '4ca007723eaee72a3e148ec4bd3d7ad13e1702760000000100000000'
          '0057015901950d400b010c020c210000000000000000000000000000'
          '00000000000000000000000100a0658080000000bbe75cc0000000',
      3: '2f1282b225460195d0756a5c4f006100000000000000000000702d608a610000'
          'bcaa5aa63e146e7e3eae8761bdd7ebd63eea4d7300000001000000'
          '0000a90194016e0e000b010c020c30000000000000000000000000'
          '0000000000000000000000000000010049668080000000af4845c0000000',
    };

    test('every state the band can report comes through as its raw code', () {
      for (final e in real.entries) {
        final s = sampleFromGen5Historical(parseGen5Historical(hex(e.value)));
        expect(s, isNotNull, reason: 'state ${e.key} failed to decode');
        expect(s!.bandSleepState, e.key);
        // The neighbouring 2-bit field in the same byte is NOT mapped: bits
        // 0-1 are the primary-flags bit-8 snapshot, not wear (disproven on
        // 1.59M records), so onWrist stays absent while the nibble beside it
        // decodes — proof the byte is being sliced, not read whole.
        expect(s.onWrist, isNull);
      }
    });

    test('the enum this maps to is not re-derived here', () {
      // Stored as the RAW CODE on purpose: a stored name freezes a meaning,
      // and this one is an envelope whose meaning has a known ceiling. The
      // mapping to a name stays in protocol, where the evidence for it lives.
      final s = sampleFromGen5Historical(parseGen5Historical(hex(real[2]!)))!;
      expect(s.bandSleepState, Gen5SleepState.sleep.index);
    });

    test('gen4 carries no such field', () {
      // Nothing in the gen4 mapper sets it, and it must stay null there rather
      // than defaulting to 0 — which is `wake`, a claim, not an absence.
      expect(Sample(tsEpoch: 1, counter: 1, hr: 60).bandSleepState, isNull);
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
