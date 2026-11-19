// Holding a chart cursor updates the live map position in the saved summary.
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/ui2/activity/run_detail.dart';
import 'package:whoop_companion/ui2/activity/summary.dart';
import 'package:whoop_companion/ui2/ui2.dart';

import 'coverage_route_context_history_test.dart' show result;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('saved-route-graph-cursor');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  for (final type in ['Running', 'Walking']) {
    testWidgets('$type summary chart scrubs the same point on the map', (
      t,
    ) async {
      final sample = result(type: type, id: null);
      final fixes = List.of(sample.track);
      await localizedPage(t, ActivitySummary(sample));
      await t.tap(find.text('Graphs'));
      await t.pumpAndSettle();

      final charts = find.byType(RunCharts);
      final map = find.byType(RunMapCard);
      final cursor = find.descendant(
        of: charts,
        matching: find.byType(Scrubber),
      );
      expect(t.widget<RunCharts>(charts).cursor, isNull);
      expect(t.widget<RunMapCard>(map).cursor, isNull);
      await reveal(t, cursor);
      final rect = t.getRect(cursor);
      expect(rect.width, greaterThan(20));
      final touch = await t.startGesture(
        Offset(rect.left + rect.width * .25, rect.top + 15),
      );
      await t.pump();
      expect(t.widget<RunCharts>(charts).cursor, closeTo(.25, .015));
      await touch.moveTo(Offset(rect.left + rect.width * .8, rect.top + 15));
      await touch.up();
      await t.pumpAndSettle();

      final selected = t.widget<RunCharts>(charts).cursor!;
      expect(selected, closeTo(.8, .015));
      expect(
        t.widget<Scrubber>(cursor).describe(selected),
        contains('130 bpm'),
      );
      await reveal(t, map);
      expect(t.widget<RunMapCard>(map).cursor, selected);
      expect(t.widget<RunMapCard>(map).v.r.track, fixes);
      final db = await t.runAsync(() => LocalDb.instance);
      expect(await t.runAsync(() => db!.query('sessions')), isEmpty);
      expect(t.takeException(), isNull);
    });
  }
}
