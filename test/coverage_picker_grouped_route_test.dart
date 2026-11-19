// Open the actual grouped catalogue and return without starting a session.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/ui2/activity/catalogue.dart';
import 'package:whoop_companion/ui2/activity/picker.dart';
import 'package:whoop_companion/ui2/activity/setup.dart';

import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('picker-grouped-route');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  for (final (scale, activity) in [(1.0, 'Dancing'), (3.1, 'Intimacy')]) {
    testWidgets('Other group opens $activity setup at scale $scale', (t) async {
      await localizedPage(t, const ActivityPicker(weightKg: 74), scale: scale);
      final chosen = activityByName(activity)!;
      final group = find.text('Other');
      final row = find.byWidgetPredicate(
        (w) => w is ActivityRow && w.a.typeKey == chosen.typeKey,
      );
      expect(row, findsNothing);
      await reveal(t, group);
      await t.tap(group);
      await t.pumpAndSettle();
      expect(row, findsOneWidget);
      expect(
        find.descendant(of: row, matching: find.byIcon(LucideIcons.lock)),
        chosen.private ? findsOneWidget : findsNothing,
      );
      final calorieHint = find.descendant(
        of: row,
        matching: find.textContaining('kcal / 30 min'),
      );
      expect(calorieHint, scale == 1 ? findsOneWidget : findsNothing);

      await reveal(t, row);
      await t.tap(row);
      await t.pumpAndSettle();
      final page = find.byType(ActivitySetup);
      final setup = t.widget<ActivitySetup>(page);
      expect(setup.a, same(chosen));
      expect(setup.weightKg, 74);
      Navigator.of(t.element(page)).pop();
      await t.pumpAndSettle();

      expect(row, findsOneWidget);
      expect(t.widget<TextField>(find.byType(TextField)).controller!.text, '');
      final sessions = await t.runAsync(
        () async => (await LocalDb.instance).query('sessions'),
      );
      expect(sessions, isEmpty);
      expect(t.takeException(), isNull);
    });
  }
}
