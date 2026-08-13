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

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ble/ble_engine.dart';
import 'package:openstrap_protocol/openstrap_protocol.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
