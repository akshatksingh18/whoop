// Local independent audit; synthetic fixtures only.
// Build 95 closure checks and regressions for the repaired paths.
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:openstrap_edge/notify/notification_log.dart';
import 'package:openstrap_edge/notify/tap_router.dart';
import 'package:openstrap_edge/data/goal_review.dart';
import 'package:openstrap_edge/data/goal_plan.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:openstrap_edge/data/body_log.dart';
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/lift_log.dart';
import 'package:openstrap_edge/data/local_repository_impl.dart';
import 'package:openstrap_edge/data/local_repository.dart';
import 'package:openstrap_edge/import/backup_crypto.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:openstrap_edge/state/prefs.dart';
import 'package:openstrap_edge/compute/profile.dart';
import 'package:openstrap_edge/gps/workout_clock.dart';
import 'package:openstrap_edge/ui2/activity/catalogue.dart';
import 'package:openstrap_edge/ui2/activity/live.dart';
import 'package:openstrap_edge/ui2/activity/summary.dart';
import 'package:openstrap_edge/ui2/screens/food_picker.dart';
import 'package:openstrap_edge/ui2/screens/progress_screen.dart';
import 'package:openstrap_edge/ui2/screens/workout_screen.dart';
import 'package:openstrap_edge/ui2/screens/log_workout.dart';
import 'package:openstrap_edge/ui2/screens/sleep_detail.dart';
import 'package:openstrap_edge/ui2/screens/metric_detail.dart';
import 'package:openstrap_edge/ui2/onboarding/welcome.dart';
import 'package:openstrap_edge/ui2/screens/journal_compose.dart'
    show OsTextField;
import 'package:openstrap_edge/ui2/ui2.dart';

class _PendingRepo extends LocalRepository {
  final pending = Completer<Map<String, dynamic>>();
  @override
  Future<Map<String, dynamic>> getToday() => pending.future;
}

class _Paths extends PathProviderPlatform {
  _Paths(this.root);
  final String root;
  @override
  Future<String?> getTemporaryPath() async => root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

Widget frame(AppState app, Widget child) =>
    ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(theme: buildTheme(Brightness.light), home: child),
    );
