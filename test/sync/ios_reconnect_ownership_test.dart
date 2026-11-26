// Actual reconnect ownership awaits, with authored radio/native boundaries.
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/ble/ios_ble_restore.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/sync/band_ownership.dart';
import 'package:whoop_companion/sync/paired_device.dart';
import '../gps/connection_lifecycle_test.dart' show LifecycleBand;
import '../support/coverage_store.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('whoop/ble_restore');
  setUpAll(() => coverageStore('ios-reconnect-ownership', fresh: true));
  setUp(() async {
    await resetCoverageStore();
    BandOwnership.resetForTest();
    IosBleRestore.foregroundActive = false;
  });
  tearDownAll(() async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    await LocalDb.close();
  });
  Future<void> settled(bool Function() ready) async {
    for (var i = 0; i < 500 && !ready(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(ready(), true, reason: 'Authored reconnect must settle');
  }

  for (final action in ['continue', 'end', 'forget', 'dispose']) {
    test(
      'iOS reconnect ownership ACK after $action cannot revive a retired session',
      () async {
        final gate = Completer<void>(), entered = Completer<void>();
        final native = <MethodCall>[];
        binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
          c,
        ) async {
          native.add(c);
          if (c.method == 'setOwnsBand' && c.arguments == true) {
            if (!entered.isCompleted) {
              entered.complete();
            }
            await gate.future;
          }
          return null;
        });
        final band = LifecycleBand()..delay = Duration.zero;
        var connects = 0, disposed = false;
        band.connecting = (_) async => ++connects > 1;
        await PairedDevice.save('authored-ios-band', null, generation: 'gen4');
        final app = AppState.forTesting(engine: band, isIOS: true)
          ..paired = await PairedDevice.load();
        final before = await (await LocalDb.instance).query('device');
        Future<void>? reconnect;
        try {
          // Establish intent through the first genuine failure, then exercise
          // the existing disconnect/supervisor adapter's actual retry loop.
          await app.openSession();
          reconnect = app.debugReconnect();
          await settled(() => entered.isCompleted);
          expect(connects, 2);
          expect(
            native.where(
              (c) => c.method == 'setOwnsBand' && c.arguments == true,
            ),
            hasLength(1),
          );
          if (action == 'dispose') {
            app.dispose();
            disposed = true;
          } else if (action == 'forget') {
            await app.unpair();
          } else if (action == 'end') {
            await app.endSession();
          } else {
            // Retire before unrelated historical derivation: the ownership ACK
            // must first permit the existing foreground live command.
            band.command = (at) async {
              if (at == 'live') {
                await app.endSession();
              }
            };
          }
          gate.complete();
          await reconnect;
          if (action == 'continue') {
            await settled(() => band.calls.contains('live'));
          } else {
            await Future<void>.delayed(const Duration(milliseconds: 30));
            expect(band.calls, isNot(contains('live')));
          }
          expect(band.calls, isNot(contains('sync')));
          expect(await (await LocalDb.instance).query('day_result'), isEmpty);
          if (action == 'forget') {
            expect(await PairedDevice.load(), isNull);
          } else {
            expect(await (await LocalDb.instance).query('device'), before);
          }
        } finally {
          if (!gate.isCompleted) {
            gate.complete();
          }
          if (!disposed) {
            app.dispose();
          }
          await reconnect;
          await Future<void>.delayed(const Duration(milliseconds: 50));
          binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          );
          IosBleRestore.foregroundActive = false;
          BandOwnership.resetForTest();
        }
      },
      timeout: const Timeout(Duration(seconds: 15)),
    );
  }
}
