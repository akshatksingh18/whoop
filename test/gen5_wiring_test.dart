// Wiring the band generation actually reaches the wire, plus the two
// historical-ingest routing bugs that quietly threw a user's records away.
//
// What each group here is standing in for:
//   - the plausibility-drop path used to write the record NOWHERE, so a record
//     we merely mistrusted fared worse than one we could not parse at all —
//     and the batch-ACK then let the band trim those bytes for good;
//   - only v24/v12/v10 were routed to the R24 decoder, so every other version
//     the decoder can read (v7/v9/v18/v25) was archived as undecodable — a real
//     export carried ~50k readable v25 records filed that way;
//   - the alarm bodies are generation-specific, and the gen4 forms are
//     hardware-verified, so the gen5 additions must not disturb them.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ble/ble_engine.dart';
import 'package:openstrap_edge/ble/ble_state.dart';
import 'package:openstrap_edge/data/models.dart';
import 'package:openstrap_edge/sync/sync_policy.dart';
import 'package:openstrap_protocol/openstrap_protocol.dart';

int _wallNow() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

/// A gen4 historical record inner: `[0x2f][version][…][counter@3][ts@7]`.
/// Zero-filled elsewhere, which the v24 field map reads as a (0,0,0) accel —
/// finite, and v24/v12 are the trusted path so no plausibility gate applies.
Uint8List _gen4Inner({
  required int version,
  required int ts,
  required int counter,
  int length = 89,
  // Only v24/v12 are decoded verbatim; every other version is gated on
  // physiological plausibility, so those need a real HR byte and a ~1 g accel
  // vector (float32 LE at 36/40/44).
  int? hrOffset,
  int hr = 0,
}) {
  final inner = Uint8List(length);
  inner[0] = PacketType.historicalData;
  inner[1] = version;
  final view = ByteData.sublistView(inner);
  view.setUint32(3, counter, Endian.little);
  view.setUint32(7, ts, Endian.little);
  if (hrOffset != null) {
    inner[hrOffset] = hr;
    view.setFloat32(36, 0.0, Endian.little);
    view.setFloat32(40, 0.0, Endian.little);
    view.setFloat32(44, 1.0, Endian.little);
  }
  return inner;
}

/// v25 has its own layout: time + gravity only, gated on a gravity magnitude of
/// roughly 1 g at inner[69/71/73] (i16 / 16384).
Uint8List _v25Inner({required int ts, required int counter}) {
  final inner = _gen4Inner(version: 25, ts: ts, counter: counter, length: 80);
  final view = ByteData.sublistView(inner);
  view.setInt16(69, 0, Endian.little); // gx = 0.0
  view.setInt16(71, 0, Endian.little); // gy = 0.0
  view.setInt16(73, 16384, Endian.little); // gz = 1.0 → |g| = 1.0
  return inner;
}

class _Ingest {
  final samples = <Sample?>[];
  final archives = <ArchiveRecord>[];
  late final BleEngine engine;

  _Ingest({BandProfile band = BandProfile.gen4}) {
    engine = BleEngine(
      onRecord: (sample, raw) async => samples.add(sample),
      onState: (_) {},
    );
    engine.debugInstallFakeLink(
      onWrite: (_) async => true,
      band: band,
      onArchive: (a) async => archives.add(a),
    );
  }

  void feed(Uint8List inner) =>
      engine.debugIngestHistoricalFrame(Frame(inner, true, true));
}

/// Captures every outgoing frame and decodes it back to `[opcode, ...body]`.
class _Wire {
  final frames = <Uint8List>[];
  final BandProfile band;
  late final BleEngine engine;

  _Wire({required this.band}) {
    engine = BleEngine(onRecord: (_, _) async {}, onState: (_) {});
    engine.debugInstallFakeLink(
      onWrite: (f) async {
        frames.add(f);
        return true;
      },
      band: band,
    );
  }

  /// The inner of the last frame written, minus the packet-type and seq bytes:
  /// `[opcode, ...body]`. Asserts the frame really was built for [band] — a
  /// gen4-framed frame does not parse against the gen5 envelope at all, which
  /// is precisely how high-frequency sync failed silently.
  List<int> get lastCommand {
    final parsed = parseFrame(frames.last, profile: band);
    expect(parsed, isNotNull, reason: 'frame must parse under $band');
    expect(parsed!.valid, isTrue, reason: 'header + payload CRCs must pass');
    return parsed.inner.sublist(2);
  }

