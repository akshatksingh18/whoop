// Compare the chart's localized host and its standalone reading contract.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/derivation_engine.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/l10n/app_localizations.dart';
import 'package:whoop_companion/ui2/screens/month_grid.dart';
import 'package:whoop_companion/ui2/ui2.dart';

import '../../support/audit_visual.dart' show loadAuditFonts;
import '../../support/coverage_store.dart';
import '../../support/localized_coverage.dart';

void main() {
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('month-grid-stored-history');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  for (final localized in [false, true]) {
    testWidgets(
      'Month history discloses gaps and personal shading with localization: $localized',
      (t) async {
        final now = DateTime.now();
        final repository = LocalRepositoryImpl(getProfileMap: () => {});
        final data = (await t.runAsync(() async {
          for (var age = 2; age <= 15; age++) {
            final day = dayLabelOf(
              DateTime(now.year, now.month, now.day - age),
            );
            await LocalDb.putDayResult(
              dayId: day,
              algoVersion: kAlgoVersion,
              payloadJson: '{}',
              windowJson: '{}',
              series: {'strain': (age - 2).toDouble()},
            );
          }
          final db = await LocalDb.instance;
          return (
            rows: await loadGridRows(repository),
            before: await db.query('metric_series', orderBy: 'date,key'),
          );
        }))!;
        final strain = data.rows.singleWhere(
          (row) => row.spec.chartKey == 'strain',
        );
        expect(strain.shaded, isTrue);
        expect(strain.have, 14);
        expect(strain.cells, hasLength(30));
        expect(strain.cells.where((value) => value == null), hasLength(16));
        expect(strain.cells, containsAll([0.0, 1.0, null]));

        t.view.physicalSize = const Size(430, 1800);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final grid = MonthGrid(data.rows);
        if (localized) {
          await localizedPage(
            t,
            Scaffold(body: SingleChildScrollView(child: grid)),
            scale: 3.1,
          );
        } else {
          await t.pumpWidget(
            MaterialApp(
              theme: buildTheme(Brightness.light),
              home: Scaffold(body: SingleChildScrollView(child: grid)),
            ),
          );
          await t.pumpAndSettle();
        }
        expect(
          AppLocalizations.of(t.element(find.byType(MonthGrid))) != null,
          localized,
        );
        expect(find.text('14 of 30 days'), findsOneWidget);
        expect(find.text('29 days ago'), findsOneWidget);
        expect(find.text('Today'), findsOneWidget);
        final semantics = find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.properties.label ==
                  'Strain: 14 of 30 days have a value. Shaded against your own range.',
        );
        expect(semantics, findsOneWidget);
        expect(find.text('Time asleep is not shaded yet'), findsOneWidget);
        expect(
          find.textContaining('an outlined cell is a day with no value'),
          findsOneWidget,
        );
        expect(t.takeException(), isNull);
        expect(
          await t.runAsync(
            () async => (await LocalDb.instance).query(
              'metric_series',
              orderBy: 'date,key',
            ),
          ),
          data.before,
        );
      },
    );
  }
}
