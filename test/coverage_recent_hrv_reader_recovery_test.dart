// The shipped HRV detail section reads measured-only nights, respects its
// displayed date and retains the last successful card when a reread refuses.
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/derivation_engine.dart'
    show kAlgoVersion;
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/recent_hrv_card.dart';
import 'coverage_body_history_actions_test.dart' show flush;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

String day(int index) => dayLabelOf(DateTime(2021, 4, index + 1));
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('recent-hrv-reader-recovery');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  Future<void> nights() async {
    for (var i = 0; i < 20; i++) {
      await LocalDb.putMetricSeriesValue(
        day(i),
        'ln_rmssd_v2',
        math.log(50 + i),
      );
    }
  }

  test(
    'no measured nights means no card, including an explicit prehistory date',
    () async {
      expect(await loadRecentHrv(null), isNull);
      await nights();
      expect(await loadRecentHrv('2021-03-31'), isNull);
    },
  );
  test(
    'the latest imported outlier cannot replace the newest measured night',
    () async {
      await nights();
      await LocalDb.putMetricSeriesValue(day(20), 'ln_rmssd_v2', math.log(200));
      await LocalDb.putDayResult(
        dayId: day(20),
        algoVersion: kAlgoVersion,
        payloadJson: jsonEncode({'source': 'whoop_export', 'imported': true}),
        windowJson: '{}',
        finalized: true,
      );
      final view = (await loadRecentHrv(null))!;
      expect(view.day, day(19));
      expect(view.nights, hasLength(14));
      expect(view.last, closeTo(69, .000001));
      expect(view.nights.any((n) => n.date == day(20)), false);
      expect(await LocalDb.metricSeries('ln_rmssd_v2'), hasLength(21));
    },
  );
  test(
    'a historical card contains only nights known by its requested day',
    () async {
      await nights();
      final view = (await loadRecentHrv(day(9)))!;
      expect(view.day, day(9));
      expect(view.nights, hasLength(10));
      expect(view.last, closeTo(59, .000001));
      expect(view.usual, isNull);
      expect(view.nights.every((n) => n.date.compareTo(day(9)) <= 0), true);
      expect(view.nights.last.date, day(9));
    },
  );
  testWidgets(
    'changing the viewed day and retrying a refused read keeps dated evidence',
    (t) async {
      await nights();
      final app = AppState.forTesting();
      final shown = ValueNotifier(day(19));
      addTearDown(app.dispose);
      addTearDown(shown.dispose);
      await localizedPage(
        t,
        Scaffold(
          body: SingleChildScrollView(
            child: ValueListenableBuilder(
              valueListenable: shown,
              builder: (_, value, _) => RecentHrvSection(day: value),
            ),
          ),
        ),
        app: app,
      );
      await flush(t);
      RecentHrvView view() =>
          t.widget<RecentHrvCard>(find.byType(RecentHrvCard)).view;
      expect(view().day, day(19));
      shown.value = day(10);
      await flush(t);
      expect(view().day, day(10));
      expect(view().last, closeTo(60, .000001));
      final db = await LocalDb.instance;
      await t.runAsync(
        () => db.execute(
          'ALTER TABLE metric_series RENAME TO authored_held_hrv_series',
        ),
      );
      try {
        shown.value = day(9);
        await flush(t);
        expect(view().day, day(10));
        expect(view().last, closeTo(60, .000001));
      } finally {
        await t.runAsync(
          () => db.execute(
            'ALTER TABLE authored_held_hrv_series RENAME TO metric_series',
          ),
        );
      }
      app.bumpInsights();
      await flush(t);
      expect(view().day, day(9));
      expect(view().last, closeTo(59, .000001));
      expect(
        await t.runAsync(() => LocalDb.metricSeries('ln_rmssd_v2')),
        hasLength(20),
      );
    },
  );
}
