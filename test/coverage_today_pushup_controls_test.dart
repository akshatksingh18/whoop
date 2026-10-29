// Today controls against a real authored store; OS permission is substituted as denied.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/pushups.dart';
import 'package:whoop_companion/data/pushup_reminders.dart';
import 'package:whoop_companion/notify/notification_service.dart';
import 'package:whoop_companion/ui2/screens/pushups_screen.dart';
import 'package:whoop_companion/ui2/screens/today_plan.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'coverage_pushup_screen_actions_test.dart' show flush, command;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final service = NotificationService.instance;
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('today-pushup-controls');
  });
  Future<void> resetFixture() async {
    await resetCoverageStore();
    await PushupReminders.clearInbox();
    await PushupReminders.writeMirror(null);
    service.invalidatePermissionCache();
    service.debugRequestPermission = () async => false;
    service.debugProbePermission = () async => false;
    service.debugCancel = (_) async {};
  }

  setUp(resetFixture);
  tearDown(() {
    service.debugRequestPermission = null;
    service.debugProbePermission = null;
    service.debugCancel = null;
    service.invalidatePermissionCache();
  });
  tearDownAll(LocalDb.close);
  Future<void> runControl(WidgetTester t, dynamic callback) =>
      command(t, () async {
        await callback();
      });
  final flows = <({String name, Future<void> Function(WidgetTester) run})>[];
  void scenario(String name, Future<void> Function(WidgetTester) run) =>
      flows.add((name: name, run: run));

  scenario('Today Pushups retries a refused Start and opens the retained day', (
    t,
  ) async {
    final db = await LocalDb.instance;
    await db.execute(
      "CREATE TRIGGER synthetic_start_refusal BEFORE INSERT ON pushup_session BEGIN SELECT RAISE(ABORT,'synthetic refusal'); END",
    );
    try {
      await localizedPage(
        t,
        const Scaffold(body: TodayPushupRow(showWhenEmpty: true)),
      );
      await flush(t);
      final start = find.byWidgetPredicate(
        (w) => w is Pressable && w.semanticLabel == 'Start my day',
      );
      await runControl(t, t.widget<Pressable>(start).onTap);
      await flush(t);
      expect(find.text('Pushups did not start. Try again.'), findsOneWidget);
      expect(await t.runAsync(PushupDb.active), isNull);
      await t.runAsync(
        () => db.execute('DROP TRIGGER synthetic_start_refusal'),
      );
      await runControl(t, t.widget<Pressable>(start).onTap);
      await flush(t);
      expect((await t.runAsync(PushupDb.active))!.state, PushupState.running);
      expect(find.textContaining('Next '), findsOneWidget);
      final open = find.byWidgetPredicate(
        (w) =>
            w is Surface && (w.semanticLabel?.startsWith('Pushups, ') ?? false),
      );
      await t.tap(open);
      await flush(t);
      expect(find.byType(PushupsScreen), findsOneWidget);
    } finally {
      await t.runAsync(
        () => db.execute('DROP TRIGGER IF EXISTS synthetic_start_refusal'),
      );
    }
  });
  for (final embedded in [false, true]) {
    scenario(
      'Today ${embedded ? 'plan row' : 'card'} logs a deliberate set while staying paused',
      (t) async {
        await command(t, () async {
          await Pushups.start(paused: true);
        });
        await localizedPage(
          t,
          Scaffold(
            body: TodayPushupRow(showWhenEmpty: true, embedded: embedded),
          ),
        );
        await flush(t);
        expect(find.text('Paused'), findsOneWidget);
        final callback = embedded
            ? t.widget<PlanRow>(find.byType(PlanRow)).onAction
            : t
                  .widget<Pressable>(
                    find.byWidgetPredicate(
                      (w) => w is Pressable && w.semanticLabel == 'Log a set',
                    ),
                  )
                  .onTap;
        await runControl(t, callback);
        await flush(t);
        final saved = (await t.runAsync(PushupDb.active))!;
        expect(saved.count, 1);
        expect(saved.state, PushupState.paused);
        expect(saved.anchor, isNull);
        expect(find.textContaining('Pushups · 1'), findsOneWidget);
      },
    );
  }
  // The process-wide Pushups Future must stay in one active widget clock.
  testWidgets('Today Pushups controls retain refusal, count and paused state', (
    t,
  ) async {
    for (final flow in flows) {
      await t.pumpWidget(const SizedBox());
      await flush(t);
      await t.runAsync(resetFixture);
      debugPrint('Today Pushups control: ${flow.name}');
      await flow.run(t);
    }
  });
}
