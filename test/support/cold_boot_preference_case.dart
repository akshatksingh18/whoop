// Real cold entry must survive a damaged optional preference without erasing it.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whoop_companion/app.dart';
import 'package:whoop_companion/main.dart' as entry;
import 'package:whoop_companion/ble/ios_ble_restore.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/l10n/app_localizations.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/state/locale_controller.dart';
import 'package:whoop_companion/state/units_controller.dart';
import 'package:whoop_companion/sync/ios_bg_task.dart';
import 'package:whoop_companion/theme/theme_controller.dart';
import 'audit_visual.dart' show loadAuditFonts;
import 'coverage_store.dart';

void coldBootPreferenceRecovery(String damaged) {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('cold-boot-preference-recovery-$damaged');
    AndroidFlutterLocalNotificationsPlugin.registerWith();
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  testWidgets(
    'COV-67 cold entry recovers damaged $damaged preferences and preserves saved evidence',
    (t) async {
      t.view.physicalSize = const Size(430, 1800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final badTheme = damaged == 'appearance' || damaged == 'all';
      final badUnits = damaged == 'units' || damaged == 'all';
      final badLocale = damaged == 'language' || damaged == 'all';
      final values = <String, Object>{
        'theme_choice': badTheme ? 17 : 'dark',
        'body.unit': badUnits ? true : 'lb',
        'units.distance': 'mi',
        'units.height': 'ftIn',
        'locale_override': badLocale ? 23 : 'es',
      };
      SharedPreferences.setMockInitialValues(values);
      await t.runAsync(
        () => LocalDb.setCursor('authored-cold-recovery', 'retain exactly'),
      );
      final before = await t.runAsync(
        () async => (await LocalDb.instance).query('sync_cursor'),
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const notifications = MethodChannel(
        'dexterous.com/flutter/local_notifications',
      );
      messenger.setMockMethodCallHandler(
        notifications,
        (_) async => throw PlatformException(
          code: 'authored_optional_service_unavailable',
        ),
      );
      final previousFlutter = FlutterError.onError;
      final previousPlatform = PlatformDispatcher.instance.onError;
      addTearDown(() {
        messenger.setMockMethodCallHandler(notifications, null);
        FlutterError.onError = previousFlutter;
        PlatformDispatcher.instance.onError = previousPlatform;
        IosBgTask.foregroundPull = null;
        IosBleRestore.onWake = null;
      });
      await t.runAsync(entry.main);
      await t.pump();
      final context = t.element(find.byType(WhoopApp));
      final app = context.read<AppState>();
      final theme = context.read<ThemeController>();
      final units = context.read<UnitsController>();
      final locale = context.read<LocaleController>();
      for (
        var i = 0;
        i < 150 && !app.initialized && app.initError == null;
        i++
      ) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await t.pump();
      }
      await t.pumpAndSettle();
      expect(app.initialized, true);
      expect(app.initError, isNull);
      expect(app.route, AppRoute.welcome);
      expect(
        theme.choice,
        badTheme ? AppThemeChoice.system : AppThemeChoice.dark,
      );
      expect(units.weightUnit, badUnits ? 'kg' : 'lb');
      expect(units.distanceUnit, badUnits ? 'km' : 'mi');
      expect(units.heightUnit, badUnits ? HeightUnit.cm : HeightUnit.ftIn);
      expect(locale.code, badLocale ? null : 'es');
      final rendered = AppLocalizations.of(
        t.element(find.byType(Scaffold).first),
      )!;
      expect(find.text(rendered.welcomeSetUpMyBand), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      for (final key in ['theme_choice', 'body.unit', 'locale_override']) {
        expect(prefs.get(key), values[key], reason: '$key remains recoverable');
      }
      expect(
        await t.runAsync(
          () async => (await LocalDb.instance).query('sync_cursor'),
        ),
        before,
      );
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      theme.dispose();
      units.dispose();
      locale.dispose();
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );
}
