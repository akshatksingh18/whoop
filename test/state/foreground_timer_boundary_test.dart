// Actual foreground timer -> refresh -> durable light intent;no analysis pass.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/state/app_state.dart';
import '../support/coverage_store.dart';

void main() {
  setUpAll(() => coverageStore('foreground-timer-boundary', fresh: true));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  for (final repeatStart in [false, true]) {
    testWidgets(
      'five-minute foreground timer repeatStart=$repeatStart fires once and disposal preserves queued work',
      (t) async {
        final db = await LocalDb.instance;
        await LocalDb.putSession({
          'id': 'authored-unrelated-timer',
          'start_ts': 1617714000,
          'type': 'running',
          'status': 'finished',
          'source': 'manual',
          'created_at': 1,
        });
        final before = await LocalDb.session('authored-unrelated-timer');
        final app = AppState.forTesting();
        var disposed = false;
        try {
          app.startForegroundRefresh();
          if (repeatStart) app.startForegroundRefresh();
          expect(app.insightsRevision.value, 0);
          await t.pump(
            AppState.foregroundRefreshEvery - const Duration(milliseconds: 1),
          );
          expect(app.insightsRevision.value, 0);
          expect(await t.runAsync(() => LocalDb.computeJobs()), isEmpty);
          await t.pump(const Duration(milliseconds: 1));
          for (var i = 0; i < 35; i++) {
            await t.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)),
            );
            await t.pump(const Duration(milliseconds: 1));
          }
          expect(t.takeException(), isNull);
          // The real refresh publishes exactly once.
          expect(app.insightsRevision.value, 1);
          final jobs = (await t.runAsync(() => LocalDb.computeJobs()))!;
          expect(jobs, hasLength(1));
          expect(jobs.single['type'], 'derive_light');
          expect(jobs.single['state'], 'queued');
          expect(await t.runAsync(() => db.query('day_result')), isEmpty);
          expect(await t.runAsync(() => db.query('decoded_onehz')), isEmpty);
          app.dispose();
          disposed = true;
          await t.pump(AppState.foregroundRefreshEvery);
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)),
          );
          expect(t.takeException(), isNull);
          expect(await t.runAsync(() => LocalDb.computeJobs()), jobs);
          expect(
            await t.runAsync(() => LocalDb.session('authored-unrelated-timer')),
            before,
          );
        } finally {
          if (!disposed) app.dispose();
          await t.pumpWidget(const SizedBox());
          await t.pumpAndSettle();
        }
      },
    );
  }
}
