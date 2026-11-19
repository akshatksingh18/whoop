// Persisted report -> real route request -> shell -> exact original finding.
// Authored store contents;no claim about OS notification delivery.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:whoop_companion/app.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/notify/notification_report.dart';
import 'package:whoop_companion/notify/tap_router.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/state/locale_controller.dart';
import 'package:whoop_companion/state/units_controller.dart';
import 'package:whoop_companion/theme/theme_controller.dart';
import 'package:whoop_companion/ui2/screens/what_changed.dart';
import 'coverage_app_gate_contracts_test.dart' show GateApp;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('shell-recap-report-handoff');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  for (final scale in [1.0, 3.1]) {
    for (final queued in [false, true]) {
      testWidgets(
        'saved recap route queued=$queued at ${scale}x preserves report identity and replay',
        (t) async {
          const day = '2021-04-06';
          const body = 'Original authored week finding.';
          final id = (await t.runAsync(
            () => NotificationReport.save('Your week in review', body, day),
          ))!;
          final newer = (await t.runAsync(
            () => NotificationReport.save(
              'Your week in review',
              'Later authored week finding.',
              '2021-04-13',
            ),
          ))!;
          expect(id, isNot(newer));
          final report = (await t.runAsync(() => NotificationReport.read(id)))!;
          final app = GateApp()
            ..gate = AppRoute.shell
            ..repo = LocalRepositoryImpl(getProfileMap: () => {});
          final theme = ThemeController.seed(
            AppThemeChoice.light,
            Brightness.light,
          );
          final locale = LocaleController.seed('en');
          final units = UnitsController.withUnits();
          addTearDown(() {
            app.dispose();
            theme.dispose();
            locale.dispose();
            units.dispose();
          });
          final route = datedRoute(kRouteRecap, day, id: id);
          if (queued) app.openRoute(route);
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
          if (!queued) app.openRoute(route);
          Future<void> flush() async {
            await t.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 100)),
            );
            await t.pumpAndSettle();
            expect(t.takeException(), isNull);
          }

          for (var replay = 0; replay < 2; replay++) {
            await flush();
            final page = find.byType(WhatChangedScreen);
            expect(page, findsOneWidget);
            final screen = t.widget<WhatChangedScreen>(page);
            expect(screen.day, day);
            expect(screen.reportId, id);
            final texts = (await readPage(t)).join(' ');
            expect(texts, contains(body));
            expect(texts, isNot(contains('Later authored week finding.')));
            expect(texts, isNot(contains('no longer retained')));
            expect(app.screenRequest.value, isNull);
            expect(app.navRequest.value, -1);
            expect(await t.runAsync(() => NotificationReport.read(id)), report);
            Navigator.of(t.element(page)).pop();
            await flush();
            expect(page, findsNothing);
            if (replay == 0) app.openRoute(route);
          }
          final db = await LocalDb.instance;
          for (final table in ['sessions', 'day_result', 'decoded_onehz']) {
            expect(await t.runAsync(() => db.query(table)), isEmpty);
          }
        },
      );
    }
  }
}
