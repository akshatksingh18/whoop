// Actual Home/Pushups page timers, read refusal and retry over authored SQLite.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/pushups.dart';
import 'package:whoop_companion/data/pushup_reminders.dart';
import 'package:whoop_companion/notify/notification_service.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/theme/theme_controller.dart';
import 'package:whoop_companion/ui2/screens/home_screen.dart';
import 'package:whoop_companion/ui2/screens/pushups_screen.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import '../activity/home_read_navigation_test.dart' show complete;
import '../../support/audit_visual.dart' show loadAuditFonts;
import '../../support/coverage_store.dart';
import '../../support/localized_coverage.dart';

Future<void> pageIO(WidgetTester t) async {
  for (var i = 0; i < 35; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await t.pump(const Duration(milliseconds: 25));
  }
  await t.pumpAndSettle();
  expect(t.takeException(), isNull);
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('page-timer-recovery', fresh: true);
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  for (final ticking in [false, true]) {
    for (final resumed in [false, true]) {
      testWidgets(
        'Home minute refresh obeys ticker=$ticking resumed=$resumed without changing saved metrics',
        (t) async {
          final app = AppState.forTesting();
          final theme = ThemeController.seed(
            AppThemeChoice.light,
            Brightness.light,
          );
          addTearDown(app.dispose);
          addTearDown(theme.dispose);
          await localizedPage(
            t,
            TickerMode(
              enabled: ticking,
              child: Scaffold(body: HomeScreen(data: complete())),
            ),
            app: app,
            themeController: theme,
          );
          final heart = find.byWidgetPredicate(
            (w) =>
                w is Surface &&
                (w.semanticLabel?.startsWith('Heart rate') ?? false),
          );
          await reveal(t, heart);
          binding.handleAppLifecycleStateChanged(
            resumed ? AppLifecycleState.resumed : AppLifecycleState.inactive,
          );
          await t.pumpAndSettle();
          final before = t.widget<Surface>(heart);
          final revision = app.insightsRevision.value;
          await t.pump(const Duration(minutes: 1));
          final after = t.widget<Surface>(heart);
          expect(identical(before, after), !(ticking && resumed));
          expect(app.insightsRevision.value, revision);
          expect(
            await t.runAsync(
              () async => (await LocalDb.instance).query('day_result'),
            ),
            isEmpty,
          );
          expect(find.text('Today'), findsWidgets);
          expect(t.takeException(), isNull);
          binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
          await t.pumpWidget(const SizedBox());
          await t.pump(const Duration(minutes: 2));
          expect(t.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'Pushups read refusal preserves empty and retained history through explicit retry',
    (t) async {
      // One application command queue belongs to one scheduler zone. Both saved-
      // history states retain all assertions in this same widget lifetime.
      for (final retained in [false, true]) {
        final service = NotificationService.instance;
        final cancel = service.debugCancel;
        final permission = service.debugProbePermission;
        service.debugCancel = (_) async {};
        service.debugProbePermission = () async => false;
        addTearDown(() {
          service.debugCancel = cancel;
          service.debugProbePermission = permission;
        });
        final rows = (await t.runAsync(() async {
          if (retained) {
            await PushupDb.save(
              PushupSession(
                id: 'authored-completed-history',
                day: '2021-04-06',
                started: DateTime(2021, 4, 6, 9),
                ended: DateTime(2021, 4, 6, 10),
                interval: 30,
                state: PushupState.ended,
              ),
            );
          }
          final db = await LocalDb.instance;
          final saved = await db.query('pushup_session');
          await db.execute(
            'ALTER TABLE pushup_session RENAME TO authored_preserved_pushups',
          );
          return saved;
        }))!;
        var restored = false;
        addTearDown(() async {
          if (!restored) {
            await (await LocalDb.instance).execute(
              'ALTER TABLE authored_preserved_pushups RENAME TO pushup_session',
            );
          }
        });
        await localizedPage(t, const PushupsScreen(), settle: false);
        await pageIO(t);
        expect(find.text('Pushups could not load'), findsOneWidget);
        expect(find.text('Your saved days are intact.'), findsOneWidget);
        final retry = t.widget<StatusCard>(find.byType(StatusCard).first).onFix;
        await invokeControl(t, retry);
        await pageIO(t);
        expect(find.text('Pushups could not load'), findsOneWidget);
        await t.runAsync(() async {
          final db = await LocalDb.instance;
          expect(await db.query('authored_preserved_pushups'), rows);
          await db.execute(
            'ALTER TABLE authored_preserved_pushups RENAME TO pushup_session',
          );
          restored = true;
        });
        await invokeControl(t, retry);
        await pageIO(t);
        expect(find.text('Pushups could not load'), findsNothing);
        expect(find.text('Start my day'), findsWidgets);
        await t.pump(const Duration(minutes: 1));
        await pageIO(t);
        expect(
          await t.runAsync(
            () async => (await LocalDb.instance).query('pushup_session'),
          ),
          rows,
        );
        expect((await t.runAsync(Pushups.status))!.active, isNull);
        expect(t.takeException(), isNull);

        await t.pumpWidget(const SizedBox());
        await t.pumpAndSettle();
      }
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
