// The metric pages opened by Trends use real repository/night-history readers.
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/recent_hrv_card.dart';
import 'package:whoop_companion/ui2/screens/metric_detail.dart';
import 'package:whoop_companion/ui2/screens/readiness_detail.dart';
import 'package:whoop_companion/ui2/ui2.dart' show Pressable;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

String _ago(int n) {
  final now = DateTime.parse(todayLabel());
  return dayLabelOf(DateTime(now.year, now.month, now.day - n));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('metric-nightly-reader-handoff');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  for (final scale in [1.0, 3.1]) {
    for (final historical in [false, true]) {
      testWidgets(
        'real HRV metric retains measured-only history/date=$historical at ${scale}x',
        (t) async {
          final app = AppState.forTesting()
            ..repo = LocalRepositoryImpl(getProfileMap: () => {});
          addTearDown(app.dispose);
          for (var i = 19; i >= 0; i--) {
            await LocalDb.putMetricSeriesValue(_ago(i), 'rmssd', 69.0 - i);
            await LocalDb.putMetricSeriesValue(
              _ago(i),
              'ln_rmssd_v2',
              math.log(69 - i),
            );
          }
          final db = await LocalDb.instance;
          final rows = await db.query('metric_series');
          final day = historical ? _ago(4) : null;
          await localizedPage(
            t,
            MetricDetail.at('hrv', day),
            app: app,
            scale: scale,
            push: true,
          );
          await reveal(t, find.byType(RecentHrvSection));
          for (
            var i = 0;
            i < 12 && find.byType(RecentHrvCard).evaluate().isEmpty;
            i++
          ) {
            await t.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)),
            );
            await t.pumpAndSettle();
          }
          final card = t.widget<RecentHrvCard>(find.byType(RecentHrvCard));
          expect(card.view.day, day ?? todayLabel());
          expect(card.view.last, closeTo(historical ? 65 : 69, .000001));
          expect(card.view.nights, hasLength(14));
          expect(
            card.view.nights.every(
              (n) => n.date.compareTo(day ?? todayLabel()) <= 0,
            ),
            true,
          );
          expect(
            t.widget<RecentHrvSection>(find.byType(RecentHrvSection)).day,
            day,
          );
          await t.tap(
            find
                .byWidgetPredicate(
                  (w) => w is Pressable && w.semanticLabel == 'Back',
                )
                .first,
          );
          await t.pumpAndSettle();
          expect(find.byType(MetricDetail), findsNothing);
          expect(await t.runAsync(() => db.query('metric_series')), rows);
          expect(await t.runAsync(() => db.query('day_result')), isEmpty);
          expect(t.takeException(), isNull);
        },
      );
    }
    testWidgets(
      'real empty Recovery metric keeps its existing nightly explanation at ${scale}x',
      (t) async {
        final app = AppState.forTesting()
          ..repo = LocalRepositoryImpl(getProfileMap: () => {});
        addTearDown(app.dispose);
        await localizedPage(
          t,
          const MetricDetail('readiness'),
          app: app,
          scale: scale,
          push: true,
        );
        await reveal(t, find.byType(ReadinessDetail));
        final detail = t.widget<ReadinessDetail>(find.byType(ReadinessDetail));
        expect(detail.embedded, true);
        final text = (await readPage(t)).join(' ');
        expect(text, contains('Recovery'));
        expect(text, isNot(contains('NaN')));
        expect(
          text,
          anyOf(contains('No '), contains('Not '), contains('not ')),
        );
        await t.tap(
          find
              .byWidgetPredicate(
                (w) => w is Pressable && w.semanticLabel == 'Back',
              )
              .first,
        );
        await t.pumpAndSettle();
        expect(find.byType(MetricDetail), findsNothing);
        final db = await LocalDb.instance;
        expect(await t.runAsync(() => db.query('metric_series')), isEmpty);
        expect(await t.runAsync(() => db.query('day_result')), isEmpty);
        expect(t.takeException(), isNull);
      },
    );
  }
}
