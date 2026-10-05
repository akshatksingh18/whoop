import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as path;
import 'package:openstrap_edge/compute/profile.dart';
import 'package:openstrap_edge/compute/derivation_engine.dart';
import 'package:openstrap_edge/ble/live_step_runs.dart';
import 'package:openstrap_edge/data/live_coverage_policy.dart';
import 'package:openstrap_edge/compute/day_upkeep.dart';
import 'package:openstrap_edge/compute/streak.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/data/calculation_store.dart';
import 'package:openstrap_edge/data/profile_history.dart';
import 'package:openstrap_edge/data/local_repository_impl.dart';
import 'package:openstrap_edge/data/nutrition_store.dart';
import 'package:openstrap_edge/gps/workout_clock.dart';
import 'package:openstrap_edge/gps/workout_measurements.dart';
import 'package:openstrap_edge/gps/route_models.dart';
import 'package:openstrap_edge/gps/route_math.dart';
import 'package:openstrap_edge/gps/session_track.dart';
import 'package:openstrap_edge/gps/run_analysis.dart';
import 'package:openstrap_edge/gps/run_history.dart';
import 'package:openstrap_edge/gps/run_voice.dart';
import 'package:openstrap_edge/gps/motion_window.dart';
import 'package:openstrap_edge/state/prefs.dart';
import 'package:openstrap_edge/ui2/screens/home_screen.dart';
import 'package:openstrap_edge/ui2/screens/day_steps.dart';
import 'package:openstrap_edge/ui2/screens/health_screen.dart';