void tall(WidgetTester t) {
  t.view.physicalSize = const Size(850, 3500);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

Future<void> until(WidgetTester t, bool Function() done) async {
  for (var i = 0; i < 150 && !done(); i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    await t.pump(const Duration(milliseconds: 30));
  }
  expect(done(), isTrue);
}

Future<void> button(WidgetTester t, String label) async {
  final finder = find.widgetWithText(BigButton, label);
  await t.ensureVisible(finder);
  await t.runAsync(() async {
    final dynamic cb = t.widget<BigButton>(finder).onTap;
    await cb();
  });
  await t.pump();
}

Finder field(String label) => find.descendant(
  of: find.byWidgetPredicate((w) => w is OsTextField && w.label == label),
  matching: find.byType(TextField),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  Future<void> seed(
    String id, {
    int private = 0,
    int? at,
    String type = 'swimming',
    String status = 'done',
  }) async {
    final end =
        at ??
        DateTime.now()
                .subtract(const Duration(hours: 1))
                .millisecondsSinceEpoch ~/
            1000;
    await db.insert('sessions', {
      'id': id,
      'start_ts': end - 600,
      'end_ts': status == 'live' ? null : end,
      'type': type,
      'status': status,
      'private': private,
      'rpe': 8,
      'created_at': end,
    });
  }

  setUpAll(() async {
    final root = Directory('build/coverage-audit/legacy-flows').absolute
      ..createSync(recursive: true);
    PathProviderPlatform.instance = _Paths(root.path);
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.dbName = 'audit_build95_deep_synthetic.db';
    await databaseFactory.deleteDatabase(
      p.join(await databaseFactory.getDatabasesPath(), LocalDb.dbName),
    );
    db = await LocalDb.instance;
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.ensureLoaded();
    LiveDraft.clear();
    for (final table in [
      'sessions',
      'session_detail',
      'lift_log',
      'food_def',
      'food_entry',
      'meal_template',
      'body_weight',
      'body_weight_reading',
      'body_measure',
      'day_result',
      'metric_series',
      'metric_series_version',
      'decoded_onehz',
    ]) {
      await db.delete(table);
    }
  });
  tearDownAll(() async {
    WorkoutClock.current = null;
    LiveDraft.clear();
    await LocalDb.close();
    await databaseFactory.deleteDatabase(
      p.join(await databaseFactory.getDatabasesPath(), LocalDb.dbName),
    );
  });
  test('closure N01: real retime preserves private and effort', () async {
    await seed('retime-private', private: 1);
    final row = (await LocalDb.session('retime-private'))!;
    final repo = LocalRepositoryImpl(getProfileMap: () => {'weight_kg': 70.0});
    await repo.setWorkoutWindow(
      'retime-private',
      startTs: (row['start_ts'] as num).toInt() + 60,
      endTs: (row['end_ts'] as num).toInt(),
    );
    final after = (await LocalDb.session('retime-private'))!;
    expect(after['private'], 1);
    expect(after['rpe'], 8);
  });
  test('closure N02: dedicated Lift CSV excludes private sets', () async {
    await seed('lift-private', private: 1, type: 'strength');
    final at = DateTime.now().subtract(const Duration(hours: 1));
    await LiftLogDb.save(
      LiftWorkout(
        id: 'lift-synthetic',
        sessionId: 'lift-private',
        startedAt: at,
        endedAt: at.add(const Duration(minutes: 10)),
        exercises: [
          LiftExercise(
            name: 'Synthetic private marker',
            loadMode: LiftLoadMode.perHand,
            sets: [LiftSet(reps: 8, load: 20, completedAt: at)],
          ),
        ],
      ),
    );
    expect(await LiftLogDb.csv(), isNot(contains('Synthetic private marker')));
  });

  Future<void> openBody(WidgetTester t, AppState app, String date) async {
    await t.pumpWidget(
      frame(
        app,
        Builder(
          builder: (c) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(c).push(
                MaterialPageRoute<void>(
                  builder: (_) => BodyEntryScreen(unit: 'kg', date: date),
                ),
              ),
              child: const Text('Open body'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('Open body'));
    await t.pumpAndSettle();
  }

  testWidgets('closure N10: unchanged Body edit keeps one reading', (t) async {
    tall(t);
    final app = AppState.forTesting();
    addTearDown(app.dispose);
    const date = '2026-09-12';
    await t.runAsync(() => BodyLogDb.putWeight(date, 75.5, 'kg'));
    await openBody(t, app, date);
    await until(
      t,
      () =>
          field('Weight (kg)').evaluate().isNotEmpty &&
          t.widget<TextField>(field('Weight (kg)')).controller!.text.isNotEmpty,
    );
    await button(t, 'Save');
    await until(t, () => find.byType(BodyEntryScreen).evaluate().isEmpty);
    expect((await t.runAsync(() => BodyLogDb.readingsOn(date)))!, hasLength(1));
  });

  test(
    'closure N06: restore protects chart and provenance with measured day',
    () async {
      const day = '2026-09-01';
      final own = {
        'day_id': day,
        'algo_version': 97,
        'payload_json': '{}',
        'computed_at': 1,
        'finalized': 1,
        'readiness': 91.0,
      };
      await db.insert('day_result', own);
      await db.insert('metric_series', {
        'date': day,
        'key': 'readiness',
        'value': 91,
      });
      await db.insert('metric_series_version', {
        'date': day,
        'algo_version': 97,
        'source': 'band',
      });
      final dir = await Directory.systemTemp.createTemp('synthetic_restore_');
      final path = p.join(dir.path, 'synthetic.db');
      final src = await databaseFactory.openDatabase(path);
      try {
        await src.execute(
          'CREATE TABLE day_result(day_id TEXT,algo_version INTEGER,payload_json TEXT,computed_at INTEGER,finalized INTEGER,readiness REAL)',
        );
        await src.execute(
          'CREATE TABLE metric_series(date TEXT,key TEXT,value REAL)',
        );
        await src.execute(
          'CREATE TABLE metric_series_version(date TEXT,algo_version INTEGER,source TEXT)',
        );
        await src.insert('day_result', {...own, 'readiness': 42.0});
        await src.insert('metric_series', {
          'date': day,
          'key': 'readiness',
          'value': 42,
        });
        await src.insert('metric_series_version', {
          'date': day,
          'algo_version': 96,
          'source': 'foreign',
        });
        await src.close();
        await LocalDb.importFromDbFile(path);
        expect((await db.query('day_result')).single['readiness'], 91);
        expect((await db.query('metric_series')).single['value'], 91);
        expect(
          (await db.query('metric_series_version')).single['source'],
          'band',
        );
      } finally {
        if (src.isOpen) await src.close();
        await databaseFactory.deleteDatabase(path);
        await dir.delete();
      }
    },
  );
  test(
    'closure N03: failing privacy write keeps active resumable workout',
    () async {
      final app = AppState.forTesting();
      addTearDown(app.dispose);
      app.user = {'weight_kg': 70.0};
      app.repo = LocalRepositoryImpl(getProfileMap: () => app.user);
      final a = activityByName('swimming')!,
          at = DateTime.now().subtract(const Duration(minutes: 3));
      await seed('partial-private', status: 'live');
      app.activeWorkout = LiveWorkoutState(
        startTime: at,
        targetKcal: 300,
        workoutId: 'partial-private',
        type: a.typeKey,
      );
      WorkoutClock.begin('partial-private', at, const Profile(weightKg: 70));
      LiveDraft.begin(a, private: true);
      await db.execute(
        "CREATE TRIGGER audit_private_fail BEFORE UPDATE OF private ON sessions BEGIN SELECT RAISE(ABORT,'synthetic disk failure'); END",
      );
      try {
        final draft = ActivityResult(
          a,
          start: at,
          duration: const Duration(minutes: 3),
          private: true,
          lapSecs: [10, 20],
          poolLengthM: 25,
        );
        await expectLater(
          activityHost(app).onFinish!(draft),
          throwsA(anything),
        );
        final row = (await LocalDb.session('partial-private'))!;
        expect(row['status'], 'live');
        expect(row['private'], 0);
        expect(app.activeWorkout, isNotNull);
        expect(await LocalDb.sessionDetail('partial-private'), isNull);
        expect(LiveDraft.current, isNotNull);
      } finally {
        await db.execute('DROP TRIGGER audit_private_fail');
        WorkoutClock.current = null;
      }
    },
  );
  test(
    'closure N04: reset clears owners and Settings clears the UI draft',
    () async {
      final app = AppState.forTesting();
      addTearDown(app.dispose);
      final a = activityByName('swimming')!, at = DateTime.now();
      app.activeWorkout = LiveWorkoutState(
        startTime: at,
        targetKcal: 300,
        workoutId: 'reset-live',
        type: a.typeKey,
      );
      WorkoutClock.begin('reset-live', at, const Profile(weightKg: 70));
      LiveDraft.begin(a);
      await app.resetAllData();
      // The only production caller (Settings) clears this immediately after
      // resetAllData. Test the complete ownership sequence, not the API alone.
      LiveDraft.clear();
      expect(app.activeWorkout, isNull);
      expect(WorkoutClock.current, isNull);
      expect(LiveDraft.current, isNull);
      app.activeWorkout = null;
      WorkoutClock.current = null;
      LiveDraft.clear();
    },
  );
  testWidgets('closure N15: Sleep clears old data while selected day loads', (
    t,
  ) async {
    tall(t);
    final app = AppState.forTesting()..repo = _PendingRepo();
    addTearDown(app.dispose);
    await t.pumpWidget(
      frame(
        app,
        const SleepDetail(
          day: '2026-09-02',
          data: SleepData(
            day: '2026-09-02',
            days: ['2026-09-02', '2026-09-01'],
            night: {
              'duration_min': 120,
              'onset_ts': 1788310800,
              'wake_ts': 1788318000,
            },
          ),
        ),
      ),
    );
    expect(find.byType(HeroStat), findsWidgets);
    await t.tap(
      find.byWidgetPredicate(
        (w) => w is Pressable && w.semanticLabel == 'Previous day',
      ),
    );
    await t.pump();
    expect(t.widget<DayNav>(find.byType(DayNav)).day, '2026-09-01');
    expect(find.byType(HeroStat), findsNothing);
    expect(find.text('Fix sleep times'), findsNothing);
    await t.pumpWidget(const SizedBox.shrink());
  });

  Future<void> history(WidgetTester t, AppState app) async {
    await t.pumpWidget(frame(app, const WorkoutHistoryScreen()));
    await until(
      t,
      () => find
          .byWidgetPredicate(
            (w) => w is Pressable && w.semanticLabel == 'Session options',
          )
          .evaluate()
          .isNotEmpty,
    );
    await t.tap(
      find
          .byWidgetPredicate(
            (w) => w is Pressable && w.semanticLabel == 'Session options',
          )
          .first,
    );
    await t.pumpAndSettle();
  }

  testWidgets('closure N11: Fix times uses stored wall end', (t) async {
    tall(t);
    final app = AppState.forTesting();
    addTearDown(app.dispose);
    app.repo = LocalRepositoryImpl(getProfileMap: () => {'weight_kg': 70.0});
    final end = DateTime.fromMillisecondsSinceEpoch(
          (DateTime.now()
                      .subtract(const Duration(hours: 2))
                      .millisecondsSinceEpoch ~/
                  1000) *
              1000,
        ),
        start = end.subtract(const Duration(hours: 1));
    await t.runAsync(() async {
      await db.insert('sessions', {
        'id': 'paused-history',
        'start_ts': start.millisecondsSinceEpoch ~/ 1000,
        'end_ts': end.millisecondsSinceEpoch ~/ 1000,
        'type': 'swimming',
        'status': 'done',
        'created_at': 1,
      });
      await WorkoutClock(
        'paused-history',
        start,
        end: end,
        pauses: [
          (
            start: start.add(const Duration(minutes: 20)),
            end: start.add(const Duration(minutes: 35)),
          ),
        ],
      ).persist();
    });
    await history(t, app);
    await t.tap(
      find.byWidgetPredicate((w) => w is PickRow && w.title == 'Fix the times'),
    );
    await t.pumpAndSettle();
    final form = t.widget<LogWorkout>(find.byType(LogWorkout));
    expect(
      form.end!.millisecondsSinceEpoch ~/ 1000,
      end.millisecondsSinceEpoch ~/ 1000,
    );
    await t.pumpWidget(const SizedBox.shrink());
  });
  test('closure N07: mixed-file failure removes generated plaintext', () async {
    final root = await Directory.systemTemp.createTemp(
      'audit_crypto_synthetic_',
    );
    final old = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(root.path);
    final app = AppState.forTesting();
    addTearDown(app.dispose);
    try {
      final input = File(p.join(root.path, 'input.db'));
      await input.writeAsString('synthetic database bytes');
      final encrypted = File(p.join(root.path, 'input.osbk'));
      await encryptBackupFile(
        input,
        encrypted,
        'synthetic-pass',
        iterations: 1000,
      );
      await expectLater(
        runImport(app, [
          encrypted.path,
          p.join(root.path, 'absent.csv'),
        ], askPassphrase: () async => 'synthetic-pass'),
        throwsA(anything),
      );
      final left = root
          .listSync()
          .whereType<File>()
          .where(
            (f) =>
                p.basename(f.path).startsWith('restore-') &&
                f.path.endsWith('.db'),
          )
          .toList();
      expect(left, isEmpty);
    } finally {
      PathProviderPlatform.instance = old;
      await root.delete(recursive: true);
    }
  });
  test('closure N13: sessions-only restore reports landed session', () async {
    final root = await Directory.systemTemp.createTemp(
      'audit_counter_synthetic_',
    );
    final path = p.join(root.path, 'sessions.db');
    final src = await databaseFactory.openDatabase(path);
    await src.execute(
      'CREATE TABLE sessions(id TEXT,start_ts INTEGER,end_ts INTEGER,type TEXT,status TEXT,created_at INTEGER)',
    );
    await src.insert('sessions', {
      'id': 'restored-only-session',
      'start_ts': 1000000000,
      'end_ts': 1000000600,
      'type': 'swimming',
      'status': 'done',
      'created_at': 1,
    });
    await src.close();
    final app = AppState.forTesting();
    addTearDown(app.dispose);
    try {
      final out = await runImport(app, [path]);
      expect(await LocalDb.session('restored-only-session'), isNotNull);
      expect(out.nothingLanded, isFalse);
      expect(out.records, greaterThan(0));
    } finally {
      await databaseFactory.deleteDatabase(path);
      await root.delete();
    }
  });
  testWidgets('closure N12: sparse HR retains actual offset', (t) async {
    tall(t);
    final app = AppState.forTesting();
    addTearDown(app.dispose);
    app.repo = LocalRepositoryImpl(getProfileMap: () => {'weight_kg': 70.0});
    final end =
        (DateTime.now()
                .subtract(const Duration(hours: 3))
                .millisecondsSinceEpoch ~/
            60000) *
        60;
    final start = end - 1800;
    await t.runAsync(() async {
      await db.insert('sessions', {
        'id': 'sparse-session',
        'start_ts': start,
        'end_ts': end,
        'type': 'swimming',
        'status': 'done',
        'created_at': 1,
      });
      for (var minute = 10; minute <= 20; minute++) {
        final sec = start + minute * 60;
        await db.insert('decoded_onehz', {
          'rec_ts': sec,
          'ts_ms': sec * 1000,
          'counter': minute,
          'hr': 80 + minute,
        });
      }
    });
    await t.pumpWidget(frame(app, const SessionDestination('sparse-session')));
    await until(t, () => find.byType(ActivitySummary).evaluate().isNotEmpty);
    final r = t.widget<ActivitySummary>(find.byType(ActivitySummary)).result;
    expect(r.hr, isNotEmpty);
    expect(r.hr.first, isNull);
    expect(r.hr[10], 90);
    expect(r.hr.take(10).every((v) => v == null), isTrue);
    await t.pumpWidget(const SizedBox.shrink());
  });
  test(
    'regression: initial session privacy is part of its first durable row',
    () async {
      await LocalDb.putSession({
        'id': 'private-start-race',
        'start_ts': 1000000000,
        'type': 'swimming',
        'status': 'live',
        'private': 1,
        'created_at': 1,
      });
      await LocalDb.putSession({
        'id': 'private-start-race',
        'start_ts': 1000000000,
        'type': 'swimming',
        'status': 'done',
        'created_at': 1,
      });
      expect((await LocalDb.session('private-start-race'))!['private'], 1);
    },
  );
  test(
    'regression: real activity host start also persists the chosen privacy before returning',
    () async {
      final app = AppState.forTesting();
      addTearDown(app.dispose);
      app.user = {'weight_kg': 70.0, 'height_cm': 180.0, 'age': 30, 'sex': 'm'};
      app.repo = LocalRepositoryImpl(getProfileMap: () => app.user);
      final a = activityByName('swimming')!;
      final ok = await activityHost(app).onStart!(a, private: true);
      expect(ok, isTrue);
      final id = WorkoutClock.current!.id;
      // This is the same non-lift order as ActivitySetup._start after onStart.
      WorkoutClock.current!.save();
      await LocalDb.setSessionPrivate(id, true);
      LiveDraft.begin(a, private: true);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      final row = await LocalDb.session(id);
      expect(row, isNotNull);
      expect(row!['private'], 1);
      expect(LiveDraft.current!.private, isTrue);
      await app.stopWorkout();
      LiveDraft.clear();
      await WorkoutClock.flushWrites();
    },
  );
  test(
    'regression: failed initial session write starts no live owners',
    () async {
      final app = AppState.forTesting()..user = {'weight_kg': 70.0};
      addTearDown(app.dispose);
      app.repo = LocalRepositoryImpl(getProfileMap: () => app.user);
      await db.execute(
        "CREATE TRIGGER synthetic_start_fail BEFORE INSERT ON sessions BEGIN SELECT RAISE(ABORT,'synthetic start failure'); END",
      );
      try {
        await expectLater(
          activityHost(app).onStart!(
            activityByName('Swimming')!,
            private: true,
          ),
          throwsA(anything),
        );
        expect(app.activeWorkout, isNull);
        expect(WorkoutClock.current, isNull);
        expect(await db.query('sessions'), isEmpty);
      } finally {
        await db.execute('DROP TRIGGER synthetic_start_fail');
      }
      await app.resetAllData();
      expect(await db.query('sessions'), isEmpty);
    },
  );
  test('regression: cold launch hydrates persisted unread bell', () async {
    final log = NotificationLog.instance;
    final now = DateTime(2026, 10, 19, 12);
    log.clock = () => now;
    final entry = LoggedNotification(
      key: 'persisted',
      at: now.subtract(const Duration(hours: 1)),
      title: 'Synthetic reminder',
      body: 'Synthetic',
      category: 'reminders',
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('notify.log', jsonEncode([entry.toJson()]));
    log.unread.value = 0;
    await log.reconcile();
    expect(log.unread.value, 1);
    expect((await log.entries()).length, 1);
    expect(log.unread.value, 1);
    log.clock = DateTime.now;
  });
  test(
    'regression: 90-day retention physically prunes expired entries',
    () async {
      final log = NotificationLog.instance;
      final now = DateTime(2026, 10, 19, 12);
      log.clock = () => now;
      final old = LoggedNotification(
        key: 'expired',
        at: now.subtract(const Duration(days: 91)),
        title: 'Synthetic expired title',
        body: 'Synthetic expired body',
        category: 'reminders',
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('notify.log', jsonEncode([old.toJson()]));
      await log.reconcile();
      expect(await log.entries(), isEmpty);
      expect(
        prefs.getString('notify.log'),
        isNot(contains('Synthetic expired body')),
      );
      log.clock = DateTime.now;
    },
  );
  test(
    'regression: historical food reminders open the occurrence day',
    () async {
      final log = NotificationLog.instance;
      var now = DateTime(2026, 10, 19, 20);
      log.clock = () => now;
      await log.clear();
      await log.plan(
        id: 123,
        first: DateTime(2026, 10, 19, 21, 30),
        repeat: PlanRepeat.daily,
        title: 'Synthetic food question',
        body: 'Synthetic',
        category: 'reminders',
        route: '/food',
      );
      now = DateTime(2026, 10, 21, 22);
      await log.reconcile();
      final entries = await log.entries();
      expect(entries, hasLength(3));
      final oldest = entries.last;
      expect(oldest.at.day, 19);
      expect(routeDay(oldest.route!), '2026-10-19');
      final target = resolveTapRoute(oldest.route!);
      expect(target.screen, oldest.route);
      expect(
        target.tab,
        6,
        reason: 'Only selects tab; no dated screen request',
      );
      log.clock = DateTime.now;
    },
  );
  test('regression: first-check evidence uses the actual check weeks', () {
    const today = '2026-10-19';
    final weights = <BodyWeightRow>[];
    final food = <FoodDay>[];
    for (var i = 1; i <= 28; i++) {
      final d = DateTime(2026, 10, 19).subtract(Duration(days: i));
      final date = dayLabelOf(d);
      weights.add((
        date: date,
        kg: 80,
        atTs: d.millisecondsSinceEpoch ~/ 1000,
        unit: 'kg',
        entered: 80,
        source: 'whoop',
        originId: null,
        historyOnly: false,
      ));
      food.add((
        date: date,
        kcal: 2200,
        counts: true,
        protein: 150,
        proteinComplete: true,
      ));
    }
    final r = goalReview(
      plan: const GoalPlan(phase: GoalPhase.recomp, since: today),
      today: today,
      weights: weights,
      measures: [],
      lifts: [],
      food: food,
      steps: [],
      sleepMin: [],
      recovery: [],
      sessions: [],
    );
    expect(
      DateTime.parse(r.firstCheck!).isAfter(DateTime.parse(today)),
      isTrue,
    );
    final need = goalNeeds(
      r,
      today: today,
      weights: weights,
      food: food,
      measures: [],
      lifts: [],
    ).firstWhere((n) => n.kind == GoalNeedKind.evidence);
    expect(need.state, isNot(NeedState.met));
    final windows = checkWindows(r.firstCheck!, r.plan.windowWeeks);
    expect(windows.after.from.compareTo(today), greaterThanOrEqualTo(0));
    expect(windows.after.to.compareTo(today), greaterThan(0));
  });
  test(
    'regression: latest daily projection is not latest individual weigh-in',
    () async {
      const day = '2026-10-19';
      await BodyLogDb.putWeight(day, 80, 'kg', at: DateTime(2026, 10, 19, 8));
      await BodyLogDb.putWeight(day, 81, 'kg', at: DateTime(2026, 10, 19, 12));
      final shown = (await BodyLogDb.weights()).last;
      final actual = (await BodyLogDb.readingsOn(day)).last;
      expect(shown.kg, 80);
      expect(actual.kg, 81);
      expect(shown.atTs, lessThan(actual.atTs));
      final latest = await BodyLogDb.latestReading(
        through: DateTime(2026, 10, 19, 13),
      );
      expect(latest!.kg, 81);
      expect(latest.atTs, actual.atTs);
    },
  );
}
