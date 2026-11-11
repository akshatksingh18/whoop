// Existing Settings destinations and contextual OS-settings handoff.
// Authored SQLite/preferences; permission and OS navigation are substituted.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/notify/notification_service.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/state/units_controller.dart';
import 'package:whoop_companion/theme/theme_controller.dart';
import 'package:whoop_companion/ui2/profile/alarm.dart';
import 'package:whoop_companion/ui2/profile/data.dart';
import 'package:whoop_companion/ui2/profile/devices.dart';
import 'package:whoop_companion/ui2/profile/profile.dart' show SetRow;
import 'package:whoop_companion/ui2/profile/settings.dart';

import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

class _SettingsHost extends GeolocatorPlatform {
  int opens = 0;
  Object result = true;
  @override
  Future<bool> openAppSettings() async {
    opens++;
    if (result is bool) return result as bool;
    throw result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('settings-destination-contracts');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  late AppState app;
  late UnitsController units;
  late ThemeController theme;
  late GeolocatorPlatform previousGeo;
  late _SettingsHost geo;
  setUp(() {
    app = AppState.forTesting()
      ..user = {'sex': 'f', 'age': 30, 'height_cm': 170, 'weight_kg': 70};
    units = UnitsController.seed(UnitSystem.metric);
    theme = ThemeController.seed(AppThemeChoice.light, Brightness.light);
    PackageInfo.setMockInitialValues(
      appName: 'Authored',
      packageName: 'synthetic.app',
      version: '1.0',
      buildNumber: '1',
      buildSignature: '',
    );
    NotificationService.instance
      ..invalidatePermissionCache()
      ..debugProbePermission = () async => false;
    previousGeo = GeolocatorPlatform.instance;
    GeolocatorPlatform.instance = geo = _SettingsHost();
  });
  tearDown(() {
    app.dispose();
    units.dispose();
    theme.dispose();
    NotificationService.instance
      ..debugRequestPermission = null
      ..debugProbePermission = null
      ..invalidatePermissionCache();
    GeolocatorPlatform.instance = previousGeo;
  });

  for (final language in ['en', 'es']) {
    for (final scale in [1.0, 3.1]) {
      for (final destination in [
        'profile',
        'sources',
        'alarm',
        'notifications',
        'data',
      ]) {
        testWidgets(
          '$destination Settings route/back retains saved data $language/$scale',
          (t) async {
            await LocalDb.putMetricSeriesValue('2021-04-06', 'steps', 1234);
            final db = await LocalDb.instance;
            final saved = await db.query('metric_series');
            final prefs = (await t.runAsync(SharedPreferences.getInstance))!;
            final beforePrefs = {
              for (final key in prefs.getKeys()) key: prefs.get(key),
            };
            final profile = Map.of(app.user!);
            await localizedPage(
              t,
              const MoreSettings(),
              app: app,
              units: units,
              themeController: theme,
              language: language,
              scale: scale,
              push: true,
            );
            final view = t.widget<MoreSettingsView>(
              find.byType(MoreSettingsView),
            );
            final callback = switch (destination) {
              'profile' => view.onEditProfile,
              'sources' => view.onDevices,
              'alarm' => view.onAlarm,
              'notifications' => view.onNotifications,
              _ => view.onData,
            };
            final row = find.byWidgetPredicate(
              (w) => w is SetRow && identical(w.onTap, callback),
            );
            await reveal(t, row);
            await t.tap(row);
            await t.pumpAndSettle();
            await t.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 80)),
            );
            await t.pumpAndSettle();
            final target = switch (destination) {
              'profile' => find.byType(EditProfile),
              'sources' => find.byType(MyDevices),
              'alarm' => find.byType(AlarmScreen),
              'notifications' => find.byType(NotificationSettings),
              _ => find.byType(DataScreen),
            };
            expect(target, findsOneWidget);
            Navigator.of(t.element(target)).pop();
            await t.pumpAndSettle();
            expect(find.byType(MoreSettings), findsOneWidget);
            expect(
              t
                  .widget<MoreSettingsView>(find.byType(MoreSettingsView))
                  .weightUnit,
              'kg',
            );
            expect(app.user, profile);
            expect(await t.runAsync(() => db.query('metric_series')), saved);
            expect({
              for (final key in prefs.getKeys()) key: prefs.get(key),
            }, beforePrefs);
            expect(
              geo.opens,
              0,
              reason: 'Opening a page must not open OS Settings.',
            );
            expect(t.takeException(), isNull);
          },
        );
      }
    }
  }

  for (final reply in [
    true,
    false,
    StateError('authored OS-settings refusal'),
  ]) {
    testWidgets(
      'denied notification request preserves choices when OS Settings returns $reply',
      (t) async {
        geo.result = reply;
        var requests = 0;
        NotificationService.instance.debugRequestPermission = () async {
          requests++;
          return false;
        };
        final prefs = (await t.runAsync(SharedPreferences.getInstance))!;
        final before = {for (final key in prefs.getKeys()) key: prefs.get(key)};
        await localizedPage(t, const NotificationSettings(), app: app);
        final view = t.widget<NotificationSettingsView>(
          find.byType(NotificationSettingsView),
        );
        expect(view.loaded, true);
        expect(view.granted, false);
        await invokeControl(t, view.onRequestPermission);
        expect(requests, 1);
        expect(geo.opens, 1);
        expect(
          t
              .widget<NotificationSettingsView>(
                find.byType(NotificationSettingsView),
              )
              .granted,
          false,
        );
        expect({
          for (final key in prefs.getKeys()) key: prefs.get(key),
        }, before);
        // A real foreground permission read restores access without re-prompting.
        NotificationService.instance.debugProbePermission = () async => true;
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await t.pumpAndSettle();
        expect(
          t
              .widget<NotificationSettingsView>(
                find.byType(NotificationSettingsView),
              )
              .granted,
          true,
        );
        expect(requests, 1);
        expect(geo.opens, 1);
        expect(t.takeException(), isNull);
      },
    );
  }
}