  /// [lastCommand] truncated to [length]: `buildFrame` pads the inner out to a
  /// 4-byte boundary, so trailing zeros are envelope, not body.
  List<int> lastCommandOf(int length) => lastCommand.sublist(0, length);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(BleEngine.resetBandClaimForTest);
  tearDown(BleEngine.resetBandClaimForTest);

  group('P0 — a plausibility-dropped record is archived, never discarded', () {
    test('an implausibly-old record lands in the archive as gate_dropped', () {
      final h = _Ingest();
      // 2001: decodable, but far below the plausible-epoch floor, so the
      // RecordGate refuses it.
      h.feed(_gen4Inner(version: 24, ts: 1000000000, counter: 7));

      expect(h.samples, isEmpty, reason: 'the gate still refuses to bank it');
      expect(h.archives, hasLength(1),
          reason: 'OLD BEHAVIOUR: a bare return — the bytes went nowhere at '
              'all, and the batch-ACK then let the band trim them');
      expect(h.archives.single.reason, 'gate_dropped');
      expect(h.archives.single.counter, 7);
    });

    test('an admitted record is banked and NOT archived', () {
      final h = _Ingest();
      h.feed(_gen4Inner(version: 24, ts: _wallNow() - 3600, counter: 8));

      expect(h.samples, hasLength(1));
      expect(h.archives, isEmpty);
    });

    test('the no-progress trim gate still fires once drops archive', () {
      // The knock-on: `hadDurableRows` counts banked RECORDS, not archives.
      // Were it to count archives, a drop-only burst would always look
      // "durable" and the band would be told it may trim flash we never
      // decoded.
      expect(
        TrimAckPolicy.evaluate(
          sessionCurrent: true,
          burstDiscarded: false,
          commitDurable: true,
          hadDurableRows: false,
          droppedThisBurst: 3,
        ),
        TrimAckVerdict.blockedNoDurableProgress,
      );
      expect(
        TrimAckPolicy.evaluate(
          sessionCurrent: true,
          burstDiscarded: false,
          commitDurable: true,
          hadDurableRows: true,
          droppedThisBurst: 3,
        ),
        TrimAckVerdict.send,
        reason: 'a mixed burst that banked something may still ACK',
      );
    });

    test('a gate-dropped record is neither durable progress nor offload progress',
        () {
      // The two tests above pass `hadDurableRows` in as a literal, so the thing
      // that actually COMPUTES it has never been covered — and it has been
      // patched twice. Both halves belong to the same rule: a record we dropped
      // for implausibility is archived (so it is not lost) but must not look
      // like progress, or the band gets told it may trim flash we never read
      // and the wandered-RTC remedy never surfaces.
      DrainController drain() => DrainController(
            onRecord: (_, _) async {},
            onRecordsBatch: null,
            onCommit: (_, _, _, {archives}) async {},
            onArchive: (_) async {},
            log: (_) {},
          );
      ArchiveRecord archive(String reason) => ArchiveRecord(
            counter: 1,
            hex: '2f18${reason.hashCode.toRadixString(16)}',
            packetType: 0x2F,
            capturedAt: 0,
            reason: reason,
          );

      final dropped = drain()..onUndecodableRecord(archive('gate_dropped'));
      expect(dropped.bufferedProgressArchives, 0);
      expect(dropped.recordsThisOffload, 0,
          reason: 'a drop-only burst must leave `banked` false at COMPLETE');

      final undecodable = drain()..onUndecodableRecord(archive('undecodable_v22'));
      expect(undecodable.bufferedProgressArchives, 1,
          reason: 'a version we cannot read IS progress once it is set aside');
      expect(undecodable.recordsThisOffload, 1);
    });
  });

