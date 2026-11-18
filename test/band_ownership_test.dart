import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/sync/band_ownership.dart';

void main() {
  setUp(BandOwnership.resetForTest);

  test('headless cannot acquire while foreground intent is active', () {
    BandOwnership.markForegroundIntent(true);
    expect(BandOwnership.tryAcquireHeadless(), isNull);
  });

  test('foreground waits for active headless owner to release', () async {
    final headless = BandOwnership.tryAcquireHeadless();
    expect(headless, isNotNull);

    final future = BandOwnership.acquireForeground();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(BandOwnership.owner, BandOwnerKind.headless);

    BandOwnership.release(headless!);
    final foreground = await future;
    expect(foreground.kind, BandOwnerKind.foreground);
    expect(BandOwnership.owner, BandOwnerKind.foreground);
  });

  test(
    'headless acquires when band is free and no foreground intent exists',
    () {
      final lease = BandOwnership.tryAcquireHeadless();
      expect(lease, isNotNull);
      expect(BandOwnership.owner, BandOwnerKind.headless);
    },
  );

  test('released foreground owner allows later headless recovery', () async {
    final foreground = await BandOwnership.acquireForeground();
    expect(BandOwnership.owner, BandOwnerKind.foreground);

    BandOwnership.markForegroundIntent(false);
    BandOwnership.release(foreground);

    final headless = BandOwnership.tryAcquireHeadless();
    expect(headless, isNotNull);
    expect(BandOwnership.owner, BandOwnerKind.headless);
  });

  test('foreground acquire is re-entrant for the same process owner', () async {
    final first = await BandOwnership.acquireForeground();
    final second = await BandOwnership.acquireForeground();

    expect(first.kind, BandOwnerKind.foreground);
    expect(second.kind, BandOwnerKind.foreground);
    expect(second.token, first.token);
    expect(BandOwnership.owner, BandOwnerKind.foreground);
  });

  test(
    'headless cannot steal ownership while foreground lease is held',
    () async {
      final foreground = await BandOwnership.acquireForeground();

      BandOwnership.markForegroundIntent(false);
      final headless = BandOwnership.tryAcquireHeadless();

      expect(headless, isNull);
      expect(BandOwnership.owner, BandOwnerKind.foreground);
      BandOwnership.release(foreground);
      expect(BandOwnership.owner, isNull);
    },
  );

  test('B88-05: foreground asks the headless drain to stop', () async {
    final headless = BandOwnership.tryAcquireHeadless()!;
    final reasons = <String>[];
    BandOwnership.registerHeadlessStop(headless, (r) {
      reasons.add(r);
      BandOwnership.release(headless); // the drain disconnects and lets go
    });
    final lease = await BandOwnership.acquireForeground();
    expect(reasons, ['foreground_acquire']);
    expect(lease.kind, BandOwnerKind.foreground);
  });

  test('B88-05: a wedged headless drain cannot hold the foreground forever',
      () async {
    final headless = BandOwnership.tryAcquireHeadless()!;
    BandOwnership.registerHeadlessStop(headless, (_) {}); // never lets go
    final lease = await BandOwnership.acquireForeground(
      deadline: const Duration(milliseconds: 100),
    );
    expect(lease.kind, BandOwnerKind.foreground);
    expect(BandOwnership.owner, BandOwnerKind.foreground);
    // The orphaned drain's own release later is a no-op.
    BandOwnership.release(headless);
    expect(BandOwnership.owner, BandOwnerKind.foreground);
  });

  test('B88-05: a stop request with no headless drain does nothing', () {
    BandOwnership.requestHeadlessStop('ios_bg_task_expired');
    expect(BandOwnership.owner, isNull);
  });
}
