// Real finalized-cache reads and format recovery over one authored 1 Hz row.
// This exercises orchestration, not a full night or physiological accuracy.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/derivation_engine.dart';
import 'package:whoop_companion/compute/derive_prepare.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/models.dart';

import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('sleep-candidate-recovery'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  const day = '2021-04-06';
  for (final kind in ['valid', 'malformed', 'non-map', 'empty']) {
    test(
      'finalized $kind sleep cache keeps source and can be reanalyzed',
      () async {
        final ts = localDayStartSec(day)! + 12 * 3600;
        await LocalDb.insertRecord(
          RawRecord(
            counter: 1,
            packetType: 47,
            hex: 'authored-cov48-cache',
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
          dayId: day,
          algoVersion: kAlgoVersion,
          payloadJson: jsonEncode({'scalars': <String, dynamic>{}}),
          windowJson: jsonEncode({'value': '—'}),
          finalized: true,
        );
        final original = switch (kind) {
          'valid' => jsonEncode(SleepSessionCandidate.absent(day).toJson()),
          'malformed' => '{authored-invalid-json',
          'non-map' => '[1, 2, 3]',
          _ => '',
        };
        await LocalDb.putSleepSessionCandidate(
          dayId: day,
          algoVersion: kAlgoVersion,
          payloadJson: original,
        );
        final before = await LocalDb.sleepSessionCandidate(day, kAlgoVersion);
        final logs = <String>[];
        final engine = DerivationEngine(background: true, log: logs.add);
        expect(
          await engine.runDays(const Profile(), {day}),
          1,
          reason: logs.join('\n'),
        );
        final after = (await LocalDb.sleepSessionCandidate(day, kAlgoVersion))!;
        final restored = SleepSessionCandidate.fromJson(
          (jsonDecode(after['payload_json'] as String) as Map)
              .cast<String, dynamic>(),
        );
        expect(restored.dayId, day);
        expect(restored.present, false);
        expect(restored.sleepOnsetSec, 0);
        expect(restored.sleepOffsetSec, 0);
        if (kind == 'valid') {
          expect(
            after,
            before,
            reason: 'a finalized valid cache must be reused verbatim',
          );
        } else {
          expect(after['payload_json'], isNot(original));
        }
        final row = (await LocalDb.dayResult(day))!;
        expect(row['skipped'], 0);
        expect(row['partial'], 0);
        expect(row['rhr'], isNull);
        expect(row['rmssd'], isNull);
        expect(row['readiness'], isNull);
        expect(await LocalDb.lastDecodedRecTs(), ts);
        expect(await LocalDb.baseline('sleep_user_profile'), isNull);
        expect(logs.where((s) => s.contains('FAILED/skipped')), isEmpty);
        expect(engine.running, false);
      },
    );
  }
}
