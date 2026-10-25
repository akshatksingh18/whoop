// Actual Settings controllers and persisted choices. OS delivery is substituted.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:openstrap_edge/data/off_lookup.dart';
import 'package:openstrap_edge/notify/notification_prefs.dart';
import 'package:openstrap_edge/notify/notification_service.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:openstrap_edge/state/prefs.dart';
import 'package:openstrap_edge/state/units_controller.dart';
import 'package:openstrap_edge/theme/theme_controller.dart';
import 'package:openstrap_edge/ui2/profile/settings.dart';
import 'package:openstrap_edge/ui2/profile/profile.dart' show SetRow;
import 'package:openstrap_edge/ui2/ui2.dart';
import 'support/audit_visual.dart' show loadAuditFonts;

class Store extends SharedPreferencesStorePlatform {
  final values = <String, Object>{};
  String? refuse;
  @override
  Future<Map<String, Object>> getAll() async => {...values};
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key == refuse) return false;
    values[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async => values.remove(key) != null;
  @override
  Future<bool> clear() async {
    values.clear();
    return true;
  }
}

class App extends AppState {
  App() : super.forTesting();
  int reminders = 0, thresholds = 0;
  @override
  Future<void> refreshReminders() async {
    reminders++;
  }

  @override
  Future<void> refreshBatteryThreshold(NotificationPrefs p) async {
    thresholds++;
  }
}

Future<void> flush(WidgetTester t) async {
  for (var i = 0; i < 12; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await t.pump(const Duration(milliseconds: 40));
  }
  await t.pumpAndSettle();
  expect(t.takeException(), isNull);
}

