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
        // The neighbouring 2-bit field in the same byte still reads
        // independently — proof the nibble is being sliced, not the byte.
        expect(s.onWrist, isNotNull);
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
