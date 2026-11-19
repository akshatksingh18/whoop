// Approved Body A: real selected-row semantics over authored daily weights.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/body_log.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/progress_review.dart';
import 'package:whoop_companion/state/units_controller.dart';
import 'package:whoop_companion/ui2/screens/progress_screen.dart';
import 'package:whoop_companion/ui2/screens/progress_routes.dart';
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

String relativeDay(int offset) {
  final today = DateTime.parse(todayLabel());
  return dayLabelOf(DateTime(today.year, today.month, today.day + offset));
}

BodyWeightRow reading(int offset, double kg) => (
  date: relativeDay(offset),
  kg: kg,
  atTs: localDayStartSec(relativeDay(offset))!,
  unit: 'kg',
  entered: null,
  source: 'synthetic',
  originId: null,
  historyOnly: false,
);

ProgressData data(
  List<BodyWeightRow> weights,
  String? baseline, {
  BodyWeightReading? latest,
}) => ProgressData(
  weights: weights,
  measures: [],
  photos: [],
  lifts: [],
  food: [],
  steps: [],
  sleepMin: [],
  recovery: [],
  sessions: [],
  baseline: baseline,
  heightCm: null,
  latestWeightReading: latest,
);

String selected(WidgetTester t, String heading) => t
    .widget<Semantics>(
      find.byWidgetPredicate(
        (w) =>
            w is Semantics &&
            (w.properties.label
                    ?.replaceFirst(' · selected', '')
                    .startsWith('$heading, selected period:') ??
                false),
      ),
    )
    .properties
    .label!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('body-range-average');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  List<BodyWeightRow> sparse() => [
    reading(-35, 80),
    reading(-22, 90),
    reading(-21, 70),
    reading(-5, 72),
    reading(0, 74),
    reading(1, 200),
  ];
  for (final range in [ProgressRange.all, ProgressRange.sinceStart]) {
    for (final baseline in [false, true]) {
      for (final pounds in [false, true]) {
        testWidgets(
          'COV-48 Body ${range.name} ${baseline ? 'baseline' : 'earliest'} ${pounds ? 'lb' : 'kg'} keeps range, gaps and future exclusion',
          (t) async {
            final weights = sparse();
            final input = List.of(weights);
            final d = data(weights, baseline ? relativeDay(-21) : null);
            final units = UnitsController.withUnits(
              weight: pounds ? 'lb' : 'kg',
            );
            addTearDown(units.dispose);
            await localizedPage(
              t,
              progressDetailPage(ProgressDest.weight, initial: d, range: range),
              units: units,
            );
            final narrower = range == ProgressRange.sinceStart && baseline;
            final heading = range == ProgressRange.all
                ? 'Average of all readings'
                : 'Average since the start';
            final row = selected(t, heading);
            final number = pounds
                ? (narrower ? '158.7 lb' : '170.2 lb')
                : (narrower ? '72 kg' : '77.2 kg');
            expect(row, contains('selected period: $number.'));
            expect(row, contains(narrower ? '3 readings' : '5 readings'));
            expect(row, contains('First vs last week:'));
            expect(row, contains('2 readings'));
            expect(
              row,
              contains(
                pounds
                    ? (narrower ? '+6.6 lb' : '−15.4 lb')
                    : (narrower ? '+3 kg' : '−7 kg'),
              ),
            );
            expect(row, isNot(contains('200')));
            final week = t
                .widget<Semantics>(
                  find.byWidgetPredicate(
                    (w) =>
                        w is Semantics &&
                        (w.properties.label?.startsWith('7-day average:') ??
                            false),
                  ),
                )
                .properties
                .label!;
            expect(week, contains(pounds ? '160.9 lb' : '73 kg'));
            expect(week, contains('2 readings'));
            expect(d.weights, input);
            expect(
              await t.runAsync(
                () async =>
                    (await LocalDb.instance).query('body_weight_reading'),
              ),
              isEmpty,
            );
          },
        );
      }
    }
  }
  for (final (range, heading, value, count) in [
    (ProgressRange.week, '7-day average', '73 kg', 2),
    (ProgressRange.month, '30-day average', '76.5 kg', 4),
    (ProgressRange.threeMonths, '3-month average', '77.2 kg', 5),
  ]) {
    testWidgets(
      'COV-48 approved Body A retains ${range.name} selected rolling average',
      (t) async {
        await localizedPage(
          t,
          progressDetailPage(
            ProgressDest.weight,
            initial: data(sparse(), relativeDay(-21)),
            range: range,
          ),
        );
        final row = selected(t, heading);
        expect(row, contains('selected period: $value.'));
        expect(row, contains('$count readings'));
        expect(row, isNot(contains('First vs last week:')));
      },
    );
  }
  for (final range in [ProgressRange.all, ProgressRange.sinceStart]) {
    testWidgets(
      'COV-48 Body ${range.name} keeps the approved single-day explanation without duplicate averages',
      (t) async {
        final weight = reading(0, 74);
        await localizedPage(
          t,
          progressDetailPage(
            ProgressDest.weight,
            initial: data(
              [weight],
              null,
              latest: (
                id: 'authored-single-reading',
                date: weight.date,
                kg: weight.kg,
                atTs: weight.atTs,
                unit: 'kg',
                entered: 74,
                source: 'synthetic',
                historyOnly: false,
              ),
            ),
            range: range,
          ),
        );
        expect(find.textContaining('One day of weight data.'), findsOneWidget);
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is Semantics &&
                (w.properties.label?.contains('selected period:') ?? false),
          ),
          findsNothing,
        );
        expect(find.text('7-DAY AVERAGE'), findsNothing);
        expect(
          await t.runAsync(
            () async => (await LocalDb.instance).query('body_weight_reading'),
          ),
          isEmpty,
        );
      },
    );
    testWidgets(
      'COV-48 Body ${range.name} short history reports its actual mean without a fabricated comparison',
      (t) async {
        await localizedPage(
          t,
          progressDetailPage(
            ProgressDest.weight,
            initial: data([reading(-1, 70), reading(0, 72)], relativeDay(-1)),
            range: range,
          ),
        );
        final row = selected(
          t,
          range == ProgressRange.all
              ? 'Average of all readings'
              : 'Average since the start',
        );
        expect(row, contains('selected period: 71 kg.'));
        expect(row, contains('2 readings'));
        expect(row, contains('no earlier stretch to compare'));
        expect(row, isNot(contains('First vs last week:')));
      },
    );
  }
}
