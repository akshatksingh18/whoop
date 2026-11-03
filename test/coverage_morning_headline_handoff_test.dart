// Complete authored nights: cloud execution only, never a local targeted probe.
// These test orchestration/persistence, not physiological or phone acceptance.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/derivation_engine.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/models.dart';
import 'coverage_derived_effort_handoff_test.dart' show authored;
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('morning-headline-handoff'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  const profile = Profile(ageYears: 30, sex: 'f', weightKg: 70, heightCm: 170);
  for (final mode in [
    'first',
    'held',
    'previous_day',
    'incomplete',
    'no_baseline',
  ]) {
    test(
      'complete morning handoff retains honest headline state: $mode',
      () async {
        final day = todayLabel();
        final calendar = DateTime.parse(day);
        String ago(int n) => dayLabelOf(
          DateTime(calendar.year, calendar.month, calendar.day - n),
        );
        final source = authored();
        final start = localDayStartSec(day)! + 3600;
        // Preserve the previously verified complete-night signal shape; move its
        // absolute stamps together. The incomplete case has only a 30-min wake
        // tail, below the existing one-hour headline settle margin.
        final count = mode == 'incomplete' ? 18900 : source.tsSec.length;
        await LocalDb.upsertDevice(adapterId: 'gen4');
        await LocalDb.insertRecordsBatch(
          [
            for (var i = 0; i < count; i++)
              RawRecord(
                counter: i + 1,
                packetType: 47,
                hex: 'authored-cov52-morning-$i',
                capturedAt: (start + i) * 1000,
                recTs: start + i,
              ),
          ],
          [
            for (var i = 0; i < count; i++)
              Sample(
                tsEpoch: start + i,
                counter: i + 1,
                hr: source.hr[i],
                rrIntervalsMs: [source.rrMs[i].round()],
                ax: source.ax[i],
                ay: source.ay[i],
                az: source.az[i],
              ),
          ],
        );
        if (mode != 'no_baseline') {
          for (var i = 1; i <= 28; i++) {
            final variation = (i % 7 - 3).toDouble();
            for (final metric in {
              'ln_rmssd_v2': 3.5 + variation * .12,
              'rhr': 61.0 + variation,
              'resp_rate': 15.0 + variation * .3,
              'tst_min': 270.0 + variation * 10,
            }.entries) {
              await LocalDb.putMetricSeriesValue(
                ago(i),
                metric.key,
                metric.value,
              );
            }
          }
        }
        if (mode == 'held' || mode == 'previous_day') {
          await LocalDb.setFrozenHeadline(
            mode == 'held' ? day : ago(1),
            17,
            explanation: {
              'format': 1,
              'composite': {'score': 17},
              'values': <String, dynamic>{},
              'baselines': <String, dynamic>{},
              'authored_marker': 'original morning evidence',
            },
          );
        }
        final logs = <String>[];
        final engine = DerivationEngine(background: true, log: logs.add);
        expect(
          await engine.runDays(profile, {day}),
          1,
          reason: logs.join('\n'),
        );
        final row = (await LocalDb.dayResult(day))!;
        final bundle = jsonDecode(row['payload_json'] as String) as Map;
        // The current writer stores SleepWindow.toJson() directly; this is not
        // the older Metric envelope. Check the real persisted bounds before
        // checking any score/pin so a missing night cannot make these vacuous.
        final sleep = jsonDecode(row['window_json'] as String) as Map;
        expect(sleep['offset_ms'], greaterThan(sleep['onset_ms'] as num));
        expect(engine.running, false);
        final pin = await LocalDb.frozenHeadline();
        if (mode == 'no_baseline') {
          expect(row['readiness'], isNull);
          expect(
            pin,
            isNull,
            reason: 'Settling an unknown value never creates a score',
          );
        } else {
          expect(
            row['readiness'],
            isNotNull,
            reason:
                'The authored night must really supply a score, not bypass the pin path',
          );
          if (mode == 'incomplete') {
            expect(
              pin,
              isNull,
              reason: 'An incomplete settle must keep the headline live',
            );
          } else if (mode == 'held') {
            expect(pin, (day: day, value: 17));
            expect(
              (await LocalDb.frozenHeadlineExplanation(
                day,
                17,
              ))!['authored_marker'],
              'original morning evidence',
            );
          } else {
            expect(pin, (day: day, value: (row['readiness'] as num).round()));
            final evidence = await LocalDb.frozenHeadlineExplanation(
              day,
              pin!.value,
            );
            expect(evidence, isNotNull);
            expect(evidence, isNot(contains('authored_marker')));
            expect(bundle['readiness_absent_diag'], isNull);
            final originalCursor = await LocalDb.getCursor(
              LocalDb.kFrozenHeadlineCursor,
            );
            // A second real pass may refresh details, but never re-pin its first
            // morning score or replace the original explanatory evidence.
            expect(await engine.runDays(profile, {day}), 1);
            expect(
              await LocalDb.getCursor(LocalDb.kFrozenHeadlineCursor),
              originalCursor,
            );
          }
        }
        expect(await LocalDb.lastDecodedRecTs(), start + count - 1);
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  }
}
