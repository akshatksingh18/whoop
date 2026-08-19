// HeadlessSyncGate: mutual exclusion across EVERY headless wake source — the
// three iOS ones (BLE-restore, BGProcessingTask, BGAppRefreshTask) and the
// Android post-boot wake — plus the skip-streak telemetry that makes repeated
// wake-source collisions observable instead of a single easy-to-miss
// debugPrint line.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/sync/band_ownership.dart';
import 'package:openstrap_edge/sync/headless_boot.dart';
import 'package:openstrap_edge/sync/headless_gate.dart';

void main() {
  setUp(() {
    HeadlessSyncGate.resetForTest();
    BandOwnership.resetForTest();
  });

  test('a solo run is never a skip and leaves no streak', () async {
    final result = await HeadlessSyncGate.tryRun<int>('owner_a', () async => 1);
    expect(result, 1);
    expect(HeadlessSyncGate.consecutiveSkipsFor('owner_a'), 0);
    expect(HeadlessSyncGate.totalSkips, 0);
  });

  test('a collision skips the second caller and returns null', () async {
    final gateHeld = Completer<void>();
    final releaseGate = Completer<void>();
    final firstRun = HeadlessSyncGate.tryRun<void>('owner_a', () async {
      gateHeld.complete();
      await releaseGate.future;
    });
    await gateHeld.future;

    final second = await HeadlessSyncGate.tryRun<int>('owner_b', () async => 2);
    expect(second, isNull);
    expect(HeadlessSyncGate.consecutiveSkipsFor('owner_b'), 1);
    expect(HeadlessSyncGate.totalSkips, 1);

    releaseGate.complete();
    await firstRun;
  });

  test('consecutive skips accumulate per-owner independently', () async {
    final gateHeld = Completer<void>();
    final releaseGate = Completer<void>();
    final firstRun = HeadlessSyncGate.tryRun<void>('owner_a', () async {
      gateHeld.complete();
      await releaseGate.future;
    });
    await gateHeld.future;

    await HeadlessSyncGate.tryRun<int>('owner_b', () async => 2); // skip #1
    await HeadlessSyncGate.tryRun<int>('owner_b', () async => 2); // skip #2
    await HeadlessSyncGate.tryRun<int>('owner_c', () async => 3); // owner_c skip #1

    expect(HeadlessSyncGate.consecutiveSkipsFor('owner_b'), 2);
    expect(HeadlessSyncGate.consecutiveSkipsFor('owner_c'), 1);
    expect(HeadlessSyncGate.totalSkips, 3);

    releaseGate.complete();
    await firstRun;
  });

  test('a successful run resets that owner\'s own streak, not others\'',
      () async {
    final gateHeld = Completer<void>();
    final releaseGate = Completer<void>();
    final firstRun = HeadlessSyncGate.tryRun<void>('owner_a', () async {
      gateHeld.complete();
      await releaseGate.future;
    });
    await gateHeld.future;
    await HeadlessSyncGate.tryRun<int>('owner_b', () async => 2); // skip
    await HeadlessSyncGate.tryRun<int>('owner_c', () async => 3); // skip
    releaseGate.complete();
    await firstRun;

    expect(HeadlessSyncGate.consecutiveSkipsFor('owner_b'), 1);
    expect(HeadlessSyncGate.consecutiveSkipsFor('owner_c'), 1);

    // owner_b finally gets to run — its OWN streak clears; owner_c's doesn't.
    await HeadlessSyncGate.tryRun<int>('owner_b', () async => 4);
    expect(HeadlessSyncGate.consecutiveSkipsFor('owner_b'), 0);
    expect(HeadlessSyncGate.consecutiveSkipsFor('owner_c'), 1);
  });

  test('busy reflects gate ownership across the run', () async {
    expect(HeadlessSyncGate.busy, isFalse);
    final gateHeld = Completer<void>();
    final releaseGate = Completer<void>();
    final run = HeadlessSyncGate.tryRun<void>('owner_a', () async {
      gateHeld.complete();
      await releaseGate.future;
    });
    await gateHeld.future;
    expect(HeadlessSyncGate.busy, isTrue);
    releaseGate.complete();
    await run;
    expect(HeadlessSyncGate.busy, isFalse);
  });

  group('a wedged run cannot hold the gate forever', () {
    test('the run is abandoned at the ceiling and the gate is handed back',
        () async {
      final wedged = Completer<void>(); // never completed — the whole point
      final result = await HeadlessSyncGate.tryRun<int>(
        'bg_task',
        () async {
          await wedged.future;
          return 1;
        },
        ceiling: const Duration(milliseconds: 20),
      );

      // OLD BEHAVIOUR: tryRun awaited body() with nothing above it, so this
      // never returned and `busy` stayed true for the life of the process —
      // every later BGProcessingTask / BGAppRefreshTask / BLE-restore / boot
      // wake skipped forever and background sync silently stopped.
      expect(result, isNull);
      expect(HeadlessSyncGate.busy, isFalse);
      expect(HeadlessSyncGate.timedOutRuns, 1);

      // And the next wake actually runs.
      expect(
        await HeadlessSyncGate.tryRun<int>('bg_refresh', () async => 7),
        7,
      );
    });

    test(
        'a timeout also frees the band, not just the gate — the orphaned '
        'body never gets to run its own release', () async {
      // Mirrors the three iOS entry points: runHeadlessSync() self-acquires
      // its lease with no way for the caller to hand it back, so the ONLY
      // thing that can free the band on a wedge is the gate's own timeout
      // handler.
      final wedged = Completer<void>();
      final lease = BandOwnership.tryAcquireHeadless();
      expect(lease, isNotNull, reason: 'nothing else owns the band yet');

      final result = await HeadlessSyncGate.tryRun<int>(
        'ios_bg_task',
        () async {
          await wedged.future; // never completes — the orphaned frame
          BandOwnership.release(lease!); // never reached
          return 1;
        },
        ceiling: const Duration(milliseconds: 20),
      );

      expect(result, isNull);
      // Before this fix: BandOwnership stayed headless-owned forever here —
      // every later headless wake would silently no-op, and a foreground
      // connect attempt would spin in acquireForeground()'s wait loop with
      // nothing left alive to ever complete it.
      expect(BandOwnership.owner, isNull,
          reason: 'a wedged run must not strand the band lease');

      // A foreground connect attempt actually completes instead of hanging.
      final fg = await BandOwnership.acquireForeground();
      expect(fg.kind, BandOwnerKind.foreground);
    });

    test('an owner that keeps losing is reported as starved', () async {
      final release = Completer<void>();
      final holder = HeadlessSyncGate.tryRun<void>('bg_task', () async {
        await release.future;
      });
      await Future<void>.delayed(Duration.zero);

      for (var i = 0; i < HeadlessSyncGate.starvedAfterSkips; i++) {
        expect(HeadlessSyncGate.isStarved('ble_restore_wake'), isFalse,
            reason: 'not starved until the threshold is actually crossed');
        await HeadlessSyncGate.tryRun<int>('ble_restore_wake', () async => 1);
      }
      expect(HeadlessSyncGate.isStarved('ble_restore_wake'), isTrue);
      // Its own successful run clears it.
      release.complete();
      await holder;
      await HeadlessSyncGate.tryRun<int>('ble_restore_wake', () async => 1);
      expect(HeadlessSyncGate.isStarved('ble_restore_wake'), isFalse);
    });
  });

  group('P2 — the Android boot wake goes through the gate too', () {
    test('the gate is BUSY for the whole duration of a boot drain', () async {
      final lease = BandOwnership.tryAcquireHeadless()!;
      final started = Completer<void>();
      final finish = Completer<void>();

      final run = runBootSyncThroughGate(
        lease,
        runner: (l) async {
          started.complete();
          await finish.future;
          return true;
        },
      );

      await started.future;
      // OLD BEHAVIOUR: the boot path called runHeadlessSync(lease: lease)
      // directly and fire-and-forget, so `busy` read false for the entire
      // boot drain and any other wake source would have run concurrently.
      expect(HeadlessSyncGate.busy, isTrue);
      expect(
        await HeadlessSyncGate.tryRun<int>('ble_restore_wake', () async => 7),
        isNull,
        reason: 'another wake source must SKIP while the boot drain holds it',
      );

      finish.complete();
      expect(await run, isTrue);
      expect(HeadlessSyncGate.busy, isFalse);
    });

    test('a boot wake that loses the race skips AND releases its band lease',
        () async {
      final lease = BandOwnership.tryAcquireHeadless()!;
      expect(BandOwnership.owner, BandOwnerKind.headless);

      final finish = Completer<void>();
      final holder = HeadlessSyncGate.tryRun<void>('ios_bg_task', () async {
        await finish.future;
      });

      var ran = false;
      final result = await runBootSyncThroughGate(
        lease,
        runner: (l) async {
          ran = true;
          return true;
        },
      );

      expect(result, isNull);
      expect(ran, isFalse);
      // The lease was acquired before the gate was consulted; a skipped cycle
      // must hand it back or the band stays owned by a run that never happened.
      expect(BandOwnership.owner, isNull);
      expect(HeadlessSyncGate.consecutiveSkipsFor(kBootWakeGateOwner), 1);

      finish.complete();
      await holder;
    });
  });
}
