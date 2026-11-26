// Real AppState -> shared scheduler -> SQLite queue,using the existing host read.
// No worker or physical background wake runs in this focused host contract.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/derivation_engine.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/state/app_state.dart';
import '../support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('app-background-queue-handoff'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  for (final resume in [false, true]) {
    testWidgets(
      'iOS background keeps the exact queued intent through ${resume ? 'foreground release' : 'disposal'}',
      (t) async {
        final app = AppState.forTesting(isIOS: true);
        var disposed = false;
        try {
          await LocalDb.putMetricSeriesValue('2021-04-06', 'steps', 1234);
          final db = await LocalDb.instance;
          final observations = await db.query('metric_series');
          await t.runAsync(app.refreshForeground);
          final queued = (await t.runAsync(() => LocalDb.computeJobs()))!;
          expect(queued, hasLength(1));
          expect(queued.single['state'], 'queued');
          expect(app.derivePending, true);
          expect(app.deriving, false);
          final generation = DeriveStop.generation;
          await app.pauseForBackground();
          await app.pauseForBackground();
          await t.pump(const Duration(seconds: 20));
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          expect(
            DeriveStop.generation,
            generation,
            reason: 'An idle real engine has no detached calculation to cancel',
          );
          expect(app.deriving, false);
          expect(await t.runAsync(() => LocalDb.computeJobs()), queued);
          if (resume) {
            await t.runAsync(app.openSession);
            expect(app.derivePending, true);
            expect(app.deriving, false);
            expect(await t.runAsync(() => LocalDb.computeJobs()), queued);
            // Cancel the newly armed settle timer before any worker can start.
          }
          app.dispose();
          disposed = true;
          await t.pump(const Duration(minutes: 1));
          expect(await t.runAsync(() => LocalDb.computeJobs()), queued);
          expect(
            await t.runAsync(() => db.query('metric_series')),
            observations,
          );
          expect(await t.runAsync(() => db.query('day_result')), isEmpty);
          expect(await t.runAsync(() => db.query('decoded_onehz')), isEmpty);
          expect(t.takeException(), isNull);
        } finally {
          if (!disposed) app.dispose();
          await t.pumpWidget(const SizedBox());
          await t.pumpAndSettle();
        }
      },
    );
  }
}
