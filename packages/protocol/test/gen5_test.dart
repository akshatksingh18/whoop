// gen5 (WHOOP 5 / "fd4b") multi-band framing + command tests.
//
// The framing/CRC/BandProfile tests below are unchanged in spirit from the
// original file. The historical-record decoders (v18/v20/v21/v26) moved to
// their own golden-fixture suite: gen5_historical_test.dart.

import 'dart:typed_data';
import 'package:test/test.dart';
import 'support/synthetic_packet.dart';
import 'package:whoop_protocol/whoop_protocol.dart';

Uint8List hex(String s) {
  final clean = s.replaceAll(' ', '');
  final out = Uint8List(clean.length ~/ 2);
  for (int i = 0; i < out.length; i++) {
    out[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

void main() {
  group('crc16Modbus', () {
    test('gen5 hello header → 0x71E6', () {
      // header bytes aa 01 08 00 00 01 → crc16-modbus 0x71E6 (LE e6 71).
      expect(crc16Modbus([0xaa, 0x01, 0x08, 0x00, 0x00, 0x01]), 0x71E6);
    });
    test('empty input is the init value', () {
      expect(crc16Modbus(const []), 0xFFFF);
    });
  });

  group('BandProfile', () {
    test('gen4/gen5 header shapes', () {
      expect(BandProfile.gen4.headerLen, 4);
      expect(BandProfile.gen4.sizeFieldOffset, 1);
      expect(BandProfile.gen5.headerLen, 8);
      expect(BandProfile.gen5.sizeFieldOffset, 2);
      expect(BandProfile.of(DeviceType.gen5).isGen5, isTrue);
      expect(BandProfile.of(DeviceType.gen4).isGen5, isFalse);
    });
    test('GATT prefixes differ, low nibble shared', () {
      expect(GattProfile.gen4.servicePrefix, '61080001');
      expect(GattProfile.gen5.servicePrefix, 'fd4b0001');
      expect(GattProfile.gen5.cmdTo.startsWith('fd4b0002'), isTrue);
      expect(GattProfile.gen5.data.startsWith('fd4b0005'), isTrue);
    });
    test(
        'direction markers: outbound COMMAND is [0x00,0x01], never gates inbound',
        () {
      // §1.1a — byte-verified against 8 real fixtures. gen4 has no such field.
      expect(BandProfile.gen4.outboundDirectionMarker, isNull);
      expect(BandProfile.gen5.outboundDirectionMarker, [0x00, 0x01]);
      expect(BandProfile.gen5.inboundDirectionMarker, [0x01, 0x00]);
    });
  });

  group('gen5 client HELLO', () {
    test('reproduces the canonical 16-byte frame byte-for-byte', () {
      // Canonical gen5 CLIENT_HELLO (GET_HELLO 0x91) — independently
      // byte-verified (CRC16 + CRC32 both check out).
      final expected = hex('aa0108000001e67123019101363e5c8d');
      expect(gen5ClientHello(), expected);
    });
  });

  group('gen5 framing round-trip', () {
    test('buildFrame(gen5) → parseFrame(gen5) preserves inner + both CRCs', () {
      final inner = <int>[0x2f, 24, 0, 1, 0, 0, 0, 0xaa, 0xbb, 0, 0, 0, 0, 55];
      final frame = buildFrame(inner, profile: BandProfile.gen5);
      expect(frame[0], 0xAA);
      expect(frame[1], 0x01); // gen5 fixed header byte
      final parsed = parseFrame(frame, profile: BandProfile.gen5)!;
      expect(parsed.headerCrcOk, isTrue);
      expect(parsed.crc32Ok, isTrue);
      expect(parsed.valid, isTrue);
      // inner is padded to /4; the leading bytes must survive verbatim.
      expect(parsed.inner.sublist(0, inner.length), Uint8List.fromList(inner));
    });

    test('a corrupted gen5 header CRC is flagged', () {
      final frame =
          buildFrame(const [0x2f, 24, 0, 1], profile: BandProfile.gen5);
      frame[6] ^= 0xFF; // trash the crc16 low byte
      final parsed = parseFrame(frame, profile: BandProfile.gen5)!;
      expect(parsed.headerCrcOk, isFalse);
    });

    test(
        'a real inbound (strap→host) frame parses despite [0x01,0x00] header bytes',
        () {
      // §1.1a: buildHeader always stamps the OUTBOUND marker [0x00,0x01], but
      // real strap→host frames carry [0x01,0x00] instead. Nothing in
      // parseFrame/headerCrcValid gates on this — it must decode regardless.
      final realtimeFixture = hex(
          'aa011800010022e128029ea0266aae4762025b024b020000000001005ed515dc');
      expect(realtimeFixture[4], 0x01);
      expect(realtimeFixture[5], 0x00);
      final parsed = parseFrame(realtimeFixture, profile: BandProfile.gen5)!;
      expect(parsed.valid, isTrue);
    });
  });

  group('gen4 regression (default profile unchanged)', () {
    test('default buildFrame is still the 4-byte gen4 envelope', () {
      final a = buildFrame(const [0x23, 0, 0x0b]);
      final b = buildFrame(const [0x23, 0, 0x0b], profile: BandProfile.gen4);
      expect(a, b);
      expect(a[0], 0xAA);
      final parsed = parseFrame(a)!; // default gen4
      expect(parsed.valid, isTrue);
    });
  });

  group('FrameReassembler(gen5)', () {
    test('carves two concatenated gen5 frames + waits for a partial', () {
      final f1 = buildFrame(const [0x2f, 24, 0, 1, 0, 0, 0],
          profile: BandProfile.gen5);
      final f2 = buildFrame(const [0x2f, 24, 0, 2, 0, 0, 0],
          profile: BandProfile.gen5);
      final ra = FrameReassembler(profile: BandProfile.gen5);
      final combined = <int>[...f1, ...f2.sublist(0, 5)]; // f2 arrives partial
      final got = ra.feed(combined);
      expect(got.length, 1); // only f1 is complete
      expect(got.first.valid, isTrue);
      final rest = ra.feed(f2.sublist(5)); // deliver the remainder
      expect(rest.length, 1);
      expect(rest.first.valid, isTrue);
    });
  });

  group('gen5 history ACK (safe-trim token echo)', () {
    test(
        'buildHistoryResultOk(gen5) is a valid frame echoing the verbatim token',
        () {
      final token = <int>[0xde, 0xad, 0xbe, 0xef, 0x01, 0x02, 0x03, 0x04];
      final ack = buildHistoryResultOk(7, token, profile: BandProfile.gen5);
      final parsed = parseFrame(ack, profile: BandProfile.gen5)!;
      expect(parsed.valid, isTrue); // both gen5 CRCs must check out
      // inner = [0x23 COMMAND][seq][0x17 HISTORICAL_DATA_RESULT][0x01][token…]
      expect(parsed.inner[2], 0x17);
      expect(parsed.inner[3], 0x01);
      expect(parsed.inner.sublist(4, 12), Uint8List.fromList(token));
    });
    test('rejects a non-8-byte token', () {
      expect(
        () =>
            buildHistoryResultOk(1, const [0, 0, 0], profile: BandProfile.gen5),
        throwsArgumentError,
      );
    });
    test('reproduces the real byte-verified ACK frame', () {
      // aa0110000001e0d12300170141b6010010000000667da4fb — CRC16+CRC32 both
      // independently verified. inner = [0x23][seq=0][0x17][0x01] + 8B token.
      final token = hex('41b6010010000000');
      final ack = buildHistoryResultOk(0, token, profile: BandProfile.gen5);
      expect(ack, hex('aa0110000001e0d12300170141b6010010000000667da4fb'));
    });
  });

  group('gen5 R22 SET_CONFIG builder', () {
    test('cmdSetConfigGen5 produces the verified 44-byte inner shape', () {
      final frame = cmdSetConfigGen5(1, 'enable_r22_packets', '2');
      final parsed = parseFrame(frame, profile: BandProfile.gen5)!;
      expect(parsed.valid, isTrue);
      final inner = parsed.inner;
      expect(inner[0], 0x23); // COMMAND
      expect(inner[1], 1); // seq
      expect(inner[2], 120); // SET_FF_VALUE / SET_CONFIG
      expect(inner[3], 1); // fixed 4th byte
      final nameBytes = inner.sublist(4, 36);
      final nul = nameBytes.indexOf(0);
      final name = String.fromCharCodes(nameBytes.sublist(0, nul));
      expect(name, 'enable_r22_packets');
      expect(inner[36], '2'.codeUnitAt(0)); // value byte
      expect(inner.sublist(37, 44), Uint8List(7)); // 7 zero bytes
    });

    test('rejects an over-length name / non-ASCII / multi-char value', () {
      expect(() => cmdSetConfigGen5(1, 'x' * 32, '2'), throwsArgumentError);
      expect(() => cmdSetConfigGen5(1, 'ok', '22'), throwsArgumentError);
    });

    test('buildR22EnableSequence builds one frame per flag, sequential seq',
        () {
      final frames = buildR22EnableSequence(startSeq: 1);
      expect(frames.length, kGen5R22EnableFlags.length);
      // '1' = enable ('2' would force-DISABLE these). See
      // gen5_command_surface_test.dart for the full value coverage, including
      // the omitContestedFlags opt-out.
      expect(kGen5R22EnableFlags[0], ('enable_r22_packets', '1'));
      expect(kGen5R22EnableFlags.last, ('disable_pip_r26_packets', '2'));
      for (int i = 0; i < frames.length; i++) {
        final parsed = parseFrame(frames[i], profile: BandProfile.gen5)!;
        expect(parsed.valid, isTrue);
        expect(parsed.inner[1], 1 + i); // sequential seq
        expect(parsed.inner[2], 120);
      }
    });
  });

  group('gen5 Maverick haptics + clock', () {
    test('cmdBuzzGen5Maverick builds the verified 12-byte payload', () {
      final frame = cmdBuzzGen5Maverick(1, overallLoop: 7);
      final parsed = parseFrame(frame, profile: BandProfile.gen5)!;
      expect(parsed.valid, isTrue);
      expect(parsed.inner[2], 0x13); // RUN_HAPTIC_PATTERN_MAVERICK
      // sublist(3, 15): the payload is 12 bytes; inner is /4-padded to 16, so
      // stop before the trailing pad byte.
      expect(parsed.inner.sublist(3, 15),
          [0x01, 47, 152, 0, 0, 0, 0, 0, 0, 0, 0, 7]);
    });

    test('gen5 uses the established clock opcodes 10/11, gen5-framed', () {
      // gen5 SET_CLOCK(10) carries <u32 sec><u32 subsec>; GET_CLOCK(11) is
      // the empty-body fallback. Hardware-confirmed on a real gen5 strap:
      // 11 reads a usable time and 10 answers SUCCESS for the 8-byte form.
      final now = DateTime.fromMillisecondsSinceEpoch(0x5F000000 * 1000 + 500,
          isUtc: true);
      final setParsed = parseFrame(
        cmdSetClock(3, now: now, profile: BandProfile.gen5),
        profile: BandProfile.gen5,
      )!;
      expect(setParsed.valid, isTrue, reason: 'must be gen5-framed (crc16)');
      expect(setParsed.inner[2], Cmd.setClock);
      expect(Cmd.setClock, 10);
      // 8-byte body: u32 seconds then u32 subseconds (no revision byte).
      expect(setParsed.inner.sublist(3, 11), [
        0x00, 0x00, 0x00, 0x5F, // seconds LE
        0x00, 0x40, 0x00, 0x00, // subsec = 500ms * 32768 / 1000 = 16384
      ]);

      final getParsed = parseFrame(
        cmdGetClock(4, profile: BandProfile.gen5),
        profile: BandProfile.gen5,
      )!;
      expect(getParsed.valid, isTrue);
      expect(getParsed.inner[2], Cmd.getClock);
      expect(Cmd.getClock, 11);
      // EMPTY body — the shape the probe physically used on gen5.
      expect(getParsed.inner.sublist(0, 3), [0x23, 4, Cmd.getClock]);
    });

    test(
        'a gen5 GET_CLOCK(11) reply decodes its epoch, and a FAILURE reply '
        'publishes nothing', () {
      // Reply body is the gen4 shape [u32 sec][u32 subsec] at body offset 0
      // (probe: whoopTimeMillis reads u32 @0 / u32 @4).
      Uint8List reply(int status) {
        final inner = Uint8List(5 + 8);
        inner[0] = PacketType.commandResponse;
        inner[2] = Cmd.getClock;
        inner[3] = 4; // echoed req seq
        inner[4] = status;
        ByteData.sublistView(inner).setUint32(5, 1785483780, Endian.little);
        return inner;
      }

      final ok = parseCommandResponse(reply(1), profile: BandProfile.gen5)!;
      expect(ok.decoded['clock_epoch'], 1785483780);

      // A non-success reply leaves the body unpopulated; an epoch guessed from
      // stale bytes becomes the reference every alarm is armed against.
      for (final bad in [0, 2, 3]) {
        final r = parseCommandResponse(reply(bad), profile: BandProfile.gen5)!;
        expect(r.decoded.containsKey('clock_epoch'), isFalse,
            reason: 'status $bad must not publish a clock');
      }
    });

    test(
        'the deprecated Maverick clock builders still emit their documented '
        'bytes (kept only for a guarded experiment)', () {
      // ignore: deprecated_member_use_from_same_package
      final setFrame = cmdSetClockGen5(1, now: DateTime.utc(2026, 1, 1));
      final setParsed = parseFrame(setFrame, profile: BandProfile.gen5)!;
      expect(setParsed.valid, isTrue);
      expect(setParsed.inner[2], Cmd.setClockMaverick);
      expect(Cmd.setClockMaverick, 146);

      // ignore: deprecated_member_use_from_same_package
      final getFrame = cmdGetClockGen5(1);
      final getParsed = parseFrame(getFrame, profile: BandProfile.gen5)!;
      expect(getParsed.valid, isTrue);
      expect(getParsed.inner[2], Cmd.getClockGen5);
      expect(Cmd.getClockGen5, 147);
    });

    test('the gen5 clock bodies carry the leading revision byte', () {
      // Without it the strap reads the epoch's low byte as the revision and
      // refuses the command, so the RTC never latches.
      final setParsed = parseFrame(
        cmdSetClockGen5(1, now: DateTime.utc(2026, 1, 1)),
        profile: BandProfile.gen5,
      )!;
      expect(setParsed.inner[3], revision1);
      final epoch =
          ByteData.sublistView(setParsed.inner).getUint32(4, Endian.little);
      expect(epoch, DateTime.utc(2026, 1, 1).millisecondsSinceEpoch ~/ 1000);

      final getParsed =
          parseFrame(cmdGetClockGen5(1), profile: BandProfile.gen5)!;
      expect(getParsed.inner[3], revision1);
    });
  });

  group('OpcodeSafety', () {
    test('classifies the whoop-rs forbidden/destructive lists', () {
      expect(OpcodeSafety.isForbidden(Cmd.setClockMaverick), isTrue); // 146
      expect(OpcodeSafety.isForbidden(Cmd.forceTrim), isTrue); // 25
      expect(OpcodeSafety.isDestructive(Cmd.forceTrim), isTrue);
      expect(OpcodeSafety.isForbidden(Cmd.setFfValue), isTrue); // 120 — see doc
      expect(OpcodeSafety.isDestructive(Cmd.setFfValue), isFalse);
      expect(OpcodeSafety.isForbidden(Cmd.getBatteryLevel), isFalse);
    });
  });

  group('gen5 EVENT vocabulary', () {
    test('BLE_REALTIME_HR_ON/OFF are new gen5 event ids', () {
      expect(EventId.name(EventId.bleRealtimeHrOn), 'BLE_REALTIME_HR_ON');
      expect(EventId.name(EventId.bleRealtimeHrOff), 'BLE_REALTIME_HR_OFF');
      expect(EventId.bleRealtimeHrOn, 33);
      expect(EventId.bleRealtimeHrOff, 34);
    });

    test('an event id never borrows a Cmd name for the same number', () {
      // 123 = Cmd.selectWrist (0x7B) as a COMMAND opcode — a real, documented
      // numeric collision. Event 123 is GENERIC_FIRMWARE_EVENT;
      // the two namespaces are separate and must stay that way.
      expect(Cmd.selectWrist, 123);
      expect(EventId.name(123), 'GENERIC_FIRMWARE_EVENT');
      expect(EventId.name(123), isNot(contains('WRIST')));
    });

    test('an id outside the vocabulary still renders raw', () {
      // Unlisted event id — 110 arrives and has no vocabulary entry.
      expect(EventId.name(110), 'EVENT_110');
    });
  });
  group('gen5 live IMU (0x2B record 21)', () {
    // Authored planar axes: X/Y=0, Z=4096; independent of captures.
    final liveHex = syntheticHex('g5-live-imu');

    test('decodes the planar accel block and carries the frame timestamp', () {
      final f = frameAccelGen5Live(liveHex)!;
      expect(f.mags, hasLength(100));
      expect(f.xs, hasLength(100));
      // A still wrist reads ~1g; an interleaved read of the same bytes swings
      // 0.03..1.3g, so this pins the planar layout.
      final avg = f.mags.reduce((a, b) => a + b) / f.mags.length;
      expect(avg, closeTo(1.0, 1e-9));
      for (final m in f.mags) {
        expect(m, closeTo(1.0, 1e-9));
      }
      // unix @ inner[7:11] — the frame carries a real time, not a sentinel.
      expect(f.ts, 1609459500);
    });

    test('the same buffer decodes identically through the record path', () {
      final buf = parseGen5ImuBuffer(hexToBytes(liveHex))!;
      final f = frameAccelGen5Live(liveHex)!;
      expect(buf.histVersion, 21);
      expect(buf.accelXg, hasLength(100));
      expect(buf.gyroXdps, hasLength(100));
      // Same samples, just expressed raw vs in g.
      expect(f.xs![0], closeTo(buf.accelXg[0] / kGen5AccelScaleG, 1e-6));
    });

    test('frameAccelForBand routes it, and gen4 frames still reach frameAccel',
        () {
      expect(frameAccelForBand(liveHex)!.ts, 1609459500);
      // A gen4 0x33 IMU frame must not be claimed by the gen5 gate.
      expect(frameAccelGen5Live('33${'00' * 90}'), isNull);
    });
  });
}
