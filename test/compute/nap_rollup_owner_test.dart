// Two real coordinators compete for the stored-day rollup; run on Linux CI.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/derivation_engine.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/state/app_state.dart';

import '../support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('nap-rollup-owner'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  test(
    'a competing read-side rollup leaves durable nap corrections queued for retry',
    () async {
      final now = DateTime.now();
      final days = [
        for (final offset in [2, 1])
          todayLabel(DateTime(now.year, now.month, now.day - offset)),
      ];
      for (final day in days) {
        await LocalDb.putDayResult(
          dayId: day,
          algoVersion: kAlgoVersion,
          payloadJson:
              '{"source":"whoop_export","imported":true,"scalars":{"rhr":55}}',
          windowJson: '{}',
          series: {'rhr': 55},
        );
      }
      final db = await LocalDb.instance;
      final before = await db.query('day_result', orderBy: 'day_id');
      final app = AppState.forTesting();
      Future<void>? contender;
      final waiting = Completer<void>();
      void observe() {
        if (app.napRebuilding &&
            app.reanalyzing &&
            contender == null &&
            !app.insightsRebuilding) {
          // The onChanged boundary publishes before taking the engine lock.
          // A simultaneous rebuild request can win that lock in this gap.
          contender = app.rebuildInsights();
        }
        if (app.insightsRebuilding &&
            app.napRebuildMessage?.contains(
                  'Waiting for the current calculation',
                ) ==
                true &&
            !waiting.isCompleted) {
          waiting.complete();
        }
      }

      app.addListener(observe);
      Future<void> add(String day) {
        final noon = localDayStartSec(day)! + 12 * 3600;
        return LocalDb.putNapEdit(
          dayId: day,
          startTs: noon,
          endTs: noon + 20 * 60,
          source: 'manual',
        );
      }

      Future<void>? rebuild;
      try {
        await add(days.first);
        rebuild = app.reanalyzeForNapEdit(days.first);
        await waiting.future.timeout(const Duration(seconds: 6));
        expect(await LocalDb.pendingNapDays(), contains(days.first));
        await add(days.last);
        expect(app.reanalyzeForNapEdit(days.last), same(rebuild));
        final accepted = [for (final day in days) await LocalDb.napEdits(day)];
        await contender;
        await rebuild;
        expect(app.napRebuilding, isFalse);
        expect(app.reanalyzing, isFalse);
        expect(app.napRebuildMessage, isNull);
        expect(await LocalDb.pendingNapDays(), isEmpty);
        expect([for (final day in days) await LocalDb.napEdits(day)], accepted);
        expect(await db.query('day_result', orderBy: 'day_id'), before);
      } finally {
        app.removeListener(observe);
        try {
          await contender;
          await rebuild;
        } finally {
          app.dispose();
          await app.engine.disconnect();
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
