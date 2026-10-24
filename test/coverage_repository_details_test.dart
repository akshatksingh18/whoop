// Real stored metric envelopes through the public screen-read contract.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:openstrap_edge/compute/derivation_engine.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/data/local_repository_impl.dart';
import 'package:openstrap_edge/data/local_repository.dart';
import 'package:openstrap_edge/state/prefs.dart';

Map<String, Object?> env(Object? value) => {
  'value': value,
  'confidence': .8,
  'tier': 'ESTIMATE',
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String day;
  late int start;
  late LocalRepositoryImpl repo;
  late Map<String, dynamic> payload;
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final root = (await Directory(
      'build/coverage-remainder/repository',
    ).create(recursive: true)).absolute;
    LocalDb.dbName = '${root.path}/synthetic.sqlite';
    await LocalDb.close();
    await databaseFactory.deleteDatabase(LocalDb.dbName);
    await LocalDb.instance;
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.ensureLoaded();
    await LocalDb.wipeAll();
    DayClock.install([], []);
    day = todayLabel();
    start = localDayStartSec(day)!;
    repo = LocalRepositoryImpl(
      getProfileMap: () => {
        'age': 30,
        'sex': 'f',
        'weight_kg': 70,
        'height_cm': 170,
      },
    );
    payload = {
      'date': day,
      'device_family': 'whoop4',
      'scalars': {
        'rhr': 50,
        'rmssd': 48,
        'sdnn': 61,
        'readiness': 72,
        'strain': 6.1,
        'wear_min': 1350,
        'worn_min': 1350,
        'calories': 230,
        'calories_total': 1900,
        'resp_rate': 14,
        'sleeping_hr_nadir': 44,
        'sleeping_hr_nadir_ts': start + 3600,
        'waking_hr': 70,
        'dip_pct': 8,
      },
      'sleep': {
        'accounting': env({
          'tst_sec': 25200,
          'spt_sec': 28800,
          'waso_sec': 3600,
          'efficiency_pct': 87.5,
          'light_sec': 14400,
          'deep_sec': 5400,
          'rem_sec': 5400,
          'nrem_sec': 19800,
        }),
        'window': env({
          'onset_ms': start * 1000,
          'offset_ms': (start + 28800) * 1000,
        }),
        'cycles': [
          {'len_min': 80},
          {'len_min': 90},
        ],
        'cycle_count': 2,
        'cycles_metric': env({'count': 2}),
      },
      'clinical': {
        'resting_hr': env(50),
        'hrv_time': {'confidence': .8},
        'hrv_freq': env({'lf_hf': 1.23456}),
        'readiness_composite': env(72),
        'irregular': env({'sd1': 20, 'sd2': 30}),
        'cv': 12,
      },
      'respiration': {'rsa': env(14)},
      'series': {
        'hr_curve': [
          {'t': start + 60, 'v': 55},
          {'t': start + 120, 'v': 75},
        ],
        'hrv_day': [
          {'t': start + 60, 'v': 48},
          {'t': start + 120, 'v': 400},
        ],
        'hypnogram': [
          {'start': start, 'end': start + 14400, 'stage': 'nrem'},
          {'start': start + 14400, 'end': start + 28800, 'stage': 'rem'},
        ],
      },
      'coverage': {
        'record_count': 81000,
        'hr_samples': 81000,
        'hr_valid': 80000,
      },
      'wear': {
        'worn_min': 1350,
        'coverage_pct': 94,
        'segments': [
          {'start': start, 'end': start + 81000, 'state': 'worn'},
        ],
      },
    };
  });
  tearDownAll(LocalDb.close);
  Future<void> seed() async {
    await LocalDb.putDayResult(
      dayId: day,
      algoVersion: kAlgoVersion,
      payloadJson: jsonEncode(payload),
      windowJson: jsonEncode({
        'onset_ms': start * 1000,
        'offset_ms': (start + 28800) * 1000,
      }),
      series: {'rhr': 50, 'rmssd': 48},
    );
    await LocalDb.putMetricSeriesValue(shiftDayLabel(day, -1), 'rhr', 54);
    await LocalDb.putMetricSeriesValue(shiftDayLabel(day, -1), 'rmssd', 52);
    await LocalDb.putComputeFreshness(
      'today',
      jsonEncode({
        'today_day': day,
        'overnight_state': 'ready',
        'activity_state': 'ready',
      }),
    );
    await LocalDb.putBaseline(
      'crossday',
      jsonEncode({
        'algo_version': kAlgoVersion,
        'built_for_day': day,
        'sleep_coach': {
          'need': env({'need_sec': 28800}),
        },
        'illness': {'flag': false},
        'readiness_glassbox': {
          'drivers': [
            {'label': 'Synthetic driver', 'detail': 'Synthetic explanation'},
            {'label': ''},
          ],
        },
      }),
    );
  }

  test(
    'Today and Heart share the stored night, provenance and personal baseline',
    () async {
      await seed();
      final today = await repo.getToday(), heart = await repo.getDayHeart(day);
      expect((today['daily'] as Map)['recovery']['value'], 72);
      expect((today['sleep'] as Map)['duration_min']['value'], 420);
      expect((today['sleep'] as Map)['need_min']['value'], 480);
      expect(today['hrv']['baseline'], 50);
      expect(heart['resting_hr'], 50);
      expect(heart['avg_hr'], 65);
      expect(heart['max_hr'], 75);
      expect(heart['hrv']['lf_hf'], 1.23);
      expect(heart['hrv']['baseline'], 50);
      expect(heart['nocturnal']['vs_baseline_bpm'], -2);
      expect(
        heart['skin_temp']['value'],
        isNull,
        reason: 'unconfirmed optical fields remain absent',
      );
    },
  );
  test(
    'Sleep keeps accounting, absolute boundaries and cycles; lungs share its respiratory envelope',
    () async {
      await seed();
      final sleep = await repo.getDaySleep(day),
          lungs = await repo.getDayLungs(day);
      expect(sleep['has_sleep'], isTrue);
      expect(sleep['duration_min'], 420);
      expect(sleep['onset_ts'], start);
      expect(sleep['wake_ts'], start + 28800);
      expect(sleep['efficiency'], .875);
      expect(sleep['need_min'], 480);
      expect(sleep['debt_min'], 60);
      expect(sleep['cycle_count'], 2);
      expect(sleep['cycles_mean_min'], 85);
      expect((sleep['hypnogram'] as List).last, {
        't': start + 28800,
        'stage': 'rem',
      });
      expect(lungs['resp']['value'], 14);
      expect(lungs['sleep_window']['start'], start);
    },
  );
  test(
    'timeline rejects implausible HRV and keeps the actual high/low instants',
    () async {
      await seed();
      final timeline = await repo.getDayTimeline(day);
      expect(timeline['hrv'], [
        {'t': start + 60, 'v': 48},
      ]);
      expect(timeline['highs']['peak_hr'], {'t': start + 120, 'v': 75});
      expect(timeline['highs']['low_hr'], {'t': start + 60, 'v': 55});
      expect(timeline['day_start'], start);
      expect(timeline['date'], day);
      final wear = await repo.getDayWear(day);
      expect(wear['worn_min'], 1350);
      expect(wear['coverage_pct'], 94);
      expect(wear['segments'], hasLength(1));
    },
  );
  test(
    'stress exposes actual stress only and does not manufacture a score from recovery',
    () async {
      payload['stress'] = {'score': 31, 'si': 44, 'level': 'low'};
      await seed();
      final stress = await repo.getDayStress(day);
      expect(stress['stress']['score'], 31);
      expect(stress['stress']['si'], 44);
      expect(stress['drivers'], [
        {'label': 'Synthetic driver', 'detail': 'Synthetic explanation'},
      ]);
      payload.remove('stress');
      await seed();
      expect((await repo.getDayStress(day))['stress']['score'], isNull);
    },
  );
  test(
    'HRV detail re-exposes the exact beat family and both clinical envelopes',
    () async {
      await seed();
      final hrv = await repo.getDayHrv(day);
      expect(hrv['rmssd'], 48);
      expect(hrv['sdnn'], 61);
      expect(hrv['baseline'], 50);
      expect(hrv['hrv_freq']['value']['lf_hf'], 1.23456);
      expect(hrv['irregular']['value'], {'sd1': 20, 'sd2': 30});
      expect(hrv['coverage']['record_count'], 81000);
      expect(hrv['device_family'], 'whoop4');
    },
  );
  for (final fallback in ['worn_min', 'records', 'absent']) {
    test(
      'legacy wear $fallback preserves missing coverage and missing off-wrist evidence',
      () async {
        payload.remove('wear');
        if (fallback != 'worn_min')
          (payload['scalars'] as Map).remove('worn_min');
        if (fallback == 'absent') payload.remove('coverage');
        await seed();
        final w = await repo.getDayWear(day);
        expect(w['worn_min'], fallback == 'absent' ? isNull : 1350);
        expect(w['coverage_pct'], isNull);
        expect(w.containsKey('segments'), isFalse);
      },
    );
  }
  for (final days in [8, -8]) {
    test(
      'stale/future rollup by $days days withholds learned need and old advice',
      () async {
        await seed();
        await LocalDb.putBaseline(
          'crossday',
          jsonEncode({
            'algo_version': kAlgoVersion,
            'built_for_day': shiftDayLabel(day, days),
            'sleep_coach': {
              'need': env({'need_sec': 28800}),
            },
            'illness': {'flag': true},
          }),
        );
        final sleep = await repo.getDaySleep(day),
            heart = await repo.getDayHeart(day);
        expect(sleep.containsKey('need_min'), isFalse);
        expect(heart['illness'], isNull);
        expect((await repo.getInsights())['stale'], isNotNull);
      },
    );
  }
  for (final goal in [499, 100001]) {
    test('step target $goal is rejected without a profile writer', () async {
      await expectLater(
        repo.setStepGoal(goal),
        throwsA(isA<RepositoryException>()),
      );
    });
  }
  test(
    'step target requires a writer and returns only its acknowledged result',
    () async {
      await expectLater(
        repo.setStepGoal(8000),
        throwsA(isA<RepositoryException>()),
      );
      Map<String, dynamic>? written;
      final writer = LocalRepositoryImpl(
        getProfileMap: () => {},
        saveProfileFields: (m) async {
          written = m;
          return m;
        },
      );
      expect(await writer.setStepGoal(9000), {'step_goal': 9000});
      expect(written, {'step_goal': 9000});
    },
  );
}

String shiftDayLabel(String label, int by) {
  final d = DateTime.parse(label);
  return dayLabelOf(DateTime(d.year, d.month, d.day + by));
}
