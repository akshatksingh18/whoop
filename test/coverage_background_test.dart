// Synthetic callbacks and leases, without a real radio or OS background task.
import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:whoop_companion/ble/ios_ble_restore.dart';
import 'package:whoop_companion/compute/derivation_engine.dart';
import 'package:whoop_companion/sync/band_ownership.dart';
import 'package:whoop_companion/sync/headless_gate.dart';
import 'package:whoop_companion/sync/sync_policy.dart';
import 'package:whoop_companion/sync/file_log.dart';

class _Paths extends PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async => (await Directory(
    'build/coverage-audit/background',
  ).create(recursive: true)).absolute.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final native = <String>[];
  setUp(() {
    PathProviderPlatform.instance = _Paths();
    HeadlessSyncGate.resetForTest();
    BandOwnership.resetForTest();
    IosBleRestore.foregroundActive = false;
    IosBleRestore.onWake = null;
    native.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('whoop/ble_restore'),
          (call) async {
            native.add(call.method);
            return null;
          },
        );
  });
  tearDown(() async {
    await FileLog.write('Synthetic callback test cleanup');
    IosBleRestore.onWake = null;
    IosBleRestore.foregroundActive = false;
    HeadlessSyncGate.resetForTest();
    BandOwnership.resetForTest();
  });

  test(
    'overlapping wakes skip, record starvation and recover on the next run',
    () async {
      final release = Completer<int>();
      final first = HeadlessSyncGate.tryRun('first', () => release.future);
      expect(HeadlessSyncGate.busy, isTrue);
      for (var i = 0; i < 4; i++) {
        expect(
          await HeadlessSyncGate.tryRun(
            'second',
            () async => fail('must skip'),
          ),
          isNull,
        );
      }
      expect(HeadlessSyncGate.totalSkips, 4);
      expect(HeadlessSyncGate.isStarved('second'), isTrue);
      release.complete(7);
      expect(await first, 7);
      expect(HeadlessSyncGate.busy, isFalse);
      expect(await HeadlessSyncGate.tryRun('second', () async => 8), 8);
      expect(HeadlessSyncGate.consecutiveSkipsFor('second'), 0);
    },
  );

  test('a thrown body releases the gate and preserves the error', () async {
    await expectLater(
      HeadlessSyncGate.tryRun('bad', () async => throw StateError('synthetic')),
      throwsStateError,
    );
    expect(HeadlessSyncGate.busy, isFalse);
    expect(await HeadlessSyncGate.tryRun('retry', () async => true), isTrue);
  });

  test(
    'gate ceiling requests transport stop before releasing its abandoned lease',
    () async {
      final lease = BandOwnership.tryAcquireHeadless()!;
      String? reason;
      BandOwnership.registerHeadlessStop(lease, (r) => reason = r);
      final held = Completer<int>();
      expect(
        await HeadlessSyncGate.tryRun(
          'held',
          () => held.future,
          ceiling: const Duration(milliseconds: 5),
        ),
        isNull,
      );
      expect(reason, 'headless_gate_timeout');
      expect(BandOwnership.owner, isNull);
      expect(HeadlessSyncGate.timedOutRuns, 1);
      final next = BandOwnership.tryAcquireHeadless()!;
      held.complete(1);
      BandOwnership.release(lease);
      expect(BandOwnership.owner, BandOwnerKind.headless);
      BandOwnership.release(next);
    },
  );

  test(
    'restore expiry stops calculation and the active headless transfer',
    () async {
      final lease = BandOwnership.tryAcquireHeadless()!;
      String? reason;
      BandOwnership.registerHeadlessStop(lease, (r) => reason = r);
      final generation = DeriveStop.generation;
      await IosBleRestore.handleCall(const MethodCall('expire'));
      expect(DeriveStop.generation, greaterThan(generation));
      expect(reason, 'ble_wake_expired');
      expect(native, isEmpty);
      BandOwnership.release(lease);
    },
  );

  test(
    'foreground ownership acknowledges wake without a competing drain',
    () async {
      IosBleRestore.foregroundActive = true;
      IosBleRestore.onWake = () async => throw StateError('must not call');
      await IosBleRestore.handleCall(const MethodCall('wake'));
      expect(native, ['syncDone']);
      expect(HeadlessSyncGate.busy, isFalse);
    },
  );

  test(
    'connected acknowledges, rearmed preserves the pending native handoff',
    () async {
      IosBleRestore.onWake = () async => RestoreWakeOutcome.connected;
      await IosBleRestore.handleCall(const MethodCall('wake'));
      expect(native, ['syncDone']);
      native.clear();
      IosBleRestore.onWake = () async => RestoreWakeOutcome.rearmed;
      await IosBleRestore.handleCall(const MethodCall('wake'));
      expect(native, isEmpty);
    },
  );

  test(
    'busy peer and a failed live handler leave its cycle in charge',
    () async {
      final held = Completer<void>();
      final peer = HeadlessSyncGate.tryRun('peer', () => held.future);
      IosBleRestore.onWake = () async => throw StateError('synthetic failure');
      await IosBleRestore.handleCall(const MethodCall('wake'));
      expect(native, isEmpty);
      expect(HeadlessSyncGate.totalSkips, 1);
      held.complete();
      await peer;
      await IosBleRestore.handleCall(const MethodCall('unknown'));
      expect(native, isEmpty);
    },
  );
}
