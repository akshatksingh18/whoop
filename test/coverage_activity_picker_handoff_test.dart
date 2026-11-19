// Real picker gestures and the default setup route; no session is started.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/ui2/activity/catalogue.dart';
import 'package:whoop_companion/ui2/activity/picker.dart';
import 'package:whoop_companion/ui2/activity/setup.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('activity-picker-handoff');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  for (final recent in [false, true]) {
    testWidgets(
      'picker search cancellation restores ${recent ? 'actual recents' : 'quick start'} without logging',
      (t) async {
        await localizedPage(
          t,
          ActivityPicker(
            recent: recent ? [activityByName('Rowing')!] : const [],
          ),
        );
        expect(find.text(recent ? 'RECENT' : 'QUICK START'), findsOneWidget);
        await t.enterText(find.byType(TextField), 'zzzz no authored activity');
        await t.pumpAndSettle();
        expect(find.text('No activity matches that'), findsOneWidget);
        expect(find.byType(ActivitySetup), findsNothing);
        final clear = find.byWidgetPredicate(
          (w) => w is Pressable && w.semanticLabel == 'Clear search',
        );
        await t.tap(clear);
        await t.pumpAndSettle();
        expect(
          t.widget<TextField>(find.byType(TextField)).controller!.text,
          '',
        );
        expect(find.text(recent ? 'RECENT' : 'QUICK START'), findsOneWidget);
        expect(find.text('No activity matches that'), findsNothing);
        final db = (await t.runAsync(() => LocalDb.instance))!;
        expect(await t.runAsync(() => db.query('sessions')), isEmpty);
      },
    );
  }
  for (final activity in ['Rowing', 'Running']) {
    testWidgets(
      'default picker route carries $activity and body weight and Back preserves search',
      (t) async {
        await localizedPage(t, const ActivityPicker(weightKg: 73.25));
        await t.enterText(find.byType(TextField), activity);
        await t.pumpAndSettle();
        final row = find.byWidgetPredicate(
          (w) => w is ActivityRow && w.a.name == activity,
        );
        expect(row, findsOneWidget);
        await t.tap(row);
        await t.pumpAndSettle();
        final setup = t.widget<ActivitySetup>(find.byType(ActivitySetup));
        expect(setup.a.typeKey, activityByName(activity)!.typeKey);
        expect(setup.weightKg, 73.25);
        Navigator.of(t.element(find.byType(ActivitySetup))).pop();
        await t.pumpAndSettle();
        expect(find.byType(ActivityPicker), findsOneWidget);
        expect(
          t.widget<TextField>(find.byType(TextField)).controller!.text,
          activity,
        );
        expect(row, findsOneWidget);
        final db = (await t.runAsync(() => LocalDb.instance))!;
        expect(await t.runAsync(() => db.query('sessions')), isEmpty);
      },
    );
  }
}
