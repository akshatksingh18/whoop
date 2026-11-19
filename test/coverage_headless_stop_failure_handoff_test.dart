// Native-stop callback failure must not wedge the shared timeout gate/lease.
// This checks process-local policy;no OS wake,transport or ACK is fabricated.
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/sync/band_ownership.dart';
import 'package:whoop_companion/sync/headless_gate.dart';

void main() {
  setUp(() {
    HeadlessSyncGate.resetForTest();
    BandOwnership.resetForTest();
  });
  tearDown(() {
    HeadlessSyncGate.resetForTest();
    BandOwnership.resetForTest();
  });
  for (final lateFailure in [false, true]) {
    test(
      'refused stop releases the timed-out lease;late failure=$lateFailure cannot release its successor',
      () async {
        final old = BandOwnership.tryAcquireHeadless()!;
        final release = Completer<int>(), nextRelease = Completer<int>();
        final reasons = <String>[];
        BandOwnership.registerHeadlessStop(old, (reason) {
          reasons.add(reason);
          throw StateError('authored native stop refusal');
        });
        try {
          final first = HeadlessSyncGate.tryRun<int>(
            'authored-old-native-stop',
            () async {
              try {
                return await release.future;
              } finally {
                BandOwnership.release(old);
              }
            },
            ceiling: const Duration(milliseconds: 20),
          );
          expect(await first, isNull);
          expect(reasons, ['headless_gate_timeout']);
          expect(HeadlessSyncGate.timedOutRuns, 1);
          expect(HeadlessSyncGate.busy, false);
          expect(BandOwnership.owner, isNull);
          final next = BandOwnership.tryAcquireHeadless()!;
          final second = HeadlessSyncGate.tryRun<int>(
            'authored-new-native-stop',
            () => nextRelease.future,
            ceiling: const Duration(seconds: 2),
          );
          expect(HeadlessSyncGate.busy, true);
          if (lateFailure) {
            release.completeError(
              StateError('authored late transport failure'),
            );
          } else {
            release.complete(7);
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
          expect(BandOwnership.owner, BandOwnerKind.headless);
          expect(BandOwnership.tryAcquireHeadless(), isNull);
          expect(HeadlessSyncGate.busy, true);
          expect(reasons, ['headless_gate_timeout']);
          nextRelease.complete(11);
          expect(await second, 11);
          BandOwnership.release(next);
          expect(HeadlessSyncGate.busy, false);
          expect(BandOwnership.owner, isNull);
        } finally {
          if (!release.isCompleted) release.complete(0);
          if (!nextRelease.isCompleted) nextRelease.complete(0);
        }
      },
    );
  }
}