  group('P0 — every gen4 version the decoder can read is decoded', () {
    test('v25 is still archived — it has no heart rate to bank', () {
      // The other versions here decode into 1 Hz rows; v25 deliberately does
      // not. It carries a timestamp and a gravity vector and nothing else, and
      // the decoder reports hr 0 because the record has no HR field. hr is NOT
      // NULL in decoded_onehz and 0 is the off-skin sentinel, so banking v25
      // would claim the band was off the wrist for every one of those seconds
      // — while the real gravity makes the accel-coverage gate accept the
      // window. Archiving keeps the bytes for a re-decode once hr is nullable.
      final ts = _wallNow() - 7200;
      final h = _Ingest();
      h.feed(_v25Inner(ts: ts, counter: 4242));

      expect(h.samples, isEmpty, reason: 'no fabricated hr 0 row');
      expect(h.archives, hasLength(1), reason: 'bytes kept, nothing lost');
      expect(h.archives.single.reason, 'undecodable_rec_v25');
      expect(h.archives.single.counter, 4242);
    });

    test('v9 and v7 decode too', () {
      final ts = _wallNow() - 600;
      // HR offset moves per version; the rest of the field map is shared.
      for (final entry in {7: 27, 9: 17}.entries) {
        final h = _Ingest();
        h.feed(_gen4Inner(
          version: entry.key,
          ts: ts,
          counter: 11,
          hrOffset: entry.value,
          hr: 61,
        ));
        expect(h.samples, hasLength(1), reason: 'v${entry.key} must decode');
        expect(h.samples.single!.hr, 61);
        expect(h.archives, isEmpty,
            reason: 'v${entry.key} must not be archived');
      }
    });

    test('a genuinely unknown version is still archived', () {
      final h = _Ingest();
      h.feed(_gen4Inner(version: 99, ts: _wallNow() - 60, counter: 12));

      expect(h.samples, isEmpty);
      expect(h.archives.single.reason, 'undecodable_rec_v99');
    });

    test('a gen5 v18 is not routed through the gen4 field map', () {
      // Same version byte, completely different layout. The gen5 branch claims
      // it first; these zeroed bytes are not a valid gen5 v18, so it archives
      // rather than yielding a fabricated gen4-shaped sample.
      final h = _Ingest(band: BandProfile.gen5);
      h.feed(_gen4Inner(version: 18, ts: _wallNow() - 60, counter: 13));

      expect(h.samples, isEmpty);
      expect(h.archives.single.reason, 'undecodable_rec_v18');
    });
  });

  group('P1 — alarm bodies are generation-correct', () {
    test('gen4 forms are byte-identical (hardware-verified — do not change)',
        () {
      expect(AlarmPayloads.disableForBand(isGen5: false), <int>[0x01]);
      expect(AlarmPayloads.getPayloadForBand(isGen5: false), <int>[0x01]);
      expect(AlarmPayloads.disable, <int>[0x01]);
      // gen4 keeps alarm slot 0.
      expect(AlarmPayloads.setPayloadForBand(DateTime.now(), isGen5: false)[1],
          0);
    });

    test('gen5 disable is revision 2 + an alarm id', () {
      expect(AlarmPayloads.disableForBand(isGen5: true), <int>[0x02, 0xFF]);
      expect(AlarmPayloads.disableForBand(isGen5: true, id: 1), <int>[0x02, 1]);
    });

    test('gen5 get-alarm is revision 4 + the alarm id', () {
      expect(AlarmPayloads.getPayloadForBand(isGen5: true), <int>[0x04, 1]);
      expect(AlarmPayloads.getPayloadForBand(isGen5: true, id: 0),
          <int>[0x04, 0]);
      // The default id is the slot the gen5 SET arms.
      expect(AlarmPayloads.setPayloadForBand(DateTime.now(), isGen5: true)[1],
          AlarmPayloads.gen5Slot);
    });

    test('the engine writes the gen4 alarm bodies unchanged', () async {
      final w = _Wire(band: BandProfile.gen4);
      await w.engine.disableAlarm();
      expect(w.lastCommandOf(2), <int>[Cmd.disableAlarm, 0x01]);
      await w.engine.getAlarm();
      expect(w.lastCommandOf(2), <int>[Cmd.getAlarmTime, 0x01]);
    });

    test('the engine writes the gen5 alarm bodies', () async {
      final w = _Wire(band: BandProfile.gen5);
      await w.engine.disableAlarm();
      expect(w.lastCommandOf(3), <int>[Cmd.disableAlarm, 0x02, 0xFF]);
      await w.engine.getAlarm();
      expect(w.lastCommandOf(3), <int>[Cmd.getAlarmTime, 0x04, 1]);
    });
  });

