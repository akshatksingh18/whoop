import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/derivation_engine.dart'
    show kAlgoVersion;
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/screens/sleep_detail.dart';

import 'nutrition_root_test.dart' show io;
import '../../support/audit_visual.dart' show loadAuditFonts;
import '../../support/coverage_store.dart';
import '../../support/localized_coverage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('sleep-nap-retry-handoff', fresh: true);
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  for (final scale in [1.0, 3.1]) {
    testWidgets(
      'Sleep retries a durable nap edit after SQLite refusal at ${scale}x',
      (t) async {
        const day = '2021-04-06';
        final app = AppState.forTesting()
          ..repo = LocalRepositoryImpl(getProfileMap: () => {});
        addTearDown(app.dispose);
        final db = await LocalDb.instance;
        await LocalDb.putDayResult(
          dayId: day,
          algoVersion: kAlgoVersion,
          payloadJson:
              '{"source":"whoop_export","imported":true,"scalars":{"rhr":55}}',
          windowJson: '{}',
          series: {'rhr': 55},
        );
        await SleepNapStore.putEdit(
          dayId: day,
          startTs: 1617714000,
          endTs: 1617715200,
          source: 'manual',
        );
        final dayRows = await db.query('day_result');
        final edits = await SleepNapStore.edits(day);
        final stamp = await MetricSeriesStore.baseline('nap_dirty:$day');
        expect(edits, hasLength(1));
        expect(stamp, isNotNull);

        // Refuse only clearing the pending stamp. One saved day keeps the rollup
        // under the input floor, so the test needs no full derivation.
        await db.execute(
          "CREATE TRIGGER authored_nap_cleanup_refusal BEFORE DELETE ON baselines "
          "WHEN OLD.key='nap_dirty:$day' BEGIN SELECT RAISE(ABORT,'authored refusal'); END",
        );
        addTearDown(
          () =>
              db.execute('DROP TRIGGER IF EXISTS authored_nap_cleanup_refusal'),
        );
        await t.runAsync(() async {
          await expectLater(
            app.reanalyzeForNapEdit(day),
            throwsA(isA<Exception>()),
          );
        });
        final page = SleepDetail(day: day);
        await localizedPage(t, page, app: app, scale: scale, settle: false);
        await io(t);
        final retry = find.text('Retry update');
        await reveal(t, retry);
        expect(find.text('Nap edit saved'), findsOneWidget);
        expect(
          find.textContaining('Sleep calculations could not update'),
          findsOneWidget,
        );
        final revision = app.insightsRevision.value;
        await t.tap(retry);
        await io(t);
        expect(app.insightsRevision.value, revision + 1);
        expect(app.napRebuilding, isFalse);
        expect(await MetricSeriesStore.baseline('nap_dirty:$day'), stamp);
        expect(await SleepNapStore.edits(day), edits);
        expect(retry, findsOneWidget);

        await db.execute('DROP TRIGGER authored_nap_cleanup_refusal');
        await t.tap(retry);
        await io(t);
        expect(app.napRebuilding, isFalse);
        expect(app.napRebuildMessage, isNull);
        expect(await SleepNapStore.pendingDays(), isEmpty);
        expect(find.text('Retry update'), findsNothing);
        expect(await SleepNapStore.edits(day), edits);
        expect(await db.query('day_result'), dayRows);
        expect(t.takeException(), isNull);
      },
    );
  }
}
