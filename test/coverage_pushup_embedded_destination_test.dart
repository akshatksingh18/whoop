// The embedded Today row opens Pushups without running its Start/Done action.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/pushup_reminders.dart';
import 'package:whoop_companion/notify/notification_service.dart';
import 'package:whoop_companion/ui2/screens/pushups_screen.dart';
import 'package:whoop_companion/ui2/screens/today_plan.dart';

import 'coverage_nutrition_root_test.dart' show io;
import 'coverage_pushup_screen_actions_test.dart' show command;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  final service = NotificationService.instance;
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('pushup-embedded-destination');
  });
  setUp(() async {
    await resetCoverageStore();
    await PushupReminders.clearInbox();
    await PushupReminders.writeMirror(null);
    service.invalidatePermissionCache();
    service.debugRequestPermission = () async => false;
    service.debugProbePermission = () async => false;
    service.debugCancel = (_) async {};
  });
  tearDown(() {
    service.debugRequestPermission = null;
    service.debugProbePermission = null;
    service.debugCancel = null;
    service.invalidatePermissionCache();
  });
  tearDownAll(LocalDb.close);

  testWidgets('embedded Pushups opens empty and paused days without logging', (
    t,
  ) async {
    for (final paused in [false, true]) {
      if (paused) {
        await t.pumpWidget(const SizedBox());
        await io(t);
        await command(t, () async {
          await Pushups.start(paused: true);
        });
      }
      final db = await LocalDb.instance;
      // Opening the page refreshes the row's modification time. Preserve the
      // entire session payload, including its events and action receipts.
      Future<List<Map<String, Object?>>> sessionEvidence() async => [
        for (final row in await db.query('pushup_session', orderBy: 'id'))
          Map<String, Object?>.of(row)..remove('updated_at'),
      ];
      final before = await t.runAsync(sessionEvidence);
      await localizedPage(
        t,
        const Scaffold(
          body: TodayPushupRow(embedded: true, showWhenEmpty: true),
        ),
        settle: false,
      );
      await io(t);
      final row = find.byType(PlanRow);
      final label = paused ? 'Paused' : 'Not started today';
      expect(t.widget<PlanRow>(row).sub, label);
      await t.tap(find.descendant(of: row, matching: find.text(label)));
      await io(t);
      final page = find.byType(PushupsScreen);
      expect(page, findsOneWidget);
      expect(await t.runAsync(sessionEvidence), before);
      Navigator.of(t.element(page)).pop();
      await io(t);
      expect(t.widget<PlanRow>(row).sub, label);
      expect(await t.runAsync(sessionEvidence), before);
      expect(t.takeException(), isNull);
    }
  });
}
