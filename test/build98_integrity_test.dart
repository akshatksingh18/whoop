// Build 98 deep-flow regressions. Every value and file is synthetic.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:openstrap_edge/data/body_log.dart';
import 'package:openstrap_edge/ble/ble_engine.dart';
import 'package:openstrap_protocol/openstrap_protocol.dart' show BandProfile;
import 'package:openstrap_edge/data/calculation_store.dart';
import 'package:openstrap_edge/ui2/profile/data.dart';
import 'package:openstrap_edge/ui2/activity/live.dart';
import 'package:openstrap_edge/ui2/activity/catalogue.dart';
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/lift_log.dart';
import 'package:openstrap_edge/data/local_repository_impl.dart';
import 'package:openstrap_edge/data/nutrition_store.dart';
import 'package:openstrap_edge/data/home_region.dart';
import 'package:openstrap_edge/data/pushups.dart';
import 'package:openstrap_edge/data/pushup_reminders.dart';
import 'package:openstrap_edge/notify/notification_prefs.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:openstrap_edge/state/prefs.dart';
import 'package:openstrap_edge/state/units_controller.dart';
import 'package:openstrap_edge/sync/file_log.dart';
import 'package:openstrap_edge/ui2/screens/progress_screen.dart';
import 'package:openstrap_edge/ui2/screens/food_diary.dart';
import 'package:openstrap_edge/ui2/screens/journal_compose.dart';
import 'package:openstrap_edge/ui2/activity/lift_log_ui.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

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

class _RefusingStore extends SharedPreferencesStorePlatform {
  final values = <String, Object>{};
  int writes = 0;
  bool refuse = true;
  int? throwAtWrite;
  @override
  Future<Map<String, Object>> getAll() async => Map.of(values);
  @override
  Future<bool> clear() async {
    values.clear();
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    values.remove(key);
    return true;
  }

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    writes++;
    if (writes == throwAtWrite)
      throw StateError('Synthetic preference refusal');
    if (refuse) return false;
    values[key] = value;
    return true;
  }
}

