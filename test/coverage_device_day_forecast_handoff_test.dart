// Stored battery history -> unchanged estimator -> current source/detail page.
// Engine-state callbacks are the input boundary;no radio acceptance is claimed.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/notify/notification_service.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/sync/paired_device.dart';
import 'package:whoop_companion/ui2/profile/devices.dart';
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('device-day-forecast-handoff');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  for (final scale in [1.0, 3.1]) {
    for (final refuseRead in [false, true]) {
      testWidgets(
        'day-scale battery forecast read refusal=$refuseRead recovers and charging suppresses it at ${scale}x',
        (t) async {
          final app = AppState.forTesting()
            ..paired = PairedDevice(
              'authored-forecast-band',
              'Authored band',
              generation: 'gen4',
            );
          final service = NotificationService.instance;
          service.debugProbePermission = () async => false;
          service.invalidatePermissionCache();
          var hidden = false;
          final db = await LocalDb.instance;
          addTearDown(() async {
            if (hidden) {
              await t.runAsync(
                () => db.execute(
                  'ALTER TABLE authored_hidden_battery RENAME TO band_battery',
                ),
              );
            }
            app.dispose();
            service.debugProbePermission = null;
            service.invalidatePermissionCache();
          });
          await t.runAsync(
            () => PairedDevice.save(
              app.paired!.remoteId,
              app.paired!.serial,
              generation: app.paired!.generation,
            ),
          );
          final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
          for (var i = 3; i >= 1; i--) {
            await LocalDb.insertBandBatterySample(
              ts: now - i * 7200,
              batteryPct: 72 + i * 3.0,
              charging: false,
              source: 'band_event',
            );
          }
          app.device
            ..batteryPct = 72
            ..charging = false;
          app.engine.onState(app.device);
          for (var i = 0; i < 50 && app.batteryRevision.value == 0; i++) {
            await t.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)),
            );
          }
          expect(app.batteryRevision.value, 1);
          final samples = (await t.runAsync(
            () => db.query('band_battery', orderBy: 'ts'),
          ))!;
          expect(samples, hasLength(4));
          if (refuseRead) {
            await t.runAsync(
              () => db.execute(
                'ALTER TABLE band_battery RENAME TO authored_hidden_battery',
              ),
            );
            hidden = true;
          }
          await localizedPage(
            t,
            DeviceDetail(liveSources(app).single),
            app: app,
            scale: scale,
            push: true,
          );
          Future<void> flush() async {
            for (var i = 0; i < 6; i++) {
              await t.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 20)),
              );
              await t.pump();
            }
            await t.pumpAndSettle();
            expect(t.takeException(), isNull);
          }

          await flush();
          DeviceDetailView view() =>
              t.widget<DeviceDetailView>(find.byType(DeviceDetailView));
          if (refuseRead) {
            expect(view().forecast, isNull);
            expect(view().s.batteryPct, 72);
            expect(
              await t.runAsync(
                () => db.query('authored_hidden_battery', orderBy: 'ts'),
              ),
              samples,
            );
            await t.runAsync(
              () => db.execute(
                'ALTER TABLE authored_hidden_battery RENAME TO band_battery',
              ),
            );
            hidden = false;
            t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
            t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
            await flush();
          }
          expect(view().forecast!.isUsable, true);
          expect(view().forecast!.samplesUsed, 4);
          expect(view().forecast!.drainPctPerHour, closeTo(1.5, .01));
          await reveal(t, find.text('about 2 days left'));
          expect(find.text('about 2 days left'), findsOneWidget);
          expect(
            await t.runAsync(() => db.query('band_battery', orderBy: 'ts')),
            samples,
          );
          app.device.charging = true;
          app.engine.onState(app.device);
          await flush();
          expect(view().s.charging, true);
          expect(view().forecast, isNull);
          expect(find.textContaining('days left'), findsNothing);
          expect(await t.runAsync(() => db.query('day_result')), isEmpty);
          expect(await t.runAsync(() => db.query('decoded_onehz')), isEmpty);
        },
      );
    }
  }
}