  group('P1 — band-specific opcodes and framing', () {
    test('strap rename uses the opcodes each generation implements', () async {
      final g4 = _Wire(band: BandProfile.gen4);
      await g4.engine.setStrapName('band');
      expect(g4.lastCommand.first, Cmd.setAdvertisingNameHarvard);
      await g4.engine.getStrapName();
      expect(g4.lastCommand.first, Cmd.getAdvertisingNameHarvard);

      final g5 = _Wire(band: BandProfile.gen5);
      await g5.engine.setStrapName('band');
      expect(g5.lastCommand.first, Cmd.setCustomAdvertisingName,
          reason: 'gen5 does not implement the gen4 advertising-name opcodes');
      await g5.engine.getStrapName();
      expect(g5.lastCommand.first, Cmd.getCustomAdvertisingName);
    });

    test('high-frequency sync is framed for the session band', () async {
      final w = _Wire(band: BandProfile.gen5);
      await w.engine.applyHighFreqWakeWindow(
        enabled: true,
        targetWake: DateTime.now().add(const Duration(hours: 1)),
      );
      // The assertion that matters is inside lastCommand: a gen4-framed frame
      // does not parse under the gen5 envelope, so the strap could never act
      // on it — while the engine claimed the mode had engaged.
      expect(w.lastCommand.first, Cmd.enterHighFreqSync);
    });

    test('the mode is not claimed when the write fails', () async {
      final engine = BleEngine(onRecord: (_, _) async {}, onState: (_) {});
      engine.debugInstallFakeLink(onWrite: (_) async => false);
      await engine.applyHighFreqWakeWindow(
        enabled: true,
        targetWake: DateTime.now().add(const Duration(hours: 1)),
      );
      expect(engine.offloadSnapshot['high_freq_requested'], isFalse);
    });

    test('the gen5 clock commands carry the revision byte', () async {
      final w = _Wire(band: BandProfile.gen5);
      await w.engine.getClock();
      expect(w.lastCommandOf(2), <int>[Cmd.getClockGen5, 0x01]);
    });
  });

  group('P0 — an unset strap RTC is visible to the clock policy', () {
    test('an implausibly-low clock_epoch reaches shouldSetClock', () {
      final logs = <String>[];
      final engine = BleEngine(
        onRecord: (_, _) async {},
        onState: (_) {},
        log: logs.add,
      );
      // A strap whose RTC was never set. This is the exact reading
      // ClockPolicy.shouldSetClock was written for, and it used to be dropped
      // by the decoder before the policy ever saw it.
      engine.debugAbsorbDecoded(Decoded('cmd_response', {'clock_epoch': 100}));

      expect(ClockPolicy.shouldSetClock(100, _wallNow()), isTrue);
      expect(engine.clockRef, isNull,
          reason: 'a factory-epoch clock must not become the alarm '
              'correlation — the drift would be decades');
      expect(logs.where((l) => l.contains('never set')), isNotEmpty);
    });
  });


  group('the dangerous-opcode block sits on _write, not only on _send', () {
    // Nine call sites build their own frame and hand it to the lowest-level
    // write, bypassing `_send` entirely. All were benign, but the guard against
    // FORCE_TRIM (whose full-erase form is two 0xFEFEFEFE args), REBOOT and
    // POWER_CYCLE was bypassable by construction rather than by an audited
    // opt-out, on BOTH generations (the header length differs, the opcode's
    // position within the inner frame does not).
    for (final (label, band) in [
      ('gen4', BandProfile.gen4),
      ('gen5', BandProfile.gen5),
    ]) {
      test('a framed destructive opcode never reaches the radio ($label)',
          () {
        final sent = <Uint8List>[];
        final engine = BleEngine(
          onRecord: (_, _) async {},
          onState: (_) {},
          log: (_) {},
        );
        engine.debugInstallFakeLink(
          onWrite: (f) async {
            sent.add(f);
            return true;
          },
          band: band,
        );

        for (final opcode in dangerousCmds) {
          final frame = buildCommand(1, opcode, const [], band);
          expect(engine.debugWriteRaw(frame), completion(isFalse),
              reason: 'opcode 0x${opcode.toRadixString(16)} must be refused');
        }
      });
    }

    test('an ordinary command still goes out', () async {
      final sent = <Uint8List>[];
      final engine = BleEngine(
        onRecord: (_, _) async {},
        onState: (_) {},
        log: (_) {},
      );
      engine.debugInstallFakeLink(
        onWrite: (f) async {
          sent.add(f);
          return true;
        },
      );
      final ok = await engine.debugWriteRaw(
        buildCommand(1, Cmd.getBatteryLevel, const [], BandProfile.gen4),
      );
      expect(ok, isTrue);
      expect(sent, hasLength(1));
    });
  });
}
