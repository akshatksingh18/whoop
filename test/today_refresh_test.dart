import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ble/ble_engine.dart';
import 'package:openstrap_edge/compute/derivation_engine.dart';
import 'package:openstrap_edge/compute/derive_scheduler.dart';
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/local_repository_impl.dart';
import 'package:openstrap_edge/health/phone_pedometer.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _ConnectedBand extends BleEngine {
  _ConnectedBand() : super(onRecord: (_, _) async {}, onState: (_) {});
  @override
  bool get isConnected => true;
}

class _RefreshApp extends AppState {
  _RefreshApp() : super.forTesting(engine: _ConnectedBand()) {
    phoneStepsEnabled = true;
  }
  final bandStarted = Completer<void>();
  final releaseBand = Completer<void>();
  final calls = <String>[];
  bool phoneFails = false;
  @override
  Future<int> syncPhoneSteps({int days = 2}) async {
    calls.add('phone:$days');
    if (phoneFails) return 0;
    await _phone(2100);
    return days;
  }

  @override
  Future<void> foregroundCatchUp() async {
    calls.add('band');
    bandStarted.complete();
    await releaseBand.future;
  }
}

Future<void> _phone(int steps) =>
    LocalDb.replacePhoneCoverageForDay(todayLabel(), [
      (
        startTs: localDayStartSec(todayLabel())!,
        endTs: localDayStartSec(todayLabel())! + 3600,
        steps: steps,
      ),
    ]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final repo = LocalRepositoryImpl(getProfileMap: () => {});

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.dbName = 'openstrap_today_refresh_test.db';
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalDb.close();
    await databaseFactory.deleteDatabase(
      p.join(await databaseFactory.getDatabasesPath(), LocalDb.dbName),
    );
  });
  tearDownAll(() async {
    await LocalDb.close();
    await databaseFactory.deleteDatabase(
      p.join(await databaseFactory.getDatabasesPath(), LocalDb.dbName),
    );
  });

  Future<Map> todaySteps() async =>
      ((await repo.getToday())['daily'] as Map)['steps'] as Map;

  test(
    'Today reads phone counts without band records or a derived day',
    () async {
      await _phone(1500);
      expect((await todaySteps())['value'], 1500);
      await _phone(2100);
      final steps = await todaySteps();
      expect(steps['value'], 2100);
      expect(steps['source'], 'phone');
      expect(steps['inputs_used'], ['phone_pedometer']);
      expect(((await repo.getToday())['daily'] as Map)['strain'], isNull);
      expect((await repo.getDaySteps(todayLabel()))['day_total'], 2100);
      expect(
        ((await repo.getChart('steps'))['points'] as List).single['v'],
        2100,
      );
    },
  );

  test(
    'fresh measured counts replace a stale calculated total without adding',
    () async {
      await LocalDb.putDayResult(
        dayId: todayLabel(),
        algoVersion: kAlgoVersion,
        windowJson: '{}',
        series: {'steps': 300},
        payloadJson: jsonEncode({
          'scalars': {'steps': 300},
          'steps': {'value': 300, 'source': 'phone'},
        }),
      );
      await _phone(2100);
      expect((await todaySteps())['value'], 2100);
      final detail = await repo.getDaySteps(todayLabel());
      expect(detail['total'], 2100);
      expect(detail['day_total'], 2100);
      expect((await repo.getDayStrain(todayLabel()))['steps'], 2100);
      final chart = (await repo.getChart('steps'))['points'] as List;
      expect(chart, hasLength(1));
      expect(chart.single['v'], 2100);
    },
  );

  test(
    'measured zero clears an older phone total; missing input stays absent',
    () async {
      expect((await todaySteps())['value'], '—');
      await _phone(2100);
      expect((await todaySteps())['value'], 2100);
      await _phone(0);
      expect((await todaySteps())['value'], 0);
      expect((await repo.getDaySteps(todayLabel()))['day_total'], 0);
    },
  );

  test(
    'native phone sync publishes new data to cached screens without a pull',
    () async {
      var stepsPerHour = 5;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(phoneStepsChannel, (call) async {
        if (call.method == 'authorized') return true;
        if (call.method == 'stepsInInterval') return stepsPerHour;
        return null;
      });
      final app = AppState.forTesting()..phoneStepsEnabled = true;
      addTearDown(() {
        messenger.setMockMethodCallHandler(phoneStepsChannel, null);
        app.dispose();
      });
      for (final n in [5, 9]) {
        stepsPerHour = n;
        final revision = app.insightsRevision.value;
        expect(await app.syncPhoneSteps(days: 1), 1);
        expect(app.insightsRevision.value, greaterThan(revision));
        if (app.phoneStepsToday > 0) {
          expect((await todaySteps())['value'], app.phoneStepsToday);
        }
      }
    },
  );

  test(
    'a real band walk with the phone left behind names only the band',
    () async {
      await _phone(0);
      final start = localDayStartSec(todayLabel())!;
      await LocalDb.addLiveCoverage(start, start + 100, 100, todayLabel());
      final steps = await todaySteps();
      expect(steps['value'], 100);
      expect(steps['source'], 'strap');
      expect(steps['inputs_used'], ['band_pedometer_100hz']);
    },
  );

  test(
    'a stored hardware counter remains a fallback without span measurements',
    () async {
      await LocalDb.putDayResult(
        dayId: todayLabel(),
        algoVersion: kAlgoVersion,
        windowJson: '{}',
        payloadJson: jsonEncode({
          'scalars': {'steps': 330},
          'steps': {
            'value': 330,
            'source': 'strap_counter',
            'inputs_used': ['band_step_counter'],
          },
        }),
      );
      expect((await todaySteps())['value'], 330);
      expect((await todaySteps())['source'], 'strap_counter');
    },
  );

  test(
    'phone reads and screen revision precede a blocked band sync; timeout is visible',
    () async {
      final app = _RefreshApp();
      final revision = app.insightsRevision.value;
      final refresh = app.pullRefresh(
        timeout: const Duration(milliseconds: 250),
      );
      await app.bandStarted.future;
      expect(app.calls, ['phone:1', 'band']);
      expect(app.insightsRevision.value, greaterThan(revision));
      expect((await todaySteps())['value'], 2100);
      expect(await refresh, contains('still running'));
      app.releaseBand.complete();
      // Let the actual operation finish (the timeout does not cancel capture).
      await Future<void>.delayed(const Duration(seconds: 9));
      app.dispose();
    },
  );

  test(
    'phone read failure is visible instead of pretending refresh succeeded',
    () async {
      final app = _RefreshApp()..phoneFails = true;
      final refresh = app.pullRefresh();
      await app.bandStarted.future;
      app.releaseBand.complete();
      expect(await refresh, contains('Phone steps could not be read'));
      app.dispose();
    },
  );

  test(
    'awaited enqueue exposes pending work and respects capture/workout gates',
    () async {
      var runs = 0;
      final scheduler = DeriveScheduler(
        run: ({required kind}) async {
          runs++;
        },
        log: (_) {},
        onChanged: () {},
        lightSettle: Duration.zero,
      )..setOffloadActive(true);
      await scheduler.markStoredData();
      expect(scheduler.pendingLight, isTrue);
      expect(
        (await LocalDb.computeJobs(state: 'queued', limit: 50)),
        isNotEmpty,
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(runs, 0);
      scheduler.setWorkoutActive(true);
      scheduler.setOffloadActive(false);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(runs, 0);
      scheduler.setWorkoutActive(false);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(runs, 1);
      expect(scheduler.pendingLight, isFalse);
      scheduler.dispose();
    },
  );
}
