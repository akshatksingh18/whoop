// Real accepted correction -> coordinator read -> stop generation -> retry.
// Thin daytime input cannot certify or manufacture a replacement night.
import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/derivation_engine.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/data/models.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('sleep-correction-expiry-retry'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  const day = '2021-04-06';
  for (final action in ['manual', 'confirmed', 'rejected', 'clear']) {
    test(
      '$action survives first-read expiry and releases the actual shared retry',
      () async {
        final start = localDayStartSec(day)!;
        await LocalDb.putDayResult(
          dayId: day,
          algoVersion: kAlgoVersion - 1,
          payloadJson: jsonEncode({
            'sleep_source': 'manual',
            'sleep': {
              'window': {
                'value': {
                  'onset_ms': (start - 3600) * 1000,
                  'offset_ms': (start + 7 * 3600) * 1000,
                },
              },
              'accounting': {
                'value': {'tst_sec': 7 * 3600},
              },
            },
            'scalars': {'rhr': 52, 'rmssd': 44, 'readiness': 72},
          }),
          windowJson: '{}',
          finalized: true,
          rhr: 52,
          rmssd: 44,
          readiness: 72,
          series: {'rhr': 52, 'rmssd': 44, 'readiness': 72},
        );
        await LocalDb.putSleepOverride(
          dayId: day,
          onsetTs: start - 3600,
          offsetTs: start + 7 * 3600,
          source: 'manual',
        );
        await LocalDb.setFrozenHeadline(
          day,
          72,
          explanation: {'authored': 'retained pin'},
        );
        final before = (await LocalDb.dayResult(day))!;
        final ts = start + 12 * 3600;
        await LocalDb.insertRecord(
          RawRecord(
            counter: 1,
            packetType: 47,
            hex: 'authored-expiry-retry',
            recTs: ts,
            capturedAt: ts * 1000,
          ),
          Sample(tsEpoch: ts, counter: 1, hr: 60, ax: 0, ay: 0, az: 1),
        );
        final db = await LocalDb.instance;
        final raw = await db.query('decoded_onehz');
        final app = AppState.forTesting();
        final repo = LocalRepositoryImpl(getProfileMap: () => null);
        app.repo = repo;
        var fired = false, wasRunning = false;
        var passes = 0;
        final retryDone = Completer<void>();
        app.addListener(() {
          if (app.reanalyzing && !wasRunning) passes++;
          if (!app.reanalyzing &&
              wasRunning &&
              passes == 2 &&
              !retryDone.isCompleted) {
            retryDone.complete();
          }
          wasRunning = app.reanalyzing;
          if (app.reanalyzing && !fired) {
            fired = true;
            // Delivery after run() captures its generation but before its first
            // async read returns models actual expiration,not a failed fake run.
            scheduleMicrotask(
              () => DeriveStop.request('authored sleep-edit expiry'),
            );
          }
        });
        Future<void> command() => switch (action) {
          'manual' => app.setSleepOverride(
            day,
            DateTime.fromMillisecondsSinceEpoch((start - 1800) * 1000),
            DateTime.fromMillisecondsSinceEpoch((start + 6 * 3600) * 1000),
          ),
          'confirmed' => app.confirmSleep(day),
          'rejected' => app.rejectSleep(day),
          _ => app.clearSleepOverride(day),
        };
        try {
          await command();
          expect(fired, true);
          expect(app.reanalyzing, false);
          expect(
            app.logLines.join('\n'),
            contains('sleep-override re-derive deferred:'),
          );
          final correction = (await LocalDb.sleepCorrection(day))!;
          expect(correction['action'], action);
          final recovery = correction['recovery'] as List;
          expect(
            recovery.any(
              (g) => (g['day_results'] as List).any(
                (r) => r['payload_json'] == before['payload_json'],
              ),
            ),
            true,
          );
          expect(await db.query('decoded_onehz'), raw);
          expect((await repo.getDaySleep(day))['has_sleep'], false);
          expect((await repo.getDayHrv(day))['rmssd'], isNull);
          expect(await LocalDb.frozenHeadline(), isNull);
          // Confirm reads the saved proposal;after an explicit correction it is
          // intentionally unavailable. Resume the accepted pending edit instead.
          await app.openSession();
          await retryDone.future.timeout(const Duration(seconds: 20));
          expect(passes, 2);
          expect(app.reanalyzing, false);
          expect((await LocalDb.sleepCorrection(day))!['action'], action);
          expect(await db.query('decoded_onehz'), raw);
          expect((await repo.getDaySleep(day))['has_sleep'], false);
          expect((await repo.getDayHrv(day))['rmssd'], isNull);
        } finally {
          app.dispose();
          await app.engine.disconnect();
        }
      },
    );
  }
}
