// Issue #208: a band taken off for ten minutes, or carried out of range, never
// reconnects. The app shows "reconnecting", falls back to "disconnected", and
// stays there until the user forgets the band and re-pairs it.
//
// The dead end was terminal-by-design rather than flaky: `_reconnect()` was
// EDGE-triggered — its only caller is the `connected → disconnected`
// transition — and the whole retry loop sat inside one try/catch. Any throw
// inside the loop abandoned it for good, after which the engine rests at
// 'disconnected' so the edge can never fire again.

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/sync/sync_policy.dart';

void main() {
  group('superviseReconnect', () {
    ReconnectSupervisorAction call({
      bool paired = true,
      bool keepAlive = true,
      bool connected = false,
      bool loopRunning = false,
      bool connectInFlight = false,
      Duration? runningFor,
    }) => superviseReconnect(
      paired: paired,
      keepAlive: keepAlive,
      connected: connected,
      loopRunning: loopRunning,
      connectInFlight: connectInFlight,
      attemptRunningFor: runningFor,
    );

    test('disconnected with no loop running restarts the loop', () {
      // The state the app was stuck in — nothing else would ever fire.
      expect(call(), ReconnectSupervisorAction.start);
    });

    test('does nothing while connected', () {
      expect(call(connected: true), ReconnectSupervisorAction.none);
    });

    test('does nothing when unpaired or when we do not want a link', () {
      expect(call(paired: false), ReconnectSupervisorAction.none);
      expect(call(keepAlive: false), ReconnectSupervisorAction.none);
    });

    test('never fights a healthy attempt', () {
      // The Android OS-autoConnect branch waits up to 15 minutes for the band
      // to reappear. That is one NORMAL attempt, and restarting it is actively
      // harmful: the abandoned attempt's eventual disconnect() cancels the OS
      // pending connect its replacement is waiting on.
      expect(
        call(loopRunning: true, runningFor: const Duration(minutes: 15)),
        ReconnectSupervisorAction.none,
      );
      expect(
        call(loopRunning: true, runningFor: const Duration(minutes: 24)),
        ReconnectSupervisorAction.none,
      );
      expect(
        call(loopRunning: true, runningFor: null),
        ReconnectSupervisorAction.none,
      );
    });

    test('a loop running for hours is fine while its attempts turn over', () {
      // A band left at home keeps the loop alive indefinitely; only an
      // individual attempt that never returns is evidence of a wedge.
      expect(
        call(loopRunning: true, runningFor: const Duration(minutes: 3)),
        ReconnectSupervisorAction.none,
      );
    });

    test('restarts an attempt wedged well past the autoConnect window', () {
      // An await that never returns (a leaked band lease, a hung platform call)
      // leaves the in-flight flag true forever; re-triggering cannot fix that,
      // so the flag has to be treated as stale.
      expect(
        call(loopRunning: true, runningFor: const Duration(minutes: 25)),
        ReconnectSupervisorAction.restartStale,
      );
    });

    test('stays out of the way of a user-initiated connect', () {
      // `openSession` starts the supervisor before doing its own connect, and a
      // first connect (discovery, INIT) can outlast a 60 s tick. Starting a loop underneath it makes two callers race the
      // same peripheral and re-run the whole post-connect block.
      expect(call(connectInFlight: true), ReconnectSupervisorAction.none);
    });
  });

  // iOS: a suspended process runs no Dart timers, so a reconnect loop parked
  // in a long backoff never tried inside the few seconds a restore wake
  // grants. The wake has to be able to end the wait.
  group('WakeableDelay', () {
    test('a wake ends the backoff early', () {
      fakeAsync((async) {
        final d = WakeableDelay();
        var done = false;
        d.wait(const Duration(minutes: 5)).then((_) => done = true);
        async.elapse(const Duration(seconds: 1));
        expect(done, isFalse);
        expect(d.waiting, isTrue);
        expect(d.wake(), isTrue);
        async.flushMicrotasks();
        expect(done, isTrue);
        expect(d.waiting, isFalse);
      });
    });

    test('without a wake it waits the full backoff', () {
      fakeAsync((async) {
        final d = WakeableDelay();
        var done = false;
        d.wait(const Duration(seconds: 30)).then((_) => done = true);
        async.elapse(const Duration(seconds: 29));
        expect(done, isFalse);
        async.elapse(const Duration(seconds: 1));
        expect(done, isTrue);
      });
    });

    test('a wake with nothing waiting is a no-op, and says so', () {
      final d = WakeableDelay();
      expect(d.wake(), isFalse);
    });
  });
}
