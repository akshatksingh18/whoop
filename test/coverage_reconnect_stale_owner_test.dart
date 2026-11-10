// Real one-minute supervisor and reconnect-generation ownership. Cloud only:
// transport futures and policy time are authored; no native/radio claim.
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/sync/band_ownership.dart';
import 'package:whoop_companion/sync/file_log.dart';
import 'package:whoop_companion/sync/paired_device.dart';

import 'coverage_ble_durable_boundary_test.dart' show until;
import 'coverage_connection_lifecycle_test.dart' show LifecycleBand;
import 'support/coverage_store.dart';

class _TimedBand extends LifecycleBand {
  _TimedBand(this.clock);
  final DateTime Function() clock;
  @override
  DateTime Function() get policyNow => clock;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await coverageStore('reconnect-stale-owner');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_timezone'),
          (_) async => 'UTC',
        );
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  for (final (name, seconds, failOld) in [
    ('before', 25 * 60 - 1, false),
    ('exact', 25 * 60, false),
    ('after', 25 * 60 + 1, false),
    ('old error', 25 * 60, true),
  ]) {
    test(
      'real stale supervisor $name preserves one current retry owner',
      () async {
        BandOwnership.resetForTest();
        var now = DateTime.now();
        final band = _TimedBand(() => now)..delay = Duration.zero;
        final app = AppState.forTesting(engine: band)
          ..paired = PairedDevice(
            'authored-stale-owner',
            null,
            generation: 'gen4',
          );
        final old = Completer<bool>(), replacement = Completer<bool>();
        var attempts = 0;
        Future<void>? firstLoop;
        band.connecting = (_) {
          attempts++;
          if (attempts == 1) return Future.value(false); // public initial reach
          return attempts == 2 ? old.future : replacement.future;
        };
        // Once the replacement reaches its current live setup,the actual public
        // end-session action retires it before unrelated heavy historical work.
        band.command = (name) async {
          if (name == 'live') await app.endSession();
        };
        try {
          await app.openSession();
          expect(attempts, 1);
          firstLoop = app.debugReconnect();
          await until(() => attempts == 2);
          now = now.add(Duration(seconds: seconds));
          await Future<void>.delayed(const Duration(seconds: 61));
          final stale = seconds >= 25 * 60;
          expect(attempts, stale ? 3 : 2);
          expect(
            app.logLines.any((s) => s.contains('treating it as wedged')),
            stale,
          );
          if (!stale) {
            expect(band.calls.where((s) => s == 'live'), isEmpty);
            await app.endSession();
            old.complete(false);
            await firstLoop;
            expect(attempts, 2);
            return;
          }
          final disconnects = band.calls.where((s) => s == 'disconnect').length;
          if (failOld) {
            old.completeError(
              StateError('authored retired connection refusal'),
            );
          } else {
            old.complete(false);
          }
          await firstLoop;
          // An old finally must not clear the replacement's running latch. This
          // actual re-entry must return immediately rather than start attempt4.
          await app.debugReconnect().timeout(const Duration(seconds: 1));
          expect(attempts, 3);
          expect(
            band.calls.where((s) => s == 'disconnect'),
            hasLength(disconnects),
          );
          expect(BandOwnership.foregroundIntent, true);
          replacement.complete(true);
          await until(() => band.calls.contains('live'));
          await until(() => !BandOwnership.foregroundIntent);
          expect(band.calls.where((s) => s == 'live'), hasLength(1));
          expect(attempts, 3);
          expect(app.busy, false);
        } finally {
          await app.endSession();
          if (!old.isCompleted) old.complete(false);
          if (!replacement.isCompleted) replacement.complete(false);
          await firstLoop;
          app.dispose();
          BandOwnership.resetForTest();
          await FileLog.write('Authored stale-owner completion barrier');
        }
      },
      timeout: const Timeout(Duration(seconds: 95)),
    );
  }
}
