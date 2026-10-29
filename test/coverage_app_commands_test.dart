// Public AppState commands against synthetic storage and a substituted band boundary.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whoop_companion/ble/ble_engine.dart';
import 'package:whoop_companion/compute/derivation_engine.dart';
import 'package:whoop_companion/data/body_log.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/local_repository.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/data/nutrition_store.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/state/prefs.dart';
import 'package:whoop_companion/sync/paired_device.dart';
import 'package:whoop_companion/sync/band_ownership.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.root);
  final String root;
  @override
  Future<String?> getTemporaryPath() async => root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
}

class _Band extends BleEngine {
  _Band() : super(onRecord: (_, _) async {}, onState: (_) {});
  final calls = <String>[];
  bool refuse = false, fail = false;
  bool connected = false, enabled = false;
  Duration rxAge = Duration.zero;
  @override
  Duration get sinceLastRx => rxAge;
  @override
  bool get isConnected => connected;
  @override
  bool get liveEnabled => enabled;
  @override
  Future<bool> connectToRemoteId(
    String remoteId, {
    String? generationHint,
  }) async {
    calls.add('connect:$remoteId');
    if (fail) throw StateError('synthetic connect refusal');
    state.connection = refuse ? 'disconnected' : 'connected';
    return connected = !refuse;
  }

  @override
  Future<void> getBattery() async {
    calls.add('battery');
  }

  @override
  Future<void> enableLiveStreams() async {
    enabled = true;
    calls.add('live');
  }

  @override
  Future<void> disconnect() async {
    connected = false;
    enabled = false;
    state.connection = 'disconnected';
    calls.add('disconnect');
  }

  @override
  Future<void> requestHistorySync() async {
    calls.add('history');
  }

  @override
  Future<SyncReport> runSync({
    Duration timeout = const Duration(seconds: 600),
  }) async {
    if (fail) throw StateError('synthetic sync refusal');
    calls.add('sync');
    return SyncReport(0, 0, true);
  }

  @override
  Future<bool> requestForegroundSync() async {
    calls.add('foreground');
    return !refuse;
  }

  Completer<DateTime?>? heldAlarm;
  @override
  Future<DateTime?> setAlarm(
    DateTime when, {
    int index = 0,
    List<int>? haptics,
  }) async {
    calls.add('set');
    if (heldAlarm != null) return heldAlarm!.future;
    if (fail) throw StateError('synthetic radio refusal');
    return refuse ? null : when;
  }

  @override
  Future<void> disableAlarm({int? id}) async {
    calls.add('disable');
    if (fail) throw StateError('synthetic radio refusal');
  }

  @override
  Future<void> runAlarm() async {
    calls.add('run');
    if (fail) throw StateError('synthetic radio refusal');
  }

  @override
  Future<bool> buzz() async {
    calls.add('buzz');
    if (fail) throw StateError('synthetic radio refusal');
    return !refuse;
  }

  @override
  Future<void> setStrapName(String name) async {
    calls.add('name:$name');
    if (fail) throw StateError('synthetic radio refusal');
  }

  @override
  Future<void> getStrapName() async {
    calls.add('read-name');
  }
}

