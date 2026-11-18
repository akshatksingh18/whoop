// Real cached-history readers: rolling state and per-day inputs have different bounds.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/derivation_engine.dart';
import 'package:whoop_companion/data/db.dart';
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('baseline-window-bounds'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  for (final key in ['rhr', 'ln_rmssd_v2']) {
    test(
      'COV-48 $key keeps the newest 28 eligible prior days and excludes self/future values',
      () async {
        final target = DateTime.utc(2021, 4, 6);
        String label(int offset) => DateTime.utc(
          target.year,
          target.month,
          target.day + offset,
        ).toIso8601String().substring(0, 10);
        double value(int i) => key == 'rhr' ? 60.0 + i : 4.0 + i / 100;
        Future<void> seed(String day, double v) => LocalDb.putDayResult(
          dayId: day,
          algoVersion: kAlgoVersion,
          payloadJson: jsonEncode({
            'date': day,
            'device_family': 'gen4',
            'scalars': {key: v},
          }),
          windowJson: '{}',
          finalized: true,
          source: 'band',
          series: {key: v},
        );
        await seed(
          label(-61),
          value(90),
        ); // Outside target day, exactly 60 days before the preceding day.
        for (var i = 1; i <= 29; i++) {
          await seed(label(i - 30), value(i));
        }
        await seed(label(0), value(100));
        await seed(label(1), value(110));
        final db = await LocalDb.instance;
        final before = await db.query('metric_series', orderBy: 'date,key');
        final bundles = await db.query('day_result', orderBy: 'day_id');
        final windows = await debugSweepBaselineWindows(key, [
          label(0),
          label(-1),
          label(-2),
        ]);
        expect(windows, [
          [for (var i = 2; i <= 29; i++) value(i)],
          [for (var i = 1; i <= 28; i++) value(i)],
          [value(90), for (var i = 1; i <= 27; i++) value(i)],
        ]);
        // The rolling artifact describes the latest stored state; the sweep
        // above deliberately excludes a target's own and later observations.
        expect(await debugBaselineWindow(key), [
          for (var i = 4; i <= 29; i++) value(i),
          value(100),
          value(110),
        ]);
        expect(await debugSweepBaselineWindows(key, [label(0)]), [
          windows.first,
        ]);
        expect(await db.query('metric_series', orderBy: 'date,key'), before);
        expect(await db.query('day_result', orderBy: 'day_id'), bundles);
      },
    );
  }
}
