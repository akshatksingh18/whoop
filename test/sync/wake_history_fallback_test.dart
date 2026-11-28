// Read retained window/payload history through the actual SQLite planner seam.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/sync/high_freq_wake_window.dart';
import '../support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('wake-history-fallback'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  Future<void> seed({bool primary = false, String? invalid}) async {
    for (var i = 0; i < 3; i++) {
      final wake = DateTime(2021, 4, 4 + i, 7, 30);
      final offset = wake.millisecondsSinceEpoch;
      final date = '2021-04-0${4 + i}';
      expect(
        await DayResultStore.put(
          dayId: date,
          algoVersion: 90,
          payloadJson: invalid == 'malformed' && i == 2
              ? '{authored-invalid-json'
              : jsonEncode({
                  'sleep': {
                    'window': {
                      'value': {
                        'offset_ms': invalid == 'nonpositive' && i == 2
                            ? 0
                            : offset,
                      },
                    },
                  },
                }),
          windowJson: primary
              ? jsonEncode({
                  'value': {'offset_ms': offset},
                })
              : '{}',
          source: 'band',
        ),
        true,
      );
    }
  }

  for (final primary in [false, true]) {
    for (final boundary in ['lease-start', 'wake', 'after-wake']) {
      test(
        '${primary ? 'primary' : 'legacy payload'} wake history respects $boundary without rewriting history',
        () async {
          await seed(primary: primary);
          final db = await LocalDb.instance;
          final history = await db.query('day_result', orderBy: 'day_id');
          final series = await db.query('metric_series', orderBy: 'date,key');
          final now = switch (boundary) {
            'lease-start' => DateTime(2021, 4, 7, 6),
            'wake' => DateTime(2021, 4, 7, 7, 30),
            _ => DateTime(2021, 4, 7, 7, 30, 1),
          };
          for (var reopening = 0; reopening < 2; reopening++) {
            final plan = await HighFreqWakeWindow.planNow(now);
            expect(plan.source, 'habitual_wake');
            expect(plan.sampleCount, 3);
            expect(plan.shouldEnable, boundary == 'lease-start');
            expect(
              plan.targetWake,
              DateTime(2021, 4, boundary == 'after-wake' ? 8 : 7, 7, 30),
            );
            expect(await db.query('day_result', orderBy: 'day_id'), history);
            expect(
              await db.query('metric_series', orderBy: 'date,key'),
              series,
            );
          }
        },
      );
    }
  }
  for (final invalid in ['malformed', 'nonpositive']) {
    test(
      'one $invalid stored wake cannot manufacture the minimum history',
      () async {
        await seed(invalid: invalid);
        final db = await LocalDb.instance;
        final history = await db.query('day_result', orderBy: 'day_id');
        final plan = await HighFreqWakeWindow.planNow(DateTime(2021, 4, 7, 6));
        expect(plan.source, 'insufficient_sleep_history');
        expect(plan.shouldEnable, false);
        expect(plan.targetWake, isNull);
        expect(plan.sampleCount, 0);
        expect(await db.query('day_result', orderBy: 'day_id'), history);
      },
    );
  }
  test(
    'a refused history read propagates and leaves the original rows available for retry',
    () async {
      await seed();
      final db = await LocalDb.instance;
      final history = await db.query('day_result', orderBy: 'day_id');
      await db.execute(
        'ALTER TABLE day_result RENAME TO authored_held_day_result',
      );
      try {
        await expectLater(
          HighFreqWakeWindow.planNow(DateTime(2021, 4, 7, 6)),
          throwsA(isA<Exception>()),
        );
      } finally {
        await db.execute(
          'ALTER TABLE authored_held_day_result RENAME TO day_result',
        );
      }
      expect(
        (await HighFreqWakeWindow.planNow(
          DateTime(2021, 4, 7, 6),
        )).shouldEnable,
        true,
      );
      expect(await db.query('day_result', orderBy: 'day_id'), history);
    },
  );
}
