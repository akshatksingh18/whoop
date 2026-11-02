// Application gate, lifecycle dispatch and queued tab requests, synthetic state only.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:whoop_companion/app.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/state/locale_controller.dart';
import 'package:whoop_companion/state/units_controller.dart';
import 'package:whoop_companion/theme/theme_controller.dart';
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

class GateApp extends AppState {
  GateApp() : super.forTesting();
  AppRoute gate = AppRoute.failed;
  final calls = <String>[];
  @override
  AppRoute get route => gate;
  @override
  Future<void> retryInit() async {
    calls.add('retry');
  }

  @override
  Future<void> runCadenceChecks() async {
    calls.add('cadence');
  }

  @override
  Future<void> runBackupIfDue() async {
    calls.add('backup');
  }

  @override
  Future<void> refreshSigningStatus() async {
    calls.add('signing');
  }

  @override
  Future<void> refreshForeground() async {
    calls.add('refresh');
  }

  @override
  void startForegroundRefresh() {
    calls.add('start');
  }

  @override
  void stopForegroundRefresh() {
    calls.add('stop');
  }

  @override
  Future<void> pauseForBackground() async {
    calls.add('pause');
  }
}

void main() {
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('app-gates');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  Future<void> open(WidgetTester t, GateApp app) async {
    final theme = ThemeController.seed(AppThemeChoice.system, Brightness.light);
    final locale = LocaleController.seed('en');
    final units = UnitsController.withUnits();
    addTearDown(theme.dispose);
    addTearDown(locale.dispose);
    addTearDown(units.dispose);
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
    );
  }

  testWidgets(
    'COV-44 failed startup preserves exact diagnostic and retry action',
    (t) async {
      final app = GateApp()..initError = 'Synthetic initialization refusal';
      addTearDown(app.dispose);
      await open(t, app);
      expect(find.text('Synthetic initialization refusal'), findsOneWidget);
      await t.tap(find.byType(FilledButton));
      await t.pumpAndSettle();
      expect(app.calls, contains('retry'));
      t.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await t.pumpAndSettle();
      expect(
        t.widgetList<MaterialApp>(find.byType(MaterialApp)).last.themeMode,
        ThemeMode.light,
      );
      t.platformDispatcher.clearPlatformBrightnessTestValue();
    },
  );
  testWidgets(
    'COV-44 lifecycle delegates resume and pause work through app ownership',
    (t) async {
      final app = GateApp();
      addTearDown(app.dispose);
      await open(t, app);
      app.calls.clear();
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await t.pump();
      expect(app.calls, containsAll(['pause', 'stop']));
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await t.pump();
      expect(
        app.calls,
        containsAll(['cadence', 'backup', 'signing', 'refresh', 'start']),
      );
    },
  );
  testWidgets(
    'COV-44 shell consumes programmatic Train and Progress tab requests once',
    (t) async {
      final app = GateApp()
        ..gate = AppRoute.shell
        ..repo = LocalRepositoryImpl(getProfileMap: () => {});
      addTearDown(app.dispose);
      await open(t, app);
      for (final (tab, title) in [(4, 'Train'), (5, 'Progress')]) {
        app.navRequest.value = tab;
        await t.pump();
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await t.pumpAndSettle();
        expect(app.navRequest.value, -1);
        expect(find.text(title), findsWidgets);
      }
    },
  );
}
