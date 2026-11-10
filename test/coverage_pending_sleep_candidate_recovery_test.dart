// Pending-day recalculation uses a later candidate recovery path than the
// finalized cache. Keep that actual entry policy,thin-input absence and retry.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/derivation_engine.dart';
import 'package:whoop_companion/compute/derive_prepare.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/models.dart';

import 'coverage_derived_effort_handoff_test.dart' show authored;
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('pending-sleep-candidate-recovery'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  const date = '2021-04-06', older = '2021-04-01';
  for (final entry in ['ordinary', 'rescan']) {
    test(
      '$entry retains the genuinely banked night after its raw window is pruned',
      () async {
        // Actual short segmentation preflight of the shared authored night;the
        // expensive complete-night analytics are not run on this host.
        final prepared = prepareDerivationPayload(authored()).days.single;
        expect(prepared.sleepJson['tst_sec'], greaterThanOrEqualTo(3 * 3600));
        final candidate = SleepSessionCandidate(
          dayId: date,
          confidence: prepared.confidence,
          flags: prepared.flags,
          sleepJson: prepared.sleepJson,
          hypnoStages: prepared.hypnoStages,
          sleepOnsetSec: prepared.sleepOnsetSec,
          sleepOffsetSec: prepared.sleepOffsetSec,
          sleepSource: prepared.sleepSource,
        );
        final encoded = jsonEncode(candidate.toJson());
        expect(
          await LocalDb.putSleepSessionCandidate(
            dayId: date,
            algoVersion: kAlgoVersion,
            payloadJson: encoded,
          ),
          true,
        );
        final cached = await LocalDb.sleepSessionCandidate(date, kAlgoVersion);
        await LocalDb.putDayResult(
          dayId: date,
          algoVersion: kAlgoVersion,
          payloadJson: jsonEncode({
            'scalars': {'rhr': 60, 'rmssd': 41, 'readiness': 72},
            'sleep': {
              'accounting': {
                'value': {'tst_sec': prepared.sleepJson['tst_sec']},
              },
            },
          }),
          windowJson: '{}',
          rhr: 60,
          rmssd: 41,
          readiness: 72,
          finalized: false,
          series: {'rhr': 60, 'rmssd': 41, 'readiness': 72},
        );
        final banked = await LocalDb.dayResult(date);
        final db = await LocalDb.instance;
        final series = await db.query(
          'metric_series',
          where: 'date=?',
          whereArgs: [date],
          orderBy: 'key',
        );
        // Raw retention has kept only a daytime point;it cannot supply the
        // banked candidate's main-night HR/RR again.
        final ts = localDayStartSec(date)! + 12 * 3600;
        await LocalDb.insertRecord(
          RawRecord(
            counter: 1,
            packetType: 47,
            hex: 'authored-retained-daytime',
            capturedAt: ts * 1000,
            recTs: ts,
          ),
          Sample(
            tsEpoch: ts,
            counter: 1,
            hr: 60,
            rrIntervalsMs: const [],
            ax: 0,
            ay: 0,
            az: 1,
          ),
        );
        final logs = <String>[];
        final engine = DerivationEngine(background: true, log: logs.add);
        expect(
          await (entry == 'ordinary'
              ? engine.run(const Profile(), force: true)
              : engine.rescanRecent(const Profile())),
          1,
          reason: logs.join('\n'),
        );
        expect(logs, contains(contains('kept the banked night')));
        expect(logs, contains(contains('sleep-window substrate pruned out')));
        expect(await LocalDb.sleepSessionCandidate(date, kAlgoVersion), cached);
        expect(await LocalDb.dayResult(date), banked);
        expect(
          await db.query(
            'metric_series',
            where: 'date=?',
            whereArgs: [date],
            orderBy: 'key',
          ),
          series,
        );
        expect(await LocalDb.lastDecodedRecTs(), ts);
        expect(engine.running, false);
      },
    );
    for (final kind in ['valid-absent', 'malformed', 'non-map', 'empty']) {
      test(
        '$entry replaces a pending $kind candidate without inventing a night',
        () async {
          final ts = localDayStartSec(date)! + 12 * 3600;
          await LocalDb.insertRecord(
            RawRecord(
              counter: 1,
              packetType: 47,
              hex: 'authored-pending-candidate',
              capturedAt: ts * 1000,
              recTs: ts,
            ),
            Sample(
              tsEpoch: ts,
              counter: 1,
              hr: 60,
              rrIntervalsMs: const [],
              ax: 0,
              ay: 0,
              az: 1,
            ),
          );
          await LocalDb.putDayResult(
            dayId: older,
            algoVersion: kAlgoVersion,
            payloadJson: '{"authored":"keep banked history"}',
            windowJson: '{}',
            readiness: 72,
            rmssd: 41,
            finalized: true,
          );
          final banked = await LocalDb.dayResult(older);
          await LocalDb.putDayResult(
            dayId: date,
            algoVersion: kAlgoVersion,
            payloadJson: '{"scalars":{}}',
            windowJson: '{}',
            finalized: false,
          );
          final original = switch (kind) {
            'valid-absent' => jsonEncode(
              SleepSessionCandidate.absent(date).toJson(),
            ),
            'malformed' => '{authored-invalid-json',
            'non-map' => '[1,2,3]',
            _ => '',
          };
          expect(
            await LocalDb.putSleepSessionCandidate(
              dayId: date,
              algoVersion: kAlgoVersion,
              payloadJson: original,
            ),
            true,
          );
          final logs = <String>[];
          final engine = DerivationEngine(background: true, log: logs.add);
          Future<int> run() => entry == 'ordinary'
              ? engine.run(const Profile(), force: true)
              : engine.rescanRecent(const Profile());
          expect(await run(), 1, reason: logs.join('\n'));
          final after = (await LocalDb.sleepSessionCandidate(
            date,
            kAlgoVersion,
          ))!;
          final repaired = SleepSessionCandidate.fromJson(
            (jsonDecode(after['payload_json'] as String) as Map)
                .cast<String, dynamic>(),
          );
          expect(repaired.dayId, date);
          expect(repaired.present, false);
          expect(repaired.sleepOnsetSec, 0);
          expect(repaired.sleepOffsetSec, 0);
          if (kind != 'valid-absent') {
            expect(after['payload_json'], isNot(original));
          }
          final row = (await LocalDb.dayResult(date))!;
          expect(row['skipped'], 0);
          expect(row['partial'], 0);
          expect(
            row['finalized'],
            0,
            reason: 'the decoded edge is midday,not a complete end of day',
          );
          expect(row['rhr'], isNull);
          expect(row['rmssd'], isNull);
          expect(row['readiness'], isNull);
          expect(await LocalDb.dayResult(older), banked);
          expect(await LocalDb.lastDecodedRecTs(), ts);
          expect(await LocalDb.baseline('sleep_user_profile'), isNull);
          expect(logs.where((s) => s.contains('FAILED/skipped')), isEmpty);
          expect(engine.running, false);
          // A subsequent actual command must reuse/recover normally after the
          // same-version candidate write,without leaking the global engine lock.
          expect(await run(), entry == 'ordinary' ? 1 : 0);
          if (entry == 'rescan') {
            expect(
              logs,
              contains(contains('baseline unchanged — rescan skipped')),
            );
            expect(await LocalDb.dayResult(date), row);
          }
          expect(await LocalDb.dayResult(older), banked);
          expect(await LocalDb.lastDecodedRecTs(), ts);
          expect(engine.running, false);
        },
      );
    }
  }
}