class _Picker extends FilePicker {
  _Picker(this.file);
  final File file;
  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async => FilePickerResult([
    PlatformFile(
      path: file.path,
      name: file.uri.pathSegments.last,
      size: await file.length(),
    ),
  ]);
}

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 12; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    await t.pump(const Duration(milliseconds: 40));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late Directory tmp;
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final root = Directory('build/research-local/build98-probe-files').absolute;
    await root.create(recursive: true);
    LocalDb.dbName = p.join(root.path, 'synthetic.sqlite');
    await LocalDb.close();
    await databaseFactory.deleteDatabase(LocalDb.dbName);
    db = await LocalDb.instance;
  });
  setUp(() async {
    tmp = await Directory(
      'build/research-local/build98-probe-files',
    ).absolute.createTemp('case-');
    PathProviderPlatform.instance = _Paths(tmp.path);
    SharedPreferences.setMockInitialValues({});
    await Prefs.ensureLoaded();
    await LocalDb.wipeAll();
    DayClock.install([], []);
  });
  tearDown(() async {
    DayClock.install([], []);
    await FileLog.write('Synthetic audit cleanup barrier');
    await tmp.delete(recursive: true);
  });
  tearDownAll(() async {
    await LocalDb.close();
    await databaseFactory.deleteDatabase(LocalDb.dbName);
  });

  String body({
    List<Object> weights = const [],
    List<Object> measures = const [],
    List<Object> photos = const [],
  }) => jsonEncode({
    'format': 'whoop-body-history',
    'version': 1,
    'source': 'synthetic',
    'weights': weights,
    'measurements': measures,
    'photos': photos,
  });

  test(
    'duplicate body identities and empty tape sessions fail before any write',
    () async {
      final invalid = [
        body(
          weights: [
            {'id': 'same', 'date': '2026-09-01', 'value': 70, 'unit': 'kg'},
            {'id': 'same', 'date': '2026-09-02', 'value': 71, 'unit': 'kg'},
          ],
        ),
        body(
          measures: [
            {
              'id': 'same',
              'day': '2026-09-01',
              'recordedAt': '2026-09-01T08:00:00Z',
              'inches': {'waistNavel': 34},
            },
            {
              'id': 'same',
              'day': '2026-09-02',
              'recordedAt': '2026-09-02T08:00:00Z',
              'inches': {'waistNavel': 33},
            },
          ],
        ),
        body(
          weights: [
            {'id': 'valid', 'date': '2026-09-01', 'value': 70, 'unit': 'kg'},
          ],
          measures: [
            {
              'id': 'empty',
              'day': '2026-09-01',
              'recordedAt': '2026-09-01T08:00:00Z',
              'inches': {},
            },
          ],
        ),
      ];
      for (final input in invalid) {
        await expectLater(planBodyImport(input), throwsA(anything));
        expect(await BodyLogDb.weights(), isEmpty);
        expect(await BodyLogDb.measures(), isEmpty);
      }
    },
  );

  test(
    'regression: missing photo files remain explicit in an empty data plan',
    () async {
      final plan = await planBodyImport(
        body(
          photos: [
            {
              'id': 'missing-photo',
              'day': '2026-09-01',
              'recordedAt': '2026-09-01T08:00:00Z',
            },
          ],
        ),
      );
      expect(plan.missingPhotoFiles.length, 1);
      expect(plan.alreadyHere, 0);
      expect(plan.isEmpty, true);
    },
  );

  test(
    'regression: merged weights use the earliest retained reading',
    () async {
      const date = '2026-09-01';
      await BodyLogDb.putWeight(date, 71, 'kg', at: DateTime(2026, 9, 1, 8));
      final snapshot = await LocalDb.exportCopy();
      await LocalDb.wipeAll();
      await BodyLogDb.putWeight(date, 70, 'kg', at: DateTime(2026, 9, 1, 7));
      await LocalDb.importFromDbFile(snapshot);
      final readings = await BodyLogDb.readingsOn(date);
      expect(readings.length, 2);
      expect(readings.first.kg, 70);
      expect((await BodyLogDb.weightOn(date))!.kg, 70);
      await File(snapshot).delete();
    },
  );

  test(
    'regression: refused unit save stays unchanged and the same choice can retry',
    () async {
      final original = SharedPreferencesStorePlatform.instance;
      final store = _RefusingStore();
      SharedPreferencesStorePlatform.instance = store;
      SharedPreferences.resetStatic();
      addTearDown(() {
        SharedPreferencesStorePlatform.instance = original;
        SharedPreferences.resetStatic();
      });
      final units = UnitsController.withUnits();
      await expectLater(units.setWeightUnit('lb'), throwsStateError);
      expect(units.weightUnit, 'kg');
      expect(store.values, isEmpty);
      store.refuse = false;
      await units.setWeightUnit('lb');
      expect(store.writes, greaterThan(1));
      SharedPreferences.resetStatic();
      final restored = await UnitsController.bootstrap();
      expect(restored.weightUnit, 'lb');
      restored.dispose();
      units.dispose();
    },
  );

  test(
    'regression: refused notification settings report failure without optimistic cache state',
    () async {
      final original = SharedPreferencesStorePlatform.instance;
      final store = _RefusingStore();
      SharedPreferencesStorePlatform.instance = store;
      SharedPreferences.resetStatic();
      addTearDown(() {
        SharedPreferencesStorePlatform.instance = original;
        SharedPreferences.resetStatic();
      });
      await expectLater(
        const NotificationPrefs(
          healthEnabled: false,
          quietEnabled: false,
          deviceEnabled: false,
        ).save(),
        throwsStateError,
      );
      expect(store.values, isEmpty);
      expect((await NotificationPrefs.load()).healthEnabled, true);
      SharedPreferences.resetStatic();
      final fresh = await NotificationPrefs.load();
      expect(fresh.healthEnabled, true);
      expect(fresh.quietEnabled, true);
      expect(fresh.deviceEnabled, true);
    },
  );

  testWidgets(
    'regression: private lift stays in history and out of Progress aggregates',
    (t) async {
      final start = DateTime.now().subtract(const Duration(days: 1));
      await t.runAsync(() async {
        await LocalDb.putSession({
          'id': 'private-lift',
          'type': 'weightlifting',
          'status': 'done',
          'private': 1,
          'start_ts': start.millisecondsSinceEpoch ~/ 1000,
          'end_ts':
              start.add(const Duration(minutes: 20)).millisecondsSinceEpoch ~/
              1000,
          'created_at': 1,
        });
        await LiftLogDb.save(
          LiftWorkout(
            id: 'private-log',
            sessionId: 'private-lift',
            startedAt: start,
            endedAt: start.add(const Duration(minutes: 20)),
            exercises: [
              LiftExercise(
                name: 'Synthetic press',
                loadMode: LiftLoadMode.total,
                sets: [
                  LiftSet(
                    reps: 8,
                    load: 50,
                    completedAt: start.add(const Duration(minutes: 5)),
                  ),
                ],
              ),
            ],
          ),
        );
      });
      final app = AppState.forTesting()..user = {'weight_kg': 70};
      app.repo = LocalRepositoryImpl(getProfileMap: () => app.user);
      late BuildContext context;
      await t.pumpWidget(
        ChangeNotifierProvider.value(
          value: app,
          child: MaterialApp(
            home: Builder(
              builder: (c) {
                context = c;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      final data = await t.runAsync(() => ProgressData.load(context));
      expect(data!.sessions, isEmpty);
      expect(data.lifts, isEmpty);
      expect(
        (await t.runAsync(() => LiftLogDb.finished()))!.single.sessionId,
        'private-lift',
      );
      await t.pumpWidget(const SizedBox());
      app.dispose();
    },
  );

  test(
    'positive control: two valid unique-origin weights keep both timed readings',
    () async {
      final plan = await planBodyImport(
        body(
          weights: [
            {'id': 'one', 'date': '2026-09-01', 'value': 70, 'unit': 'kg'},
            {'id': 'two', 'date': '2026-09-02', 'value': 71, 'unit': 'kg'},
          ],
        ),
      );
      await applyBodyImport(plan, encode: (_) async => []);
      expect((await BodyLogDb.weights()).length, 2);
      expect((await BodyLogDb.readingsOn('2026-09-01')).single.kg, 70);
      expect((await BodyLogDb.readingsOn('2026-09-02')).single.kg, 71);
    },
  );

  void installTokyo() {
    final begin = dayZoneCalendarStart('2026-09-01', 'Asia/Tokyo')!;
    final end = dayZoneCalendarStart('2026-09-03', 'Asia/Tokyo')!;
    DayClock.install(
      [
        DayZone(
          date: '2026-09-01',
          zoneId: 'Asia/Tokyo',
          startSec: begin,
          endSec: end - 86400,
          startOffsetSec: 32400,
          endOffsetSec: 32400,
        ),
        DayZone(
          date: '2026-09-02',
          zoneId: 'Asia/Tokyo',
          startSec: end - 86400,
          endSec: end,
          startOffsetSec: 32400,
          endOffsetSec: 32400,
        ),
      ],
      [ZoneChange(begin, 'Asia/Tokyo')],
    );
  }

  test(
    'regression: historical Food defaults to meal time in the recorded zone',
    () {
      installTokyo();
      final actual = foodEntryTime(
        '2026-09-01',
        'breakfast',
        now: DateTime(2026, 10, 22),
      );
      final expected = DayClock.onDate('2026-09-01', 8, 0);
      expect(actual.millisecondsSinceEpoch, expected.millisecondsSinceEpoch);
      expect(DayClock.localAt(actual.millisecondsSinceEpoch ~/ 1000).hour, 8);
    },
  );

  test(
    'regression: copied Food keeps its clock time on the destination day',
    () {
      installTokyo();
      final source = DayClock.onDate('2026-09-01', 8, 0);
      final entry = FoodEntry(
        id: 'synthetic-food',
        date: '2026-09-01',
        meal: 'breakfast',
        label: 'Synthetic food',
        atTs: source.millisecondsSinceEpoch ~/ 1000,
        kcal: 100,
      );
      final copy = entry.copyTo(
        '2026-09-02',
        'breakfast',
        newId: 'synthetic-copy',
      );
      expect(DayClock.localAt(entry.atTs!).hour, 8);
      expect(dayLabelOf(DayClock.localAt(copy.atTs!)), copy.date);
      expect(copy.date, '2026-09-02');
    },
  );

  test('regression: changing a Food heading preserves the exact instant', () {
    installTokyo();
    final source = DayClock.onDate('2026-09-01', 8, 0);
    final entry = FoodEntry(
      id: 'synthetic-group-food',
      date: '2026-09-01',
      meal: 'breakfast',
      label: 'Synthetic food',
      atTs: source.millisecondsSinceEpoch ~/ 1000,
      kcal: 100,
    );
    final regrouped = entry.inGroup('Synthetic heading');
    expect(regrouped.date, entry.date);
    expect(regrouped.atTs, entry.atTs);
    expect(dayLabelOf(DayClock.localAt(regrouped.atTs!)), regrouped.date);
  });

  testWidgets(
    'regression: Progress counts a travel session on its recorded day',
    (t) async {
      installTokyo();
      final start =
          DayClock.onDate('2026-09-01', 0, 30).millisecondsSinceEpoch ~/ 1000;
      await t.runAsync(
        () => LocalDb.putSession({
          'id': 'travel-session',
          'type': 'walking',
          'status': 'done',
          'private': 0,
          'start_ts': start,
          'end_ts': start + 1200,
          'created_at': 1,
        }),
      );
      final app = AppState.forTesting()..user = {'weight_kg': 70};
      app.repo = LocalRepositoryImpl(getProfileMap: () => app.user);
      late BuildContext context;
      await t.pumpWidget(
        ChangeNotifierProvider.value(
          value: app,
          child: MaterialApp(
            home: Builder(
              builder: (c) {
                context = c;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      final data = await t.runAsync(() => ProgressData.load(context));
      expect(DayClock.at(start)!.date, '2026-09-01');
      expect(data!.sessions.single.date, '2026-09-01');
      expect(data.rolling('2026-09-07').now.workouts.total, 1);
      expect(data.rolling('2026-09-07').was.workouts.total, 0);
      await t.pumpWidget(const SizedBox());
      app.dispose();
    },
  );

  test(
    'regression: Home exit remains pending until its Pushups transition commits',
    () async {
      const channel = MethodChannel('openstrap/home_region');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var drainCalls = 0;
      var pending = true;
      final now = DateTime.now();
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'drain') {
          drainCalls++;
          return pending
              ? [
                  {
                    'id': 'synthetic-exit',
                    'kind': 'exit',
                    'at': now.millisecondsSinceEpoch / 1000,
                  },
                ]
              : [];
        }
        if (call.method == 'ack') pending = false;
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await HomeRegion.setHome((lat: 0, lon: 0, radius: 150));
      await PushupDb.save(
        PushupSession(
          id: 'synthetic-home-day',
          day: dayLabelOf(now),
          started: now.subtract(const Duration(minutes: 20)),
          interval: 30,
          state: PushupState.running,
          anchor: now.add(const Duration(minutes: 10)),
        ),
      );
      await db.execute(
        "CREATE TRIGGER synthetic_pushup_fail BEFORE INSERT ON pushup_session BEGIN SELECT RAISE(ABORT,'synthetic failure'); END",
      );
      try {
        await expectLater(Pushups.reconcile(), throwsA(anything));
        expect((await HomeRegion.automation()).presence, HomePresence.unknown);
        expect((await PushupDb.active())!.state, PushupState.running);
      } finally {
        await db.execute('DROP TRIGGER IF EXISTS synthetic_pushup_fail');
      }
      // Skip any unsupported platform scheduling failures: they occur after the
      // relevant save, and are not the injected fault this diagnostic measures.
      try {
        await Pushups.reconcile();
      } catch (_) {}
      expect(drainCalls, 2);
      expect((await PushupDb.active())!.state, PushupState.paused);
      expect(pending, false);
      expect((await HomeRegion.automation()).presence, HomePresence.outside);
    },
  );

  test(
    'Body import rolls back earlier weights when a later tape write fails',
    () async {
      final plan = await planBodyImport(
        body(
          weights: [
            {'id': 'weight-a', 'date': '2026-09-01', 'value': 70, 'unit': 'kg'},
          ],
          measures: [
            {
              'id': 'measure-a',
              'day': '2026-09-01',
              'recordedAt': '2026-09-01T08:00:00Z',
              'inches': {'waistNavel': 34},
            },
          ],
        ),
      );
      await db.execute(
        "CREATE TRIGGER synthetic_body_fail BEFORE INSERT ON body_measure BEGIN SELECT RAISE(ABORT,'synthetic write refusal'); END",
      );
      try {
        await expectLater(
          applyBodyImport(plan, encode: (_) async => []),
          throwsA(anything),
        );
        expect(await BodyLogDb.weights(), isEmpty);
        expect(await BodyLogDb.readingsOn('2026-09-01'), isEmpty);
        expect(await BodyLogDb.measures(), isEmpty);
      } finally {
        await db.execute('DROP TRIGGER synthetic_body_fail');
      }
      expect(await applyBodyImport(plan, encode: (_) async => []), 2);
    },
  );

  test(
    'Home event replay after automation failure does not duplicate the committed transition',
    () async {
      const channel = MethodChannel('openstrap/home_region');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final original = SharedPreferencesStorePlatform.instance;
      final store = _RefusingStore()..refuse = false;
      SharedPreferencesStorePlatform.instance = store;
      SharedPreferences.resetStatic();
      var pending = true;
      final now = DateTime.now();
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'drain')
          return pending
              ? [
                  {
                    'id': 'replayed-exit',
                    'kind': 'exit',
                    'at': now.millisecondsSinceEpoch / 1000,
                  },
                ]
              : [];
        if (call.method == 'ack') pending = false;
        return null;
      });
      try {
        await HomeRegion.setHome((lat: 0, lon: 0, radius: 150));
        await PushupDb.save(
          PushupSession(
            id: 'replay-day',
            day: todayLabel(),
            started: now.subtract(const Duration(minutes: 10)),
            interval: 30,
            state: PushupState.running,
          ),
        );
        store.refuse = true;
        await expectLater(Pushups.reconcile(), throwsStateError);
        expect(pending, true);
        expect((await PushupDb.active())!.state, PushupState.paused);
        expect((await PushupDb.active())!.events, hasLength(1));
        store.refuse = false;
        try {
          await Pushups.reconcile();
        } catch (_) {}
        expect(pending, false);
        expect((await PushupDb.active())!.events, hasLength(1));
        expect((await HomeRegion.automation()).presence, HomePresence.outside);
      } finally {
        messenger.setMockMethodCallHandler(channel, null);
        SharedPreferencesStorePlatform.instance = original;
        SharedPreferences.resetStatic();
      }
    },
  );

  test(
    'thrown preference write retains units and supports a durable retry',
    () async {
      final original = SharedPreferencesStorePlatform.instance;
      final store = _RefusingStore()
        ..refuse = false
        ..throwAtWrite = 1;
      SharedPreferencesStorePlatform.instance = store;
      SharedPreferences.resetStatic();
      final units = UnitsController.withUnits();
      try {
        await expectLater(units.setWeightUnit('lb'), throwsStateError);
        expect(units.weightUnit, 'kg');
        await units.setWeightUnit('lb');
        SharedPreferences.resetStatic();
        final restored = await UnitsController.bootstrap();
        expect(restored.weightUnit, 'lb');
        restored.dispose();
      } finally {
        units.dispose();
        SharedPreferencesStorePlatform.instance = original;
        SharedPreferences.resetStatic();
      }
    },
  );

  test(
    'rapid unit changes persist in request order across a cold reload',
    () async {
      final original = SharedPreferencesStorePlatform.instance;
      final store = _RefusingStore()..refuse = false;
      SharedPreferencesStorePlatform.instance = store;
      SharedPreferences.resetStatic();
      final units = UnitsController.withUnits();
      try {
        await Future.wait([
          units.setWeightUnit('lb'),
          units.setWeightUnit('kg'),
          units.setDistanceUnit('mi'),
        ]);
        expect(units.weightUnit, 'kg');
        expect(units.distanceUnit, 'mi');
        SharedPreferences.resetStatic();
        final restored = await UnitsController.bootstrap();
        expect(restored.weightUnit, 'kg');
        expect(restored.distanceUnit, 'mi');
        restored.dispose();
      } finally {
        units.dispose();
        SharedPreferencesStorePlatform.instance = original;
        SharedPreferences.resetStatic();
      }
    },
  );

  test(
    'partial notification preference failure restores all earlier keys',
    () async {
      final original = SharedPreferencesStorePlatform.instance;
      final store = _RefusingStore()..refuse = false;
      SharedPreferencesStorePlatform.instance = store;
      SharedPreferences.resetStatic();
      try {
        await const NotificationPrefs().save();
        store.throwAtWrite = store.writes + 3;
        await expectLater(
          const NotificationPrefs(
            healthEnabled: false,
            recoveryEnabled: false,
            deviceEnabled: false,
            quietEnabled: false,
          ).save(),
          throwsStateError,
        );
        SharedPreferences.resetStatic();
        final restored = await NotificationPrefs.load();
        expect(restored.healthEnabled, true);
        expect(restored.recoveryEnabled, true);
        expect(restored.deviceEnabled, true);
        expect(restored.quietEnabled, true);
      } finally {
        SharedPreferencesStorePlatform.instance = original;
        SharedPreferences.resetStatic();
      }
    },
  );

  for (final gen5 in [false, true]) {
    test(
      'buzz command keeps transport failure and success for gen5=$gen5',
      () async {
        final engine = BleEngine(onRecord: (_, _) async {}, onState: (_) {});
        var succeeds = false;
        var throwsOnWrite = false;
        engine.debugInstallFakeLink(
          band: gen5 ? BandProfile.gen5 : BandProfile.gen4,
          onWrite: (_) async {
            if (throwsOnWrite) throw StateError('Synthetic transport refusal');
            return succeeds;
          },
        );
        final app = AppState.forTesting(engine: engine);
        app.device.connection = 'connected';
        try {
          expect(await app.buzzBand(), false);
          succeeds = true;
          expect(await app.buzzBand(), true);
          throwsOnWrite = true;
          expect(await app.buzzBand(), false);
        } finally {
          app.dispose();
        }
      },
    );
  }

  test(
    'Find my band does not claim a command was sent while disconnected',
    () async {
      final app = AppState.forTesting();
      try {
        expect(await app.buzzBand(), false);
      } finally {
        app.dispose();
      }
    },
  );

  test(
    'calculation cache refusal cannot undo a committed configuration import',
    () async {
      final original = SharedPreferencesStorePlatform.instance;
      SharedPreferencesStorePlatform.instance = _RefusingStore();
      SharedPreferences.resetStatic();
      try {
        await CalculationStore.write('synthetic.config', 'saved');
        expect(
          (await LocalDb.baseline(
            'calculation:synthetic.config',
          ))!['payload_json'],
          'saved',
        );
        expect(await CalculationStore.read('synthetic.config'), 'saved');
      } finally {
        SharedPreferencesStorePlatform.instance = original;
        SharedPreferences.resetStatic();
      }
    },
  );

  test(
    'live draft surfaces a refused save and retries the latest entries',
    () async {
      final original = SharedPreferencesStorePlatform.instance;
      final store = _RefusingStore();
      SharedPreferencesStorePlatform.instance = store;
      SharedPreferences.resetStatic();
      await Prefs.ensureLoaded();
      try {
        final draft = LiveDraft.begin(storedActivity('swimming'));
        draft.put('synthetic-note', 'Retain this draft');
        await LiveDraft.retrySave();
        expect(LiveDraft.saveError.value, isNotNull);
        store.refuse = false;
        await LiveDraft.retrySave();
        expect(LiveDraft.saveError.value, isNull);
        LiveDraft.debugForget();
        expect(LiveDraft.current!.data['synthetic-note'], 'Retain this draft');
        LiveDraft.clear();
        await LiveDraft.retrySave();
        LiveDraft.debugForget();
        expect(LiveDraft.current, isNull);
      } finally {
        SharedPreferencesStorePlatform.instance = original;
        SharedPreferences.resetStatic();
        LiveDraft.debugForget();
      }
    },
  );

  for (final kind in ['body', 'lift', 'pushups']) {
    testWidgets('Data import exposes $kind missing-media/config-only result', (
      t,
    ) async {
      t.view.physicalSize = const Size(700, 1200);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final file = File('${tmp.path}/synthetic-$kind.json');
      await t.runAsync(
        () => file.writeAsString(
          kind == 'body'
              ? body(
                  photos: [
                    {
                      'id': 'absent',
                      'day': '2026-09-01',
                      'recordedAt': '2026-09-01T08:00:00Z',
                    },
                  ],
                )
              : kind == 'lift'
              ? jsonEncode({
                  'version': 1,
                  'workouts': [],
                  'splits': [
                    LiftSplit(
                      id: 'synthetic-split',
                      name: 'Synthetic split',
                    ).toJson(),
                  ],
                })
              : jsonEncode({
                  'version': 1,
                  'sessions': [],
                  'settings': {'interval': 45, 'goal': 3},
                }),
        ),
      );
      FilePicker.platform = _Picker(file);
      final app = AppState.forTesting();
      addTearDown(app.dispose);
      await t.pumpWidget(
        ChangeNotifierProvider.value(
          value: app,
          child: MaterialApp(
            theme: buildTheme(Brightness.light),
            home: const DataScreen(),
          ),
        ),
      );
      await settle(t);
      final label = kind == 'body'
          ? 'Import body history'
          : kind == 'lift'
          ? 'Import from AkshatOS'
          : 'Import Pushups from AkshatOS';
      await t.scrollUntilVisible(
        find.text(label),
        350,
        scrollable: find.byType(Scrollable).first,
      );
      await settle(t);
      await t.ensureVisible(find.text(label));
      await t.pumpAndSettle();
      await t.tap(find.text(label));
      await settle(t);
      if (kind == 'body') {
        expect(
          find.textContaining('photo files were not selected'),
          findsOneWidget,
        );
        expect(find.textContaining('Nothing new:'), findsNothing);
      } else {
        expect(
          find.text(
            kind == 'lift' ? 'Use its splits too?' : 'Use its settings too?',
          ),
          findsOneWidget,
        );
        await t.tap(find.text('Use them'));
        await settle(t);
        expect(
          find.textContaining(
            kind == 'lift' ? 'Splits saved.' : 'Settings saved.',
          ),
          findsOneWidget,
        );
        if (kind == 'lift') {
          expect(
            (await t.runAsync(() => LiftLogDb.splits()))!.single.name,
            'Synthetic split',
          );
        } else {
          expect(await t.runAsync(() => PushupDb.goal()), 3);
        }
      }
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
  }

  Finder field(String label) => find.descendant(
    of: find.byWidgetPredicate((w) => w is OsTextField && w.label == label),
    matching: find.byType(TextField),
  );

  testWidgets(
    'regression: finished-set editor keeps invalid drafts and saves on correction',
    (t) async {
      t.view.physicalSize = const Size(700, 1200);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final start = DateTime.now().subtract(const Duration(hours: 2));
      await t.runAsync(
        () => LiftLogDb.save(
          LiftWorkout(
            id: 'edit-log',
            sessionId: 'edit-session',
            startedAt: start,
            endedAt: start.add(const Duration(minutes: 20)),
            exercises: [
              LiftExercise(
                name: 'Synthetic press',
                loadMode: LiftLoadMode.total,
                sets: [
                  LiftSet(
                    reps: 8,
                    load: 50,
                    completedAt: start.add(const Duration(minutes: 5)),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
      await t.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light),
          home: const Scaffold(
            body: SingleChildScrollView(
              child: LiftSummaryCard(sessionId: 'edit-session'),
            ),
          ),
        ),
      );
      await settle(t);
      final set = find.byWidgetPredicate(
        (w) => w is Pressable && (w.semanticLabel?.endsWith('. Fix') ?? false),
      );
      expect(set, findsOneWidget);
      await t.tap(set);
      await settle(t);
      await t.enterText(field('lb total'), '60');
      await t.enterText(field('Reps'), 'bad');
      await t.tap(find.widgetWithText(BigButton, 'Save'));
      await settle(t);
      expect(find.text('Fix set'), findsOneWidget);
      expect(
        find.text('Enter a valid weight and repetitions.'),
        findsOneWidget,
      );
      expect(t.widget<TextField>(field('lb total')).controller!.text, '60');
      expect(t.widget<TextField>(field('Reps')).controller!.text, 'bad');
      await t.enterText(field('Reps'), '9');
      await t.tap(find.widgetWithText(BigButton, 'Save'));
      await settle(t);
      expect(find.text('Fix set'), findsNothing);
      final saved = await t.runAsync(
        () => LiftLogDb.forSession('edit-session'),
      );
      expect(saved!.exercises.single.sets.single.load, 60);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'regression: diary editor retains the portion after failure and can retry',
    (t) async {
      t.view.physicalSize = const Size(700, 1200);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final app = AppState.forTesting()
        ..user = {'weight_kg': 70, 'kcal_target': 2300};
      addTearDown(app.dispose);
      final def = myFoodDef(
        key: 'synthetic-quantity',
        label: 'Synthetic quantity food',
        refGrams: 100,
        unit: 'g',
        kcal: 200,
      );
      const entry = FoodEntry(
        id: 'quantity-entry',
        date: '2026-09-01',
        meal: 'breakfast',
        label: 'Synthetic quantity food',
        foodKey: 'synthetic-quantity',
        quantity: 100,
        unit: 'g',
        kcal: 200,
        confirmed: true,
      );
      await t.runAsync(() async {
        await NutritionDb.putFoodDef(db, def);
        await NutritionDb.put(db, entry);
        await db.execute(
          "CREATE TRIGGER synthetic_quantity_fail BEFORE INSERT ON food_entry BEGIN SELECT RAISE(ABORT,'synthetic failure'); END",
        );
      });
      addTearDown(
        () => db.execute('DROP TRIGGER IF EXISTS synthetic_quantity_fail'),
      );
      await t.pumpWidget(
        ChangeNotifierProvider.value(
          value: app,
          child: MaterialApp(
            theme: buildTheme(Brightness.light),
            home: Builder(
              builder: (c) => Scaffold(
                body: TextButton(
                  onPressed: () => editDiaryEntry(c, entry),
                  child: const Text('Edit portion'),
                ),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('Edit portion'));
      await settle(t);
      final amount = find.byType(TextField).first;
      await t.enterText(amount, '150');
      await t.tap(find.widgetWithText(BigButton, 'Save'));
      await settle(t);
      expect(find.textContaining('Could not save'), findsOneWidget);
      expect(find.byType(TextField), findsWidgets);
      expect(
        t.widget<TextField>(find.byType(TextField).first).controller!.text,
        '150',
      );
      await t.runAsync(
        () => db.execute('DROP TRIGGER synthetic_quantity_fail'),
      );
      await t.tap(find.widgetWithText(BigButton, 'Save'));
      await settle(t);
      expect(find.byType(TextField), findsNothing);
      final entries = await t.runAsync(
        () => NutritionDb.entriesForDay(db, '2026-09-01'),
      );
      expect(entries!.single.quantity, 150);
      await t.pumpWidget(const SizedBox());
    },
  );
}
