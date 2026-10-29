// Real activity-host persistence and enrichment over authored SQLite inputs.
// Coordinates are an invented line at the equator, not a recorded route.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/data/calculation_store.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/gps/motion_window.dart';
import 'package:whoop_companion/gps/route_models.dart';
import 'package:whoop_companion/gps/screen_wake.dart';
import 'package:whoop_companion/gps/workout_clock.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/state/prefs.dart';
import 'package:whoop_companion/sync/file_log.dart';
import 'package:whoop_companion/ui2/activity/catalogue.dart';
import 'package:whoop_companion/ui2/activity/live.dart';
import 'package:whoop_companion/ui2/activity/summary.dart';
import 'package:whoop_companion/ui2/screens/workout_screen.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'support/audit_visual.dart' show loadAuditFonts;

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

class _Reads extends LocalRepositoryImpl {
  _Reads() : super(getProfileMap: () => {'weight_kg': 70.0});
  bool refuseRoute = false;
  @override
  Future<WorkoutRoute?> getWorkoutRoute(String id) {
    if (refuseRoute) throw StateError('synthetic route read refusal');
    return super.getWorkoutRoute(id);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState app;
  late _Reads repo;
  late Database db;
  const id = 'synthetic-host';
  final start = DateTime(2021, 4, 6, 12);
  final end = start.add(const Duration(minutes: 5));
  setUpAll(() async {
    await loadAuditFonts();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    final root = (await Directory(
      'build/coverage-remainder/activity-host',
    ).create(recursive: true)).absolute;
    PathProviderPlatform.instance = _Paths(root.path);
    LocalDb.dbName = '${root.path}/synthetic.sqlite';
    await LocalDb.close();
    await databaseFactory.deleteDatabase(LocalDb.dbName);
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.ensureLoaded();
    await LocalDb.wipeAll();
    DayClock.install([], []);
    WorkoutClock.current = null;
    LiveDraft.clear();
    ScreenWake.resetForTest();
    repo = _Reads();
    app = AppState.forTesting()
      ..user = {'age': 30, 'sex': 'f', 'height_cm': 170.0, 'weight_kg': 70.0}
      ..repo = repo;
    db = await LocalDb.instance;
  });
  tearDown(() async {
    await db.execute('DROP TRIGGER IF EXISTS synthetic_host_refusal');
    app.dispose();
    await WorkoutClock.flushWrites();
    WorkoutClock.current = null;
    LiveDraft.clear();
    await LiveDraft.retrySave();
    await FileLog.write('Synthetic activity-host barrier');
    ScreenWake.resetForTest();
  });
  tearDownAll(LocalDb.close);

  Future<void> seed({
    String type = 'swimming',
    bool finished = true,
    DateTime? at,
  }) async {
    final origin = at ?? start;
    await LocalDb.putSession({
      'id': id,
      'type': type,
      'start_ts': origin.millisecondsSinceEpoch ~/ 1000,
      'status': 'live',
      'private': 0,
      'created_at': 1,
    });
    app.activeWorkout = LiveWorkoutState(
      startTime: origin,
      targetKcal: 300,
      workoutId: id,
      type: type,
      profile: const Profile(weightKg: 70),
    );
    final clock = WorkoutClock.begin(id, origin, const Profile(weightKg: 70));
    if (finished) clock.finish(origin.add(const Duration(minutes: 5)));
    await WorkoutClock.flushWrites();
  }

  ActivityResult draft({
    String type = 'swimming',
    bool typed = true,
    DateTime? at,
  }) => ActivityResult(
    activityByName(type)!,
    start: at ?? start,
    duration: const Duration(minutes: 5),
    private: true,
    lapSecs: typed ? [0, 35, 40] : [],
    poolLengthM: typed ? 25 : null,
    stroke: typed ? 'freestyle' : null,
    rounds: typed ? [const IntervalRound(60, 30, avgHr: 120)] : [],
    poses: typed ? ['synthetic pose'] : [],
    breathsPerMin: typed ? 0 : null,
    gameScore: typed ? [(0, 1), (2, 0)] : [],
  );

  const typedExpected = {
    'laps': [0, 35, 40],
    'pool': 25,
    'stroke': 'freestyle',
    'rounds': [
      [60, 30, 120],
    ],
    'poses': ['synthetic pose'],
    'breaths': 0.0,
    'score': [
      [0, 1],
      [2, 0],
    ],
  };

  test(
    'COV-43 host typed-detail refusal retains the live draft and retries',
    () async {
      await seed(finished: false);
      LiveDraft.begin(
        activityByName('swimming')!,
        private: true,
        startedAt: start,
      );
      final host = activityHost(app);
      await db.execute(
        "CREATE TRIGGER synthetic_host_refusal BEFORE INSERT ON session_detail BEGIN SELECT RAISE(ABORT,'synthetic detail refusal'); END",
      );
      await expectLater(
        host.onFinish!(draft()),
        throwsA(isA<DatabaseException>()),
      );
      expect((await LocalDb.session(id))!['status'], 'live');
      expect(app.activeWorkout?.workoutId, id);
      expect(WorkoutClock.current!.end, isNull);
      expect(LiveDraft.current!.private, isTrue);
      expect(await LocalDb.sessionDetail(id), isNull);
      await db.execute('DROP TRIGGER synthetic_host_refusal');
      WorkoutClock.current!.finish(end);
      final saved = await host.onFinish!(draft());
      expect(saved.sessionId, id);
      expect((await LocalDb.session(id))!['private'], 1);
      expect(jsonDecode((await LocalDb.sessionDetail(id))!), typedExpected);
      expect(saved.lapSecs, [0, 35, 40]);
      expect(saved.gameScore, [(0, 1), (2, 0)]);
    },
  );

  test(
    'COV-43 host final-write refusal preserves staged measurements and finish time',
    () async {
      await seed();
      final host = activityHost(app);
      await db.execute(
        "CREATE TRIGGER synthetic_host_refusal BEFORE INSERT ON sessions WHEN NEW.status='done' BEGIN SELECT RAISE(ABORT,'synthetic final refusal'); END",
      );
      await expectLater(
        host.onFinish!(draft()),
        throwsA(isA<DatabaseException>()),
      );
      final staged = WorkoutClock.current!.pendingSession!;
      expect(staged['end_ts'], end.millisecondsSinceEpoch ~/ 1000);
      expect(app.activeWorkout?.workoutId, id);
      expect(jsonDecode((await LocalDb.sessionDetail(id))!), typedExpected);
      await db.execute('DROP TRIGGER synthetic_host_refusal');
      final saved = await host.onFinish!(draft());
      expect(saved.sessionId, id);
      expect(saved.duration, const Duration(minutes: 5));
      expect((await LocalDb.session(id))!['end_ts'], staged['end_ts']);
      expect(app.activeWorkout, isNull);
      await LocalDb.close();
      db = await LocalDb.instance;
      expect((await db.query('sessions')), hasLength(1));
      expect(jsonDecode((await LocalDb.sessionDetail(id))!), typedExpected);
    },
  );

  test(
    'COV-43 host retries enrichment after stop with the original saved identity',
    () async {
      await seed();
      final host = activityHost(app);
      repo.refuseRoute = true;
      await expectLater(host.onFinish!(draft()), throwsStateError);
      expect(app.activeWorkout, isNull);
      final row = await LocalDb.session(id);
      expect(row!['status'], 'done');
      final revision = app.insightsRevision.value;
      repo.refuseRoute = false;
      final saved = await host.onFinish!(draft());
      expect(saved.sessionId, id);
      expect(saved.lapSecs, [0, 35, 40]);
      expect(await LocalDb.session(id), row);
      expect(app.insightsRevision.value, revision);
      expect(await db.query('session_detail'), hasLength(1));
    },
  );

  test(
    'COV-43 a host without a real session does not invent a saved identity',
    () async {
      final original = draft();
      expect(await activityHost(app).onFinish!(original), same(original));
      expect(await db.query('sessions'), isEmpty);
      expect(await db.query('session_detail'), isEmpty);
    },
  );

  test('COV-43 an empty typed draft preserves already stored detail', () async {
    await seed();
    const existing = '{"laps":[35,40],"pool":25}';
    await LocalDb.putSessionDetail(id, existing);
    await activityHost(app).onFinish!(draft(typed: false));
    expect(await LocalDb.sessionDetail(id), existing);
  });

  test(
    'COV-43 repeated host finish does not extend, duplicate or republish a session',
    () async {
      await seed();
      final host = activityHost(app);
      final first = await host.onFinish!(draft());
      final revision = app.insightsRevision.value;
      final row = await LocalDb.session(id);
      final second = await host.onFinish!(draft());
      expect(second.sessionId, first.sessionId);
      expect(second.duration, first.duration);
      expect(await LocalDb.session(id), row);
      expect(await db.query('sessions'), hasLength(1));
      expect(await db.query('session_detail'), hasLength(1));
      expect(app.insightsRevision.value, revision);
    },
  );

  test(
    'COV-43 host finish excludes pauses and keeps its pinned profile',
    () async {
      await seed(finished: false);
      final clock = WorkoutClock.current!;
      clock.setPaused(true, start.add(const Duration(minutes: 1)));
      clock.setPaused(false, start.add(const Duration(minutes: 2)));
      clock.setPaused(true, start.add(const Duration(minutes: 4)));
      clock.finish(end); // The last minute remains paused.
      app.user = {'weight_kg': 200.0};
      final saved = await activityHost(app).onFinish!(draft());
      expect(saved.duration, const Duration(minutes: 3));
      expect(saved.calculationProfile!.weightKg, 70);
      final restored = WorkoutClock.read(id, start, end: end);
      expect(restored.windows(), [
        (start: start, end: start.add(const Duration(minutes: 1))),
        (
          start: start.add(const Duration(minutes: 2)),
          end: start.add(const Duration(minutes: 4)),
        ),
      ]);
      expect((await LocalDb.session(id))!['duration_min'], 3);
    },
  );

  for (final meters in <double?>[null, 10, 400]) {
    test(
      'COV-43 host motion enrichment distinguishes absent, short and usable distance: $meters',
      () async {
        await seed(type: 'walking');
        final key =
            'motion.$id.${start.millisecondsSinceEpoch ~/ 1000}-'
            '${end.millisecondsSinceEpoch ~/ 1000}';
        await CalculationStore.write(
          key,
          jsonEncode(
            MotionWindow(start, 60, [
              60,
              0,
              60,
              60,
              60,
            ], List<double?>.filled(5, meters)).toJson(),
          ),
        );
        final saved = await activityHost(app).onFinish!(draft(type: 'walking'));
        expect(saved.phoneSteps, 240);
        expect(saved.cadenceSeries, [60, null, 60, 60, 60]);
        expect(saved.cadence, 60);
        expect(saved.motionDistance, meters == 400);
        expect(saved.distanceKm, meters == 400 ? 2.0 : null);
        expect(saved.splits, meters == 400 ? hasLength(2) : isEmpty);
        expect(saved.mileSplits, meters == 400 ? isNotEmpty : isEmpty);
        expect(saved.lapSecs, [0, 35, 40]);
      },
    );
  }

  for (final measured in [true, false]) {
    test(
      'COV-43 host route enrichment preserves typed data with measured or missing altitude/speed: $measured',
      () async {
        await seed(type: 'running');
        final points = [
          for (var i = 0; i < 4; i++)
            RoutePoint(
              seq: i,
              tsMs: start.add(Duration(seconds: i * 60)).millisecondsSinceEpoch,
              lat: 0,
              lng: i * .001,
              accuracy: 5,
              alt: measured ? [10.0, 14.0, 11.0, 11.0][i] : null,
              speed: measured ? 2 : null,
            ),
        ];
        await LocalDb.appendRoutePoints(id, [
          for (final p in points) p.toRow(id),
        ]);
        final saved = await activityHost(app).onFinish!(draft(type: 'running'));
        expect(saved.geo, [(0.0, 0.0), (0.0, .001), (0.0, .002), (0.0, .003)]);
        expect(saved.route, hasLength(4));
        expect(saved.distanceKm, greaterThan(.3));
        expect(saved.lapSecs, [0, 35, 40]);
        expect(saved.elevationM, measured ? [10.0, 14.0, 11.0, 11.0] : isEmpty);
        expect(saved.routePace, measured ? [.5, .5, .5, .5] : null);
        expect(saved.lossM, measured ? 3.0 : null);
        expect(saved.splits, isNotEmpty);
        expect(saved.mileSplits, isNotEmpty);
        expect(await LocalDb.routePoints(id), hasLength(4));
      },
    );
  }
  Finder control(String label) =>
      find.byWidgetPredicate((w) => w is Pressable && w.semanticLabel == label);
  Future<void> flush(WidgetTester t, {bool Function()? ready}) async {
    for (var i = 0; i < 100; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await t.pump(const Duration(milliseconds: 30));
      if (i >= 10 && (ready?.call() ?? true)) break;
    }
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    if (ready != null) expect(ready(), isTrue);
  }

  Future<void> openLive(WidgetTester t) async {
    final at = DateTime.now().subtract(const Duration(minutes: 3));
    await t.runAsync(() => seed(finished: false, at: at));
    LiveDraft.begin(activityByName('swimming')!, startedAt: at, private: true);
    final host = activityHost(app);
    t.view.physicalSize = const Size(430, 1800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    addTearDown(() async {
      await t.pumpWidget(const SizedBox());
      await flush(t);
      await t.runAsync(() async {
        await WorkoutClock.flushWrites();
        await LiveDraft.retrySave();
        await FileLog.write('Synthetic live widget barrier');
      });
    });
    await t.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(
          theme: buildTheme(Brightness.light),
          home: Builder(
            builder: (c) => Scaffold(
              body: TextButton(
                child: const Text('Open live'),
                onPressed: () => Navigator.of(c).push(
                  MaterialPageRoute<void>(
                    builder: (_) => LiveShell(
                      activityByName('swimming')!,
                      private: true,
                      body: (c, elapsed) => const Text('Synthetic body'),
                      result: (_) => draft(at: at),
                      onFinish: host.onFinish,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('Open live'));
    await flush(t);
  }

  Future<void> confirmFinish(WidgetTester t) async {
    await t.tap(control('Finish session'));
    await t.pumpAndSettle();
    expect(find.text('Finish this workout?'), findsOneWidget);
    await t.tap(find.text('Finish').last);
    await flush(
      t,
      ready: () => find.byType(ActivitySummary).evaluate().isNotEmpty,
    );
  }

  testWidgets(
    'COV-43 real live controls retain pause/minimise/reopen and cancelled finish',
    (t) async {
      await openLive(t);
      await t.tap(control('Pause'));
      await flush(t);
      final current = LiveDraft.current;
      expect(current!.pausedAt, isNotNull);
      expect(WorkoutClock.current!.pausedAt, isNotNull);
      await t.tap(control('Minimise'));
      await flush(t);
      expect(find.byType(LiveShell), findsNothing);
      expect(LiveDraft.current, same(current));
      await t.tap(find.text('Open live'));
      await flush(t);
      expect(control('Resume'), findsOneWidget);
      await t.tap(control('Resume'));
      await flush(t);
      expect(WorkoutClock.current!.pausedAt, isNull);
      expect(LiveDraft.current!.pausedAt, isNull);
      await t.tap(control('Finish session'));
      await t.pumpAndSettle();
      await t.tap(find.text('Keep going').last);
      await flush(t);
      expect(find.byType(LiveShell), findsOneWidget);
      expect(find.byType(ActivitySummary), findsNothing);
      expect((await t.runAsync(() => LocalDb.session(id)))!['status'], 'live');
      expect(WorkoutClock.current!.end, isNull);
    },
  );

  for (final finalWrite in [false, true]) {
    testWidgets(
      'COV-43 real live finish and summary retry survive refused ${finalWrite ? 'session' : 'typed'} write',
      (t) async {
        await openLive(t);
        await t.runAsync(
          () => db.execute(
            finalWrite
                ? "CREATE TRIGGER synthetic_host_refusal BEFORE INSERT ON sessions WHEN NEW.status='done' BEGIN SELECT RAISE(ABORT,'synthetic final refusal'); END"
                : "CREATE TRIGGER synthetic_host_refusal BEFORE INSERT ON session_detail BEGIN SELECT RAISE(ABORT,'synthetic typed refusal'); END",
          ),
        );
        await confirmFinish(t);
        expect(find.text('This session is not saved yet'), findsOneWidget);
        expect(LiveDraft.current, isNotNull);
        expect(app.activeWorkout?.workoutId, id);
        final stoppedAt = WorkoutClock.current!.end;
        expect(stoppedAt != null, finalWrite);
        expect(
          find.text('Not now'),
          findsNothing,
          reason:
              'no rating can be offered for a draft without a saved identity',
        );
        await t.runAsync(
          () => db.execute('DROP TRIGGER synthetic_host_refusal'),
        );
        await t.ensureVisible(find.text('Try again'));
        // Invoke the rendered callback inside the real-I/O zone and await it.
        // Gesture hit-testing is separate; this asserts the shared save path.
        final retry = t.widget<StatusCard>(
          find.byWidgetPredicate(
            (w) => w is StatusCard && w.what == 'This session is not saved yet',
          ),
        );
        await t.runAsync(() async {
          final dynamic callback = retry.onFix;
          await callback();
        });
        await flush(
          t,
          ready: () =>
              find.text('This session is not saved yet').evaluate().isEmpty,
        );
        expect(app.activeWorkout, isNull);
        expect(LiveDraft.current, isNull);
        final row = (await t.runAsync(() => LocalDb.session(id)))!;
        expect(row['status'], 'done');
        if (stoppedAt != null) {
          expect(row['end_ts'], stoppedAt.millisecondsSinceEpoch ~/ 1000);
        }
        expect(
          jsonDecode(
            (await t.runAsync<String?>(() => LocalDb.sessionDetail(id)))!,
          ),
          typedExpected,
        );
        expect(await t.runAsync(() => db.query('sessions')), hasLength(1));
      },
    );
  }
}
