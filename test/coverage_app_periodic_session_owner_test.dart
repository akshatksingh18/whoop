// The production session callback owns its tick and cancels it on End.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/sync/band_ownership.dart';
import 'package:whoop_companion/sync/paired_device.dart';

import 'coverage_ble_durable_boundary_test.dart' show until;
import 'coverage_connection_lifecycle_test.dart' show LifecycleBand;
import 'coverage_legacy_ble_link_timing_test.dart' show ManualPeriodicTimer;
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('app-session-timer-owner'));
  setUp(() async {
    await resetCoverageStore();
    BandOwnership.resetForTest();
  });
  tearDownAll(LocalDb.close);

  for (final background in [false, true]) {
    test(
      'the paired session tick respects background ownership: $background',
      () async {
        final band = LifecycleBand()..connecting = (_) async => true;
        final app = AppState.forTesting(engine: band, isIOS: false)
          ..paired = PairedDevice(
            'authored-periodic-band',
            null,
            generation: 'gen4',
          );
        final timers = <ManualPeriodicTimer>[];
        await LocalDb.setCursor('authored-old-frontier', 'keep');
        try {
          await runZoned(
            app.openSession,
            zoneSpecification: ZoneSpecification(
              createPeriodicTimer: (self, parent, zone, duration, callback) {
                if (duration != const Duration(minutes: 5)) {
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
          await until(
            () => app.logLines.any((line) => line.contains('Backlog drained:')),
          );
          expect(band.connected, isTrue);
          final timer = timers.single;
          expect(timer.isActive, isTrue);
          if (background) await app.pauseForBackground();
          band.calls.clear();

          timer.fire();
          await until(
            () => app.logLines.any(
              (line) => line.contains(
                background
                    ? 'backgrounded; the engine'
                    : 'Periodic backlog check:',
              ),
            ),
          );
          expect(
            band.calls.where((c) => c == 'history' || c == 'sync'),
            background ? isEmpty : ['history', 'sync'],
          );
          expect(await LocalDb.getCursor('authored-old-frontier'), 'keep');
          expect(timer.tick, 1);

          await app.endSession();
          expect(timer.isActive, isFalse);
          expect(BandOwnership.owner, isNull);
          final trace = List<String>.of(band.calls);
          timer.fire();
          expect(timer.tick, 1);
          expect(band.calls, trace);
        } finally {
          await app.endSession();
          app.dispose();
          BandOwnership.resetForTest();
        }
      },
    );
  }
}
