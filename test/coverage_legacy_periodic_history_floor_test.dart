// The real legacy connection owns and cancels its periodic backfill timer.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart'
    as os;
import 'package:whoop_companion/ble/ble_engine.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/sync/sync_policy.dart';
import 'package:whoop_protocol/whoop_protocol.dart';

import 'coverage_ble_durable_boundary_test.dart'
    show historyStart, historyComplete, until;
import 'coverage_gatt_connection_test.dart' show Peripheral;
import 'coverage_legacy_ble_link_timing_test.dart' show ManualPeriodicTimer;
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final peripheral = Peripheral();
  setUpAll(() async {
    os.FlutterBluePlusPlatform.instance = peripheral;
    await coverageStore('legacy-periodic-history-floor');
  });
  tearDownAll(LocalDb.close);

  test(
    'periodic backfill respects the INIT cooldown and dies with the link',
    () async {
      final timers = <ManualPeriodicTimer>[];
      final engine = BleEngine(onRecord: (_, _) async {}, onState: (_) {});
      peripheral.engine = engine;
      BleEngine.resetBandClaimForTest();
      await LocalDb.setCursor('authored-retained-cursor', 'keep');
      try {
        final ready = await runZoned(
          () => engine.connectToRemoteId(
            Peripheral.id.str,
            generationHint: 'gen4',
          ),
          zoneSpecification: ZoneSpecification(
            createPeriodicTimer: (self, parent, zone, duration, callback) {
              if (duration !=
                  const Duration(seconds: kBackfillIntervalSeconds)) {
                return parent.createPeriodicTimer(zone, duration, callback);
              }
              final timer = ManualPeriodicTimer(
                zone.bindUnaryCallback(callback),
              );
              timers.add(timer);
              return timer;
            },
          ),
        );
        expect(ready, isTrue);
        final timer = timers.single;
        expect(timer.isActive, isTrue);
        expect(engine.offloadActive, isTrue);

        final initWrites = peripheral.trace
            .where((value) => value == 'write:${Cmd.sendHistoricalData}')
            .length;
        expect(initWrites, 1);
        timer.fire();
        await Future<void>.delayed(const Duration(milliseconds: 15));
        expect(engine.offloadActive, isTrue);
        expect(
          peripheral.trace.where(
            (value) => value == 'write:${Cmd.sendHistoricalData}',
          ),
          hasLength(initWrites),
        );

        for (final packet in [historyStart(), historyComplete()]) {
          engine.debugReceiveFrame(Frame(packet, true, true), role: 'events');
        }
        await until(() => !engine.offloadActive);
        final before = List<String>.of(peripheral.trace);
        timer.fire();
        await Future<void>.delayed(const Duration(milliseconds: 15));
        expect(timer.tick, 2);
        expect(peripheral.trace, before);
        expect(engine.offloadActive, isFalse);
        expect(engine.isConnected, isTrue);
        expect(await LocalDb.getCursor('authored-retained-cursor'), 'keep');
      } finally {
        await engine.disconnect();
        BleEngine.resetBandClaimForTest();
      }

      final timer = timers.single;
      expect(timer.isActive, isFalse);
      final after = List<String>.of(peripheral.trace);
      timer.fire();
      expect(timer.tick, 2);
      expect(peripheral.trace, after);
    },
  );
}
