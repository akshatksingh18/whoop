import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/ui2/activity/catalogue.dart';
import 'package:whoop_companion/ui2/activity/summary.dart';
import 'package:whoop_companion/ui2/profile/gallery.dart';
import 'package:whoop_companion/ui2/profile/profile.dart' show SetRow;
import 'package:whoop_companion/ui2/ui2.dart' show NavBar;

import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('gallery-unpriced-workout');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  testWidgets('general workout preview preserves absent MET and calories', (
    tester,
  ) async {
    await localizedPage(tester, const GalleryScreen());

    Finder row(String title) => find.byWidgetPredicate(
      (widget) => widget is SetRow && widget.title == title,
    );

    final workout = row('General workout');
    await reveal(tester, workout);
    final descriptor = activityByName('General workout')!;
    expect(descriptor.met, isNull);
    await tester.tap(workout);
    await tester.pumpAndSettle();
    expect(find.text('These numbers are invented'), findsOneWidget);
    final header = tester.widget<NavBar>(find.byType(NavBar));
    expect(header.sub, archLabel(archOf(descriptor)).toUpperCase());
    expect(find.textContaining('preview-only stand-in'), findsOneWidget);

    final summary = row('Summary');
    await reveal(tester, summary);
    await tester.tap(summary);
    await tester.pumpAndSettle();
    final page = find.byType(ActivitySummary);
    final result = tester.widget<ActivitySummary>(page).result;
    expect(result.activity, same(descriptor));
    expect(result.calories, isNull);
    expect(tester.takeException(), isNull);
    Navigator.of(tester.element(page)).pop();
    await tester.pumpAndSettle();
    expect(summary, findsOneWidget);

    final database = (await tester.runAsync(() => LocalDb.instance))!;
    expect(await tester.runAsync(() => database.query('sessions')), isEmpty);
    expect(
      await tester.runAsync(() => database.query('decoded_onehz')),
      isEmpty,
    );
  });
}
