// Current-day Home reads after the real accepted-correction transaction. A prior
// usable night/pin cannot fill the explicitly withheld result for this night.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/derivation_engine.dart'
    show kAlgoVersion;
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/ui2/screens/sleep_detail.dart' show SleepData;
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('current-home-sleep-correction'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  test(
    'an ordinary pre-sync morning still opens the retained prior night',
    () async {
      final today = todayLabel();
      final d = DateTime.parse(today);
      final prior = dayLabelOf(DateTime(d.year, d.month, d.day - 1));
      final on = DateTime(
        d.year,
        d.month,
        d.day - 2,
        23,
      ).millisecondsSinceEpoch;
      final off = DateTime(
        d.year,
        d.month,
        d.day - 1,
        7,
      ).millisecondsSinceEpoch;
      await LocalDb.putDayResult(
        dayId: prior,
        algoVersion: kAlgoVersion,
        payloadJson: jsonEncode({
          'date': prior,
          'sleep_source': 'manual',
          'sleep': {
            'accounting': {
              'value': {'tst_sec': 28800},
            },
            'window': {
              'value': {'onset_ms': on, 'offset_ms': off},
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
      final db = await LocalDb.instance;
      final results = await db.query('day_result');
      final series = await db.query('metric_series');
      final repo = LocalRepositoryImpl(getProfileMap: () => null);
      final home = await repo.getToday();
      expect(home['status']['today_day'], today);
      expect(home['status']['showing_prior_overnight'], true);
      expect(home['status']['overnight_day'], prior);
      expect(home['status']['overnight_state'], isNot('corrected_unknown'));
      expect((await SleepData.load(repo)).day, prior);
      expect(await db.query('day_result'), results);
      expect(await db.query('metric_series'), series);
      expect(await LocalDb.sleepCorrection(today), isNull);
    },
  );
  for (final action in ['rejected', 'clear', 'manual', 'confirmed']) {
    for (final published in [false, true]) {
      test(
        'current Home $action ${published ? 'completed unknown' : 'pending'} '
        'keeps the correction reason and cannot reuse yesterday or a pin',
        () async {
          final today = todayLabel();
          final d = DateTime.parse(today);
          final prior = dayLabelOf(DateTime(d.year, d.month, d.day - 1));
          final onset =
              DateTime(d.year, d.month, d.day - 1, 23).millisecondsSinceEpoch ~/
              1000;
          final wake =
              DateTime(d.year, d.month, d.day, 7).millisecondsSinceEpoch ~/
              1000;
          for (final day in [prior, today]) {
            await LocalDb.putDayResult(
              dayId: day,
              algoVersion: kAlgoVersion,
              payloadJson: jsonEncode({
                'date': day,
                'sleep_source': 'manual',
                'sleep': {
                  'accounting': {
                    'value': {'tst_sec': 28800},
                  },
                  'window': {
                    'value': {
                      'onset_ms': onset * 1000,
                      'offset_ms': wake * 1000,
                    },
                  },
                },
                'scalars': {
                  'rhr': 52,
                  'rmssd': 44,
                  'readiness': 72,
                  'strain': 8,
                },
              }),
              windowJson: '{}',
              finalized: true,
              rhr: 52,
              rmssd: 44,
              readiness: 72,
              series: {'rhr': 52, 'rmssd': 44, 'readiness': 72, 'strain': 8},
            );
          }
          await LocalDb.setFrozenHeadline(
            today,
            72,
            explanation: {'authored': 'retained'},
          );
          await LocalDb.acceptSleepCorrection(
            dayId: today,
            action: action,
            onsetTs: onset,
            offsetTs: wake,
          );
          if (published) {
            expect(
              await LocalDb.putDayResult(
                dayId: today,
                algoVersion: kAlgoVersion,
                payloadJson: jsonEncode({
                  'date': today,
                  'scalars': {'strain': 9},
                }),
                windowJson: '{}',
                finalized: true,
                sleepIntentGeneration: 1,
                sleepRevision: await LocalDb.sleepCorrectionRevision(),
              ),
              isTrue,
            );
          }
          final db = await LocalDb.instance;
          final results = await db.query('day_result');
          final series = await db.query('metric_series');
          final correction = await LocalDb.sleepCorrection(today);
          final pin = await LocalDb.getCursor(LocalDb.kFrozenHeadlineCursor);
          final payload =
              jsonDecode(
                    (await LocalDb.dayResult(today))!['payload_json'] as String,
                  )
                  as Map;
          final reason = (payload['absent_notes'] as Map)['readiness'];
          expect(
            reason,
            isA<String>().having(
              (s) => s.isNotEmpty,
              'has correction reason',
              isTrue,
            ),
          );
          final home = await LocalRepositoryImpl(
            getProfileMap: () => null,
          ).getToday();
          final status = home['status'] as Map;
          final daily = home['daily'] as Map;
          expect(status['today_day'], today);
          expect(status['overnight_state'], 'corrected_unknown');
          expect(status['showing_prior_overnight'], isFalse);
          for (final key in ['readiness', 'recovery', 'resting_hr']) {
            expect((daily[key] as Map)['value'], '—');
            expect((daily[key] as Map)['note'], reason);
          }
          expect((daily['strain'] as Map)['value'], published ? 9 : 8);
          expect(home['hrv'], isNull);
          expect((home['sleep']['duration_min'] as Map)['value'], '—');
          expect((home['sleep']['duration_min'] as Map)['note'], reason);
          expect(await db.query('day_result'), results);
          expect(await db.query('metric_series'), series);
          expect(await LocalDb.sleepCorrection(today), correction);
          expect(await LocalDb.getCursor(LocalDb.kFrozenHeadlineCursor), pin);
        },
      );
    }
  }
}
