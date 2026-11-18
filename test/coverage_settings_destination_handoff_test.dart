// The shipped Settings host owns these routes. Substitute only the OS browser
// boundary; this test never opens a network page or claims native acceptance.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/link.dart' show LinkDelegate;
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/state/units_controller.dart';
import 'package:whoop_companion/theme/theme_controller.dart';
import 'package:whoop_companion/ui2/profile/profile.dart' show SetRow;
import 'package:whoop_companion/ui2/profile/settings.dart';
import 'package:whoop_companion/ui2/profile/status.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

class _Browser extends UrlLauncherPlatform {
  final calls = <(String, LaunchOptions)>[];
  bool accepted = true;
  @override
  LinkDelegate? get linkDelegate => null;
  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    calls.add((url, options));
    return accepted;
  }
}

void main() {
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('settings-destination-handoff');
  });
  setUp(() async {
    await resetCoverageStore();
    PackageInfo.setMockInitialValues(
      appName: 'Authored app',
      packageName: 'authored.app',
      version: '1.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });
  tearDownAll(LocalDb.close);

  Future<AppState> open(WidgetTester t, double scale) async {
    final app = AppState.forTesting()
      ..user = {'weight_kg': 70.0, 'name': 'Authored'};
    final units = UnitsController.seed(UnitSystem.metric);
    final theme = ThemeController.seed(AppThemeChoice.light, Brightness.light);
    addTearDown(() {
      app.dispose();
      units.dispose();
      theme.dispose();
    });
    await localizedPage(
      t,
      const MoreSettings(),
      app: app,
      units: units,
      themeController: theme,
      scale: scale,
    );
    return app;
  }

  Future<void> tapRow(WidgetTester t, Finder row) async {
    await reveal(t, row);
    await t.ensureVisible(row);
    await t.tap(row);
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  }

  for (final scale in [1.0, 3.1]) {
    for (final accepted in [false, true]) {
      testWidgets(
        'Settings licence browser admission=$accepted keeps its host $scale',
        (t) async {
          final old = UrlLauncherPlatform.instance;
          final browser = _Browser()..accepted = accepted;
          UrlLauncherPlatform.instance = browser;
          addTearDown(() => UrlLauncherPlatform.instance = old);
          final app = await open(t, scale);
          final owner = t.state(find.byType(MoreSettings));
          final row = find.byWidgetPredicate(
            (w) => w is SetRow && w.title.toLowerCase().contains('licen'),
          );
          await tapRow(t, row);
          expect(browser.calls, hasLength(1));
          expect(
            browser.calls.single.$1,
            'https://github.com/akshatksingh18/whoop/blob/main/LICENSE',
          );
          expect(
            browser.calls.single.$2.mode,
            PreferredLaunchMode.externalApplication,
          );
          expect(browser.calls.single.$2.webViewConfiguration.headers, isEmpty);
          expect(t.state(find.byType(MoreSettings)), same(owner));
          expect(app.user!['weight_kg'], 70);
          browser.accepted = true;
          await tapRow(t, row);
          expect(browser.calls, hasLength(2));
          expect(browser.calls.last.$1, browser.calls.first.$1);
          expect(t.state(find.byType(MoreSettings)), same(owner));
        },
      );
    }
    testWidgets(
      'Settings Status opens its real destination and Back keeps choices $scale',
      (t) async {
        final app = await open(t, scale);
        final owner = t.state(find.byType(MoreSettings));
        final original = t.widget<MoreSettingsView>(
          find.byType(MoreSettingsView),
        );
        await tapRow(
          t,
          find.byWidgetPredicate((w) => w is SetRow && w.title == 'Status'),
        );
        expect(find.byType(StatusScreen), findsOneWidget);
        expect(find.byType(MoreSettings), findsNothing);
        expect(app.user!['weight_kg'], 70);
        // Exercise the rendered custom Back action rather than an SDK-only
        // AppBar assumption; its default path pops the same real navigator.
        final back = find.descendant(
          of: find.byType(NavBar).last,
          matching: find.byType(Pressable),
        );
        expect(back, findsWidgets);
        await t.tap(back.first);
        await t.pumpAndSettle();
        expect(find.byType(StatusScreen), findsNothing);
        expect(t.state(find.byType(MoreSettings)), same(owner));
        final returned = t.widget<MoreSettingsView>(
          find.byType(MoreSettingsView),
        );
        expect(returned.weightUnit, original.weightUnit);
        expect(returned.appearance, original.appearance);
        expect(returned.phoneSteps, original.phoneSteps);
        expect(t.takeException(), isNull);
      },
    );
  }
}
