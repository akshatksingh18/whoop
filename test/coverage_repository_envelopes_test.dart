// Synthetic SQLite envelopes through the same readers used by active screens.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/derivation_engine.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String day;
  late int start;
  late LocalRepositoryImpl repo;
  String shiftDayLabel(String value, int n) {
    final d = DateTime.parse(value);
    return dayLabelOf(DateTime(d.year, d.month, d.day + n));
  }

  setUpAll(() => coverageStore('repository-envelopes'));
  setUp(() async {
    await resetCoverageStore();
    day = todayLabel();
    start = localDayStartSec(day)!;
    repo = LocalRepositoryImpl(getProfileMap: () => {'age': 30});
  });
  tearDownAll(LocalDb.close);
  Future<void> seed(Map<String, dynamic> payload) async {
    await LocalDb.putDayResult(
      dayId: day,
      algoVersion: kAlgoVersion,
      payloadJson: jsonEncode({'date': day, ...payload}),
      windowJson: '{}',
    );
    await LocalDb.putComputeFreshness(
      'today',
      jsonEncode({
        'today_day': day,
        'overnight_state': 'ready',
        'activity_state': 'ready',
      }),
    );
  }

  for (final known in [false, true]) {
    test(
      'COV-47 verified temperature retains relative provenance $known',
      () async {
        await LocalDb.putMetricSeriesValue(day, 'skin_temp_adc', 1200);
        await seed({
          'device_family': 'gen5',
          'coverage': {'hr_samples': 7200},
          'scalars': {if (known) 'skin_temp_z': 1.25},
          'wellness': {
            'skin_temp': {
              'confidence': .65,
              'tier': 'RELATIVE',
              'inputs_used': ['skin_temp_raw'],
              'note': 'Synthetic relative ADC',
            },
          },
          'clinical': {
            'readiness_composite': {'note': 'need_baseline:have=1,need=3'},
          },
          'spo2': {'relative': true},
          'activity': {'source': 'synthetic'},
        });
        final today = await repo.getToday();
        expect(today['daily']['wear_min']['value'], 120);
        expect(today['daily']['readiness']['value'], '—');
        expect(today['daily']['readiness']['confidence'], 0);
        expect(
          today['daily']['readiness']['note'],
          'need_baseline:have=1,need=3',
        );
        expect(today['spo2'], {'relative': true});
        expect(today['activity'], {'source': 'synthetic'});
        final skin = today['skin_temp'] as Map;
        if (known) {
          expect(skin, {
            'value': 1.25,
            'confidence': .65,
            'tier': 'RELATIVE',
            'inputs_used': ['skin_temp_raw'],
            'note': 'Synthetic relative ADC',
          });
        } else {
          expect(skin, {'value': null, 'note': 'need_baseline:have=1,need=3'});
        }
        expect(await repo.getDaySleepV2(day), await repo.getDaySleep(day));
      },
    );
  }
  for (final values in [false, true]) {
    test(
      'COV-47 interim wake figures preserve absence or measured zero $values',
      () async {
        final wake = {
          'strain': values ? 0 : null,
          'wear_min': values ? 5 : null,
          'calories': values ? 0 : null,
          'calories_total': values ? 80 : null,
          'activity': {'source': 'interim'},
          'absent_notes': {
            'strain': 'need_input:motion',
            'calories': 'need_input:profile',
          },
        };
        await LocalDb.putWakeDayFeatures(
          dayId: day,
          algoVersion: kAlgoVersion,
          payloadJson: jsonEncode(wake),
        );
        await LocalDb.putComputeFreshness(
          'today',
          jsonEncode({
            'today_day': day,
            'overnight_state': 'missing',
            'activity_state': 'partial',
          }),
        );
        final result = await repo.getToday();
        expect(result['activity'], {'source': 'interim'});
        for (final field in [
          'strain',
          'wear_min',
          'calories',
          'calories_total',
        ]) {
          expect(result['daily'][field]['value'], wake[field] ?? '—');
        }
        if (!values) {
          expect(result['daily']['strain']['note'], 'need_input:motion');
          expect(result['daily']['calories']['note'], 'need_input:profile');
        }
        expect((await repo.getDayStrain(day))['interim'], true);
        expect(await repo.getDayStrain(shiftDayLabel(day, -2)), isEmpty);
      },
    );
  }
  test(
    'COV-47 stored strain timeline and load use their own envelopes',
    () async {
      final curve = [
        {'t': start + 60, 'v': 1.5},
      ];
      final zones = [
        {'t': start + 60, 'z': 2},
      ];
      final hrv = [
        {'t': start + 60, 'v': 35},
      ];
      await seed({
        'scalars': {'strain': 1.5, 'trimp': 45},
        'series': {
          'strain_curve': curve,
          'zone_timeline': zones,
          'hrv_timeline': hrv,
        },
        'hr_stats': {'min': 55, 'max': 150, 'avg': 88},
      });
      await LocalDb.putBaseline(
        'crossday',
        jsonEncode({
          'algo_version': kAlgoVersion,
          'built_for_day': day,
          'load': {'acwr': 1.2},
        }),
      );
      final strain = await repo.getDayStrain(day);
      expect(strain['curve'], curve);
      expect(strain['zone_timeline'], zones);
      expect(strain['hr'], {'max': 150, 'avg': 88, 'min': 55});
      expect(strain['load'], {'acwr': 1.2});
      expect((await repo.getDayTimeline(day))['hrv'], hrv);
    },
  );
  test(
    'COV-47 chart keeps worn-day denominator and algorithm boundaries',
    () async {
      final db = await LocalDb.instance;
      for (var offset = -2; offset <= 0; offset++) {
        final date = shiftDayLabel(day, offset);
        await LocalDb.putMetricSeriesValue(date, 'rhr', 60.0 + offset);
        await LocalDb.putMetricSeriesValue(date, 'worn_min', 100.0 + offset);
        await db.insert('metric_series_version', {
          'date': date,
          'algo_version': offset == -2 ? kAlgoVersion - 1 : kAlgoVersion,
        });
      }
      final chart = await repo.getChart('rhr');
      expect((chart['wear'] as List).map((e) => e['v']), [98, 99, 100]);
      final breaks = chart['algo_breaks'] as List;
      expect(breaks.single['from'], kAlgoVersion - 1);
      expect(breaks.single['to'], kAlgoVersion);
    },
  );
  test(
    'COV-47 changing an unknown workout cannot manufacture a session',
    () async {
      await expectLater(
        repo.setWorkoutWindow(
          'synthetic-missing',
          startTs: start,
          endTs: start + 300,
        ),
        throwsStateError,
      );
      expect(await LocalDb.session('synthetic-missing'), isNull);
    },
  );
  test(
    'COV-48 timeline reaches current day events beyond two thousand old rows',
    () async {
      await seed({});
      final end = localDayEndSec(day)!;
      final db = await LocalDb.instance;
      final batch = db.batch();
      for (var i = 0; i < 2001; i++) {
        batch.insert('events', {
          'hex': 'authored-old-$i',
          'event_id': 7,
          'ts': start - 2001 + i,
          'captured_at': 0,
        });
      }
      final expected = [
        {'event_id': 7, 'ts': start},
        {'event_id': 8, 'ts': start + 3600},
        {'event_id': 7, 'ts': end - 1},
      ];
      for (var i = 0; i < expected.length; i++) {
        batch.insert('events', {
          'hex': 'authored-in-day-$i',
          ...expected[i],
          'captured_at': 0,
        });
      }
      batch.insert('events', {
        'hex': 'authored-next-midnight',
        'event_id': 8,
        'ts': end,
        'captured_at': 0,
      });
      await batch.commit(noResult: true);
      final timeline = await repo.getDayTimeline(day);
      expect(timeline['date'], day);
      expect(timeline['day_start'], start);
      expect(timeline['events'], expected);
      expect(await db.query('events'), hasLength(2005));
    },
  );
  test(
    'COV-48 refused recent HR read retains calculated curve and retries',
    () async {
      final curve = [
        {'t': start - 60, 'v': 99},
        {'t': start + 60, 'v': 55},
        {'t': start + 120, 'v': 65},
      ];
      await seed({
        'series': {'hr_curve': curve},
      });
      final expected = {'points': curve.sublist(1)};
      final db = await LocalDb.instance;
      await db.execute(
        'ALTER TABLE decoded_onehz RENAME TO authored_unavailable_hr',
      );
      try {
        expect(await repo.getChart('hr'), expected);
      } finally {
        await db.execute(
          'ALTER TABLE authored_unavailable_hr RENAME TO decoded_onehz',
        );
      }
      expect(await repo.getChart('hr'), expected);
      final saved = await LocalDb.dayResult(day);
      expect(saved, isNotNull);
      expect(await db.query('decoded_onehz'), isEmpty);
    },
  );
}
