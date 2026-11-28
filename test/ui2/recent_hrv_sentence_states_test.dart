// The real measured-night reader supplies the card's sparse/mixed-night states.
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/recent_hrv_card.dart';
import 'package:whoop_companion/ui2/screens/food_diary.dart' show shiftDay;
import 'screens/food_calendar_recovery_test.dart' show flush;
import '../support/audit_visual.dart' show loadAuditFonts;
import '../support/coverage_store.dart';
import '../support/localized_coverage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('recent-hrv-sentence-states');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  for (final scale in [1.0, 3.1]) {
    for (final scenario in [
      'today-unknown',
      'historical-unknown',
      'thin',
      'opposite',
      'one-night',
    ]) {
      testWidgets(
        'measured HRV $scenario retains its honest sentence and history at ${scale}x',
        (t) async {
          final today = todayLabel();
          final at = scenario == 'today-unknown' ? today : '2021-04-05';
          if (scenario.endsWith('-unknown')) {
            for (var i = 1; i <= 3; i++) {
              await MetricSeriesStore.putValue(
                shiftDay(at, -i),
                'ln_rmssd_v2',
                math.log(50 + i),
              );
            }
          } else if (scenario == 'thin') {
            await MetricSeriesStore.putValue(
              '2021-04-04',
              'ln_rmssd_v2',
              math.log(55),
            );
            await MetricSeriesStore.putValue(at, 'ln_rmssd_v2', math.log(60));
          } else {
            for (var i = 0; i < 35; i++) {
              final value = i >= 29
                  ? (scenario == 'opposite' ? 20.0 : 52.0)
                  : 50.0 + i % 5;
              await MetricSeriesStore.putValue(
                dayLabelOf(DateTime(2021, 3, i + 1)),
                'ln_rmssd_v2',
                math.log(value),
              );
            }
            await MetricSeriesStore.putValue(at, 'ln_rmssd_v2', math.log(120));
          }
          final view = (await loadRecentHrv(at))!;
          final db = await LocalDb.instance;
          final series = await db.query('metric_series', orderBy: 'date,key');
          final app = AppState.forTesting();
          addTearDown(app.dispose);
          // Recovery already displays the night;HRV detail uses the complete sentence.
          final nightShown = scenario == 'opposite';
          await localizedPage(
            t,
            Scaffold(
              body: SingleChildScrollView(
                child: RecentHrvCard(view, nightShown: nightShown),
              ),
            ),
            app: app,
            scale: scale,
          );
          await flush(t);
          final text = (await readPage(t)).join(' ');
          if (scenario == 'today-unknown') {
            expect(view.last, isNull);
            expect(text, contains('No HRV measured last night.'));
          } else if (scenario == 'historical-unknown') {
            expect(view.last, isNull);
            expect(text, contains('No HRV measured for '));
            expect(text, isNot(contains('No HRV measured last night.')));
          } else if (scenario == 'thin') {
            expect(view.last, closeTo(60, .000001));
            expect(view.usual, isNull);
            expect(
              text,
              contains('Your usual range appears after 14 measured nights.'),
            );
          } else if (scenario == 'opposite') {
            expect(view.last, greaterThan(view.usual!.hi));
            expect(view.before, lessThan(view.usual!.lo));
            expect(
              text,
              contains(
                'The nights before averaged 20 ms, below your usual range.',
              ),
            );
            expect(text, isNot(contains('several nights, not one')));
          } else {
            expect(view.last, greaterThan(view.usual!.hi));
            expect(
              view.before,
              inInclusiveRange(view.usual!.lo, view.usual!.hi),
            );
            expect(text, contains('one night, not a trend yet.'));
          }
          expect(
            text,
            contains('Same nightly HRV and 28-night window as Recovery.'),
          );
          expect(view.day, at);
          expect(await db.query('metric_series', orderBy: 'date,key'), series);
          expect(t.takeException(), isNull);
        },
      );
    }
  }
}
