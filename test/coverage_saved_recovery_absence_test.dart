// Saved morning absence reasons must survive a later measured replacement.
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/derivation_engine.dart';
import 'package:whoop_companion/compute/readiness_explain.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/ui2/screens/readiness_detail.dart';
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('saved-recovery-absence'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  for (final historical in [false, true]) {
    for (final noisy in [false, true]) {
      test(
        'COV-60 saved ${historical ? 'historical' : 'current'} absence keeps ${noisy ? 'noise' : 'missing beats'} provenance',
        () async {
          final current = todayLabel();
          final at = DateTime.parse(current);
          final day = historical
              ? dayLabelOf(DateTime(at.year, at.month, at.day - 1))
              : current;
          final bundle = <String, dynamic>{
            'scalars': {'readiness': 80, 'rhr': 52},
            'clinical': {
              'readiness_composite': {
                'value': {'score': 80},
                'confidence': .8,
                'drivers': [
                  {'label': 'RHR', 'contribution': math.log(4)},
                ],
              },
              'rmssd_sleep_session': {
                'note': noisy
                    ? 'rmssd_refused:authored noisy beats'
                    : 'no RR beats inside the session window',
              },
            },
            'respiration': {
              'rsa': {'note': noisy ? 'artifact' : 'consensus disagree'},
            },
          };
          final snapshot = recoveryExplanationSnapshot(bundle, {
            'rhr_history': [for (var i = 0; i < 28; i++) 54.0 + i % 3],
          }, day: day)!;
          expect((snapshot['values'] as Map).containsKey('hrv'), false);
          expect((snapshot['values'] as Map).containsKey('resp'), false);
          await LocalDb.putDayResult(
            dayId: day,
            algoVersion: kAlgoVersion,
            payloadJson: jsonEncode({
              'scalars': {
                'readiness': 56,
                'rhr': 60,
                'ln_rmssd_v2': math.log(42),
                'resp_rate': 14.5,
              },
              'clinical': {
                'rmssd_sleep_session': {'value': 42},
              },
            }),
            windowJson: '{}',
            series: {'readiness': 56, 'ln_rmssd_v2': math.log(42)},
          );
          await LocalDb.putComputeFreshness(
            'today',
            jsonEncode({
              'today_day': current,
              'overnight_day': day,
              'overnight_state': historical ? 'missing' : 'ready',
              'activity_state': 'ready',
            }),
          );
          await LocalDb.setFrozenHeadline(day, 80, explanation: snapshot);
          final pin = await LocalDb.getCursor(LocalDb.kFrozenHeadlineCursor);
          final d = await ReadinessData.load(
            LocalRepositoryImpl(getProfileMap: () => {}),
            day: historical ? day : null,
          );
          expect(d.readiness.value, 80);
          expect(d.savedMorningExplanation, true);
          expect(d.originalExplanationMissing, false);
          expect(d.inputsUsed, 1);
          expect(
            d.breakdown.where((r) => r['used'] == true).single['label'],
            'rhr',
          );
          expect(
            50 +
                d.breakdown.fold<int>(
                  0,
                  (sum, row) => sum + ((row['points'] as int?) ?? 0),
                ),
            80,
          );
          expect(
            d.hrvNote,
            noisy
                ? 'The beat timing was too noisy last night to measure HRV.'
                : 'No heartbeats were recorded while you slept.',
          );
          expect(
            d.breathingNote,
            noisy
                ? 'too much movement or signal noise'
                : "the night's breathing windows disagreed",
          );
          expect(
            await LocalDb.frozenHeadlineExplanation(day, 80),
            equals(snapshot),
          );
          expect(await LocalDb.getCursor(LocalDb.kFrozenHeadlineCursor), pin);
          final live =
              jsonDecode(
                    (await LocalDb.dayResult(day))!['payload_json'] as String,
                  )
                  as Map;
          expect((live['scalars'] as Map)['readiness'], 56);
          expect((live['scalars'] as Map)['resp_rate'], 14.5);
        },
      );
    }
  }
}
