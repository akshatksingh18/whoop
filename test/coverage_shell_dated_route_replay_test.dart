// Supported persisted notification routes through AppState and the real shell.
// Synthetic empty SQLite history; no claim about physical OS notification delivery.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:whoop_companion/app.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/notify/tap_router.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/state/locale_controller.dart';
import 'package:whoop_companion/state/units_controller.dart';
import 'package:whoop_companion/theme/theme_controller.dart';
import 'package:whoop_companion/ui2/screens/readiness_detail.dart';
import 'package:whoop_companion/ui2/screens/sleep_detail.dart';
import 'package:whoop_companion/ui2/screens/what_changed.dart';
import 'coverage_app_gate_contracts_test.dart' show GateApp;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GateApp app;
  late ThemeController theme;
  late LocaleController locale;
  late UnitsController units;
  const viewed = '2021-04-06';
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('shell-dated-route-replay');
  });
  setUp(() async {
    await resetCoverageStore();
    app = GateApp()..gate = AppRoute.shell;
    app.repo = LocalRepositoryImpl(getProfileMap: () => {});
    theme = ThemeController.seed(AppThemeChoice.light, Brightness.light);
    locale = LocaleController.seed('en');
    units = UnitsController.withUnits();
  });
  tearDown(() {
    app.dispose();
    theme.dispose();
    locale.dispose();
    units.dispose();
  });
  tearDownAll(LocalDb.close);
  Future<void> flush(WidgetTester t) async {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  }

  for (final route in ['/sleep', '/heart', kRouteRecovery]) {
    for (final queued in [false, true]) {
      for (final scale in [1.0, 3.1]) {
        testWidgets(
          '$route historical replay queued=$queued at ${scale}x retains date and Back',
          (t) async {
            final payload = datedRoute(route, viewed);
            if (queued) app.openRoute(payload);
            await localizedPage(
              t,
              MultiProvider(
                providers: [
                  ChangeNotifierProvider.value(value: theme),
                  ChangeNotifierProvider.value(value: locale),
                  ChangeNotifierProvider.value(value: units),
                ],
                child: const WhoopApp(),
              ),
              app: app,
              scale: scale,
            );
            if (!queued) app.openRoute(payload);
            await flush(t);
            Finder page() => find.byWidgetPredicate(
              (w) => switch (route) {
                '/sleep' => w is SleepDetail && w.day == viewed,
                '/heart' => w is WhatChangedScreen && w.day == viewed,
                _ => w is ReadinessDetail && w.day == viewed,
              },
            );
            expect(page(), findsOneWidget);
            expect(app.screenRequest.value, isNull);
            expect(app.navRequest.value, -1);
            Navigator.of(t.element(page())).pop();
            await flush(t);
            expect(page(), findsNothing);
            app.openRoute(payload);
            await flush(t);
            expect(page(), findsOneWidget);
            expect(app.screenRequest.value, isNull);
            final db = await LocalDb.instance;
            for (final table in ['sessions', 'day_result', 'decoded_onehz']) {
              expect(await t.runAsync(() => db.query(table)), isEmpty);
            }
            Navigator.of(t.element(page())).pop();
            await flush(t);
            expect(page(), findsNothing);
          },
        );
      }
    }
  }
}
