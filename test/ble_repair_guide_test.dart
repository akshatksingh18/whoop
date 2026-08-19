// Regression tests for two engine flags that were effectively set-only:
// `needsRepairGuide` (renders a fault card telling the user to forget the bond
// and re-pair) and `_strapHistoryNewestTs` (the backlog target the foreground
// catch-up loop chases).

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ble/ble_engine.dart';
import 'package:openstrap_protocol/openstrap_protocol.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  BleEngine newEngine([List<String>? logs]) => BleEngine(
        onRecord: (sample, raw) async {},
        onState: (_) {},
        log: logs?.add,
      );

  int wallNow() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  group('the re-pair guide can be contradicted', () {
    test('a command reply clears it', () {
      final engine = newEngine();
      // What one refused createBond, or a post-bond loop trip, leaves behind.
      engine.state.needsRepairGuide = true;

      engine.debugAbsorbDecoded(Decoded('cmd_response', <String, dynamic>{}));

      expect(engine.state.needsRepairGuide, isFalse,
          reason: 'the band answered an encrypted command — nothing about the '
              'bond is blocking traffic, so the card must go. It used to be '
              'clearable ONLY inside refreshAutoReconnectPause, behind an '
              '`autoReconnectPaused` that a single bond failure never sets.');
    });

    test('a live-HR frame is not evidence and does not clear it', () {
      final engine = newEngine();
      engine.state.needsRepairGuide = true;

      engine.debugAbsorbDecoded(Decoded('realtime_hr', {'hr': 61}));

      expect(engine.state.needsRepairGuide, isTrue,
          reason: 'an unsolicited notification is not a command round-trip');
    });
  });

  group('post-bond loop needs REAL timeouts', () {
    test('two ordinary drops just after setup do not raise the guide', () {
      final engine = newEngine();
      // PostBondTimeoutLoopDetector(tripThreshold: 2, quickTimeoutWindow: 8.0)
      // and `_bondTime` is stamped in the connect setup on BOTH platforms, so
      // with the old hardcoded `timedOut: true` these two calls tripped it.
      engine.debugFeedDisconnect(timedOut: false);
      engine.debugFeedDisconnect(timedOut: false);

      expect(engine.state.needsRepairGuide, isFalse);
    });

    test('two quick post-bond timeouts still raise it', () {
      final engine = newEngine();
      engine.debugFeedDisconnect(timedOut: true);
      engine.debugFeedDisconnect(timedOut: true);

      expect(engine.state.needsRepairGuide, isTrue,
          reason: 'the detector this exists for must still fire');
    });

    test('a command reply re-arms the detector, so it can trip again', () {
      final engine = newEngine();
      engine.debugFeedDisconnect(timedOut: true);
      engine.debugFeedDisconnect(timedOut: true);
      expect(engine.state.needsRepairGuide, isTrue);

      engine.debugAbsorbDecoded(Decoded('cmd_response', <String, dynamic>{}));
      expect(engine.state.needsRepairGuide, isFalse);

      // PostBondTimeoutLoopDetector latches on `tripped`, so without a reset
      // alongside the clear the guide would be gone for good.
      engine.debugFeedDisconnect(timedOut: true);
      engine.debugFeedDisconnect(timedOut: true);
      expect(engine.state.needsRepairGuide, isTrue);
    });
  });

  group('GET_DATA_RANGE has ONE gate', () {
    Decoded rangeReply(int oldest, int newest) => Decoded('cmd_response', {
          'opcode': Cmd.getDataRange,
          'range_oldest': oldest,
          'range_newest': newest,
        });

    test('a plausible range is adopted as the backlog target', () {
      final engine = newEngine();
      final now = wallNow();

      engine.debugAbsorbDecoded(rangeReply(now - 86400, now - 60));

      expect(engine.strapHistoryNewestTs, now - 60);
      expect(engine.state.dataRangeNewest, now - 60);
    });

    test('a corrupt future newest reaches neither field', () {
      final engine = newEngine();
      final now = wallNow();
      // Inside protocol's own screen (`_maxPlausibleUnix` = 2100-01) and so
      // emitted, but years past isCorruptFutureRtc's ceiling. This used to be
      // rejected for `dataRangeNewest` and accepted for `strapHistoryNewestTs`
      // in the very same callback — which pinned `backlogRemains` true and
      // burned all 20 backfill sessions on every foreground catch-up.
      engine.debugAbsorbDecoded(rangeReply(now - 86400, now + 400 * 86400));

      expect(engine.strapHistoryNewestTs, isNull);
      expect(engine.state.dataRangeNewest, isNull);
    });

    // SD-08. `pages_behind` was parsed by protocol and read by nobody.
    test('pages_behind is read off the same reply', () {
      final engine = newEngine();
      final now = wallNow();

      engine.debugAbsorbDecoded(Decoded('cmd_response', {
        'opcode': Cmd.getDataRange,
        'range_oldest': now - 86400,
        'range_newest': now - 60,
        'pages_behind': const {
          'written': 1200,
          'used': 4000,
          'capacity': 2048,
          'trim_page': 900,
          'wrap_count': 3,
          'free_records': 500,
        },
      }));

      expect(engine.lastPagesBehind?['free_records'], 500);
      expect(engine.lastPagesBehind?['wrap_count'], 3);
    });

    test('a corrupt-clock reply still yields its backlog', () {
      final engine = newEngine();
      final now = wallNow();
      // The epochs are rejected by isCorruptFutureRtc; the page counters are
      // not timestamps and must not be thrown away with them.
      engine.debugAbsorbDecoded(Decoded('cmd_response', {
        'opcode': Cmd.getDataRange,
        'range_oldest': now - 86400,
        'range_newest': now + 400 * 86400,
        'pages_behind': const {'free_records': 7, 'wrap_count': 1},
      }));

      expect(engine.strapHistoryNewestTs, isNull);
      expect(engine.lastPagesBehind?['free_records'], 7);
    });
  });
}
