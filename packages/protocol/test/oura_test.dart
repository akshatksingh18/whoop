// Authored Oura wire contracts, independent of a real ring's measurements.
// Original empirical tests remain local-only. These check representation,
// dispatch, bounds and absence; they do not validate physiological accuracy.
import 'package:test/test.dart';
import 'package:whoop_protocol/whoop_protocol.dart';

List<int> _hex(String value) => [
      for (var i = 0; i < value.length; i += 2)
        int.parse(value.substring(i, i + 2), radix: 16),
    ];

void main() {
  group('framing and event envelope', () {
    test('exact declared bytes, ignored tail and independent batch fields', () {
      // Tag 11, 8 bytes; received=3, bytesLeft=0x010203, unused tail zero.
      const bytes = '11080300030201000000';
      final frame = parseOuraFrame(_hex(bytes))!;
      expect(frame.tag, 0x11);
      expect(frame.payload, hasLength(8));
      expect(
          parseOuraFrame([..._hex(bytes), 0xAA, 0xBB])!.payload, frame.payload);
      final summary = parseBatchSummary(frame)!;
      expect(summary.received, 3);
      expect(summary.bytesLeft, 66051);
    });

    test('decisecond envelope stamp and body stay separate', () {
      final event = parseOuraEvent(parseOuraFrame(_hex('61050403020124'))!)!;
      expect(event.tag, 0x61);
      expect(event.tsDs, 0x01020304);
      expect(event.body, [0x24]);
    });

    test('empty, truncated and wrong-tag events refuse', () {
      for (final bytes in [
        <int>[],
        [0x61],
        [0x61, 20, 1, 2, 3]
      ]) {
        expect(parseOuraFrame(bytes), isNull);
      }
      expect(parseOuraEvent(parseOuraFrame(_hex('0d03560100'))!), isNull);
      expect(parseOuraEvent(parseOuraFrame(_hex('6103010203'))!), isNull);
    });
  });

  group('debug dispatch and refusal', () {
    test('subtype 04 is text although its prefix is not printable', () {
      expect(decodeDebugData(_hex('046578616d706c653b31'))!.text, 'example;1');
      expect(_hex('046578')[0], lessThan(0x20));
      expect(decodeDebugData(_hex('04')), isNull);
      expect(decodeDebugData(_hex('0454070a')), isNull);
    });

    test('printable or NUL binary bytes are never text', () {
      for (final bytes in [
        '2800000000000000000000000000',
        '2900000000000000'
      ]) {
        final result = decodeDebugData(_hex(bytes))!;
        expect(result.text, isNull);
        expect(result.batteryPct, isNull);
      }
    });

    test('independent authored battery and gauge offsets', () {
      // 70%, 4000 mV versus 65%, 3800 mV. Remaining gauge bytes are poison.
      final a = decodeDebugData(_hex('2446a00f00'))!;
      final b = decodeDebugData(_hex('2441d80e00'))!;
      expect(a.batteryPct, 70);
      expect(a.batteryMv, 4000);
      expect(b.batteryPct, 65);
      expect(b.batteryMv, 3800);
      expect(
          decodeDebugData(_hex('14a5a5a00fa5a5a5a5a5a5a5a5'))!.batteryMv, 4000);
      expect(
          decodeDebugData(_hex('14a5a5d80ea5a5a5a5a5a5a5a5'))!.batteryMv, 3800);
      expect(a.text, isNull);
    });

    test('empty, truncated, impossible voltage and impossible percent refuse',
        () {
      for (final bytes in ['', '2446', '2446a0', '2446102700', '2491a00f00']) {
        expect(decodeDebugData(_hex(bytes)), isNull, reason: bytes);
      }
    });
  });

  group('temperature and clock boundaries', () {
    test('one invalid probe refuses the whole temperature array', () {
      final good = parseOuraEvent(parseOuraFrame(_hex('460601000000800c'))!)!;
      expect(decodeTemperatures(good), [32.0]);
      final bad =
          parseOuraEvent(parseOuraFrame(_hex('460801000000800c3075'))!)!;
      expect(decodeTemperatures(bad), isNull);
      final odd = parseOuraEvent(parseOuraFrame(_hex('460701000000800c30'))!)!;
      expect(decodeTemperatures(odd), isNull);
    });

    test('authored Unix time decodes, unset RTC refuses', () {
      final good =
          parseOuraEvent(parseOuraFrame(_hex('42080100000000f15365'))!)!;
      expect(decodeTimeSync(good), 1700000000);
      final unset =
          parseOuraEvent(parseOuraFrame(_hex('42080100000000000000'))!)!;
      expect(decodeTimeSync(unset), isNull);
    });
  });

  group('outbound byte contracts', () {
    test('history cursor, cap and signed filter', () {
      expect(ouraCmdGetEvents(0, maxEvents: 8), _hex('10090000000008ffffffff'));
      expect(ouraCmdGetEvents(0x01020304).sublist(2, 6), [4, 3, 2, 1]);
    });

    test('authentication declares its body length', () {
      final frame = ouraCmdAuthenticate(List.filled(16, 0xAB));
      expect(frame[0], 0x2F);
      expect(frame[1], 17);
      expect(frame, hasLength(19));
    });

    test('clock encoding retains both low and high 32-bit words', () {
      expect(
          ouraCmdSyncTime(1609459200).sublist(2, 10), _hex('0066ee5f00000000'));
      expect(ouraCmdSyncTime(0x100000001).sublist(2, 10),
          _hex('0100000001000000'));
    });
  });

  group('authentication result dispatch, not cryptography', () {
    test('challenge keeps exactly fifteen authored bytes', () {
      final frame =
          parseOuraFrame(_hex('2f102c000102030405060708090a0b0c0d0e'))!;
      expect(ouraAuthNonce(frame), List.generate(15, (i) => i));
    });

    test('success, refusal and authentication gate remain distinct', () {
      expect(ouraAuthResult(parseOuraFrame(_hex('2f022e00'))!), 0);
      expect(ouraAuthResult(parseOuraFrame(_hex('2f022e01'))!), 1);
      final gate = parseOuraFrame(_hex('2f022f01'))!;
      expect(ouraIsAuthRequired(gate), isTrue);
      expect(ouraAuthResult(gate), isNull);
      expect(ouraAuthNonce(gate), isNull);
    });
  });
}
