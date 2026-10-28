// Real command-body decode and burst diagnostics; authored bytes, no radio claims.
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/ble/ble_engine.dart';
import 'package:whoop_protocol/whoop_protocol.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final band in [p.BandProfile.gen4, p.BandProfile.gen5]) {
    for (final outcome in ['unset', 'refused', 'short', 'measured']) {
      test(
        '${band.type.name} $outcome clock body cannot invent an alarm correlation',
        () async {
          final logs = <String>[], writes = <Uint8List>[];
          final engine = BleEngine(
            onRecord: (_, _) async {},
            onState: (_) {},
            log: logs.add,
          );
          engine.debugInstallFakeLink(
            band: band,
            onWrite: (frame) async {
              writes.add(frame);
              return false; // The test peripheral refuses all corrective writes.
            },
          );
          final gen5 = band.isGen5;
          final body = Uint8List(outcome == 'short' ? 5 : (gen5 ? 10 : 9));
          body[0] = p.PacketType.commandResponse;
          body[1] = 17;
          body[2] = gen5 ? p.Cmd.getClockGen5 : p.Cmd.getClock;
          body[3] = 11;
          body[4] = outcome == 'refused' ? 3 : 1;
          if (gen5 && body.length > 5)
            body[5] = 1; // Documented clock-body revision.
          final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
          if (outcome == 'measured')
            ByteData.sublistView(
              body,
            ).setUint32(gen5 ? 6 : 5, now, Endian.little);
          try {
            engine.debugProcessImmediateFrame(p.Frame(body, true, true));
            await Future<void>.delayed(const Duration(milliseconds: 80));
            if (outcome == 'measured') {
              expect(engine.clockRef, isNotNull);
              expect(writes, isEmpty);
            } else {
              expect(engine.clockRef, isNull);
              expect(engine.historyPausedForClock, false);
              expect(
                logs.any((l) => l.contains('strap RTC was never set')),
                outcome == 'unset',
              );
              expect(writes.isNotEmpty, outcome == 'unset');
            }
            expect(engine.pendingCommandCount, 0);
          } finally {
            await engine.disconnect();
          }
        },
      );
    }
  }
  test(
    'burst loss diagnostics distinguish per-revision missing, backward and non-data traffic',
    () {
      final stats = BurstStats();
      for (final (revision, counters) in [
        (24, [1, 3, 2]),
        (18, [10, 13, 13]),
      ]) {
        for (final counter in counters)
          stats.onHistoricalData(
            p.PacketType.historicalData,
            counter,
            revision,
          );
      }
      for (final revision in [16, 19, 22, 25, 26, -1, 99]) {
        stats.onHistoricalData(p.PacketType.historicalData, 1, revision);
      }
      stats
        ..onEvent()
        ..onConsole()
        ..onUnknown();
      expect(stats.intraBurstGapCount, 2);
      expect(stats.intraBurstMissing, 3);
      expect(stats.intraBurstBackward, 2);
      expect(stats.historicalPacketCount, 11);
      expect(stats.eventCount, 1);
      expect(stats.consoleCount, 1);
      expect(stats.unknownCount, 3);
      expect(stats.totalTrafficPacketCount, 16);
      expect(
        stats.sequenceSummary,
        'seqV18(gaps=1, missing=2, backward=1), seqV24(gaps=1, missing=1, backward=1)',
      );
      expect(
        stats.breakdownString,
        contains('V16=1, V19=1, V22=1, V25=1, V26=1'),
      );
      expect(() => stats.sequenceByRevision.clear(), throwsUnsupportedError);
      stats.reset();
      expect(stats.totalTrafficPacketCount, 0);
      expect(stats.sequenceSummary, isEmpty);
      expect(stats.breakdownString, '{}');
    },
  );
}
