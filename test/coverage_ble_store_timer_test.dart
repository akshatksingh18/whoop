// Real store debounce and GATT ownership, with authored bytes and a scripted OS.
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

final class RefusingOwner extends BleEngine {
  RefusingOwner()
    : super(
        onRecord: (_, _) async {},
        onState: (_) {},
        isBackgroundDrainer: true,
      );
  bool refuse = true;
  @override
  Future<void> disconnect() async {
    if (refuse) throw StateError('synthetic teardown refusal');
    await super.disconnect();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final peripheral = Peripheral();
  setUpAll(() => os.FlutterBluePlusPlatform.instance = peripheral);
  setUp(BleEngine.resetBandClaimForTest);
  for (final held in [false, true]) {
    test(
      'COV-47 committed records coalesce after the store acknowledges $held',
      () async {
        var stores = 0, derives = 0;
        final gate = Completer<void>();
        if (!held) gate.complete();
        final engine = BleEngine(
          onRecord: (_, _) async {
            await gate.future;
            stores++;
          },
          onState: (_) {},
          onDataStored: () => derives++,
          deriveDebouncer: const DeriveDebouncer(
            foregroundQuietPeriod: Duration(milliseconds: 30),
            foregroundMaxWait: Duration(milliseconds: 80),
          ),
          isForegroundActive: () => true,
        );
        try {
          final f = p.parseFrame(p.buildFrame(record(p.BandProfile.gen4)))!;
          engine.debugIngestHistoricalFrame(f);
          engine.debugIngestHistoricalFrame(f);
          await Future<void>.delayed(const Duration(milliseconds: 20));
          if (held) {
            expect(stores, 0);
            expect(derives, 0);
            gate.complete();
          }
          await Future<void>.delayed(const Duration(milliseconds: 1200));
          expect(stores, 2);
          expect(derives, 1);
          await Future<void>.delayed(const Duration(milliseconds: 60));
          expect(derives, 1);
        } finally {
          if (!gate.isCompleted) gate.complete();
          await engine.disconnect();
        }
      },
    );
  }
  test(
    'COV-47 a background-tier pending derive is rechecked after foreground transition',
    () async {
      var foreground = false, derives = 0;
      final engine = BleEngine(
        onRecord: (_, _) async {},
        onState: (_) {},
        onDataStored: () => derives++,
        isForegroundActive: () => foreground,
        deriveDebouncer: const DeriveDebouncer(
          freshQuietPeriod: Duration(seconds: 2),
          freshMaxWait: Duration(seconds: 3),
          foregroundQuietPeriod: Duration(milliseconds: 10),
          foregroundMaxWait: Duration(milliseconds: 20),
        ),
      );
      try {
        engine.debugIngestHistoricalFrame(
          p.parseFrame(p.buildFrame(record(p.BandProfile.gen4)))!,
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(derives, 0);
        engine.setBackground(true);
        foreground = true;
        engine.setBackground(false);
        await Future<void>.delayed(const Duration(milliseconds: 1150));
        expect(derives, 1);
      } finally {
        await engine.disconnect();
      }
    },
  );
  test(
    'COV-47 a background competitor yields the real GATT owner and a link drop releases it',
    () async {
      final states = <String>[], logs = <String>[];
      final owner = BleEngine(
        onRecord: (_, _) async {},
        onState: (s) => states.add(s.connection),
      );
      final guest = BleEngine(
        onRecord: (_, _) async {},
        onState: (_) {},
        isBackgroundDrainer: true,
        log: logs.add,
      );
      peripheral.engine = owner;
      try {
        expect(await owner.connectToRemoteId(Peripheral.id.str), true);
        final connects = peripheral.trace.where((s) => s == 'connect').length;
        expect(await guest.connectToRemoteId(Peripheral.id.str), false);
        expect(
          peripheral.trace.where((s) => s == 'connect'),
          hasLength(connects),
        );
        expect(logs.join(' '), contains('yielding'));
        expect(owner.holdsBandLink, true);
        peripheral.link(false);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(owner.isConnected, false);
        expect(owner.holdsBandLink, false);
        expect(states.last, 'disconnected');
        expect(BleEngine.bandClaimed, false);
      } finally {
        await owner.disconnect();
        await guest.disconnect();
      }
    },
  );
  test(
    'COV-47 foreground ownership records and survives an incumbent teardown refusal',
    () async {
      final owner = RefusingOwner(), logs = <String>[];
      final replacement = BleEngine(
        onRecord: (_, _) async {},
        onState: (_) {},
        log: logs.add,
      );
      peripheral.engine = owner;
      try {
        expect(await owner.connectToRemoteId(Peripheral.id.str), true);
        peripheral.engine = replacement;
        expect(await replacement.connectToRemoteId(Peripheral.id.str), true);
        expect(logs.join(' '), contains('synthetic teardown refusal'));
        expect(replacement.holdsBandLink, true);
        expect(BleEngine.bandClaimed, true);
        // The OS transport is shared: its eventual real disconnect is a link
        // drop for both sessions, so teardown is kept in finally below.
      } finally {
        owner.refuse = false;
        await owner.disconnect();
        await replacement.disconnect();
      }
      expect(BleEngine.bandClaimed, false);
    },
  );
}
