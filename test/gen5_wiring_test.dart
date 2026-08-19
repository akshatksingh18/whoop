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

    test('INIT no longer re-sends the hello — it belongs to connect setup',
        () async {
      // The official order is hello FIRST, during setup, so its timestamp can
      // drive the clock decision and its identity fields are available to
      // everything after. Sending it again at INIT would be a second identity
      // exchange after every consumer has already run.
      final w = _Wire(band: BandProfile.gen5);
      await w.engine.sendInit();
      final opcodes = w.frames
          .map((f) => parseFrame(f, profile: BandProfile.gen5))
          .where((p) => p != null && p.valid)
          .map((p) => p!.inner[2])
          .toList();
      expect(opcodes, isNot(contains(Cmd.getHello)));
      expect(opcodes, contains(Cmd.sendHistoricalData));
    });

    test('the wake window uses the official 180 s / 7200 s Smart Alarm values',
        () async {
      // doc 14: ENTER_HIGH_FREQ_SYNC(96) body `02 b4 00 20 1c` — rev 2, then
      // interval 180 s and duration 7200 s as u16 LE. The old 61 s/90 min
      // defaults were picked only to clear gen5's "> 60" floor.
      final w = _Wire(band: BandProfile.gen5);
      await w.engine.applyHighFreqWakeWindow(
        enabled: true,
        targetWake: DateTime.now().add(const Duration(hours: 2)),
      );
      expect(w.lastCommandOf(6), <int>[
        Cmd.enterHighFreqSync,
        0x02, // revision
        0xb4, 0x00, // interval 180 s, u16 LE
        0x20, 0x1c, // duration 7200 s, u16 LE
      ]);
    });

    test('runStoredAlarm sends the official rev-2 body with the alarm id',
        () async {
      // doc 14 "Run alarm now — opcode 68": body `02 01`. This is the early-wake
      // mechanism; the rev-1 gen4 body does nothing on gen5.
      final w = _Wire(band: BandProfile.gen5);
      await w.engine.runStoredAlarm();
      expect(w.lastCommandOf(3),
          <int>[Cmd.runAlarm, 0x02, AlarmPayloads.gen5Slot]);
      expect(AlarmPayloads.gen5Slot, 1);
    });

    test('gen5 reads the clock with the OFFICIAL GET_CLOCK(11), empty body',
        () async {
      // Opcode 147 ("GET_CLOCK_GEN5") appears nowhere in the official 75-opcode
      // enum. The confirmed gen5 contract is the shared opcode 11 with an EMPTY
      // body — physically exercised on a real WHOOP 5 (the probe read the clock
      // this way and measured ~2410 ms drift before setting it).
      final w = _Wire(band: BandProfile.gen5);
      await w.engine.getClock();
      expect(w.lastCommandOf(1), <int>[Cmd.getClock]);
      expect(Cmd.getClock, 11);
    });

    test('gen5 sets the clock with the OFFICIAL SET_CLOCK(10), 8-byte body',
        () async {
      // <u32 whole seconds><u32 subseconds>, no revision byte — the form that
      // returned SUCCESS from a real WHOOP 5. A wrong clock write is silent:
      // the RTC never latches and every alarm is then armed against it.
      final w = _Wire(band: BandProfile.gen5);
      await w.engine.setClock();
      // setClock() reads the RTC back afterwards, so SET is not the last frame.
      final set = w.frames
          .map((f) => parseFrame(f, profile: BandProfile.gen5))
          .where((p) => p != null && p.valid)
          .map((p) => p!.inner.sublist(2))
          .firstWhere((c) => c.first == Cmd.setClock);
      expect(Cmd.setClock, 10);
      // opcode + 8 body bytes (the frame is 4-byte padded beyond that).
      expect(set.sublist(0, 9).length, 9);
      // Subseconds are a u16 in the low half of the second u32; top 2 bytes 0.
      expect(set.sublist(7, 9), <int>[0, 0]);
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
}
