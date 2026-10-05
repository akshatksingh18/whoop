import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as path;
import 'package:openstrap_analytics/onehz.dart' as ana;
import 'package:openstrap_edge/compute/profile.dart';
import 'package:openstrap_edge/compute/day_upkeep.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/data/local_repository.dart';
import 'package:openstrap_edge/data/local_repository_impl.dart';
import 'package:openstrap_edge/data/calculation_store.dart';
import 'package:openstrap_edge/gps/route_models.dart';
import 'package:openstrap_edge/gps/workout_measurements.dart';
import 'package:openstrap_edge/health/phone_pedometer.dart';
import 'package:openstrap_edge/ui2/screens/metric_detail.dart';
import 'package:openstrap_edge/notify/notification_report.dart';
import 'package:openstrap_edge/gps/run_history.dart';
import 'package:openstrap_edge/gps/workout_clock.dart';
import 'package:openstrap_edge/live/live_activity.dart';
import 'package:openstrap_edge/notify/tap_router.dart';
import 'package:openstrap_edge/notify/notification_event.dart';
import 'package:openstrap_edge/notify/notification_prefs.dart';
import 'package:openstrap_edge/state/prefs.dart';
import 'package:openstrap_edge/ui2/grammar.dart';
import 'package:openstrap_edge/ui2/activity/catalogue.dart';
import 'package:openstrap_edge/ui2/activity/summary.dart';
import 'package:openstrap_edge/ui2/activity/run_detail.dart';
import 'package:openstrap_edge/state/app_state.dart';

const profile = Profile(
  ageYears: 23,
  weightKg: 80.5,
  heightCm: 186.69,
  sex: 'm',
);

