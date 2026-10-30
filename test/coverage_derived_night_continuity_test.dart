// Complete synthetic night orchestration. Run on Linux CI, not in laptop probes.
// These check persistence and provenance; authored signals do not validate sleep accuracy.
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/derivation_engine.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/compute/sleep_profile_policy.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/models.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('derived-night-continuity'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  const profile = Profile(ageYears: 30, sex: 'f', weightKg: 70, heightCm: 170);
  const day = '2021-04-06';
  Future<int> seedNight() async {
    final start = localDayStartSec(day)! + 3600;
    const seconds = 3 * 3600;
    final raws = <RawRecord>[], samples = <Sample?>[];
    for (var i = 0; i < seconds; i++) {
      final asleep = i >= 900 && i < seconds - 900;
      final phase = i / 4 * 2 * math.pi;
      raws.add(
        RawRecord(
          counter: i + 1,
          packetType: 47,
          hex: 'authored-cov47-night-$i',
          capturedAt: (start + i) * 1000,
          recTs: start + i,
        ),
      );
      samples.add(
        Sample(
          tsEpoch: start + i,
          counter: i + 1,
          hr: asleep ? 60 + (i ~/ 30 % 3) : 95 + i % 8,
          rrIntervalsMs: [(1000 + 35 * math.sin(phase)).round()],
          ax: asleep ? .001 * math.sin(i / 30) : .3 * math.sin(i / 3),
          ay: asleep ? .001 : .25 * math.cos(i / 3),
          az: 1,
          spo2RedRaw: 1200,
          spo2IrRaw: 1600,
          skinTempRaw: 2500,
          ambientRaw: 1,
        ),
      );
    }
    await LocalDb.upsertDevice(adapterId: 'gen4');
    await LocalDb.insertRecordsBatch(raws, samples);
    return start;
  }

  for (final refuseRead in [false, true]) {
    test(
      'COV-48 complete authored night follows real manual/confirmed commands read-refusal=$refuseRead',
      () async {
        final start = await seedNight();
        final app = AppState.forTesting()..user = profile.toMap();
        final repo = LocalRepositoryImpl(getProfileMap: () => app.user);
        app.repo = repo;
        addTearDown(app.dispose);
        DateTime at(int offset) =>
            DateTime.fromMillisecondsSinceEpoch((start + offset) * 1000);
        Future<void> boundary(int onset, int offset, String source) async {
          final sleep = await repo.getDaySleep(day);
          expect(sleep['has_sleep'], true, reason: app.logLines.join('\n'));
          expect(sleep['sleep_source'], source);
          expect(sleep['onset_ts'], start + onset);
          expect(sleep['wake_ts'], start + offset);
          expect((await LocalDb.dayResult(day))!['algo_version'], kAlgoVersion);
          expect(app.reanalyzing, false);
        }

        await app.setSleepOverride(day, at(900), at(9900));
        await boundary(900, 9900, 'manual');
        final old = await LocalDb.dayResult(day);
        final db = await LocalDb.instance;
        final rawCount = (await db.rawQuery(
          'SELECT COUNT(*) AS n FROM decoded_onehz',
        )).single['n'];
        final revision = app.insightsRevision.value;
        if (refuseRead) {
          await db.execute(
            'ALTER TABLE decoded_onehz RENAME TO authored_night_retained',
          );
          try {
            await app.setSleepOverride(day, at(1200), at(9600));
            expect(
              (await LocalDb.getSleepOverride(day))!['onset_ts'],
              start + 1200,
            );
            expect(
              await LocalDb.dayResult(day),
              old,
              reason:
                  'A durable correction cannot replace the richer night without its substrate',
            );
            expect(app.reanalyzing, false);
          } finally {
            await db.execute(
              'ALTER TABLE authored_night_retained RENAME TO decoded_onehz',
            );
          }
        }
        await app.setSleepOverride(day, at(1200), at(9600));
        await boundary(1200, 9600, 'manual');
        expect(app.insightsRevision.value, greaterThan(revision));
        await app.confirmSleep(day);
        await boundary(1200, 9600, 'confirmed');
        final confirmed = await LocalDb.getSleepOverride(day);
        final saved = await LocalDb.dayResult(day);
        final confirmedRevision = app.insightsRevision.value;
        await app.setSleepOverride(day, at(9600), at(1200));
        expect(await LocalDb.getSleepOverride(day), confirmed);
        expect(await LocalDb.dayResult(day), saved);
        expect(app.insightsRevision.value, confirmedRevision);
        expect(
          (await db.rawQuery(
            'SELECT COUNT(*) AS n FROM decoded_onehz',
          )).single['n'],
          rawCount,
        );
        expect(await LocalDb.lastDecodedRecTs(), start + 10800 - 1);
        expect(
          await LocalDb.baseline('sleep_user_profile'),
          isNull,
          reason:
              'User-entered or confirmed windows are not automatic profile observations',
        );
      },
      timeout: const Timeout(Duration(minutes: 4)),
    );
  }

  for (final manual in [false, true]) {
    test(
      'COV-47 ${manual ? 'confirmed' : 'automatic'} night retains stage/profile provenance across rederive',
      () async {
        final start = await seedNight();
        const seconds = 3 * 3600;
        if (manual) {
          await LocalDb.putSleepOverride(
            dayId: day,
            onsetTs: start + 900,
            offsetTs: start + seconds - 900,
            source: 'confirmed',
          );
        }
        final logs = <String>[], done = <String>[];
        final engine = DerivationEngine(background: true, log: logs.add);
        expect(
          await engine.runDays(
            profile,
            {day},
            onDayDone: (d, i, n) {
              expect(i, 1);
              expect(n, 1);
              done.add(d);
            },
          ),
          1,
          reason: logs.join('\n'),
        );
        expect(done, [day]);
        expect(engine.running, false);
        final row = (await LocalDb.dayResult(day))!;
        expect(row['skipped'], 0);
        expect(row['partial'], 0);
        expect(row['algo_version'], kAlgoVersion);
        final candidate = (await LocalDb.sleepSessionCandidate(
          day,
          kAlgoVersion,
        ));
        if (!manual) {
          expect(candidate, isNotNull);
          final staged =
              jsonDecode(candidate!['payload_json'] as String) as Map;
          expect(staged['sleep_json'], isNotEmpty);
          final learned =
              (await LocalDb.baseline('sleep_user_profile'))!['payload_json']
                  as String;
          expect(SleepProfilePolicy.foldedDays(learned), contains(day));
          final learnedBefore = jsonDecode(learned) as Map;
          expect(learnedBefore['nights'], 1);
          expect(await engine.runDays(profile, {day}), 1);
          final learnedAfter = jsonDecode(
            (await LocalDb.baseline('sleep_user_profile'))!['payload_json']
                as String,
          );
          expect(
            learnedAfter['nights'],
            1,
            reason:
                'a repeated day must never add another physiological observation',
          );
          expect(SleepProfilePolicy.foldedDays(jsonEncode(learnedAfter)), {
            day,
          });
        } else {
          expect((await LocalDb.getSleepOverride(day))!['source'], 'confirmed');
          expect(
            await LocalDb.baseline('sleep_user_profile'),
            isNull,
            reason:
                'a user-confirmed boundary is not an automatic profile observation',
          );
        }
        // The source window remains available: a successful derive cannot erase a
        // night still inside the data-edge retention interval.
        expect(await LocalDb.lastDecodedRecTs(), start + seconds - 1);
      },
      timeout: const Timeout(Duration(minutes: 4)),
    );
  }
}
