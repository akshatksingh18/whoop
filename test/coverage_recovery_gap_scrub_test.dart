// The actual Recovery history scrubber reads the selected day's stored reason.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/derivation_engine.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/ui2/grammar.dart';
import 'package:whoop_companion/ui2/screens/readiness_detail.dart';
import 'support/audit_visual.dart';
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await coverageStore('recovery-gap-scrub');
    await loadAuditFonts();
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  for (final shape in ['missing', 'diagnostic', 'malformed', 'read refusal']) {
    testWidgets('COV-60 Recovery gap scrub retains $shape provenance', (
      t,
    ) async {
      final now = DateTime.parse(todayLabel());
      final day = dayLabelOf(DateTime(now.year, now.month, now.day - 1));
      if (shape != 'missing') {
        await t.runAsync(
          () => LocalDb.putDayResult(
            dayId: day,
            algoVersion: kAlgoVersion,
            payloadJson: shape == 'malformed'
                ? '{"readiness_absent_diag":'
                : jsonEncode({
                    'readiness_absent_diag': {
                      'hrv': {'value': true, 'baseline_n': 3},
                      'rhr': {'value': true, 'baseline_n': 3},
                    },
                  }),
            windowJson: '{}',
          ),
        );
      }
      final before = await t.runAsync(() => LocalDb.dayResult(day));
      final db = await t.runAsync(() => LocalDb.instance);
      var held = false;
      try {
        if (shape == 'read refusal') {
          await t.runAsync(
            () => db!.execute(
              'ALTER TABLE day_result RENAME TO authored_held_day_result',
            ),
          );
          held = true;
        }
        await localizedPage(
          t,
          const ReadinessDetail(data: ReadinessData(series: [65, null, 70])),
        );
        final scrubber = find.byWidgetPredicate(
          (w) => w is Scrubber && w.label == 'Readiness history',
        );
        await reveal(t, scrubber);
        final rect = t.getRect(scrubber);
        await t.tapAt(rect.center);
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        final expected = switch (shape) {
          'missing' => 'no data that day',
          'diagnostic' => 'baseline',
          _ => 'not scored',
        };
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is RichText &&
                w.text.toPlainText().contains('no score, ') &&
                w.text.toPlainText().contains(expected),
          ),
          findsOneWidget,
        );
        expect(t.widget<Scrubber>(scrubber).value, .5);
        // The same slot can be revisited without changing its evidence or
        // manufacturing a score while its diagnostic is cached.
        await t.tapAt(rect.centerRight - const Offset(2, 0));
        await t.pumpAndSettle();
        await t.tapAt(rect.center);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        await t.pumpAndSettle();
      } finally {
        if (held) {
          await t.runAsync(
            () => db!.execute(
              'ALTER TABLE authored_held_day_result RENAME TO day_result',
            ),
          );
        }
      }
      expect(await t.runAsync(() => LocalDb.dayResult(day)), equals(before));
    });
  }
}
