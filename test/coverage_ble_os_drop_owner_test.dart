// Actual OS-drop/claim lifecycle;the scripted boundary replaces only native BLE.
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart'
    as os;
import 'package:whoop_companion/ble/ble_engine.dart';
import 'coverage_gatt_connection_test.dart' show Peripheral;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final peripheral = Peripheral();
  setUpAll(() => os.FlutterBluePlusPlatform.instance = peripheral);
  setUp(() {
    peripheral.trace.clear();
    BleEngine.resetBandClaimForTest();
  });
  for (final osDrop in [false, true]) {
    for (final background in [false, true]) {
      test(
        'replacement background=$background keeps ownership after OS drop=$osDrop',
        () async {
          final dropped = Completer<void>();
          var armed = false, records = 0, commits = 0;
          final logs = <String>[];
          final owner = BleEngine(
            onRecord: (_, _) async {
              records++;
            },
            onCommitBatch: (_, _, _, {archives, deviceFamily}) async {
              commits++;
            },
            onState: (s) {
              if (armed &&
                  s.connection == 'disconnected' &&
                  !dropped.isCompleted) {
                dropped.complete();
              }
            },
          );
          final replacement = BleEngine(
            isBackgroundDrainer: background,
            onRecord: (_, _) async {
              records++;
            },
            onCommitBatch: (_, _, _, {archives, deviceFamily}) async {
              commits++;
            },
            onState: (_) {},
            log: logs.add,
          );
          peripheral.engine = owner;
          try {
            expect(await owner.connectToRemoteId(Peripheral.id.str), true);
            expect(owner.holdsBandLink, true);
            armed = true;
            if (osDrop) {
              peripheral.link(false);
              await dropped.future.timeout(const Duration(seconds: 3));
            } else {
              await owner.disconnect();
            }
            peripheral.engine = replacement;
            final connected = await replacement.connectToRemoteId(
              Peripheral.id.str,
            );
            expect(connected, true, reason: logs.join('\n'));
            await Future<void>.delayed(const Duration(milliseconds: 50));
            expect(replacement.isConnected, true, reason: logs.join('\n'));
            expect(replacement.holdsBandLink, true);
            expect(BleEngine.bandClaimed, true);
            expect(
              logs.join(' '),
              osDrop
                  ? contains('STALE band claim')
                  : isNot(contains('STALE band claim')),
            );
            final disconnects = peripheral.trace
                .where((e) => e == 'disconnect')
                .length;
            await owner.disconnect();
            expect(
              peripheral.trace.where((e) => e == 'disconnect'),
              hasLength(disconnects),
            );
            expect(replacement.holdsBandLink, true);
            expect(BleEngine.bandClaimed, true);
            expect(records, 0);
            expect(commits, 0);
          } finally {
            await owner.disconnect();
            await replacement.disconnect();
          }
          expect(BleEngine.bandClaimed, false);
        },
        timeout: const Timeout(Duration(seconds: 35)),
      );
    }
  }
  for (final background in [false, true]) {
    for (final refuse in [false, true]) {
      test(
        'replacement background=$background waits for held native cleanup refusal=$refuse',
        () async {
          final entered = Completer<void>(), release = Completer<void>();
          final owner = BleEngine(onRecord: (_, _) async {}, onState: (_) {});
          final replacement = BleEngine(
            isBackgroundDrainer: background,
            onRecord: (_, _) async {},
            onState: (_) {},
          );
          peripheral.engine = owner;
          try {
            expect(await owner.connectToRemoteId(Peripheral.id.str), true);
            peripheral.beforeDisconnect = () async {
              if (!entered.isCompleted) {
                entered.complete();
              }
              await release.future;
              if (refuse) {
                throw StateError('synthetic native disconnect refused');
              }
            };
            peripheral.link(false);
            await entered.future.timeout(const Duration(seconds: 3));
            peripheral.engine = replacement;
            final opening = replacement.connectToRemoteId(Peripheral.id.str);
            await Future<void>.delayed(const Duration(milliseconds: 30));
            expect(peripheral.trace.where((e) => e == 'connect'), hasLength(1));
            expect(replacement.holdsBandLink, false);
            peripheral.beforeDisconnect = null;
            release.complete();
            expect(await opening, true);
            await Future<void>.delayed(const Duration(milliseconds: 50));
            expect(replacement.holdsBandLink, true);
            expect(replacement.isConnected, true);
            expect(BleEngine.bandClaimed, true);
            final disconnects = peripheral.trace
                .where((e) => e == 'disconnect')
                .length;
            await owner.disconnect();
            expect(
              peripheral.trace.where((e) => e == 'disconnect'),
              hasLength(disconnects),
            );
            expect(replacement.isConnected, true);
          } finally {
            peripheral.beforeDisconnect = null;
            if (!release.isCompleted) release.complete();
            await owner.disconnect();
            await replacement.disconnect();
          }
          expect(BleEngine.bandClaimed, false);
        },
        timeout: const Timeout(Duration(seconds: 35)),
      );
    }
  }
  test(
    'foreground replacement retains priority over a simultaneous background stale-owner waiter',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      final owner = BleEngine(onRecord: (_, _) async {}, onState: (_) {});
      final front = BleEngine(onRecord: (_, _) async {}, onState: (_) {});
      final background = BleEngine(
        isBackgroundDrainer: true,
        onRecord: (_, _) async {},
        onState: (_) {},
      );
      peripheral.engine = owner;
      try {
        expect(await owner.connectToRemoteId(Peripheral.id.str), true);
        peripheral.beforeDisconnect = () async {
          if (!entered.isCompleted) {
            entered.complete();
          }
          await release.future;
        };
        peripheral.link(false);
        await entered.future.timeout(const Duration(seconds: 3));
        peripheral.engine = front;
        final f = front.connectToRemoteId(Peripheral.id.str);
        final b = background.connectToRemoteId(Peripheral.id.str);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        peripheral.beforeDisconnect = null;
        release.complete();
        expect(await b, false);
        expect(await f, true);
        expect(front.isConnected, true);
        expect(background.holdsBandLink, false);
        expect(peripheral.trace.where((s) => s == 'connect'), hasLength(2));
      } finally {
        peripheral.beforeDisconnect = null;
        if (!release.isCompleted) release.complete();
        await owner.disconnect();
        await background.disconnect();
        await front.disconnect();
      }
    },
    timeout: const Timeout(Duration(seconds: 35)),
  );
}
