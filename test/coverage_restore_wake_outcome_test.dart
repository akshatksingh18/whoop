// Real registered Dart channel handler; authored owner replies, no native wake.
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/ble/ios_ble_restore.dart';
import 'package:whoop_companion/compute/derivation_engine.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/sync/headless_gate.dart';
import 'package:whoop_companion/sync/sync_policy.dart';
import 'support/coverage_store.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('whoop/ble_restore');
  const codec = StandardMethodCodec();
  final calls = <MethodCall>[];
  var refuseDone = false;
  Future<Object?> receive(String method) async {
    final reply = Completer<ByteData?>();
    binding.channelBuffers.push(
      channel.name,
      codec.encodeMethodCall(MethodCall(method)),
      reply.complete,
    );
    return codec.decodeEnvelope((await reply.future)!);
  }

  setUpAll(() async {
    await coverageStore('restore-wake-outcome');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      if (call.method == 'syncDone' && refuseDone) {
        throw PlatformException(code: 'authored completion refusal');
      }
      return null;
    });
    await IosBleRestore.init(isIOS: true);
    await IosBleRestore.announceReady(isIOS: true);
  });
  setUp(() async {
    await resetCoverageStore();
    calls.clear();
    refuseDone = false;
    IosBleRestore.foregroundActive = false;
    IosBleRestore.onWake = null;
    HeadlessSyncGate.resetForTest();
  });
  tearDown(() {
    IosBleRestore.foregroundActive = false;
    IosBleRestore.onWake = null;
    expect(HeadlessSyncGate.busy, false);
  });
  tearDownAll(() async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    await LocalDb.close();
  });
  for (final refusal in [false, true]) {
    test(
      'COV-61 connected restoration completes once with native refusal=$refusal',
      () async {
        var offered = 0;
        IosBleRestore.onWake = () async {
          offered++;
          return RestoreWakeOutcome.connected;
        };
        refuseDone = refusal;
        expect(await receive('wake'), isNull);
        expect(offered, 1);
        expect(calls.map((c) => c.method), ['syncDone']);
        expect(calls.single.arguments, isNull);
        expect(IosBleRestore.foregroundActive, false);
        expect(await (await LocalDb.instance).query('day_result'), isEmpty);
      },
    );
  }
  test(
    'COV-61 a rearmed restoration does not cancel its pending native connect',
    () async {
      var offered = 0;
      IosBleRestore.onWake = () async {
        offered++;
        return RestoreWakeOutcome.rearmed;
      };
      expect(await receive('wake'), isNull);
      expect(offered, 1);
      expect(calls, isEmpty);
      expect(IosBleRestore.foregroundActive, false);
    },
  );
  test(
    'COV-61 foreground ownership handles restoration without offering another owner',
    () async {
      IosBleRestore.foregroundActive = true;
      IosBleRestore.onWake = () async => throw StateError('must not offer');
      expect(await receive('wake'), isNull);
      expect(calls.map((c) => c.method), ['syncDone']);
      expect(IosBleRestore.foregroundActive, true);
    },
  );
  for (final throws in [false, true]) {
    test(
      'COV-61 owner ${throws ? 'failure' : 'decline'} skips an occupied transfer without duplicate completion',
      () async {
        final entered = Completer<void>(), release = Completer<void>();
        final held = HeadlessSyncGate.tryRun<void>(
          'authored-existing-transfer',
          () async {
            entered.complete();
            await release.future;
          },
        );
        await entered.future;
        var offered = 0;
        IosBleRestore.onWake = () async {
          offered++;
          if (throws) throw StateError('authored owner refusal');
          return RestoreWakeOutcome.notHandled;
        };
        try {
          expect(await receive('wake'), isNull);
          expect(offered, 1);
          expect(HeadlessSyncGate.busy, true);
          expect(calls, isEmpty);
        } finally {
          release.complete();
          await held;
        }
      },
    );
  }
  test(
    'COV-61 native expiration stops the shared generation without starting another wake',
    () async {
      IosBleRestore.onWake = () async => throw StateError('must not offer');
      final before = DeriveStop.generation;
      expect(await receive('expire'), isNull);
      expect(DeriveStop.generation, before + 1);
      expect(calls, isEmpty);
      expect(await receive('authored-unknown-call'), isNull);
      expect(calls, isEmpty);
    },
  );
}