const profile = Profile(
  ageYears: 23,
  weightKg: 80.5,
  heightCm: 186.69,
  sex: 'm',
);
int tsOf(DateTime at) => at.millisecondsSinceEpoch ~/ 1000;
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.dbName = 'build73_regressions.db';
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
    await StepGoals.flush();
    for (final t in [
      'day_result',
      'metric_series',
      'sessions',
      'live_coverage',
      'baselines',
      'food_def',
      'food_entry',
      'meal_template',
      'body_weight',
      'workout_route',
    ])
      await db.delete(t);
  });
  tearDownAll(() async {
    WorkoutClock.current = null;
    await LocalDb.close();
    await databaseFactory.deleteDatabase(
      path.join(await databaseFactory.getDatabasesPath(), LocalDb.dbName),
    );
  });
  test(
    'cross-day rebuild uses retained old-version days without raw band records',
    () async {
      final engine = DerivationEngine();
      expect(await engine.rebuildCrossDay(profile), 'needs_history');
      expect(
        jsonDecode(
          (await LocalDb.baseline('crossday_status'))!['payload_json']
              as String,
        )['days'],
        0,
      );
      for (var i = 1; i <= 14; i++) {
        final date = dayLabelOf(DateTime.now().subtract(Duration(days: i)));
        await LocalDb.putDayResult(
          dayId: date,
          algoVersion: kAlgoVersion - 1,
          finalized: true,
          windowJson: '{}',
          rhr: 55.0 + i % 3,
          rmssd: 60.0 + i % 4,
          payloadJson: jsonEncode({
            'scalars': {
              'rhr': 55.0 + i % 3,
              'rmssd': 60.0 + i % 4,
              'strain': 5.0,
              'steps': 8000,
            },
          }),
        );
      }
      final before = await db.query('day_result');
      expect(await engine.rebuildCrossDay(profile), 'ready');
      final bundle = jsonDecode(
        (await LocalDb.baseline('crossday'))!['payload_json'] as String,
      );
      expect(bundle['algo_version'], kAlgoVersion);
      expect(bundle['built_for_day'], todayLabel());
      expect(
        await db.query('day_result'),
        before,
        reason: 'retained day results must not be blanked or restamped',
      );
      expect(
        jsonDecode(
          (await LocalDb.baseline('crossday_status'))!['payload_json']
              as String,
        )['kind'],
        'ready',
      );
      // A failed write must expose a retryable state, and a retry can succeed.
      await db.execute(
        "CREATE TEMP TRIGGER reject_crossday BEFORE INSERT ON baselines WHEN NEW.key = 'crossday' BEGIN SELECT RAISE(ABORT, 'synthetic crossday write failure'); END",
      );
      try {
        expect(await engine.rebuildCrossDay(profile), 'failed');
        expect(
          jsonDecode(
            (await LocalDb.baseline('crossday_status'))!['payload_json']
                as String,
          )['kind'],
          'failed',
        );
      } finally {
        await db.execute('DROP TRIGGER reject_crossday');
      }
      expect(await engine.rebuildCrossDay(profile), 'ready');
    },
  );
  test(
    'overlapping short walks cannot manufacture a ten-minute streak',
    () async {
      final start = DateTime.now().subtract(const Duration(minutes: 20));
      for (final id in ['short', 'duplicate-short']) {
        await LocalDb.putSession({
          'id': id,
          'start_ts': tsOf(start),
          'end_ts': tsOf(start.add(const Duration(minutes: 6))),
          'status': 'done',
          'type': 'walking',
          'duration_min': 6,
          'created_at': tsOf(start),
        });
      }
      expect((await loadMoveStreak())!.todayDone, false);
    },
  );
  test(
    'paused walk excludes session steps while daily calories include them',
    () async {
      final start = DateTime(2026, 10, 3, 8),
          end = start.add(const Duration(minutes: 3));
      final c = WorkoutClock(
        'paused-walk',
        start,
        profile: profile,
        end: end,
        pauses: [
          (
            start: start.add(const Duration(minutes: 1)),
            end: start.add(const Duration(minutes: 2)),
          ),
        ],
      );
      await c.persist();
      final ts = start.millisecondsSinceEpoch ~/ 1000;
      await LocalDb.replacePhoneCoverageForDay('2026-10-03', [
        (startTs: ts, endTs: ts + 60, steps: 100),
        (startTs: ts + 60, endTs: ts + 120, steps: 100),
        (startTs: ts + 120, endTs: ts + 180, steps: 100),
      ]);
      final repo = LocalRepositoryImpl(getProfileMap: () => profile.toMap());
      final m = await WorkoutMeasurements.read(repo, c.id, start, end, profile);
      expect(m.clock.activeSeconds(), 120);
      expect(m.steps, 200);
      expect(m.method1('walking'), closeTo(2.74 * 200 * 80.5 / 8368, 1e-10));
      final daily = await DayUpkeep.read(repo, '2026-10-03', profile);
      expect(daily.steps, 300);
      expect(daily.runs.count, 0);
      expect(daily.parts!.steps, closeTo(2.74 * 300 * 80.5 / 8368, 1e-10));
    },
  );
  test(
    'step calorie views share dated weight, run deductions and fresh history',
    () async {
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day - 1, 8);
      final end = start.add(const Duration(minutes: 3));
      final day = dayLabelOf(start), today = todayLabel();
      await ProfileHistory.record(profile.toMap(), profile.toMap(), now: start);
      final updated = {...profile.toMap(), 'weight_kg': 91.25};
      await ProfileHistory.record(profile.toMap(), updated, now: now);
      final ts = tsOf(start);
      await LocalDb.replacePhoneCoverageForDay(day, [
        (startTs: ts, endTs: ts + 180, steps: 450),
        (startTs: ts + 180, endTs: ts + 780, steps: 1000),
      ]);
      final currentTs = tsOf(DateTime(now.year, now.month, now.day, 8));
      await LocalDb.replacePhoneCoverageForDay(today, [
        (startTs: currentTs, endTs: currentTs + 600, steps: 2000),
      ]);
      await LocalDb.putDayResult(
        dayId: day,
        algoVersion: kAlgoVersion - 1,
        windowJson: '{}',
        series: {'steps': 9999},
        payloadJson: '{}',
      );
      await LocalDb.putSession({
        'id': 'dated-run',
        'start_ts': ts,
        'end_ts': tsOf(end),
        'status': 'done',
        'type': 'running',
        'duration_min': 3,
        'created_at': ts,
      });
      await WorkoutClock(
        'dated-run',
        start,
        end: end,
        profile: profile,
      ).persist();
      await LocalDb.appendRoutePoints('dated-run', [
        for (var i = 0; i <= 180; i++)
          RoutePoint(
            seq: i,
            tsMs: start.millisecondsSinceEpoch + i * 1000,
            lat: 0,
            lng: i * 3 / 111195,
          ).toRow('dated-run'),
      ]);
      final repo = LocalRepositoryImpl(getProfileMap: () => updated);
      final daily = await DayUpkeep.read(repo, day, Profile.fromMap(updated));
      expect(daily.runs.steps, 450);
      expect(daily.parts!.steps, closeTo(stepCalories(1000, 80.5)!, 1e-9));
      final details = await DayStepsData.load(repo, want: day);
      expect(details.dayTotal, 1450);
      expect(details.walking!.kcal, closeTo(daily.parts!.steps, 1e-9));
      final chart = (await repo.getChart('steps'))['points'] as List;
      expect(chart.map((p) => p['v']).toList(), [1450, 2000]);
      final trends = await HealthData.load(repo);
      final kcal = trends.points('step_kcal');
      expect(kcal.first.v, closeTo(daily.parts!.steps, 1e-9));
      expect(kcal.last.v, closeTo(stepCalories(2000, 91.25)!, 1e-9));
      expect(
        (await HomeData.load(repo)).walkingKcal,
        closeTo(kcal.last.v, 1e-9),
      );
    },
  );
  test(
    'phone owns overlap; dense wrist-only time supplements it once',
    () async {
      final ts = DateTime(2026, 10, 3, 8).millisecondsSinceEpoch ~/ 1000;
      await LocalDb.replacePhoneCoverageForDay('2026-10-03', [
        (startTs: ts, endTs: ts + 60, steps: 50),
        (startTs: ts + 60, endTs: ts + 120, steps: 0),
      ]);
      await LocalDb.replaceBandCoverage(ts, ts + 60, 200, '2026-10-03');
      await LocalDb.replaceBandCoverage(ts + 60, ts + 120, 120, '2026-10-03');
      final r = resolveDaySteps([
        CoverageSpan(startTs: ts, endTs: ts + 60, steps: 50, fromBand: false),
        CoverageSpan(
          startTs: ts + 60,
          endTs: ts + 120,
          steps: 0,
          fromBand: false,
        ),
        CoverageSpan(startTs: ts, endTs: ts + 60, steps: 200, fromBand: true),
        CoverageSpan(
          startTs: ts + 60,
          endTs: ts + 120,
          steps: 120,
          fromBand: true,
        ),
      ], phoneFirst: true);
      expect(r.phone, 50);
      expect(r.strap, 120);
      expect(r.total, 170);
      await LocalDb.replaceBandCoverage(ts + 60, ts + 120, 120, '2026-10-03');
      expect(
        (await db.query(
          'live_coverage',
          where: 'source = ?',
          whereArgs: [LocalDb.kStepSourceBand],
        )),
        hasLength(2),
      );
    },
  );
  test('a growing wrist window replaces its preceding partial count', () async {
    final ts = DateTime(2026, 10, 3, 8).millisecondsSinceEpoch ~/ 1000;
    await LocalDb.replaceBandCoverage(ts, ts + 60, 100, '2026-10-03');
    await LocalDb.replaceBandCoverage(ts, ts + 120, 220, '2026-10-03');
    expect((await LocalDb.resolvedStepsForDay('2026-10-03')).total, 220);
  });
  test(
    'midnight slices conserve counts even with a stale row day label',
    () async {
      final a = DateTime(2026, 10, 3, 23, 59, 30),
          b = DateTime(2026, 10, 4, 0, 0, 30);
      await LocalDb.addLiveCoverage(
        a.millisecondsSinceEpoch ~/ 1000,
        b.millisecondsSinceEpoch ~/ 1000,
        101,
        '2026-10-03',
      );
      final left = await LocalDb.resolvedStepsForDay('2026-10-03');
      final right = await LocalDb.resolvedStepsForDay('2026-10-04');
      expect(left.total + right.total, 101);
      expect(left.total, 51);
      expect(right.total, 50);
    },
  );
  test(
    'goal-only day earns streak and increasing target preserves earned threshold',
    () async {
      final now = DateTime.now(), day = todayLabel();
      final ts =
          DateTime(now.year, now.month, now.day, 8).millisecondsSinceEpoch ~/
          1000;
      await LocalDb.replacePhoneCoverageForDay(day, [
        (startTs: ts, endTs: ts + 3600, steps: 10000),
      ]);
      final earned = await StepGoals.qualifying(initial: 8000);
      expect(earned, contains(day));
      final streak = moveStreak([], now, stepDays: earned);
      expect(streak.current, 1);
      expect(streak.todayDone, true);
      await StepGoals.change(8000, 12000);
      final h = await StepGoals.read();
      expect(StepGoals.goalOn(h, day), 8000);
      expect(StepGoals.targetOn(h, day), 12000);
      final repo = LocalRepositoryImpl(
        getProfileMap: () => {...profile.toMap(), 'step_goal': 12000},
      );
      expect((await repo.getToday())['step_goal'], 12000);
      expect((await repo.getProfile())['step_goal'], 12000);
      expect(
        StepGoals.goalOn(
          h,
          dayLabelOf(DateTime(now.year, now.month, now.day + 1)),
        ),
        12000,
      );
      expect(
        StepGoals.goalOn(
          h,
          dayLabelOf(DateTime(now.year, now.month, now.day - 1)),
        ),
        isNull,
      );
      expect(await StepGoals.qualifying(initial: 12000), contains(day));
    },
  );
  test(
    'dated profile edits preserve old weight and workout snapshots',
    () async {
      await ProfileHistory.record(
        profile.toMap(),
        profile.toMap(),
        now: DateTime(2026, 10, 3),
      );
      await BodyWeight.put(db, '2026-10-02', 79.5);
      await ProfileHistory.record(profile.toMap(), {
        ...profile.toMap(),
        'weight_kg': 81.25,
      }, now: DateTime(2026, 10, 4));
      expect((await ProfileHistory.on('2026-10-03', profile)).weightKg, 79.5);
      expect((await ProfileHistory.on('2026-10-04', profile)).weightKg, 81.25);
      final c = WorkoutClock(
        'weight-snapshot',
        DateTime(2026, 10, 3),
        profile: profile,
        end: DateTime(2026, 10, 3, 1),
      );
      await c.persist();
      expect(WorkoutClock.read(c.id, c.start).profile!.weightKg, 80.5);
    },
  );
  test(
    'serving units and fractional amounts scale every supplied nutrient',
    () async {
      final sausage = myFoodDef(
        key: 'link',
        label: 'Sausage',
        refGrams: 1,
        unit: 'link',
        kcal: 110,
        protein: 13,
        fat: 0,
      );
      final e = entryFromFood(
        sausage,
        2.5,
        id: 'portion',
        date: '2026-10-03',
        meal: 'breakfast',
      ).inGroup('Protein');
      expect(e.unit, 'link');
      expect(e.quantity, 2.5);
      expect(e.kcal, 275);
      expect(e.proteinG, 32.5);
      expect(e.fatG, 0);
      expect(e.carbsG, isNull);
      expect(portionText(2.5, 'link'), '2.5 links');
      expect(portionText(100, ''), '100');
      final half = e.atQuantity(1.25);
      expect(half.kcal, 137.5);
      expect(half.group, 'Protein');
      expect(half.id, e.id);
      await NutritionDb.putFoodDef(db, sausage);
      await NutritionDb.put(db, e);
      final saved = MealTemplate(
        key: 'saved',
        label: 'Usual',
        meal: 'breakfast',
        items: [('link', 2.5)],
        units: {'link': 'link'},
      );
      await MyFoods.putMeal(db, saved);
      await MyFoods.logMeal(
        db,
        saved,
        '2026-10-02',
        'breakfast',
        group: 'Protein',
      );
      final logged = (await NutritionDb.entriesForDay(db, '2026-10-02')).single;
      expect(logged.kcal, 275);
      expect(logged.unit, 'link');
      expect(logged.group, 'Protein');
    },
  );
  test(
    'voice milestones preserve true last-kilometre pace after rehydration',
    () {
      final voice = KmVoice();
      expect(voice.update(0.8, 480, speak: false), isNull);
      expect(voice.update(1.2, 720, speak: false), kmCue(1, 600));
      final restored = KmVoice.restore(voice.snapshot());
      expect(restored.update(2.2, 1260, speak: false), kmCue(2, 552));
      expect(restored.update(2.3, 1320, speak: false), isNull);
    },
  );
  test(
    'missing HR minutes and a final partial minute do not inflate Method 2',
    () {
      final one = keytelActiveKcal([151], 1, profile)!;
      final partial = keytelActiveKcal([151, null, 151, 151], 2.5, profile)!;
      expect(partial.kcal, closeTo(one.kcal * 1.5, 1e-9));
      expect(partial.measured, 2);
      expect(partial.slots, 3);
      expect(walkingEnergy(double.nan, profile), isNull);
      expect(maintenance(profile, steps: double.infinity), isNull);
    },
  );
  test(
    'motion cadence uses actual final seconds; malformed retained arrays abstain',
    () {
      final w = MotionWindow(
        DateTime(2026, 10, 3),
        60,
        [70],
        [120],
        seconds: [30],
      );
      expect(w.cadence, 140);
      expect(
        motionMix(
          steps: w.steps,
          meters: w.meters,
          chunkSec: 60,
          seconds: w.seconds,
        ).runM,
        120,
      );
      expect(
        MotionWindow.fromJson({
          's': 1,
          'c': 60,
          'steps': [1, 2],
          'm': [1.0],
        }),
        isNull,
      );
    },
  );
  test(
    'route pauses have no distance bridge and no best effort across a break',
    () {
      final start = DateTime(2026, 10, 3, 8);
      final pts = [
        for (var i = 0; i <= 120; i++)
          RoutePoint(
            seq: i,
            tsMs: start.millisecondsSinceEpoch + i * 1000,
            lat: 0,
            lng: i * 3 / 111195,
          ),
      ];
      final clock = WorkoutClock(
        'route-pause',
        start,
        end: start.add(const Duration(seconds: 120)),
        pauses: [
          (
            start: start.add(const Duration(seconds: 30)),
            end: start.add(const Duration(seconds: 90)),
          ),
        ],
      );
      final active = activeTrack(pts, clock);
      expect(totalDistanceMeters(active), closeTo(180, 2));
      expect(bestEffortSeconds(active, cumulativeMeters(active), 150), isNull);
      expect(clock.secondsAt(start.add(const Duration(seconds: 100))), 40);
    },
  );
  test(
    'midnight run calories conserve distance and overlapping sessions bill movement once',
    () async {
      final start = DateTime(2026, 10, 3, 23, 58),
          end = start.add(const Duration(minutes: 3));
      final clock = WorkoutClock(
        'original',
        start,
        end: end,
        profile: profile,
        pauses: [
          (
            start: start.add(const Duration(seconds: 30)),
            end: start.add(const Duration(seconds: 60)),
          ),
        ],
      );
      await clock.persist();
      for (final id in ['original', 'duplicate']) {
        final begin = id == 'original'
            ? start
            : start.add(const Duration(minutes: 1));
        await LocalDb.putSession({
          'id': id,
          'start_ts': begin.millisecondsSinceEpoch ~/ 1000,
          'end_ts': end.millisecondsSinceEpoch ~/ 1000,
          'status': 'done',
          'type': 'running',
          'duration_min': 3,
          'calories': 9999,
          'created_at': tsOf(start),
        });
        final pts = [
          for (var sec = 0; sec <= end.difference(begin).inSeconds; sec += 5)
            RoutePoint(
              seq: sec ~/ 5,
              tsMs: begin.millisecondsSinceEpoch + sec * 1000,
              lat: 30 + sec * 3 / 111195,
              lng: -95,
            ),
        ];
        await LocalDb.appendRoutePoints(id, [for (final p in pts) p.toRow(id)]);
        if (id == 'duplicate')
          await WorkoutClock(id, begin, end: end, profile: profile).persist();
      }
      final ts = start.millisecondsSinceEpoch ~/ 1000;
      await LocalDb.replacePhoneCoverageForDay('2026-10-03', [
        (startTs: ts, endTs: ts + 180, steps: 600),
      ]);
      final repo = LocalRepositoryImpl(getProfileMap: () => profile.toMap());
      final run = (await summariseRun(repo, 'original', ts, ts + 180))!;
      expect(
        run.byDay.values.fold<double>(0, (a, b) => a + b.meters),
        closeTo(run.meters, .1),
      );
      final left = await DayUpkeep.read(repo, '2026-10-03', profile),
          right = await DayUpkeep.read(repo, '2026-10-04', profile);
      expect(
        left.runs.kcal + right.runs.kcal,
        closeTo(run.floorKcal(profile.weightKg)!, 1),
      );
      expect(left.runs.steps + right.runs.steps, 500);
      expect(
        left.parts!.steps + right.parts!.steps,
        closeTo(stepCalories(100, 80.5)!, 1e-8),
      );
      final stored = await repo.getWorkout('original');
      expect(stored['calories'], closeTo(run.floorKcal(profile.weightKg)!, 1));
      expect(stored['duration_min'], 2);
      await repo.endWorkout('original');
      await repo.endWorkout('original');
      expect(
        (await LocalDb.session('original'))!['end_ts'],
        tsOf(end),
        reason: 'repeat finish must not extend the stopped session',
      );
    },
  );
  test(
    'food and weight maintenance requires every aligned day, preserving optional macros',
    () {
      final weights = [
        for (var i = 0; i <= 14; i += 2)
          (date: dayLabelOf(DateTime(2026, 9, 1 + i)), kg: 80.0),
      ];
      final days = [
        for (var i = 0; i < 14; i++)
          rollupDay(dayLabelOf(DateTime(2026, 9, 1 + i)), [
            FoodEntry(
              id: 'e$i',
              atTs: tsOf(DateTime(2026, 9, 1 + i, 20)),
              date: dayLabelOf(DateTime(2026, 9, 1 + i)),
              meal: 'dinner',
              label: 'Day',
              kcal: 2200,
              proteinG: 150,
            ),
          ], today: '2026-10-04'),
      ];
      expect(estimatedMaintenance(weights, days)!.kcal, 2200);
      expect(maintenanceFoodCoverage(weights, days), (complete: 14, days: 14));
      expect(estimatedMaintenance(weights, [...days]..removeAt(5)), isNull);
      final unrelated = [...days]..removeAt(5);
      unrelated.add(
        rollupDay('2026-08-31', [
          FoodEntry(
            id: 'outside',
            atTs: tsOf(DateTime(2026, 8, 31, 20)),
            date: '2026-08-31',
            meal: 'dinner',
            label: 'Day',
            kcal: 2200,
          ),
        ], today: '2026-10-04'),
      );
      expect(estimatedMaintenance(weights, unrelated), isNull);
    },
  );
  test(
    'varying wrist cadence at midnight keeps earlier measured counts fixed',
    () {
      final midnight = DateTime(2026, 10, 4).millisecondsSinceEpoch ~/ 1000;
      final gait = GaitRuns();
      gait.addChunk(
        endTs: midnight,
        seconds: 60,
        rawSteps: 60,
        floorTs: midnight - 60,
      );
      gait.addChunk(
        endTs: midnight + 60,
        seconds: 60,
        rawSteps: 120,
        floorTs: midnight - 60,
      );
      expect(gait.runs, hasLength(2));
      expect(gait.runs.first.rawSteps, 60);
      expect(gait.runs.last.rawSteps, 120);
      expect(gait.runs.first.endTs, midnight);
    },
  );
  test(
    'restore includes templates, weights, coverage and calculation anchors',
    () async {
      await BodyWeight.put(db, '2026-10-03', 80.5);
      await MyFoods.putMeal(
        db,
        const MealTemplate(
          key: 'restore-meal',
          label: 'Meal',
          meal: 'lunch',
          items: [],
        ),
      );
      final ts = DateTime(2026, 10, 3, 8).millisecondsSinceEpoch ~/ 1000;
      await LocalDb.replacePhoneCoverageForDay('2026-10-03', [
        (startTs: ts, endTs: ts + 60, steps: 100),
      ]);
      await CalculationStore.write(
        'profile.calculation_history',
        '{"baseline":{"weight_kg":80.5}}',
      );
      final folder = await Directory.systemTemp.createTemp('build73_restore_');
      final file = path.join(folder.path, 'export.db');
      await db.execute('VACUUM INTO ?', [file]);
      try {
        await LocalDb.wipeAll();
        expect(
          await CalculationStore.read('profile.calculation_history'),
          isNull,
        );
        await LocalDb.importFromDbFile(file);
        expect((await db.query('body_weight')).single['kg'], 80.5);
        expect((await MyFoods.meals(db)).single.label, 'Meal');
        expect((await LocalDb.resolvedStepsForDay('2026-10-03')).total, 100);
        expect(
          await CalculationStore.read('profile.calculation_history'),
          contains('80.5'),
        );
      } finally {
        await File(file).delete();
        await folder.delete();
      }
    },
  );
}
