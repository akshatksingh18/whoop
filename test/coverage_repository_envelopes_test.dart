// Synthetic SQLite envelopes through the same readers used by active screens.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/derivation_engine.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/gps/workout_clock.dart';
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

  for (final pause in ['completed', 'open', 'whole']) {
    test(
      'COV-48 paused history list excludes paused pulse without rewriting evidence: $pause',
      () async {
        final at = DateTime.now().subtract(const Duration(minutes: 10));
        final from = DateTime.fromMillisecondsSinceEpoch(
          at.millisecondsSinceEpoch ~/ 1000 * 1000,
        );
        final to = from.add(const Duration(minutes: 5));
        final ts = from.millisecondsSinceEpoch ~/ 1000;
        final id = 'authored-paused-list-$pause';
        final clock = WorkoutClock.begin(
          id,
          from,
          const Profile(ageYears: 30, weightKg: 70),
        );
        addTearDown(() async {
          await WorkoutClock.flushWrites();
          WorkoutClock.current = null;
        });
        clock.setPaused(
          true,
          pause == 'whole' ? from : from.add(const Duration(seconds: 30)),
        );
        if (pause == 'completed') {
          clock.setPaused(false, from.add(const Duration(seconds: 60)));
        }
        clock.finish(to);
        await WorkoutClock.flushWrites();
        await LocalDb.putSession({
          'id': id,
          'type': 'other',
          'start_ts': ts,
          'end_ts': ts + 300,
          'status': 'done',
          'source': 'manual',
          'duration_min': 5,
          'avg_hr': 88,
          'max_hr': 180,
          'device_family': 'gen4',
          'created_at': 1,
        });
        final db = await LocalDb.instance;
        for (final point in [(10, 60), (20, 70), (40, 180), (100, 80)]) {
          await db.insert('decoded_onehz', {
            'device_id': '',
            'ts_ms': (ts + point.$1) * 1000,
            'rec_ts': ts + point.$1,
            'counter': point.$1,
            'hr': point.$2,
            'device_family': 'gen4',
          });
        }
        final before = await LocalDb.session(id);
        final raw = await db.query('decoded_onehz');
        final timing = clock.toJson();
        final result = await repo.getWorkouts(range: 'all');
        final row = (result['workouts'] as List).single as Map;
        expect(row['id'], id);
        expect(
          row['avg_hr'],
          pause == 'whole'
              ? null
              : pause == 'open'
              ? 65
              : 70,
        );
        expect((result['summary'] as Map)['count'], 1);
        expect(await LocalDb.session(id), before);
        expect(await db.query('decoded_onehz'), raw);
        expect(clock.toJson(), timing);
        expect(
          (await repo.getWorkouts(range: 'all'))['workouts'],
          result['workouts'],
        );
      },
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

  for (final c in [
    (primary: 19, secondary: 0, calculated: true, shown: false),
    (primary: 20, secondary: 0, calculated: true, shown: true),
    (primary: 20, secondary: 0, calculated: false, shown: true),
    (primary: 0, secondary: 20, calculated: false, shown: false),
    (primary: 10, secondary: 20, calculated: false, shown: false),
  ]) {
    test(
      'COV-48 recent HR chart ${c.primary} primary/${c.secondary} secondary/calculated=${c.calculated} keeps admission and time bounds',
      () async {
        final now = DateTime.now();
        final nowSec = now.millisecondsSinceEpoch ~/ 1000;
        // A real IANA day at 09:00–15:00 keeps both the seven-hour-old and
        // recent samples inside today, independently of the runner's wall hour.
        final candidates = [
          ('Etc/UTC', 0),
          ('Etc/GMT+6', -6),
          ('Etc/GMT+12', -12),
          ('Etc/GMT-6', 6),
        ];
        final zone = candidates.firstWhere((z) {
          final localHour = (now.toUtc().hour + z.$2 + 24) % 24;
          return localHour >= 9 && localHour < 15;
        }).$1;
        final changes = [ZoneChange(nowSec - 2 * 86400, zone)];
        DayClock.install(
          buildDayZones(
            fromSec: nowSec - 2 * 86400,
            throughSec: nowSec + 2 * 86400,
            changes: changes,
          ),
          changes,
        );
        day = todayLabel();
        start = localDayStartSec(day)!;
        final minute = (nowSec ~/ 60 - 2) * 60;
        expect(nowSec - 7 * 3600, greaterThan(start));
        final calculated = {'t': minute - 60, 'v': 55};
        await seed({
          'series': {
            'hr_curve': [
              {'t': start - 60, 'v': 99},
              if (c.calculated) calculated,
            ],
          },
        });
        final original = (await LocalDb.dayResult(day))!['payload_json'];
        final db = await LocalDb.instance;
        final batch = db.batch();
        void rows(int at, int count, {bool secondary = false}) {
          for (var i = 0; i < count; i++) {
            final ts = at + i;
            batch.insert('decoded_onehz', {
              'device_id': secondary ? 'authored-secondary' : '',
              'ts_ms': ts * 1000,
              'rec_ts': ts,
              'counter': i,
              'hr': secondary ? 140 : (i.isEven ? 60 : 80),
              'source': secondary ? 'authored_secondary' : null,
            });
          }
        }

        rows(minute, c.primary);
        rows(minute, c.secondary, secondary: true);
        rows((nowSec ~/ 60 + 2) * 60, 20);
        rows((nowSec ~/ 60 - 7 * 60) * 60, 20);
        await batch.commit(noResult: true);
        expect(await repo.getChart('hr'), {
          'points': [
            if (c.calculated) calculated,
            if (c.shown) {'t': minute, 'v': 70.0, 'p': 1},
          ],
        });
        expect(
          await db.query('decoded_onehz'),
          hasLength(c.primary + c.secondary + 40),
        );
        expect((await LocalDb.dayResult(day))!['payload_json'], original);
      },
    );
  }
}