class StepRepo extends LocalRepository {
  StepRepo(this.steps);
  final num? steps;
  @override
  Future<Map<String, dynamic>> getProfile() async => profile.toMap();
  @override
  Future<Map<String, dynamic>> getWorkouts({String range = "month"}) async => {
    "workouts": [],
  };
  @override
  Future<num?> getMeasuredDaySteps(String day) async => steps;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.dbName = 'build74-regressions.db';
    await databaseFactory.deleteDatabase(
      path.join(await databaseFactory.getDatabasesPath(), LocalDb.dbName),
    );
    db = await LocalDb.instance;
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.ensureLoaded();
    WorkoutClock.current = null;
    runsChanged();
    for (final table in [
      'live_coverage',
      'baselines',
      'sessions',
      'day_result',
      'metric_series',
      'workout_route',
    ]) {
      await db.delete(table);
    }
  });
  tearDownAll(() async {
    await LocalDb.close();
    await databaseFactory.deleteDatabase(
      path.join(await databaseFactory.getDatabasesPath(), LocalDb.dbName),
    );
  });
  test(
    'foreground refresh rereads active walking steps and both calorie estimates',
    () async {
      final now = DateTime.fromMillisecondsSinceEpoch(
        DateTime.now().millisecondsSinceEpoch ~/ 1000 * 1000,
      );
      final start = now.subtract(const Duration(minutes: 10));
      final ts = start.millisecondsSinceEpoch ~/ 1000;
      const id = 'refresh-live-walk';
      await LocalDb.putSession({
        'id': id,
        'start_ts': ts,
        'status': 'live',
        'type': 'walking',
        'created_at': start.millisecondsSinceEpoch,
      });
      WorkoutClock.begin(id, start, profile);
      await LocalDb.appendRoutePoints(id, [
        for (var i = 0; i <= 600; i++)
          RoutePoint(
            seq: i,
            tsMs: start.millisecondsSinceEpoch + i * 1000,
            lat: 0,
            lng: i / 111195,
          ).toRow(id),
      ]);
      final state = AppState.forTesting()
        ..repo = LocalRepositoryImpl(getProfileMap: () => profile.toMap())
        ..activeWorkout = LiveWorkoutState(
          startTime: start,
          workoutId: id,
          type: 'walking',
          targetKcal: 0,
          profile: profile,
        );
      addTearDown(() {
        state.dispose();
        WorkoutClock.current = null;
      });
      await LocalDb.replacePhoneCoverageForDay(dayLabelOf(start), [
        (startTs: ts, endTs: ts + 600, steps: 500),
      ]);
      await state.refreshForeground();
      expect(state.workoutStepCount, 500);
      expect(
        state.workoutActiveKcal,
        stepCalories(500, profile.weightKg)!.round(),
      );
      expect(state.workoutAcsmKcal, closeTo(24, 1));
      await LocalDb.replacePhoneCoverageForDay(dayLabelOf(start), [
        (startTs: ts, endTs: ts + 600, steps: 1000),
      ]);
      await state.refreshForeground();
      expect(state.workoutStepCount, 1000);
      expect(
        state.workoutActiveKcal,
        stepCalories(1000, profile.weightKg)!.round(),
      );
      expect(
        state.workoutAcsmKcal,
        closeTo(24, 1),
      ); // Same measured distance, new steps.
    },
  );
  test(
    'Budget and ACSM preserve decimal mass and use distinct net coefficients',
    () {
      expect(
        stepCalories(10000, 80.5),
        closeTo(2.74 * 10000 * 80.5 / 8368, 1e-9),
      );
      expect(
        runFloorKcal(runMeters: 5000, weightKg: 80.5),
        closeTo(287.7875, 1e-9),
      );
      expect(acsmActiveKcal(runMeters: 5000, weightKg: 80.5), 402.5);
      expect(
        acsmActiveKcal(runMeters: 0, walkMeters: 5000, weightKg: 80.5),
        201.25,
      );
      expect(
        acsmActiveKcal(runMeters: 4600, walkMeters: 400, weightKg: 80.5),
        closeTo(386.4, 1e-9),
      );
      for (final n in [-1.0, double.nan, double.infinity]) {
        expect(acsmActiveKcal(runMeters: n, weightKg: 80.5), isNull);
      }
      expect(
        walkingEnergy(1000, const Profile(weightKg: 80.5))!.kcal,
        isPositive,
      );
      expect(walkingEnergy(1000, const Profile(weightKg: 80.5))!.km, isNull);
    },
  );
  test(
    'native indoor distance contributes without Start, and paused steps stay daily',
    () async {
      final day = DateTime(2026, 10, 3),
          label = dayLabelOf(day),
          start = day.millisecondsSinceEpoch ~/ 1000;
      await LocalDb.replacePhoneCoverageForDay(
        label,
        [(startTs: start, endTs: start + 3600, steps: 1000)],
        distances: {'$start-${start + 3600}': 600},
      );
      final repo = StepRepo(1000);
      final normal = await DayUpkeep.read(
        repo,
        label,
        profile,
        eaten: 2000,
        runs: [],
      );
      expect(normal.walkingMeters, closeTo(600, 1e-9));
      expect(normal.distanceSource, 'Phone motion-distance estimate');
      expect(normal.acsmParts!.steps, closeTo(24.15, 1e-9));
      expect(normal.parts!.bmr, normal.acsmParts!.bmr);
      expect(normal.parts!.food, normal.acsmParts!.food);
      final run = RunSummary(
        'run',
        day,
        1000,
        1800,
        {},
        end: day.add(const Duration(hours: 1)),
        mix: (
          runM: 1000.0,
          walkM: 0.0,
          climbM: 0.0,
          runSec: 1800.0,
          walkSec: 0.0,
        ),
        phoneSteps: 500,
        weightKg: 80.5,
        activeWindows: [
          (start: day, end: day.add(const Duration(minutes: 30))),
        ],
      );
      final u = await DayUpkeep.read(
        repo,
        label,
        profile,
        eaten: 0,
        runs: [run],
      );
      expect(u.walkedSteps, 500);
      expect(u.walkingMeters, closeTo(300, 1e-9));
      expect(u.parts!.steps, closeTo(stepCalories(500, 80.5)!, 1e-9));
      expect(u.acsmParts!.steps, closeTo(12.075, 1e-9));
      expect(u.acsmParts!.run, 80.5);
    },
  );
  test(
    'recorded walking route replaces overlapping motion metres once',
    () async {
      final start = DateTime(2026, 10, 3, 8);
      final ts = start.millisecondsSinceEpoch ~/ 1000, day = dayLabelOf(start);
      await LocalDb.replacePhoneCoverageForDay(
        day,
        [(startTs: ts, endTs: ts + 1200, steps: 1000)],
        distances: {'$ts-${ts + 1200}': 600},
      );
      await LocalDb.putSession({
        'id': 'walk-route',
        'start_ts': ts,
        'end_ts': ts + 600,
        'status': 'done',
        'type': 'walking',
        'duration_min': 10,
        'created_at': ts,
      });
      await WorkoutClock(
        'walk-route',
        start,
        end: start.add(const Duration(minutes: 10)),
        profile: profile,
      ).persist();
      await LocalDb.appendRoutePoints('walk-route', [
        for (var i = 0; i <= 600; i++)
          RoutePoint(
            seq: i,
            tsMs: start.millisecondsSinceEpoch + i * 1000,
            lat: 0,
            lng: i / 111195,
          ).toRow('walk-route'),
      ]);
      final repo = LocalRepositoryImpl(getProfileMap: () => profile.toMap());
      final session = await WorkoutMeasurements.read(
        repo,
        'walk-route',
        start,
        start.add(const Duration(minutes: 10)),
        profile,
      );
      final daily = await DayUpkeep.read(
        repo,
        day,
        profile,
        eaten: 0,
        runs: [],
      );
      expect(session.steps, 500);
      expect(daily.walkingMeters, closeTo(session.meters! + 300, .001));
      expect(daily.parts!.steps, closeTo(stepCalories(1000, 80.5)!, 1e-9));
      expect(daily.parts!.run, 0);
      expect(
        daily.acsmParts!.steps,
        closeTo(session.acsm('walking')! + 12.075, .001),
      );
    },
  );
  test(
    'current-day noon timestamp is kept before noon; future days are excluded',
    () async {
      final now = DateTime(2026, 10, 3, 9);
      final points = [
        for (final offset in [0, 1])
          (
            t:
                DateTime(2026, 10, 3 + offset, 12).millisecondsSinceEpoch ~/
                1000,
            v: 1000.0,
          ),
      ];
      final result = await stepCalorieModels(
        StepRepo(1000),
        points,
        days: 1,
        at: now,
      );
      expect(result.budget, hasLength(1));
      expect(result.acsm, hasLength(1));
    },
  );
  test(
    'iOS daily motion bridge persists distance in the same accepted windows',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      const channel = phoneStepsChannel;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'movementInInterval');
            return {'steps': 50, 'distance_m': 25.0};
          });
      try {
        expect(await PhonePedometer().syncDay(DateTime(2026, 10, 3)), 1200);
        final rows = await db.query('live_coverage');
        expect(rows, hasLength(24));
        expect(rows.every((r) => r['distance_m'] == 25.0), isTrue);
      } finally {
        debugDefaultTargetPlatformOverride = null;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      }
    },
  );
  test(
    'retained notification wording survives DB hydration and stale cache clearing',
    () async {
      final id = await NotificationReport.save(
        'Week',
        'Original finding',
        '2026-10-03',
      );
      await CalculationStore.clearCache();
      expect((await NotificationReport.read(id))!['body'], 'Original finding');
      expect(await NotificationReport.read('expired-id'), isNull);
    },
  );
  test(
    'absent distance never becomes ACSM zero; a measured zero remains zero',
    () async {
      final noHeight = await DayUpkeep.read(
        StepRepo(1000),
        '2026-10-03',
        const Profile(weightKg: 80.5),
        eaten: 0,
        runs: [],
      );
      expect(noHeight.walkingMeters, isNull);
      expect(noHeight.acsmParts, isNull);
      final zero = await DayUpkeep.read(
        StepRepo(0),
        '2026-10-03',
        profile,
        eaten: 0,
        runs: [],
      );
      expect(zero.acsmParts!.steps, 0);
      final absent = await DayUpkeep.read(
        StepRepo(null),
        '2026-10-03',
        profile,
        eaten: 0,
        runs: [],
      );
      expect(absent.acsmParts, isNull);
    },
  );
  test(
    'daily chart limit uses local now and leaves historical/overnight whole',
    () {
      final now = DateTime(2026, 10, 5, 9, 13);
      expect(latestDaySlot('2026-10-05', 1440, now: now), 553);
      expect(latestDaySlot('2026-10-05', 24, now: now), 9);
      expect(latestDaySlot('2026-10-04', 1440, now: now), 1439);
      expect(latestDaySlot(null, 1440, now: now), 1439);
      expect(latestDaySlot('2026-10-05', 0, now: now), 0);
    },
  );
  test('focused routes and review quiet-hours opt-in gates agree', () {
    final r = datedRoute(kRouteWorkoutIdle, '2026-10-03', id: 'a/b');
    expect(routeId(resolveTapRoute(r).screen!), 'a/b');
    expect(routeDay(r), '2026-10-03');
    expect(
      resolveTapRoute(datedRoute(kRouteRecovery, '2026-10-03')).screen,
      isNotNull,
    );
    expect(routeDay('/today/recovery?day=2026-02-30'), isNull);
    expect(resolveTapRoute('/old/unknown').tab, 0);
    const e = NotificationEvent(
      dedupeKey: 'review',
      category: NotifCategory.reminders,
      title: 'Review',
      body: 'Evidence',
      date: '2026-10-03',
      route: kRouteTrainingReview,
    );
    expect(const NotificationPrefs().shouldFireOs(e, 720), isFalse);
    expect(
      const NotificationPrefs(trainingReviewEnabled: true).shouldFireOs(e, 720),
      isTrue,
    );
    expect(
      const NotificationPrefs(
        trainingReviewEnabled: true,
      ).shouldFireOs(e, 1380),
      isFalse,
    );
  });
  test('review requires three distinct usable sessions on each side', () {
    final rows = <ana.TrainingObservation>[
      for (var i = 0; i < 3; i++)
        ana.TrainingObservation(
          id: 'old$i',
          day: '2026-09-10',
          type: 'Running',
          seconds: 1800,
          meters: 5000,
          hr: 150,
          coverage: .9,
        ),
      for (var i = 0; i < 3; i++)
        ana.TrainingObservation(
          id: 'new$i',
          day: '2026-09-25',
          type: 'Running',
          seconds: 1800,
          meters: 5000,
          hr: 145,
          coverage: .9,
        ),
    ];
    List<ana.TrainingComparison> compare(List<ana.TrainingObservation> r) =>
        ana.compareTraining(
          r,
          firstDay: '2026-09-01',
          splitDay: '2026-09-15',
          endDay: '2026-10-01',
        );
    expect(compare(rows).any((c) => c.hrChange == -5), isTrue);
    expect(compare(rows.take(5).toList()), isEmpty);
    expect(
      compare([
        rows.first,
        rows.first,
        rows.first,
        rows.last,
        rows.last,
        rows.last,
      ]),
      isEmpty,
    );
    expect(
      compare([
        for (final r in rows)
          ana.TrainingObservation(
            id: r.id,
            day: r.day,
            type: r.type,
            seconds: r.seconds,
            meters: r.meters,
            hr: r.hr,
            coverage: .5,
          ),
      ]),
      isEmpty,
    );
  });
  test('Live Activity updates pause and absent HR, then ends', () async {
    const channel = MethodChannel('openstrap/live_activity');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return true;
        });
    await LiveActivity.update(
      id: 'run',
      type: 'running',
      elapsed: 240,
      paused: false,
      distanceKm: 1,
      hr: null,
    );
    await LiveActivity.update(
      id: 'run',
      type: 'running',
      elapsed: 240,
      paused: true,
      distanceKm: 1,
      hr: null,
    );
    expect((calls.last.arguments as Map)['elapsed'], 240);
    expect((calls.last.arguments as Map)['paceSeconds'], isNull);
    expect((calls.last.arguments as Map)['hr'], isNull);
    await LiveActivity.end();
    expect(calls.last.method, 'end');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  test(
    'queued stale Live Activity updates cannot resurrect a finished session',
    () async {
      const channel = MethodChannel('openstrap/live_activity');
      final first = Completer<void>(), calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (calls.length == 1) await first.future;
            return true;
          });
      final updating = LiveActivity.update(
        id: 'old',
        type: 'running',
        elapsed: 100,
        paused: false,
        distanceKm: 1,
        hr: 130,
      );
      await Future<void>.delayed(Duration.zero);
      final queued = LiveActivity.update(
        id: 'old',
        type: 'running',
        elapsed: 101,
        paused: false,
        distanceKm: 1,
        hr: 130,
      );
      final ending = LiveActivity.end();
      final next = LiveActivity.update(
        id: 'new',
        type: 'walking',
        elapsed: 0,
        paused: false,
        distanceKm: null,
        hr: null,
      );
      first.complete();
      await Future.wait([updating, queued, ending, next]);
      expect(calls.map((c) => c.method).toList(), ['update', 'end', 'update']);
      expect((calls.last.arguments as Map)['id'], 'new');
      await LiveActivity.end();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    },
  );
  testWidgets('both calories remain visible at small width and large text', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: const Scaffold(
            body: SizedBox(
              width: 280,
              child: CaloriePair(budget: 1234.5, acsm: null),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Budget'), findsOneWidget);
    expect(find.text('ACSM'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  test('paused route readouts align HR and cadence after resume', () {
    final start = DateTime(2026, 10, 3, 8), end = DateTime(2026, 10, 3, 8, 12);
    WorkoutClock.current = WorkoutClock(
      'paused',
      start,
      end: end,
      profile: profile,
      pauses: [
        (
          start: start.add(const Duration(minutes: 1)),
          end: start.add(const Duration(minutes: 11)),
        ),
      ],
    );
    final result = ActivityResult(
      allActivities.firstWhere((a) => a.typeKey == 'running'),
      sessionId: 'paused',
      start: start,
      duration: const Duration(minutes: 2),
      hr: const [120, 150],
      cadenceSeries: const [145, 160],
      track: [
        RoutePoint(
          seq: 0,
          tsMs: start.millisecondsSinceEpoch,
          lat: 29.9,
          lng: -95.6,
        ),
        RoutePoint(
          seq: 1,
          tsMs: end.millisecondsSinceEpoch,
          lat: 29.91,
          lng: -95.6,
        ),
      ],
    );
    final view = RunView(result);
    expect(view.hrAt(.5), isNull);
    expect(view.cadenceAt(.5), isNull);
    expect(view.hrAt(11 / 12), 150);
    expect(view.cadenceAt(11 / 12), 160);
    expect(view.hrAt(1), 150);
  });
  testWidgets(
    'pointer and screen-reader scrubbing obey the same now boundary',
    (t) async {
      var value = .4;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (c, update) => SizedBox(
                width: 300,
                height: 100,
                child: Scrubber(
                  value: value,
                  maxValue: .4,
                  label: 'Bounded day',
                  describe: (v) => v.toString(),
                  onChanged: (v) => update(() => value = v),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      );
      final surface = find.byType(Scrubber);
      await t.tapAt(t.getTopRight(surface) + const Offset(-1, 20));
      await t.pump();
      expect(value, .4);
      final semantics = t.widget<Semantics>(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == 'Bounded day',
        ),
      );
      semantics.properties.onIncrease!();
      await t.pump();
      expect(value, .4);
      expect(semantics.properties.increasedValue, '0.4');
      semantics.properties.onDecrease!();
      await t.pump();
      expect(value, closeTo(.35, 1e-9));
      expect(t.takeException(), isNull);
    },
  );
  test('native activity attributes have identical Codable shapes', () {
    String shape(String path) {
      final s = File(path).readAsStringSync().replaceAll('\r\n', '\n');
      return s.substring(
        s.indexOf('struct OpenStrapWidgetAttributes'),
        s.indexOf('\n}\n', s.indexOf('struct OpenStrapWidgetAttributes')) + 3,
      );
    }

    expect(
      shape('ios/LiveActivityBridge.swift'),
      shape('ios/OpenStrapWidget/OpenStrapWidgetLiveActivity.swift'),
    );
  });
}
