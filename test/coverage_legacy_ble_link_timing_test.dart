// Exercise the legacy link's setup and maintenance through the real engine.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart'
    as os;
import 'package:whoop_companion/ble/ble_engine.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_protocol/whoop_protocol.dart';

import 'coverage_ble_durable_boundary_test.dart'
    show historyStart, historyComplete, until;
import 'coverage_gatt_connection_test.dart' show Peripheral;
import 'support/coverage_store.dart';

final class ManualPeriodicTimer implements Timer {
  ManualPeriodicTimer(this.callback);

  final void Function(Timer) callback;

  @override
  bool isActive = true;

  @override
  int tick = 0;

  void fire() {
    if (!isActive) return;
    tick++;
    callback(this);
  }

  @override
  void cancel() => isActive = false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final peripheral = Peripheral();
  setUpAll(() async {
    os.FlutterBluePlusPlatform.instance = peripheral;
    await coverageStore('legacy-link-timing');
  });
  setUp(() {
    BleEngine.resetBandClaimForTest();
    peripheral.trace.clear();
  });
  tearDown(BleEngine.resetBandClaimForTest);
  tearDownAll(LocalDb.close);

  test(
    'discovered family delay releases a stale saved-family connection on loss',
    () async {
      final logs = <String>[];
      final engine = BleEngine(
        onRecord: (_, _) async {},
        onState: (_) {},
        log: logs.add,
      );
      peripheral.band = BandProfile.gen5;
      peripheral.engine = engine;
      final connecting = engine.connectToRemoteId(
        Peripheral.id.str,
        generationHint: 'gen4',
      );
      try {
        await until(() => engine.state.generation == 'gen5');
        peripheral.link(false);
        expect(await connecting, isFalse);
        expect(logs, contains(contains('the pre-registration delay')));
        expect(engine.holdsBandLink, isFalse);
        expect(
          peripheral.trace.any((value) => value.startsWith('notify:')),
          isFalse,
        );
        expect(
          peripheral.trace.any((value) => value.startsWith('write:')),
          isFalse,
        );
      } finally {
        await engine.disconnect();
        peripheral.band = BandProfile.gen4;
      }
      expect(BleEngine.bandClaimed, isFalse);
    },
  );

  test(
    'legacy setup aborts a lost connection before discovery and can retry',
    () async {
      final logs = <String>[];
      final engine = BleEngine(
        onRecord: (_, _) async {},
        onState: (_) {},
        log: logs.add,
      );
      peripheral.engine = engine;
      var drop = true;
      engine.debugOnPriorityRequest = () {
        if (drop) peripheral.link(false);
      };

      Future<bool> connect() =>
          engine.connectToRemoteId(Peripheral.id.str, generationHint: 'gen4');

      try {
        expect(await connect(), isFalse);
        expect(logs, contains(contains('Link down')));
        expect(engine.isConnected, isFalse);
        expect(peripheral.trace, isNot(contains('discover')));
        expect(
          peripheral.trace.where((value) => value.startsWith('write:')),
          isEmpty,
        );
        expect(engine.holdsBandLink, isFalse);
        expect(BleEngine.bandClaimed, isFalse);

        drop = false;
        expect(await connect(), isTrue);
        expect(engine.isConnected, isTrue);
        expect(
          peripheral.trace.where((value) => value == 'discover'),
          hasLength(1),
        );
        expect(
          peripheral.trace.where((value) => value == 'connect'),
          hasLength(2),
        );
      } finally {
        await engine.disconnect();
      }
      expect(BleEngine.bandClaimed, isFalse);
    },
  );

  test(
    'legacy maintenance suppresses duplicate background link writes and stops on disconnect',
    () async {
      final timers = <ManualPeriodicTimer>[];
      final engine = BleEngine(onRecord: (_, _) async {}, onState: (_) {});
      peripheral.engine = engine;
      engine.setBackground(true);
      int writes() => peripheral.trace
          .where((value) => value == 'write:${Cmd.linkValid}')
          .length;

      try {
        final connected = await runZoned(
          () => engine.connectToRemoteId(
            Peripheral.id.str,
            generationHint: 'gen4',
          ),
          zoneSpecification: ZoneSpecification(
            createPeriodicTimer: (self, parent, zone, duration, callback) {
              if (duration != const Duration(seconds: 10)) {
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
        expect(connected, isTrue);
        final heartbeat = timers.single;
        final initial = writes();
        expect(engine.offloadActive, isTrue);
        heartbeat.fire();
        expect(writes(), initial);
        for (final packet in [historyStart(), historyComplete()]) {
          engine.debugReceiveFrame(Frame(packet, true, true), role: 'events');
        }
        await until(() => !engine.offloadActive);
        heartbeat.fire();
        await until(() => writes() == initial + 1);
        heartbeat.fire();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(writes(), initial + 1);
        expect(engine.isConnected, isTrue);

        engine.setBackground(false);
        heartbeat.fire();
        await until(() => writes() == initial + 2);
        expect(writes(), initial + 2);
      } finally {
        await engine.disconnect();
      }
      expect(timers.single.isActive, isFalse);
      final atDisconnect = writes();
      timers.single.fire();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(writes(), atDisconnect);
      expect(BleEngine.bandClaimed, isFalse);
    },
  );
}
