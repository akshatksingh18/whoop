// Regression tests for the phone-clock trust gate — the thing standing between
// a phone whose wall clock is a day slow and permanent, silent data loss.
//
// The failure it guards: when the phone reads slow, the strap's correctly
// stamped records look "implausibly future", the record gate drops them, and
// the HISTORY_END ACK then trims them off the band's flash for good. So while
// the phone is the suspect party we neither drain history nor push our wall
// clock onto the strap.
//
// Both halves of that refusal were reachable around, which is what these cover:
// the SET_CLOCK half was handed straight back by the drift-correction retry
// sitting behind the gate's own read-back.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ble/ble_engine.dart';
import 'package:openstrap_protocol/openstrap_protocol.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _transportTests();

  BleEngine newEngine(List<String> logs) => BleEngine(
        onRecord: (sample, raw) async {},
        onState: (_) {},
        log: logs.add,
      );

  /// A GET_CLOCK response carrying [strapEpoch] as the strap RTC.
  Decoded clockReply(int strapEpoch) =>
      Decoded('cmd_response', {'clock_epoch': strapEpoch});

  int wallNow() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  group('P0 — a slow phone never gets to write its clock onto the strap', () {
    test('a plausible strap RTC >1d ahead defers history and blocks SET_CLOCK',
        () {
      final logs = <String>[];
      final engine = newEngine(logs);

      // Strap two days ahead of us and plausible => the PHONE is the suspect
      // one. shouldSetClock is also true here (drift > 1 day), which is exactly
      // the collision: the drift correction wants to write, the trust gate says
      // it must not.
      engine.debugAbsorbDecoded(clockReply(wallNow() + 2 * 86400));

      expect(engine.historyPausedForClock, isTrue,
          reason: 'history must defer rather than drain-and-trim');
      expect(
        logs.where((l) => l.contains('re-issuing SET_CLOCK')),
        isEmpty,
        reason: 'writing our slow wall clock onto a correct RTC would corrupt '
            'it AND destroy the evidence — the read-back then agrees forever',
      );
      // Two independent gates have to stay lined up for that to hold: the
      // corrupt-read ceiling and the phone-suspect threshold both key off
      // kFutureMargin, so today the read is rejected before the SET_CLOCK
      // retry is even reached. This asserts the OUTCOME, not which gate got
      // there first — so loosening either one still trips the test.
      expect(engine.clockRef, isNull,
          reason: 'a read we do not trust must not become the alarm '
              'correlation either');
    });

    test('a strap RTC BEHIND us is a strap problem and is still corrected', () {
      final logs = <String>[];
      final engine = newEngine(logs);

      // Two days behind: drifted or unset. Nothing suspicious about the phone,
      // so the correction must still run — the gate is not allowed to become a
      // blanket "never SET_CLOCK".
      engine.debugAbsorbDecoded(clockReply(wallNow() - 2 * 86400));

      expect(engine.historyPausedForClock, isFalse);
      expect(logs.any((l) => l.contains('re-issuing SET_CLOCK')), isTrue);
    });

    test('a fast strap RTC IS corrected once the grace window expires', () {
      final logs = <String>[];
      final engine = newEngine(logs);

      engine.debugAbsorbDecoded(clockReply(wallNow() + 2 * 86400));
      expect(engine.historyPausedForClock, isTrue);
      expect(logs.any((l) => l.contains('re-issuing SET_CLOCK')), isFalse,
          reason: 'during grace the phone is still the suspect party');

      // Twelve hours on and the reading has not budged: the phone would have
      // re-synced over NTP long ago, so it is the STRAP that runs fast.
      engine.debugExpireClockSuspicion();
      engine.debugAbsorbDecoded(clockReply(wallNow() + 2 * 86400));

      expect(engine.historyPausedForClock, isFalse,
          reason: 'history must stop deferring or sync stalls for good');
      expect(
        logs.any((l) => l.contains('re-issuing SET_CLOCK')),
        isTrue,
        reason: 'OLD BEHAVIOUR: correction was nested inside the '
            'acceptsClockRead branch, which rejects on the SAME margin that '
            'flags the strap as fast — so history un-deferred straight back '
            'onto an uncorrected fast RTC whose records the gate then dropped',
      );
      // The two decisions are now independent, which is the whole point: this
      // same read is still refused as an alarm correlation (a far-future value
      // would arm the alarm years out) while being acted on as a correction.
      expect(logs.any((l) => l.contains('corrupt strap RTC read')), isTrue);
      expect(engine.clockRef, isNull);
    });

    test('the gate lifts the moment a read shows the clocks agreeing', () {
      final logs = <String>[];
      final engine = newEngine(logs);

      engine.debugAbsorbDecoded(clockReply(wallNow() + 2 * 86400));
      expect(engine.historyPausedForClock, isTrue);

      // The phone corrected itself over NTP; the next read agrees.
      engine.debugAbsorbDecoded(clockReply(wallNow()));
      expect(engine.historyPausedForClock, isFalse,
          reason: 'sync must resume without waiting out the grace window');
    });
  });
}