class _Sleep extends LocalRepository {
  Map<String, dynamic> window = {};
  @override
  Future<Map<String, dynamic>> getDaySleep(String date) async => window;
}

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 10; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await t.pump();
  }
  expect(t.takeException(), isNull);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory root;
  late Database db;
  late _Band band;
  late AppState app;
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    root = (await Directory(
      'build/coverage-remainder/commands',
    ).create(recursive: true)).absolute;
    PathProviderPlatform.instance = _Paths(root.path);
    LocalDb.dbName = '${root.path}/synthetic.sqlite';
    await LocalDb.close();
    await databaseFactory.deleteDatabase(LocalDb.dbName);
    db = await LocalDb.instance;
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.ensureLoaded();
    await LocalDb.wipeAll();
    DayClock.install([], []);
    band = _Band();
    band.state.connection = 'connected';
    app = AppState.forTesting(engine: band)
      ..user = {'age': 30, 'sex': 'f', 'weight_kg': 70, 'height_cm': 170};
    app.repo = LocalRepositoryImpl(getProfileMap: () => app.user);
    messenger.setMockMethodCallHandler(
      const MethodChannel('flutter_timezone'),
      (_) async => 'UTC',
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('whoop/ble_restore'),
      (c) async => c.method == 'appState' ? 'active' : null,
    );
  });
  tearDown(() {
    app.dispose();
    DayClock.install([], []);
    BandOwnership.resetForTest();
  });
  tearDownAll(LocalDb.close);

  test(
    'vendor import publishes committed history to every dependent revision',
    () async {
      final file = await File('${root.path}/synthetic-cycles.csv').writeAsString(
        'Cycle start time,Wake onset,Recovery score %,Resting heart rate (bpm),Heart rate variability (ms),Day Strain,Energy burned (cal),Asleep duration (min)\n'
        '2026-01-02 08:00:00,2026-01-02 08:00:00,61,55,42,6.1,2100,420\n',
      );
      final before = app.insightsRevision.value,
          food = NutritionDb.revision.value;
      final progress = <int>[];
      expect(
        await app.importWhoopCsvs([file.path], onProgress: progress.add),
        1,
      );
      expect(app.lastWhoopImport!.days, 1);
      expect(progress.last, 1);
      expect(app.insightsRevision.value, greaterThan(before));
      expect(NutritionDb.revision.value, greaterThan(food));
      final row = (await LocalDb.dayResult('2026-01-02'))!;
      expect(
        (jsonDecode(row['payload_json'] as String) as Map)['source'],
        'whoop_export',
      );
      expect(
        (await db.query(
          'metric_series',
          where: 'date = ? AND key = ?',
          whereArgs: ['2026-01-02', 'rhr'],
        )).single['value'],
        55,
      );
    },
  );
  test(
    'empty sensor CSV is refused; a valid sensor import reports counts and a missing file can retry',
    () async {
      final file = await File('${root.path}/synthetic-raw-sensor.csv')
          .writeAsString(
            'unix_s,iso_utc,stream,hr_bpm,rr_ms,grav_x,grav_y,grav_z,step_counter\n',
          );
      await expectLater(app.importNoopCsv(file.path), throwsA(anything));
      await file.writeAsString(
        'unix_s,iso_utc,stream,hr_bpm,rr_ms,grav_x,grav_y,grav_z,step_counter\n1767355200,,hr,60,,,,,\n1767355200,,gravity,,,0,0,1,\n',
      );
      expect(await app.importNoopCsv(file.path), 1);
      expect(app.lastNoopImport!.rows, 2);
      final revision = app.insightsRevision.value;
      await expectLater(
        app.importNoopCsv('${root.path}/missing.csv'),
        throwsA(isA<FileSystemException>()),
      );
      expect(app.insightsRevision.value, revision);
    },
  );
  test(
    'database restore restores readings and exposes a day count separate from row count',
    () async {
      await BodyLogDb.putWeight('2026-01-02', 70, 'kg', historyOnly: true);
      await LocalDb.putDayResult(
        dayId: '2026-01-02',
        algoVersion: kAlgoVersion,
        payloadJson:
            '{"date":"2026-01-02","source":"whoop_export","imported":true}',
        windowJson: '{}',
        series: {'rhr': 55},
      );
      final snapshot = await LocalDb.exportCopy();
      try {
        await LocalDb.wipeAll();
        final before = app.insightsRevision.value;
        expect(await app.importEdgeBackup(snapshot), 1);
        expect(app.lastImportRecords, greaterThan(1));
        expect(app.importRollupError, isNull);
        expect((await BodyLogDb.weightOn('2026-01-02'))!.kg, 70);
        expect(app.insightsRevision.value, greaterThan(before));
      } finally {
        await File(snapshot).delete();
      }
    },
  );
  test(
    'manual sleep correction is durable and clearing it removes the override',
    () async {
      final a = DateTime(2026, 1, 1, 23), b = DateTime(2026, 1, 2, 7);
      await app.setSleepOverride('2026-01-02', a, a);
      expect(await LocalDb.getSleepOverride('2026-01-02'), isNull);
      await app.setSleepOverride('2026-01-02', a, b);
      final row = (await LocalDb.getSleepOverride('2026-01-02'))!;
      expect(row['onset_ts'], a.millisecondsSinceEpoch ~/ 1000);
      expect(row['source'], 'manual');
      expect(app.reanalyzing, isFalse);
      await app.clearSleepOverride('2026-01-02');
      expect(await LocalDb.getSleepOverride('2026-01-02'), isNull);
    },
  );
  for (final valid in [false, true]) {
    test(
      'confirm/reject sleep uses ${valid ? 'the detected absolute window' : 'honest missing-window behavior'}',
      () async {
        final repo = _Sleep();
        app.repo = repo;
        if (valid)
          repo.window = {'onset_ts': 1767308400, 'wake_ts': 1767337200};
        await app.confirmSleep('2026-01-02');
        expect(
          await LocalDb.getSleepOverride('2026-01-02'),
          valid ? isNotNull : isNull,
        );
        if (valid)
          expect(
            (await LocalDb.getSleepOverride('2026-01-02'))!['source'],
            'confirmed',
          );
        await app.rejectSleep('2026-01-02');
        final rejected = (await LocalDb.getSleepOverride('2026-01-02'))!;
        expect(rejected['source'], 'rejected');
        expect(
          (rejected['offset_ts'] as int),
          greaterThan(rejected['onset_ts'] as int),
        );
        if (valid) expect(rejected['onset_ts'], 1767308400);
      },
    );
  }
  test(
    'deleting a stored day publishes removal while retaining a different day',
    () async {
      for (final d in ['2026-01-02', '2026-01-03']) {
        await LocalDb.putDayResult(
          dayId: d,
          algoVersion: kAlgoVersion,
          payloadJson: '{"date":"$d"}',
          windowJson: '{}',
          series: {'rhr': 55},
        );
      }
      final before = app.insightsRevision.value;
      expect(await app.dataHistoryDays(), hasLength(2));
      expect(await app.deleteDays({'2026-01-02'}), greaterThan(0));
      expect(await LocalDb.dayResult('2026-01-02'), isNull);
      expect(await LocalDb.dayResult('2026-01-03'), isNotNull);
      expect(app.insightsRevision.value, greaterThan(before));
    },
  );
  test(
    'permission denial persists Off without inventing step totals',
    () async {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(
        const MethodChannel('whoop/phone_steps'),
        (c) async {
          calls.add(c.method);
          return false;
        },
      );
      expect(await app.requestPhoneSteps(), isFalse);
      expect(app.phoneStepsEnabled, isFalse);
      expect(
        (await SharedPreferences.getInstance()).getBool('phone_steps'),
        isFalse,
      );
      expect(calls, ['requestPermission']);
      expect(app.phoneStepsLastTotal, isNull);
    },
  );
  test(
    'phone grant banks actual native counts; disabling removes those counts',
    () async {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(
        const MethodChannel('whoop/phone_steps'),
        (c) async {
          calls.add(c.method);
          return switch (c.method) {
            'requestPermission' || 'authorized' => true,
            'stepsInInterval' => 12,
            _ => null,
          };
        },
      );
      expect(await app.requestPhoneSteps(), isTrue);
      for (var i = 0; i < 150 && app.phoneStepsLastSyncedDays == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(app.phoneStepsLastSyncedDays, greaterThan(0));
      expect(app.phoneStepsLastTotal, greaterThan(0));
      expect(app.phoneStepsEnabled, isTrue);
      expect(calls, contains('stepsInInterval'));
      expect(
        await db.query('live_coverage', where: "source='phone'"),
        isNotEmpty,
      );
      await app.disablePhoneSteps();
      expect(app.phoneStepsEnabled, isFalse);
      expect(app.phoneStepsToday, 0);
      expect(app.phoneStepsLastTotal, isNull);
      expect(calls, contains('stop'));
      expect(await db.query('live_coverage', where: "source='phone'"), isEmpty);
      for (var i = 0; i < 30 && app.reanalyzing; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    },
  );
  for (final corrupt in [false, true]) {
    test(
      'startup ${corrupt ? 'refuses corrupt profile fields' : 'restores profile and saved alarm'} without requiring a band',
      () async {
        SharedPreferences.setMockInitialValues({
          'local_profile_json': corrupt
              ? '{bad'
              : jsonEncode({
                  'age': 30,
                  'sex': 'f',
                  'weight_kg': 70,
                  'height_cm': 170,
                  'kcal_target': 2100,
                }),
          'onboarding_choice': 'imported',
          'alarm_epoch': 1767355200,
        });
        await Prefs.ensureLoaded();
        app.user = null;
        await app.debugInit();
        expect(app.initialized, isTrue);
        expect(app.initError, isNull);
        expect(app.route, AppRoute.pairing);
        expect(app.alarmEpoch, 1767355200);
        expect(band.calls, isEmpty);
        expect(app.user?['height_cm'], corrupt ? isNull : 170);
      },
    );
  }
  for (final outcome in ['connected', 'refused', 'throws']) {
    test(
      'foreground connect $outcome releases busy and lets the session be stopped',
      () async {
        app.paired = PairedDevice('synthetic-band', null, generation: 'gen4');
        band.refuse = outcome == 'refused';
        band.fail = outcome == 'throws';
        await app.openSession();
        expect(app.busy, isFalse);
        expect(band.calls.first, 'connect:synthetic-band');
        if (outcome == 'connected') {
          expect(
            band.calls,
            containsAllInOrder(['battery', 'read-name', 'live']),
          );
          expect(band.enabled, isTrue);
        } else {
          expect(band.enabled, isFalse);
          expect(BandOwnership.owner, isNull);
        }
        await app.endSession();
        expect(band.connected, isFalse);
        expect(BandOwnership.owner, isNull);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      },
    );
  }
  for (final action in ['set', 'disable', 'test', 'rename']) {
    test(
      'disconnected $action refuses the operation before touching the band',
      () async {
        band.state.connection = 'disconnected';
        final f = switch (action) {
          'set' => app.setAlarm(DateTime.now().add(const Duration(hours: 8))),
          'disable' => app.disableAlarm(),
          'test' => app.testAlarmBuzz(),
          _ => app.renameStrap('Synthetic band'),
        };
        await expectLater(f, throwsException);
        expect(band.calls, isEmpty);
        expect(app.alarmEpoch, isNull);
      },
    );
  }
  for (final refuse in [false, true]) {
    test(
      'find-band returns ${refuse ? 'failure' : 'success'} without throwing',
      () async {
        band.refuse = refuse;
        expect(await app.buzzBand(), !refuse);
        band.fail = true;
        expect(await app.buzzBand(), isFalse);
        band.state.connection = 'disconnected';
        expect(await app.buzzBand(), isFalse);
        expect(band.calls, ['buzz', 'buzz']);
      },
    );
  }
  testWidgets(
    'a refused alarm never becomes a saved or pending alarm; retry can confirm and clear',
    (t) async {
      final when = DateTime.now().add(const Duration(hours: 8));
      band.refuse = true;
      await expectLater(app.setAlarm(when), throwsException);
      expect(app.alarmEpoch, isNull);
      expect(app.alarmPending, isFalse);
      expect(
        (await SharedPreferences.getInstance()).getInt('alarm_epoch'),
        isNull,
      );
      band.refuse = false;
      await app.setAlarm(when);
      expect(app.alarmEpoch, when.millisecondsSinceEpoch ~/ 1000);
      expect(app.alarmPending, isTrue);
      app.debugHandleAlarmEvent(56);
      expect(app.alarmConfirmed, isTrue);
      await app.disableAlarm();
      expect(app.alarmEpoch, isNull);
      expect(app.alarmConfirmed, isFalse);
      expect(
        (await SharedPreferences.getInstance()).getInt('alarm_epoch'),
        isNull,
      );
      await settle(t);
    },
  );
  testWidgets(
    'unconfirmed alarm retries once, then stays unconfirmed instead of looping forever',
    (t) async {
      await app.setAlarm(DateTime.now().add(const Duration(hours: 8)));
      await t.pump(const Duration(milliseconds: 6251));
      await settle(t);
      expect(band.calls, ['set', 'set']);
      await t.pump(const Duration(milliseconds: 6251));
      await settle(t);
      await t.pump(const Duration(seconds: 60));
      await settle(t);
      expect(band.calls, ['set', 'set']);
      expect(app.alarmConfirmed, isFalse);
    },
  );
  test('rename and test buzz reflect the band command result', () async {
    await app.renameStrap('Synthetic band');
    expect(app.strapName, 'Synthetic band');
    await app.testAlarmBuzz();
    expect(band.calls, ['name:Synthetic band', 'read-name', 'run']);
    band.fail = true;
    await expectLater(app.renameStrap('Refused'), throwsStateError);
    expect(app.strapName, 'Synthetic band');
  });

  test(
    'live updates retain repeated values at new instants, cap history and reset on disconnect',
    () async {
      app.dispose();
      app = AppState.forTesting();
      final s = app.device
        ..connection = 'connected'
        ..liveHr = 60
        ..liveHrAt = 1000;
      app.engine.onState(s);
      app.engine.onState(s);
      expect(app.liveHrTrace, [60]);
      for (var i = 1; i <= AppState.liveHrTraceMax; i++) {
        s.liveHrAt = 1000 + i;
        app.engine.onState(s);
      }
      expect(app.liveHrTrace, hasLength(AppState.liveHrTraceMax));
      expect(app.liveHrTraceRev, AppState.liveHrTraceMax + 1);
      expect(() => app.liveHrTrace.add(80), throwsUnsupportedError);
      s.connection = 'disconnected';
      app.engine.onState(s);
      expect(app.liveHrTrace, isEmpty);
      expect(BandOwnership.owner, isNull);
      await Future<void>.delayed(const Duration(milliseconds: 80));
    },
  );
  test(
    'battery changes publish only after storage and unchanged live ticks do not republish',
    () async {
      app.dispose();
      app = AppState.forTesting();
      final s = app.device
        ..connection = 'connected'
        ..batteryPct = 73.2
        ..charging = false
        ..wristOn = true;
      app.engine.onState(s);
      for (var i = 0; i < 100 && app.batteryRevision.value == 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(app.batteryRevision.value, 1);
      final saved = (await LocalDb.recentBandBatterySamples()).single;
      expect(saved['battery_pct'], 73);
      expect(saved['charging'], 0);
      expect(saved['wrist_on'], 1);
      for (var i = 0; i < 10; i++) {
        app.engine.onState(s);
      }
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(app.batteryRevision.value, 1);
      expect(await LocalDb.recentBandBatterySamples(), hasLength(1));
    },
  );
  test(
    'device identity heals an existing pair and never invents one from an unsolicited event',
    () async {
      app.dispose();
      app = AppState.forTesting();
      final s = app.device
        ..generation = 'gen4'
        ..serial = '123456789'
        ..strapName = 'Synthetic band';
      app.engine.onState(s);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(app.paired, isNull);
      expect(await PairedDevice.load(), isNull);
      expect((await LocalDb.deviceRow())?['adapter_id'], 'gen4');
      expect(app.strapName, 'Synthetic band');
      app.paired = PairedDevice('synthetic-band', null);
      app.engine.onState(s);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(app.paired?.remoteId, 'synthetic-band');
      expect(app.paired?.generation, 'gen4');
      expect((await PairedDevice.load())?.generation, 'gen4');
    },
  );
  test(
    'full reanalysis without raw releases the busy state and does not replace saved history',
    () async {
      await LocalDb.putDayResult(
        dayId: '2026-01-02',
        algoVersion: kAlgoVersion,
        payloadJson:
            '{"source":"whoop_export","imported":true,"scalars":{"rhr":55}}',
        windowJson: '{}',
        series: {'rhr': 55},
      );
      expect(await app.reanalyzeAll(), 0);
      expect(app.reanalyzing, isFalse);
      expect(app.reanalyzeProgress, '');
      expect(
        (await LocalDb.dayResult('2026-01-02'))?['payload_json'],
        contains('whoop_export'),
      );
      expect(await LocalDb.metricValueOn('2026-01-02', 'rhr'), 55);
    },
  );
  test(
    'rebuild insights states the actual history requirement and never leaves a busy latch',
    () async {
      await app.rebuildInsights();
      expect(app.insightsRebuilding, isFalse);
      expect(app.insightsRebuildMessage, contains('At least 3 usable days'));
      expect(await LocalDb.baseline('crossday'), isNull);
    },
  );
  for (final refused in ['read', 'artifact write']) {
    test(
      'rebuild $refused refusal retains saved history and releases retry',
      () async {
        await LocalDb.putDayResult(
          dayId: '2021-04-06',
          algoVersion: kAlgoVersion,
          payloadJson:
              '{"source":"whoop_export","imported":true,"scalars":{"rhr":55}}',
          windowJson: '{}',
          series: {'rhr': 55},
        );
        const previous = '{"synthetic":"previous rollup"}';
        await LocalDb.putBaseline('crossday', previous);
        final before = await db.query('day_result');
        final revision = app.insightsRevision.value;
        if (refused == 'read') {
          await db.execute(
            'ALTER TABLE day_result RENAME TO synthetic_held_rebuild_days',
          );
        } else {
          await db.execute(
            "CREATE TRIGGER synthetic_rebuild_refusal BEFORE INSERT ON baselines "
            "WHEN NEW.key='crossday_input' BEGIN SELECT RAISE(ABORT,'synthetic rebuild refusal'); END",
          );
        }
        try {
          await app.rebuildInsights();
          expect(app.insightsRebuilding, false);
          expect(
            app.insightsRebuildMessage,
            'Insights could not rebuild. Please retry.',
          );
          expect(app.insightsRevision.value, revision);
          expect(
            (await LocalDb.baseline('crossday'))?['payload_json'],
            previous,
          );
        } finally {
          if (refused == 'read') {
            await db.execute(
              'ALTER TABLE synthetic_held_rebuild_days RENAME TO day_result',
            );
          } else {
            await db.execute('DROP TRIGGER synthetic_rebuild_refusal');
          }
        }
        expect(await db.query('day_result'), before);
        await app.rebuildInsights();
        expect(app.insightsRebuilding, false);
        expect(app.insightsRebuildMessage, contains('At least 3 usable days'));
        expect(app.insightsRevision.value, greaterThan(revision));
        expect(await db.query('day_result'), before);
        expect((await LocalDb.baseline('crossday'))?['payload_json'], previous);
      },
    );
  }
  test(
    'failed force-sync can retry without disconnecting the otherwise healthy link',
    () async {
      band.connected = true;
      band.fail = true;
      await app.forceResync();
      expect(band.connected, isTrue);
      band.fail = false;
      await app.forceResync();
      expect(band.calls, ['history', 'history', 'sync']);
      expect(app.busy, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 40));
    },
  );
  for (final stale in [false, true]) {
    test(
      'foreground catch-up on a ${stale ? 'stale' : 'healthy'} link ${stale ? 'disconnects before retry' : 'joins the existing transport'}',
      () async {
        band.connected = true;
        band.enabled = true;
        band.rxAge = stale ? const Duration(hours: 1) : Duration.zero;
        await app.foregroundCatchUp();
        if (stale) {
          expect(band.calls, ['disconnect']);
          expect(band.connected, isFalse);
        } else {
          expect(band.calls, ['foreground', 'history', 'sync']);
          expect(band.connected, isTrue);
        }
        expect(app.busy, isFalse);
      },
    );
  }
}
