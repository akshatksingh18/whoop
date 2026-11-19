// Script only OS/GATT operations; the engine owns arbitration, deadlines and retry.
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart'
    as os;
import 'package:whoop_protocol/whoop_protocol.dart' as p;
import 'package:whoop_companion/ble/ble_engine.dart';
import 'package:whoop_companion/ble/ble_state.dart';
import 'coverage_gatt_connection_test.dart' show Peripheral;
import 'coverage_ble_durable_boundary_test.dart' show record;

class DeferredOwner extends BleEngine {
  DeferredOwner()
    : super(
        onRecord: (_, _) async {},
        onState: (_) {},
        isBackgroundDrainer: true,
      );
  final entered = Completer<void>(),
      release = Completer<void>(),
      completed = Completer<void>();
  bool defer = true;
  @override
  Future<void> disconnect() async {
    if (defer) {
      if (!entered.isCompleted) entered.complete();
      await release.future;
      defer = false;
    }
    await super.disconnect();
    if (!completed.isCompleted) completed.complete();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  os.FlutterBluePlusPlatform? original;
  final peripheral = Peripheral();
  setUpAll(() {
    try {
      original = os.FlutterBluePlusPlatform.instance;
    } on UnsupportedError {
      // The host has no installed native implementation before this fixture.
    }
    os.FlutterBluePlusPlatform.instance = peripheral;
  });
  setUp(BleEngine.resetBandClaimForTest);
  tearDown(BleEngine.resetBandClaimForTest);
  tearDownAll(() {
    if (original != null) os.FlutterBluePlusPlatform.instance = original!;
  });

  test(
    'the implicit foreground callback uses the background derive tier and coalesces committed records',
    () async {
      var stored = 0, derived = 0;
      final engine = BleEngine(
        onRecord: (_, _) async {
          stored++;
        },
        onState: (_) {},
        onDataStored: () {
          derived++;
        },
        deriveDebouncer: const DeriveDebouncer(
          freshQuietPeriod: Duration(milliseconds: 10),
          freshMaxWait: Duration(milliseconds: 20),
          staleQuietPeriod: Duration(milliseconds: 10),
          staleMaxWait: Duration(milliseconds: 20),
        ),
      );
      try {
        final frame = p.parseFrame(p.buildFrame(record(p.BandProfile.gen4)))!;
        engine.debugIngestHistoricalFrame(frame);
        engine.debugIngestHistoricalFrame(frame);
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        expect(stored, 2);
        expect(derived, 1);
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(derived, 1);
      } finally {
        await engine.disconnect();
      }
    },
  );

  test(
    'a held incumbent teardown reaches its bounded deadline and permits a clean later retry',
    () async {
      final owner = DeferredOwner(), logs = <String>[];
      final replacement = BleEngine(
        onRecord: (_, _) async {},
        onState: (_) {},
        log: logs.add,
      );
      try {
        peripheral.engine = owner;
        expect(await owner.connectToRemoteId(Peripheral.id.str), true);
        peripheral.engine = replacement;
        final next = replacement.connectToRemoteId(Peripheral.id.str);
        await owner.entered.future;
        expect(await next.timeout(const Duration(seconds: 15)), true);
        expect(logs.join(' '), contains('teardown timed out after 10s'));
        expect(replacement.holdsBandLink, true);
        expect(replacement.pendingCommandCount, 0);
        owner.release.complete();
        await owner.completed.future;
        // The OS may report the delayed disconnect to both links. Once it lands,
        // retry the actual connection rather than pretending that radio event did
        // not occur or leaving a stale claim to block all future recovery.
        await replacement.disconnect();
        peripheral.engine = replacement;
        expect(await replacement.connectToRemoteId(Peripheral.id.str), true);
        expect(replacement.holdsBandLink, true);
      } finally {
        if (!owner.release.isCompleted) owner.release.complete();
        owner.defer = false;
        await owner.disconnect();
        await replacement.disconnect();
      }
      expect(BleEngine.bandClaimed, false);
    },
    timeout: const Timeout(Duration(seconds: 25)),
  );
}
