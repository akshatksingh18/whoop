// Real alarm owner -> existing form -> engine/FBP; only OS transport is scripted.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart'
    as os;
import 'package:whoop_companion/ble/ble_engine.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/sync/band_ownership.dart';
import 'package:whoop_companion/ui2/profile/alarm.dart';
import 'package:whoop_companion/ui2/screens/findings_log.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'package:whoop_protocol/whoop_protocol.dart' as p;
import 'coverage_gatt_connection_test.dart' show Peripheral;
import 'coverage_page_timer_recovery_test.dart' show pageIO;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final peripheral = Peripheral();
  os.FlutterBluePlusPlatform.instance = peripheral;
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('alarm-owner-command-pages', fresh: true);
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  for (final action in ['set', 'buzz', 'cancel']) {
    for (final refused in [false, true]) {
      testWidgets(
        'actual alarm page $action refused=$refused keeps write and confirmation distinct',
        (t) async {
          BandOwnership.resetForTest();
          BleEngine.resetBandClaimForTest();
          peripheral.mode = 'ready';
          peripheral.trace.clear();
          final app = (await t.runAsync(() async => AppState.forTesting()))!;
          peripheral.engine = app.engine;
          try {
            expect(
              await t.runAsync(
                () => app.engine.connectToRemoteId(Peripheral.id.str),
              ),
              true,
            );
            final oldTime = DateTime.now().add(const Duration(hours: 8));
            await t.runAsync(() => app.setAlarm(oldTime));
            await localizedPage(t, const AlarmScreen(), app: app);
            final owner = find.byType(AlarmScreenView);
            var view = t.widget<AlarmScreenView>(owner);
            expect(view.connected, true);
            expect(view.state, AlarmArmState.pending);
            expect(
              view.armedAt!.millisecondsSinceEpoch ~/ 1000,
              app.alarmEpoch,
            );
            app.debugHandleAlarmEvent(56);
            await t.pumpAndSettle();
            expect(
              t.widget<AlarmScreenView>(owner).state,
              AlarmArmState.confirmed,
            );
            final savedEpoch = app.alarmEpoch;
            final prefs = (await t.runAsync(SharedPreferences.getInstance))!;
            expect(prefs.getInt('alarm_epoch'), savedEpoch);
            peripheral.trace.clear();
            peripheral.mode = refused ? 'write-refused' : 'ready';
            if (action == 'set') {
              await t.tap(find.text('Change the time'));
              await t.pumpAndSettle();
              await t.tap(find.byTooltip('Switch to text input mode'));
              await t.pumpAndSettle();
              await t.enterText(find.byType(TextField).first, '6');
              await t.enterText(find.byType(TextField).last, '42');
              await t.tap(find.text('OK'));
              await pageIO(t);
              expect(find.byType(TimePickerDialog), findsNothing);
            } else {
              final title = action == 'buzz'
                  ? 'Test the buzz'
                  : 'Cancel the alarm';
              final control = t.widget<BigButton>(
                find.widgetWithText(BigButton, title),
              );
              await invokeControl(t, control.onTap);
              await pageIO(t);
            }
            final opcode = action == 'set'
                ? p.Cmd.setAlarmTime
                : action == 'buzz'
                ? p.Cmd.runAlarm
                : p.Cmd.disableAlarm;
            expect(
              peripheral.trace.where((s) => s == 'write:$opcode'),
              hasLength(1),
            );
            view = t.widget<AlarmScreenView>(owner);
            if (refused || action == 'buzz') {
              expect(app.alarmEpoch, savedEpoch);
              expect(prefs.getInt('alarm_epoch'), savedEpoch);
              expect(view.state, AlarmArmState.confirmed);
            } else if (action == 'cancel') {
              expect(app.alarmEpoch, isNull);
              expect(prefs.getInt('alarm_epoch'), isNull);
              expect(view.state, AlarmArmState.none);
            } else {
              expect(app.alarmEpoch, isNot(savedEpoch));
              expect(prefs.getInt('alarm_epoch'), app.alarmEpoch);
              expect(view.state, AlarmArmState.pending);
              expect(view.armedAt!.hour % 12, 6);
              expect(view.armedAt!.minute, 42);
            }
            final text = (await readPage(t)).join(' ');
            if (refused) {
              expect(
                find.text(
                  action == 'set'
                      ? 'Alarm not set'
                      : action == 'buzz'
                      ? 'Test buzz not sent. Reconnect and retry.'
                      : 'Cancel not sent. Reconnect and retry.',
                ),
                findsOneWidget,
              );
              expect(
                text,
                isNot(
                  contains(
                    action == 'set'
                        ? 'Alarm sent to the band'
                        : action == 'buzz'
                        ? 'Buzzing the band'
                        : 'Alarm cancelled',
                  ),
                ),
              );
            } else {
              expect(
                find.text(
                  action == 'set'
                      ? 'Alarm sent to the band'
                      : action == 'buzz'
                      ? 'Buzzing the band'
                      : 'Alarm cancelled',
                ),
                findsOneWidget,
              );
            }
            expect(
              await t.runAsync(
                () async => (await LocalDb.instance).query('day_result'),
              ),
              isEmpty,
            );
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox());
            await t.runAsync(() => app.engine.disconnect());
            app.dispose();
            await t.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 50)),
            );
            BandOwnership.resetForTest();
            BleEngine.resetBandClaimForTest();
          }
        },
        timeout: const Timeout(Duration(seconds: 60)),
      );
    }
  }
  for (final scale in [1.0, 3.1]) {
    testWidgets(
      'empty observations at $scale explain absence without inventing a finding',
      (t) async {
        await localizedPage(t, const FindingsLog([]), scale: scale);
        final all = (await readPage(t)).join(' ');
        expect(find.byType(FindingRow), findsNothing);
        expect(find.byType(StatusCard), findsOneWidget);
        expect(all, contains('Nothing has stood out'));
        expect(all, contains('That is an outcome, not an empty screen.'));
        expect(
          await t.runAsync(
            () async => (await LocalDb.instance).query('day_result'),
          ),
          isEmpty,
        );
        expect(t.takeException(), isNull);
      },
    );
  }
}