/// TRANSPORT-LEVEL coverage: these drive `_readClock` and
/// `_startHistoricalRefresh` for real over a stubbed GATT write, rather than
/// injecting a `Decoded` and trusting the flows around it. That distinction is
/// the point — a reply that lands late, or one belonging to a different
/// request, only goes wrong in the ordering, which handler-level tests cannot
/// see.
void _transportTests() {
  /// Opcode of an outgoing command frame: inner starts at byte 4 and is
  /// `[pktType, seq, opcode, ...]`, so the opcode is at 6 and the seq at 5.
  int opcodeOf(Uint8List frame) => frame[6];
  int seqOf(Uint8List frame) => frame[5];

  /// A GET_CLOCK reply. Omitting [reqSeq] models firmware that does not echo
  /// the request seq back at all.
  Decoded clockReply(int strapEpoch, {int? reqSeq}) {
    final fields = <String, dynamic>{
      'opcode': Cmd.getClock,
      'clock_epoch': strapEpoch,
    };
    if (reqSeq != null) fields['req_seq'] = reqSeq;
    return Decoded('cmd_response', fields);
  }

  int wallNow() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  group('P0 — history never goes out ahead of the clock verdict', () {
    test(
      'a GET_CLOCK reply arriving long after the old 120ms sleep still gates '
      'the drain',
      () async {
        final sent = <int>[];
        final engine = BleEngine(
          onRecord: (sample, raw) async {},
          onState: (_) {},
        );
        int? clockSeq;
        engine.debugInstallFakeLink(onWrite: (frame) async {
          sent.add(opcodeOf(frame));
          if (opcodeOf(frame) == Cmd.getClock) clockSeq = seqOf(frame);
          return true;
        });

        final refresh = engine.debugStartHistoricalRefresh();

        // 500ms — four times the fixed sleep the gate used to rely on. The
        // strap is slow but perfectly healthy; a busy link queues the reply
        // behind a burst of historical frames all the time.
        await Future<void>.delayed(const Duration(milliseconds: 500));
        expect(
          sent,
          isNot(contains(Cmd.sendHistoricalData)),
          reason: 'OLD BEHAVIOUR: the 120ms sleep expired, the stale flag read '
              'false, and history drained before the strap had answered',
        );

        engine.debugAbsorbDecoded(
          clockReply(wallNow() + 2 * 86400, reqSeq: clockSeq),
        );

        expect(await refresh, isFalse);
        expect(sent, isNot(contains(Cmd.sendHistoricalData)),
            reason: 'the reply says the phone clock is suspect — defer');
        expect(engine.historyPausedForClock, isTrue);
      },
    );

    test('a healthy clock reply lets the drain through', () async {
      final sent = <int>[];
      final engine = BleEngine(onRecord: (s, r) async {}, onState: (_) {});
      int? clockSeq;
      engine.debugInstallFakeLink(onWrite: (frame) async {
        sent.add(opcodeOf(frame));
        if (opcodeOf(frame) == Cmd.getClock) clockSeq = seqOf(frame);
        return true;
      });

      final refresh = engine.debugStartHistoricalRefresh();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      engine.debugAbsorbDecoded(clockReply(wallNow(), reqSeq: clockSeq));

      expect(await refresh, isTrue);
      expect(sent, contains(Cmd.sendHistoricalData));
    });

    test(
      "another request's GET_CLOCK reply does not satisfy this read's gate",
      () async {
        final sent = <int>[];
        final engine = BleEngine(onRecord: (s, r) async {}, onState: (_) {});
        int? clockSeq;
        engine.debugInstallFakeLink(onWrite: (frame) async {
          sent.add(opcodeOf(frame));
          if (opcodeOf(frame) == Cmd.getClock) clockSeq = seqOf(frame);
          return true;
        });

        final refresh = engine.debugStartHistoricalRefresh();
        await Future<void>.delayed(const Duration(milliseconds: 20));

        // A reply to somebody else's poll — setClock's read-back, or the
        // keep-alive — carrying a healthy verdict. It must NOT release this
        // read: our own reply, still in flight, is the suspect one.
        final foreignSeq = ((clockSeq ?? 0) + 1) & 0xFF;
        engine.debugAbsorbDecoded(clockReply(wallNow(), reqSeq: foreignSeq));
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(
          sent,
          isNot(contains(Cmd.sendHistoricalData)),
          reason: "an unrelated reply released the waiter, so the drain went "
              'out on a verdict from a request this read never made',
        );

        engine.debugAbsorbDecoded(
          clockReply(wallNow() + 2 * 86400, reqSeq: clockSeq),
        );
        expect(await refresh, isFalse);
        expect(engine.historyPausedForClock, isTrue);
      },
    );

    test(
      'firmware that never echoes the seq still gates, on the grace fallback',
      () async {
        final sent = <int>[];
        final engine = BleEngine(onRecord: (s, r) async {}, onState: (_) {});
        engine.debugInstallFakeLink(onWrite: (frame) async {
          sent.add(opcodeOf(frame));
          return true;
        });

        final refresh = engine.debugStartHistoricalRefresh();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        // No req_seq at all: the correlation can never match. The read must
        // still use this verdict rather than stalling out the full timeout
        // and quietly falling back to whatever the last connection thought.
        engine.debugAbsorbDecoded(clockReply(wallNow() + 2 * 86400));

        expect(await refresh, isFalse);
        expect(engine.historyPausedForClock, isTrue);
        expect(sent, isNot(contains(Cmd.sendHistoricalData)));
      },
    );

    test('a failed SEND_HISTORICAL_DATA write is reported as not sent',
        () async {
      final engine = BleEngine(onRecord: (s, r) async {}, onState: (_) {});
      int? clockSeq;
      engine.debugInstallFakeLink(onWrite: (frame) async {
        if (opcodeOf(frame) == Cmd.getClock) {
          clockSeq = seqOf(frame);
          return true;
        }
        // The radio drops exactly the command that matters.
        return opcodeOf(frame) != Cmd.sendHistoricalData;
      });

      final refresh = engine.debugStartHistoricalRefresh();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      engine.debugAbsorbDecoded(clockReply(wallNow(), reqSeq: clockSeq));

      expect(await refresh, isFalse,
          reason: 'claiming success wedges _offloadActive on a strap that was '
              'never asked for history, and every later refresh then stops at '
              'the already-transmitting guard');
    });
  });
}
