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
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('derived-night-continuity'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  const profile = Profile(ageYears: 30, sex: 'f', weightKg: 70, heightCm: 170);
  const day = '2021-04-06';
  for (final manual in [false, true]) {
    test(
      'COV-47 ${manual ? 'confirmed' : 'automatic'} night retains stage/profile provenance across rederive',
      () async {
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