Future<void> tapRow(WidgetTester t, String title) async {
  final row = find.byWidgetPredicate((w) => w is SetRow && w.title == title);
  await t.scrollUntilVisible(
    row,
    250,
    maxScrolls: 50,
    scrollable: find
        .descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await t.pumpAndSettle();
  await t.ensureVisible(row);
  await t.pumpAndSettle();
  await t.tap(row);
  await flush(t);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferencesStorePlatform previous;
  late Store store;
  late App app;
  late UnitsController units;
  late ThemeController theme;
  var granted = true;
  setUpAll(loadAuditFonts);
  setUp(() async {
    previous = SharedPreferencesStorePlatform.instance;
    store = Store();
    SharedPreferencesStorePlatform.instance = store;
    SharedPreferences.resetStatic();
    await Prefs.ensureLoaded();
    PackageInfo.setMockInitialValues(
      appName: 'Synthetic app',
      packageName: 'synthetic.app',
      version: '1.0',
      buildNumber: '1',
      buildSignature: '',
    );
    app = App();
    units = UnitsController.seed(UnitSystem.metric);
    theme = ThemeController.seed(AppThemeChoice.light, Brightness.light);
    granted = true;
    NotificationService.instance.debugProbePermission = () async => granted;
  });
  tearDown(() async {
    app.dispose();
    units.dispose();
    theme.dispose();
    NotificationService.instance.debugProbePermission = null;
    NotificationService.instance.debugRequestPermission = null;
    SharedPreferencesStorePlatform.instance = previous;
    SharedPreferences.resetStatic();
    await Prefs.ensureLoaded();
  });
  Future<void> open(WidgetTester t, Widget page) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: app),
          ChangeNotifierProvider.value(value: units),
          ChangeNotifierProvider.value(value: theme),
        ],
        child: MaterialApp(theme: buildTheme(Brightness.light), home: page),
      ),
    );
    await flush(t);
    addTearDown(() async {
      await t.pumpWidget(const SizedBox());
      await flush(t);
    });
  }

  testWidgets(
    'each unit changes independently and survives controller reload',
    (t) async {
      await open(t, const MoreSettings());
      await tapRow(t, 'Weight');
      expect(units.weightUnit, 'lb');
      expect(units.distanceUnit, 'km');
      await tapRow(t, 'Distance');
      await tapRow(t, 'Height');
      final reloaded = (await t.runAsync(UnitsController.bootstrap))!;
      addTearDown(reloaded.dispose);
      expect(reloaded.weightUnit, 'lb');
      expect(reloaded.distanceUnit, 'mi');
      expect(reloaded.heightUnit, HeightUnit.ftIn);
      await tapRow(t, 'Weight');
      expect(units.weightUnit, 'kg');
      expect(units.distanceUnit, 'mi');
    },
  );
  testWidgets('refused unit write leaves the choice intact and retries', (
    t,
  ) async {
    store.refuse = 'flutter.units.distance';
    await open(t, const MoreSettings());
    await tapRow(t, 'Distance');
    expect(units.distanceUnit, 'km');
    expect(
      find.text('Could not save that setting. Try again.'),
      findsOneWidget,
    );
    store.refuse = null;
    await tapRow(t, 'Distance');
    expect(units.distanceUnit, 'mi');
    expect(store.values['flutter.units.distance'], 'mi');
  });
  testWidgets(
    'barcode consent can be granted and revoked without a network request',
    (t) async {
      await open(t, const MoreSettings());
      expect(offLookupAllowed, isFalse);
      await tapRow(t, 'Look barcodes up online');
      expect(offLookupAllowed, isTrue);
      await tapRow(t, 'Look barcodes up online');
      expect(offLookupAllowed, isFalse);
      expect(store.values['flutter.$kOffConsentKey'], isFalse);
    },
  );
  testWidgets(
    'refused barcode grant stays closed and explains that it did not persist',
    (t) async {
      store.refuse = 'flutter.$kOffConsentKey';
      await open(t, const MoreSettings());
      await tapRow(t, 'Look barcodes up online');
      expect(offLookupAllowed, isFalse);
      expect(find.textContaining('That could not be saved'), findsOneWidget);
    },
  );

  for (final (title, read) in <(String, bool Function(NotificationPrefs))>[
    ('Health exceptions', (p) => p.healthEnabled),
    ('Band alerts', (p) => p.deviceEnabled),
    ('Recovery ready', (p) => p.recoveryEnabled),
    ('Weekly lookback', (p) => p.remindersEnabled),
    ('Detected workouts', (p) => p.autoDetectEnabled),
    ('Quiet hours', (p) => p.quietEnabled),
  ]) {
    testWidgets('$title saves off and back on, refreshing the scheduler', (
      t,
    ) async {
      await open(t, const NotificationSettings());
      await tapRow(t, title);
      expect(read((await t.runAsync(NotificationPrefs.load))!), isFalse);
      expect(app.reminders, 1);
      expect(app.thresholds, 1);
      await tapRow(t, title);
      expect(read((await t.runAsync(NotificationPrefs.load))!), isTrue);
      expect(app.reminders, 2);
      expect(app.thresholds, 2);
    });
  }
  testWidgets('all four muted health kinds round-trip separately', (t) async {
    await open(t, const NotificationSettings());
    for (final label in [
      'Possible illness onset',
      'Unusual night',
      'Low readiness',
      'Resting heart-rate shift',
    ]) {
      await tapRow(t, label);
    }
    expect((await t.runAsync(NotificationPrefs.load))!.mutedFindings, {
      'illness',
      'anomaly',
      'lowReadiness',
      'rhrShift',
    });
    await tapRow(t, 'Unusual night');
    expect((await t.runAsync(NotificationPrefs.load))!.mutedFindings, {
      'illness',
      'lowReadiness',
      'rhrShift',
    });
  });
  testWidgets('battery threshold cycles through the actual supported choices', (
    t,
  ) async {
    await open(t, const NotificationSettings());
    for (final expected in [20, 25, 30, 40, 10, 15]) {
      await tapRow(t, 'Alert me at');
      expect(
        (await t.runAsync(NotificationPrefs.load))!.batteryAlertPct,
        expected,
      );
    }
  });
  testWidgets(
    'a refused notification save rolls back switches and does not rearm',
    (t) async {
      store.refuse = 'flutter.notif_device';
      await open(t, const NotificationSettings());
      await tapRow(t, 'Band alerts');
      expect(
        t
            .widget<NotificationSettingsView>(
              find.byType(NotificationSettingsView),
            )
            .prefs
            .deviceEnabled,
        isTrue,
      );
      expect(
        find.text('Could not save that setting. Try again.'),
        findsOneWidget,
      );
      expect(app.reminders, 0);
      expect(app.thresholds, 0);
      store.refuse = null;
      await tapRow(t, 'Band alerts');
      expect(
        (await t.runAsync(NotificationPrefs.load))!.deviceEnabled,
        isFalse,
      );
      expect(app.reminders, 1);
    },
  );
  testWidgets(
    'returning from system settings refreshes granted and revoked permission',
    (t) async {
      granted = false;
      await open(t, const NotificationSettings());
      expect(
        find.text('Notifications are off at the system level'),
        findsOneWidget,
      );
      granted = true;
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await flush(t);
      expect(
        find.text('Notifications are off at the system level'),
        findsNothing,
      );
      granted = false;
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await flush(t);
      expect(
        find.text('Notifications are off at the system level'),
        findsOneWidget,
      );
    },
  );
}
