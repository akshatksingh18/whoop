// Actual settings picker -> controller -> preference write, with native refusal.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:whoop_companion/notify/notification_prefs.dart';
import 'package:whoop_companion/notify/notification_service.dart';
import 'package:whoop_companion/state/prefs.dart';
import 'package:whoop_companion/ui2/profile/profile.dart' show SetRow;
import 'package:whoop_companion/ui2/profile/settings.dart';
import '../../data/settings_controls_test.dart' show App, Store, flush;
import '../../support/audit_visual.dart' show loadAuditFonts;
import '../../support/localized_coverage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferencesStorePlatform previous;
  late Store store;
  late App app;
  setUpAll(loadAuditFonts);
  setUp(() async {
    previous = SharedPreferencesStorePlatform.instance;
    SharedPreferencesStorePlatform.instance = store = Store();
    SharedPreferences.resetStatic();
    await Prefs.ensureLoaded();
    app = App();
    NotificationService.instance
      ..invalidatePermissionCache()
      ..debugProbePermission = () async => true;
    await const NotificationPrefs(quietStartMin: 1320, quietEndMin: 420).save();
    store.values['flutter.authored-unrelated'] = 'retain';
  });
  tearDown(() {
    app.dispose();
    NotificationService.instance
      ..debugProbePermission = null
      ..invalidatePermissionCache();
    SharedPreferencesStorePlatform.instance = previous;
    SharedPreferences.resetStatic();
  });

  for (final scale in [1.0, 3.1]) {
    for (final result in ['cancel', 'accept', 'refuse-retry']) {
      testWidgets('quiet end $result keeps the other choices at ${scale}x', (
        t,
      ) async {
        await localizedPage(
          t,
          const NotificationSettings(),
          app: app,
          scale: scale,
        );
        Future<void> choose(TimeOfDay? value) async {
          final row = find.byWidgetPredicate(
            (w) => w is SetRow && w.title == 'Ends',
          );
          await reveal(t, row);
          await t.tap(row);
          await t.pumpAndSettle();
          expect(find.byType(TimePickerDialog), findsOneWidget);
          expect(
            t
                .widget<TimePickerDialog>(find.byType(TimePickerDialog))
                .initialTime,
            const TimeOfDay(hour: 7, minute: 0),
          );
          Navigator.of(t.element(find.byType(TimePickerDialog))).pop(value);
          await flush(t);
        }

        final before = Map.of(store.values);
        if (result == 'refuse-retry') store.refuse = 'flutter.notif_quiet_end';
        await choose(
          result == 'cancel' ? null : const TimeOfDay(hour: 8, minute: 25),
        );
        if (result != 'accept') {
          expect(store.values, before);
          expect(app.reminders, 0);
          expect(app.thresholds, 0);
          expect(
            t
                .widget<NotificationSettingsView>(
                  find.byType(NotificationSettingsView),
                )
                .prefs
                .quietEndMin,
            420,
          );
        }
        if (result == 'refuse-retry') {
          expect(
            find.text('Could not save that setting. Try again.'),
            findsOneWidget,
          );
          store.refuse = null;
          await choose(const TimeOfDay(hour: 8, minute: 25));
        }
        final saved = (await t.runAsync(NotificationPrefs.load))!;
        expect(saved.quietEndMin, result == 'cancel' ? 420 : 505);
        expect(saved.quietStartMin, 1320);
        expect(saved.quietEnabled, true);
        expect(store.values['flutter.authored-unrelated'], 'retain');
        expect(app.reminders, result == 'cancel' ? 0 : 1);
        expect(app.thresholds, result == 'cancel' ? 0 : 1);
      });
    }
  }
}
