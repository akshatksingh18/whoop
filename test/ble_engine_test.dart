import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ble/ble_engine.dart';

void main() {
  group('historical burst packet accounting', () {
    test('counts ordinary historical revisions and extended revisions', () {
      final count = countHistoricalBurstPackets(
        dataPacketCountsByRevision: const {24: 30, 10: 5},
        revision16Count: 2,
        revision19Count: 3,
        revision22Count: 4,
        revision25Count: 6,
        revision26Count: 7,
      );
      expect(count, 57);
    });

    test('traffic count includes historical packets plus side traffic', () {
      final historical = countHistoricalBurstPackets(
        dataPacketCountsByRevision: const {24: 30},
      );
      final traffic = countBurstTrafficPackets(
        dataPacketCountsByRevision: const {24: 30},
        consoleCount: 17,
        eventCount: 5,
        unknownCount: 2,
      );

      expect(historical, 30);
      expect(traffic, 54);
      expect(historical, isNot(traffic));
    });

    test(
      'whoop history-end expected count matches transport-envelope traffic, not just stored historical records',
      () {
        final historical = countHistoricalBurstPackets(
          dataPacketCountsByRevision: const {24: 30},
        );
        final traffic = countBurstTrafficPackets(
          dataPacketCountsByRevision: const {24: 30},
          consoleCount: 17,
          eventCount: 2,
        );

        expect(historical, 30);
        expect(traffic, 49);
        expect(traffic, isNot(historical));
      },
    );

    test(
      'log-shaped burst from device validates on traffic count even when only a subset are persisted historical rows',
      () {
        final historical = countHistoricalBurstPackets(
          dataPacketCountsByRevision: const {24: 15},
        );
        final traffic = countBurstTrafficPackets(
          dataPacketCountsByRevision: const {24: 15},
          eventCount: 2,
          consoleCount: 37,
        );

        expect(historical, 15);
        expect(traffic, 54);
      },
    );
  });

  group('burst packet count validation (dropped-record carve-out)', () {
    test('matches when nothing was gate-rejected', () {
      expect(
        burstPacketCountMatches(
          expectedPacketCount: 26,
          actualBurstPacketCount: 26,
          droppedThisBurst: 0,
        ),
        isTrue,
      );
    });

    test(
      'a real mismatch (band reports more than we saw at all) still fails',
      () {
        expect(
          burstPacketCountMatches(
            expectedPacketCount: 50,
            actualBurstPacketCount: 26,
            droppedThisBurst: 0,
          ),
          isFalse,
        );
      },
    );

    test(
      'matches once gate-rejected (stale-clock block) records are added '
      'back in — the exact shape of the real bug: expected=50, only 26 '
      'passed the plausibility gate, 24 were legitimately dropped',
      () {
        expect(
          burstPacketCountMatches(
            expectedPacketCount: 50,
            actualBurstPacketCount: 26,
            droppedThisBurst: 24,
          ),
          isTrue,
        );
      },
    );

    test('does not over-forgive — dropped count must exactly close the gap',
        () {
      expect(
        burstPacketCountMatches(
          expectedPacketCount: 50,
          actualBurstPacketCount: 26,
          droppedThisBurst: 10, // leaves a real 14-packet gap unexplained
        ),
        isFalse,
      );
    });
  });

  group('burst completeness shortfall (log-only would-flag signal)', () {
    test('no shortfall when all-types received total equals num_packets', () {
      // Band sent 49 frames (30 R24 + 17 console + 2 event); we received all.
      final received = countBurstTrafficPackets(
        dataPacketCountsByRevision: const {24: 30},
        consoleCount: 17,
        eventCount: 2,
      );
      expect(
        burstPacketShortfall(
          expectedPacketCount: 49,
          receivedTrafficCount: received,
        ),
        0,
      );
    });

    test(
      'interleaved console/event frames do NOT false-positive: comparing '
      'against the all-types received total (not the banked R24 subset) '
      'keeps shortfall at zero',
      () {
        final received = countBurstTrafficPackets(
          dataPacketCountsByRevision: const {24: 15},
          consoleCount: 37,
          eventCount: 2,
        );
        // Banked R24 subset alone is 15 — comparing THAT to num_packets=54
        // would fabricate a 39-frame "loss". The correct all-types total is 54.
        expect(received, 54);
        expect(
          burstPacketShortfall(
            expectedPacketCount: 54,
            receivedTrafficCount: received,
          ),
          0,
        );
      },
    );

    test('positive shortfall flags true frame loss (band sent more than we got)',
        () {
      final received = countBurstTrafficPackets(
        dataPacketCountsByRevision: const {24: 20},
        consoleCount: 3,
      );
      // Band reported 30, we received 23 all-types, nothing gate-dropped → 7 lost.
      expect(
        burstPacketShortfall(
          expectedPacketCount: 30,
          receivedTrafficCount: received,
        ),
        7,
      );
    });

    test('gate-dropped records are added back so they never read as loss', () {
      // 26 all-types received, 24 legitimately gate-dropped, band expected 50 →
      // fully explained, no true loss.
      expect(
        burstPacketShortfall(
          expectedPacketCount: 50,
          receivedTrafficCount: 26,
          droppedThisBurst: 24,
        ),
        0,
      );
    });

    test('negative shortfall (retries/dupes counted extra) is not loss', () {
      expect(
        burstPacketShortfall(
          expectedPacketCount: 26,
          receivedTrafficCount: 28,
        ),
        lessThan(0),
      );
    });

    test('shortfall==0 is exactly burstPacketCountMatches', () {
      const expected = 50, received = 26, dropped = 24;
      final matches = burstPacketCountMatches(
        expectedPacketCount: expected,
        actualBurstPacketCount: received,
        droppedThisBurst: dropped,
      );
      final shortfall = burstPacketShortfall(
        expectedPacketCount: expected,
        receivedTrafficCount: received,
        droppedThisBurst: dropped,
      );
      expect(matches, (shortfall == 0));
    });
  });

  group('maintenance traffic gating', () {
    test('maintenance traffic is paused while offload is active', () {
      expect(shouldPauseMaintenanceTraffic(offloadActive: true), isTrue);
    });

    test('maintenance traffic runs when offload is inactive', () {
      expect(shouldPauseMaintenanceTraffic(offloadActive: false), isFalse);
    });
  });
}
