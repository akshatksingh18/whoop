// Tiny authored input through the real AppState scheduler and SQLite writes.
// Thin input must stay unknown; a refused write must retain a truthful retry.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/derivation_engine.dart'
    show kAlgoVersion;
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/data/models.dart';
import 'package:whoop_companion/notify/notification_center.dart';
import 'package:whoop_companion/state/app_state.dart';

import 'support/coverage_store.dart';

class _App extends AppState {
  _App() : super.forTesting();
  @override
  Future<void> syncNow() async {} // There is no radio in this scheduler check.
}

Future<void> _drain(_App app) async {
  final deadline = DateTime.now().add(const Duration(seconds: 25));
  while ((app.deriving || app.derivePending) &&
      DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  expect(app.deriving || app.derivePending, false);
  // onDayDone's asynchronous freshness publication is not awaited by the runner.
  await Future<void>.delayed(const Duration(milliseconds: 100));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('today-scheduler-publication'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  for (final refusedTable in [null, 'day_result', 'metric_series']) {
    test(
      'today publication with ${refusedTable ?? 'accepted'} writes retains history and retry',
      () async {
        final date = todayLabel();
        final older = todayLabel(
          DateTime.now().subtract(const Duration(days: 10)),
        );
        await LocalDb.putDayResult(
          dayId: older,
          algoVersion: kAlgoVersion,
          payloadJson: jsonEncode({
            'authored_recovery': 'keep the banked result',
          }),
          windowJson: '{}',
          readiness: 72,
          rmssd: 41,
          finalized: true,
        );
        final banked = await LocalDb.dayResult(older);
        final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        expect(
          dayLabelAtSec(ts),
          date,
          reason: 'this authored fixture requires a current local day input',
        );
        await LocalDb.upsertDevice(adapterId: 'gen4');
        await LocalDb.insertRecord(
          RawRecord(
            counter: 1,
            packetType: 47,
            hex: 'authored-today-scheduler',
            capturedAt: ts * 1000,
            recTs: ts,
          ),
          Sample(
            tsEpoch: ts,
            counter: 1,
            hr: 60,
            rrIntervalsMs: const [1000],
            ax: 0,
            ay: 0,
            az: 1,
          ),
        );
        final app = _App();
        app.repo = LocalRepositoryImpl(getProfileMap: () => app.user);
        final previous = NotificationCenter.instance.presentSink;
        NotificationCenter.instance.presentSink =
            (_, {bool allowPermissionPrompt = true}) async => false;
        final db = await LocalDb.instance;
        if (refusedTable != null) {
          await db.execute(
            "CREATE TRIGGER authored_today_write_refusal BEFORE INSERT ON $refusedTable "
            "BEGIN SELECT RAISE(ABORT,'authored today write refusal'); END",
          );
        }
        try {
          final revision = app.insightsRevision.value;
          final notice = await app.pullRefresh(
            timeout: const Duration(seconds: 30),
          );
          await _drain(app);
          expect(app.insightsRevision.value, greaterThan(revision));
          expect(notice, contains('Band not connected'));
          expect(await LocalDb.dayResult(older), banked);
          expect(await LocalDb.lastDecodedRecTs(), ts);
          if (refusedTable != null) {
            expect(
              notice,
              contains(
                'Some totals could not be calculated. Please try again.',
              ),
            );
            final failed = await LocalDb.dayResult(date);
            if (failed != null) {
              expect(failed['skipped'], 1);
              expect(failed['finalized'], 0);
              expect(failed['readiness'], isNull);
            }
            await db.execute('DROP TRIGGER authored_today_write_refusal');
            final retry = await app.pullRefresh(
              timeout: const Duration(seconds: 30),
            );
            await _drain(app);
            expect(retry, 'Band not connected');
          } else {
            expect(notice, 'Band not connected');
          }
          final current = (await LocalDb.dayResult(date))!;
          expect(current['skipped'], 0);
          expect(current['finalized'], 0);
          expect(current['rmssd'], isNull);
          expect(
            current['readiness'],
            isNull,
            reason: 'one heart-rate point is not a measured main night',
          );
          final freshness = await LocalDb.computeFreshness('today');
          expect(freshness, isNotNull);
          final state = jsonDecode(freshness!['payload_json'] as String) as Map;
          expect(
            state['recovery_day'],
            isNot(date),
            reason: 'today must not inherit a recovery score from one HR point',
          );
          expect(await LocalDb.dayResult(older), banked);
          expect(await LocalDb.lastDecodedRecTs(), ts);
        } finally {
          await db.execute(
            'DROP TRIGGER IF EXISTS authored_today_write_refusal',
          );
          app.dispose();
          await app.engine.disconnect();
          NotificationCenter.instance.presentSink = previous;
        }
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }
}
