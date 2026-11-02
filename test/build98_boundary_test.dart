// Build 98 import, privacy and persistence regressions. Synthetic inputs only.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/body_log.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/lift_log.dart';
import 'package:whoop_companion/data/pushups.dart';
import 'package:whoop_companion/data/nutrition_store.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/gps/run_history.dart';
import 'package:whoop_companion/gps/route_models.dart';
import 'package:whoop_companion/gps/workout_clock.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/state/prefs.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  final start = DateTime.utc(2026, 9, 1, 8);
  double apple(DateTime d) => d.millisecondsSinceEpoch / 1000 - 978307200;
  Map<String, Object?> lift({
    String id = 'synthetic-lift',
    String setId = 'set-a',
    num reps = 8,
    String notes = '',
    bool duplicateSet = false,
    bool duplicateExercise = false,
  }) {
    final exercise = <String, Object?>{
      'id': 'exercise-a',
      'name': 'Synthetic press',
      'loadMode': 'total',
      'sets': [
        {
          'id': setId,
          'reps': reps,
          'load': 20,
          'completedAt': apple(start.add(const Duration(minutes: 5))),
        },
        if (duplicateSet)
          {
            'id': setId,
            'reps': 9,
            'load': 21,
            'completedAt': apple(start.add(const Duration(minutes: 6))),
          },
      ],
    };
    return {
      'id': id,
      'startedAt': apple(start),
      'endedAt': apple(start.add(const Duration(hours: 1))),
      'notes': notes,
      'exercises': [
        exercise,
        if (duplicateExercise) {...exercise, 'name': 'Another press'},
      ],
    };
  }

  String liftFile(List<Object?> workouts, {List<Object?>? splits}) =>
      jsonEncode({
        'version': 1,
        'workouts': workouts,
        if (splits != null) 'splits': splits,
      });
  PushupSession pushup(
    String id, {
    String day = '2026-09-01',
    bool duplicateEvent = false,
  }) => PushupSession(
    id: id,
    day: day,
    started: start,
    ended: start.add(const Duration(hours: 8)),
    interval: 45,
    goal: 2,
    state: PushupState.ended,
    events: [
      PushupEvent(
        id: 'event-a',
        at: start.add(const Duration(minutes: 1)),
        kind: PushupEventKind.done,
      ),
      if (duplicateEvent)
        PushupEvent(
          id: 'event-a',
          at: start.add(const Duration(minutes: 1)),
          kind: PushupEventKind.done,
        ),
    ],
  );
  String pushupFile(List<PushupSession> sessions) => jsonEncode({
    'version': 1,
    'settings': {'interval': 45, 'goal': 2},
    'sessions': [for (final s in sessions) s.toJson()],
  });
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final root = Directory(
      'build/research-local/build98-boundary-files',
    ).absolute;
    await root.create(recursive: true);
    PathProviderPlatform.instance = _Paths(root.path);
    LocalDb.dbName = p.join(root.path, 'synthetic.sqlite');
    await LocalDb.close();
    await databaseFactory.deleteDatabase(LocalDb.dbName);
    db = await LocalDb.instance;
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.ensureLoaded();
    await LocalDb.wipeAll();
    DayClock.install([], []);
  });
  tearDown(() async {
    for (final row in await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='trigger' AND name LIKE 'synthetic_%'",
    )) {
      final name = row['name'] as String;
      await db.execute('DROP TRIGGER "${name.replaceAll('"', '""')}"');
    }
    DayClock.install([], []);
  });
  tearDownAll(() async {
    await LocalDb.close();
    await databaseFactory.deleteDatabase(LocalDb.dbName);
  });

  test(
    'CONTROL: valid Lift import is durable and repeat preview is unchanged',
    () async {
      final input = liftFile([lift()]);
      final plan = await planLiftImport(input);
      expect(await applyLiftImport(plan), 1);
      expect((await LiftLogDb.finished()).single.setCount, 1);
      expect((await planLiftImport(input)).unchanged, 1);
    },
  );
  test(
    'malformed nested Lift identities and fractional reps are rejected',
    () async {
      for (final input in [
        lift(duplicateSet: true),
        lift(duplicateExercise: true),
        lift(reps: 8.9),
      ]) {
        await expectLater(planLiftImport(liftFile([input])), throwsA(anything));
        expect(await LiftLogDb.finished(), isEmpty);
      }
    },
  );
  test(
    'regression: changed Lift notes and timing are reported as conflicts',
    () async {
      await applyLiftImport(await planLiftImport(liftFile([lift()])));
      final updated = lift(notes: 'A new synthetic setup note');
      updated['startedAt'] = apple(start.subtract(const Duration(hours: 2)));
      final plan = await planLiftImport(liftFile([updated]));
      expect(plan.unchanged, 0);
      expect(plan.conflicts, hasLength(1));
      expect((await LiftLogDb.finished()).single.notes, isEmpty);
    },
  );
  test(
    'regression: Lift config and workouts roll back together and config-only retries work',
    () async {
      final splits = [
        LiftSplit(id: 'split-a', name: 'Synthetic split').toJson(),
      ];
      final input = liftFile([lift()], splits: splits);
      final plan = await planLiftImport(input);
      await db.execute(
        "CREATE TRIGGER synthetic_split_fail BEFORE INSERT ON baselines WHEN NEW.key='calculation:${LiftLogDb.splitsKey}' BEGIN SELECT RAISE(ABORT,'synthetic split write refusal'); END",
      );
      await expectLater(
        applyLiftImport(plan, replaceSplits: true),
        throwsA(anything),
      );
      expect(await LiftLogDb.finished(), isEmpty);
      await db.execute('DROP TRIGGER synthetic_split_fail');
      final retry = await planLiftImport(input);
      expect(retry.add, hasLength(1));
      expect(await applyLiftImport(retry, replaceSplits: true), 1);
      // Configuration-only apply remains available even when all workouts exist.
      final onlyConfig = await planLiftImport(input);
      expect(onlyConfig.add, isEmpty);
      expect(await applyLiftImport(onlyConfig, replaceSplits: true), 0);
      expect((await LiftLogDb.splits()).single.name, 'Synthetic split');
    },
  );
  test(
    'regression: stale Lift preview preserves newer data and reports zero additions',
    () async {
      final plan = await planLiftImport(liftFile([lift()]));
      await LiftLogDb.save(
        plan.add.single.copy()..notes = 'Locally created after preview',
      );
      expect(await applyLiftImport(plan), 0);
      expect(
        (await LiftLogDb.finished()).single.notes,
        'Locally created after preview',
      );
    },
  );
  test(
    'CONTROL: valid Pushups import stays ended and repeat preview is unchanged',
    () async {
      final input = pushupFile([pushup('day-a')]);
      expect(await applyPushupImport(await planPushupImport(input)), 1);
      expect(await PushupDb.active(), isNull);
      expect((await planPushupImport(input)).unchanged, 1);
    },
  );
  test(
    'duplicate Pushups event ids and impossible dates fail preflight',
    () async {
      for (final input in [
        pushupFile([pushup('day-a', duplicateEvent: true)]),
        pushupFile([pushup('day-a', day: '2026-02-31')]),
      ]) {
        await expectLater(planPushupImport(input), throwsA(anything));
        expect(await PushupDb.all(), isEmpty);
      }
    },
  );
  test('regression: stale Pushups preview preserves the newer row', () async {
    final plan = await planPushupImport(pushupFile([pushup('day-a')]));
    final newer = pushup('day-a')..state = PushupState.running;
    await PushupDb.save(newer);
    expect(await applyPushupImport(plan), 0);
    expect((await PushupDb.all()).single.state, PushupState.running);
    expect(await PushupDb.active(), isNotNull);
  });
  test('regression: Pushups import rolls back when a later day fails', () async {
    final a = pushup('day-a', day: '2026-09-01'),
        b = pushup('day-b', day: '2026-09-02');
    final plan = await planPushupImport(pushupFile([a, b]));
    final second = plan.add[1].id;
    await db.execute(
      "CREATE TRIGGER synthetic_pushup_fail BEFORE INSERT ON pushup_session WHEN NEW.id='$second' BEGIN SELECT RAISE(ABORT,'synthetic second-day refusal'); END",
    );
    await expectLater(applyPushupImport(plan), throwsA(anything));
    expect(await PushupDb.all(), isEmpty);
  });
  test('CONTROL: day copy is atomic when its second food write fails', () async {
    FoodEntry entry(String id, String label) => FoodEntry(
      id: id,
      date: '2026-09-01',
      atTs: start.millisecondsSinceEpoch ~/ 1000,
      meal: 'breakfast',
      label: label,
      kcal: 100,
    );
    await db.execute(
      "CREATE TRIGGER synthetic_food_fail BEFORE INSERT ON food_entry WHEN NEW.label='Second' BEGIN SELECT RAISE(ABORT,'synthetic second-food refusal'); END",
    );
    await expectLater(
      NutritionDb.logDayCopy(
        db,
        date: '2026-09-02',
        reviewed: [entry('first', 'First'), entry('second', 'Second')],
      ),
      throwsA(anything),
    );
    expect(await NutritionDb.entriesForDay(db, '2026-09-02'), isEmpty);
  });
  test(
    'CONTROL: removing first weight reading promotes the next reading',
    () async {
      await BodyLogDb.putWeight(
        '2026-09-01',
        70,
        'kg',
        at: start,
        historyOnly: true,
      );
      await BodyLogDb.putWeight(
        '2026-09-01',
        71,
        'kg',
        at: start.add(const Duration(hours: 1)),
        historyOnly: true,
      );
      final readings = await BodyLogDb.readingsOn('2026-09-01');
      await BodyLogDb.deleteReading(readings.first.id);
      expect((await BodyLogDb.weightOn('2026-09-01'))!.kg, 71);
    },
  );
  test(
    'regression: private run stays out of aggregate inputs and contributes real maintenance movement',
    () async {
      const id = 'synthetic-private-run';
      final now = DateTime.now().subtract(const Duration(hours: 2));
      final begin = now.millisecondsSinceEpoch ~/ 1000;
      await LocalDb.putSession({
        'id': id,
        'start_ts': begin,
        'end_ts': begin + 1200,
        'status': 'done',
        'type': 'running',
        'private': 1,
        'created_at': begin,
      });
      final points = [
        for (var i = 0; i <= 120; i++)
          RoutePoint(
            seq: i,
            tsMs: (begin + i * 10) * 1000,
            lat: 1 + i * 0.00027,
            lng: 2,
          ),
      ];
      await LocalDb.appendRoutePoints(id, [
        for (final point in points) point.toRow(id),
      ]);
      final repo = LocalRepositoryImpl(getProfileMap: () => null);
      final history = await repo.getWorkouts(range: 'all');
      expect((history['summary'] as Map)['count'], 0);
      runsChanged();
      final runs = await loadRuns(repo, includePrivate: false);
      expect(runs, isEmpty);
      // Privacy hides aggregate results, not real movement from maintenance.
      expect((await loadRuns(repo)).single.meters, greaterThan(0));
      runsChanged();
    },
  );
  test(
    'regression: partial database import publishes committed rows and can resume',
    () async {
      final entry = FoodEntry(
        id: 'synthetic-merge-food',
        date: '2026-09-01',
        meal: 'breakfast',
        label: 'Synthetic merge food',
        kcal: 100,
      );
      await NutritionDb.put(db, entry);
      await BodyLogDb.putWeight(
        '2026-09-01',
        70,
        'kg',
        at: start,
        historyOnly: true,
      );
      final snapshot = await LocalDb.exportCopy();
      final app = AppState.forTesting()
        ..repo = LocalRepositoryImpl(getProfileMap: () => null);
      try {
        await LocalDb.wipeAll();
        final before = app.insightsRevision.value,
            foodBefore = NutritionDb.revision.value;
        await db.execute(
          "CREATE TRIGGER synthetic_restore_fail BEFORE INSERT ON body_weight_reading BEGIN SELECT RAISE(ABORT,'synthetic later-table refusal'); END",
        );
        await expectLater(app.importEdgeBackup(snapshot), throwsA(anything));
        expect((await NutritionDb.entriesForDay(db, '2026-09-01')).length, 1);
        expect(await BodyLogDb.readingsOn('2026-09-01'), isEmpty);
        expect(app.insightsRevision.value, greaterThan(before));
        expect(NutritionDb.revision.value, greaterThan(foodBefore));
        expect(app.lastImportRecords, greaterThan(0));
        expect(await BodyLogDb.weights(), isEmpty);
        await db.execute('DROP TRIGGER synthetic_restore_fail');
        await app.importEdgeBackup(snapshot);
        expect((await BodyLogDb.weightOn('2026-09-01'))!.kg, 70);
      } finally {
        app.dispose();
        await File(snapshot).delete();
      }
    },
  );
  test(
    'regression: failed pause shows an error and retry restores the original pause instant',
    () async {
      const id = 'synthetic-pause-failure';
      final c = WorkoutClock(id, start, profile: const Profile(weightKg: 70));
      WorkoutClock.current = c;
      try {
        await c.persist();
        await db.execute(
          "CREATE TRIGGER synthetic_pause_fail BEFORE INSERT ON baselines WHEN NEW.key='calculation:workout.clock.$id' BEGIN SELECT RAISE(ABORT,'synthetic pause save refusal'); END",
        );
        c.setPaused(true, start.add(const Duration(minutes: 5)));
        try {
          await WorkoutClock.flushWrites();
        } catch (_) {}
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(c.pausedAt, isNotNull);
        expect(WorkoutClock.saveError.value, isNotNull);
        await db.execute('DROP TRIGGER synthetic_pause_fail');
        await WorkoutClock.retryPending();
        expect(WorkoutClock.saveError.value, isNull);
        WorkoutClock.current = null;
        final cold = WorkoutClock.read(id, start);
        expect(
          cold.pausedAt!.millisecondsSinceEpoch,
          c.pausedAt!.millisecondsSinceEpoch,
        );
        expect(cold.activeSeconds(start.add(const Duration(minutes: 10))), 300);
        expect(c.activeSeconds(start.add(const Duration(minutes: 10))), 300);
      } finally {
        WorkoutClock.current = null;
      }
    },
  );
  test(
    'CONTROL: Lift preflight rejects active, backwards, duplicate and invalid-mode records',
    () async {
      final active = lift()..remove('endedAt');
      final backwards = lift()
        ..['endedAt'] = apple(start.subtract(const Duration(minutes: 1)));
      final mode = lift();
      ((mode['exercises'] as List).first as Map)['loadMode'] = 'not-a-mode';
      final blank = lift();
      ((blank['exercises'] as List).first as Map)['name'] = '  ';
      for (final input in [
        liftFile([active]),
        liftFile([backwards]),
        liftFile([lift(), lift()]),
        liftFile([mode]),
        liftFile([blank]),
      ]) {
        await expectLater(planLiftImport(input), throwsA(anything));
      }
      expect(await LiftLogDb.finished(), isEmpty);
    },
  );
  test(
    'regression: imported set bounds and split load meanings are validated',
    () async {
      final bad = lift();
      final exercise = (bad['exercises'] as List).first as Map;
      ((exercise['sets'] as List).first as Map)['completedAt'] = apple(
        start.add(const Duration(hours: 4)),
      );
      await expectLater(planLiftImport(liftFile([bad])), throwsA(anything));
      await expectLater(
        planLiftImport(
          liftFile(
            [lift()],
            splits: [
              {
                'id': 'split-a',
                'name': 'Synthetic split',
                'exercises': [
                  {
                    'id': 'split-ex-a',
                    'name': 'Synthetic press',
                    'loadMode': 'not-a-mode',
                  },
                ],
              },
            ],
          ),
        ),
        throwsA(anything),
      );
    },
  );
  test(
    'CONTROL: Pushups preflight rejects active, duplicate and invalid settings',
    () async {
      final active = pushup('active')..state = PushupState.running;
      await expectLater(
        planPushupImport(pushupFile([active])),
        throwsA(anything),
      );
      await expectLater(
        planPushupImport(pushupFile([pushup('same'), pushup('same')])),
        throwsA(anything),
      );
      final input = jsonDecode(pushupFile([pushup('day-a')])) as Map;
      (input['settings'] as Map)['interval'] = 0;
      await expectLater(planPushupImport(jsonEncode(input)), throwsA(anything));
      expect(await PushupDb.all(), isEmpty);
    },
  );
  test(
    'regression: Pushups end bounds, historical goal and event timing are validated',
    () async {
      final inputs = <Map>[];
      final backwards = pushup('backwards').toJson();
      backwards['ended'] = apple(start.subtract(const Duration(hours: 1)));
      inputs.add(backwards);
      final missingEnd = pushup('missing-end').toJson()..remove('ended');
      inputs.add(missingEnd);
      final outside = pushup('outside-event').toJson();
      ((outside['events'] as List).first as Map)['date'] = apple(
        start.add(const Duration(days: 2)),
      );
      inputs.add(outside);
      final badGoal = pushup('bad-goal').toJson()..['goal'] = -10;
      inputs.add(badGoal);
      for (final input in inputs) {
        await expectLater(
          planPushupImport(
            jsonEncode({
              'version': 1,
              'settings': {'interval': 45, 'goal': 2},
              'sessions': [input],
            }),
          ),
          throwsA(anything),
        );
      }
    },
  );
}
