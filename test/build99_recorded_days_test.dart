// Synthetic travel and timing fixtures; no personal records.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:openstrap_edge/compute/day_upkeep.dart';
import 'package:openstrap_edge/compute/profile.dart';
import 'package:openstrap_edge/compute/streak.dart';
import 'package:openstrap_edge/data/calculation_store.dart';
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/nutrition_store.dart';
import 'package:openstrap_edge/data/profile_history.dart';
import 'package:openstrap_edge/data/pushups.dart';
import 'package:openstrap_edge/data/pushup_reminders.dart';
import 'package:openstrap_edge/gps/workout_clock.dart';
import 'package:openstrap_edge/state/prefs.dart';
import 'package:openstrap_edge/ui2/screens/home_screen.dart'
    show denseDays, daysBehind;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final root = await Directory(
      'build/research-local/build99-dates',
    ).absolute.create(recursive: true);
    LocalDb.dbName = '${root.path}/synthetic.sqlite';
    await LocalDb.close();
    await databaseFactory.deleteDatabase(LocalDb.dbName);
    db = await LocalDb.instance;
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.ensureLoaded();
    await LocalDb.wipeAll();
  });
  tearDown(() => DayClock.install([], []));
  tearDownAll(() async {
    await LocalDb.close();
    await databaseFactory.deleteDatabase(LocalDb.dbName);
  });

  DateTime travelNow() {
    // Tokyo has reached Jan 2; travelling west holds that label in Honolulu.
    final start = DateTime.utc(2025, 12, 31, 15).millisecondsSinceEpoch ~/ 1000;
    final change =
        DateTime.utc(2026, 1, 1, 15, 30).millisecondsSinceEpoch ~/ 1000;
    final changes = [
      ZoneChange(start, 'Asia/Tokyo'),
      ZoneChange(change, 'Pacific/Honolulu'),
    ];
    DayClock.install(
      buildDayZones(
        fromSec: start,
        throughSec: change + 3 * 86400,
        changes: changes,
      ),
      changes,
    );
    final now = DateTime.fromMillisecondsSinceEpoch((change + 6 * 3600) * 1000);
    expect(todayLabel(now), '2026-01-02');
    return now;
  }

  test('profile edits belong to the stored travel day', () async {
    final now = travelNow();
    await ProfileHistory.record({'weight_kg': 70}, {'weight_kg': 71}, now: now);
    final history = ProfileHistory.decode(
      await CalculationStore.read(ProfileHistory.key),
    );
    expect((history['2026-01-02'] as Map?)?['weight_kg'], 71);
  });

  test(
    'startup without a profile cannot erase restored dated anchors',
    () async {
      final raw = jsonEncode({
        'baseline': {'weight_kg': 70, 'height_cm': 180},
        '2026-01-02': {'weight_kg': 71, 'height_cm': 180},
      });
      await CalculationStore.write(ProfileHistory.key, raw);
      await ProfileHistory.record(null, {}, now: DateTime(2026, 1, 2));
      expect(await CalculationStore.read(ProfileHistory.key), raw);
    },
  );

  test(
    'Food windows and calendar include the stored current travel day',
    () async {
      final now = travelNow();
      await db.insert('food_entry', {
        'id': 'synthetic-food',
        'date': '2026-01-02',
        'meal': 'breakfast',
        'label': 'Synthetic',
        'kcal': 300,
        'created_at': 1,
        'updated_at': 1,
      });
      final window = await NutritionDb.window(db, now: now);
      expect(window.days.last.date, '2026-01-02');
      expect(window.days.last.entries, hasLength(1));
      final month = await NutritionDb.month(db, '2026-01', now: now);
      expect(month.days.last.date, '2026-01-02');
    },
  );

  test('a step goal can be earned on the held travel day', () async {
    final now = travelNow();
    final day = DayClock.forDate('2026-01-02')!;
    await LocalDb.addLiveCoverage(
      day.startSec,
      now.millisecondsSinceEpoch ~/ 1000,
      1000,
      day.date,
      source: LocalDb.kStepSourcePhone,
    );
    expect(
      await StepGoals.qualifying(initial: 1000, at: now),
      contains(day.date),
    );
  });

  test(
    'dense charts place held-day evidence under today without losing a slot',
    () {
      final now = travelNow();
      final second = now.millisecondsSinceEpoch ~/ 1000;
      expect(daysBehind(second, at: now), 0);
      expect(denseDays([(t: second, v: 60)], 7, at: now), [
        null,
        null,
        null,
        null,
        null,
        null,
        60,
      ]);
    },
  );

  test('Pushups actions and day status agree on the recorded travel day', () {
    final now = travelNow();
    final session = PushupSession(
      id: 'synthetic-pushups',
      day: '2026-01-02',
      started: now.subtract(const Duration(hours: 1)),
      interval: 45,
      goal: 2,
      state: PushupState.running,
    );
    final action = PushupAction(
      id: 'synthetic-action',
      kind: 'done',
      sessionId: session.id,
      at: now,
    );
    expect(action.applyTo(session), isTrue);
    expect(
      PushupDay.of(session.day, [session], now)?.status,
      PushupGoalStatus.atRisk,
    );
    session.log(PushupEvent(at: now, kind: PushupEventKind.done));
    expect(pushupQualifiedDays([session], now), contains(session.day));
  });

  test('background Pushups bounds work without a hydrated day timeline', () {
    final now = travelNow();
    final day = DayClock.forDate('2026-01-02')!;
    final mirror = (
      session: 'synthetic-pushups',
      day: day.date,
      state: 'running',
      interval: 45,
      startSec: day.startSec,
      endSec: day.endSec,
    );
    DayClock.install([], []);
    expect(pushupMirrorContains(mirror, now), isTrue);
    expect(
      pushupMirrorContains(
        mirror,
        DateTime.fromMillisecondsSinceEpoch(day.endSec * 1000),
      ),
      isFalse,
    );
  });

  test(
    'activity streak files a workout under its recorded travel day',
    () async {
      final now = travelNow();
      final end = now.subtract(const Duration(minutes: 10));
      final start = end.subtract(const Duration(minutes: 20));
      await LocalDb.putSession({
        'id': 'synthetic-travel',
        'start_ts': start.millisecondsSinceEpoch ~/ 1000,
        'end_ts': end.millisecondsSinceEpoch ~/ 1000,
        'type': 'weight_training',
        'status': 'done',
        'created_at': 1,
      });
      final streak = await loadMoveStreak(at: now);
      expect(streak?.todayDone, isTrue);
      expect(streak?.last7.last, MoveDay.lift);
    },
  );

  test(
    'lifting overlap during a pause retains all unique active minutes',
    () async {
      final start = DateTime(2026, 1, 5, 9);
      final middle = start.add(const Duration(minutes: 30));
      final endA = start.add(const Duration(hours: 1));
      final endB = start.add(const Duration(minutes: 90));
      final profile = Profile.fromMap({'weight_kg': 70});
      for (final (id, begin, end, pauses) in [
        ('synthetic-a', start, endA, [(start: middle, end: endA)]),
        ('synthetic-b', middle, endB, <ActiveWindow>[]),
      ]) {
        await LocalDb.putSession({
          'id': id,
          'start_ts': begin.millisecondsSinceEpoch ~/ 1000,
          'end_ts': end.millisecondsSinceEpoch ~/ 1000,
          'type': 'weight_training',
          'status': 'done',
          'created_at': 1,
        });
        await WorkoutClock(
          id,
          begin,
          end: end,
          profile: profile,
          pauses: pauses,
        ).persist();
      }
      final lifting = await liftingOn('2026-01-05', profile);
      final expected = sessionActiveKcal(
        p: profile,
        type: 'weight_training',
        minutes: 90,
      )!;
      expect(lifting?.kcal, closeTo(expected, 0.001));
      expect(lifting?.sessions, 2);
      // Historical session anchors remain usable if today's weight is absent.
      expect(
        (await liftingOn('2026-01-05', Profile.fromMap({})))?.kcal,
        closeTo(expected, 0.001),
      );
    },
  );

  test(
    'actual lifting overlap counts once and retains captured weights',
    () async {
      final start = DateTime(2026, 1, 5, 9);
      final profile = Profile.fromMap({'weight_kg': 70});
      for (final (id, begin, end, kg) in [
        ('synthetic-a', start, start.add(const Duration(hours: 1)), 70),
        (
          'synthetic-b',
          start.add(const Duration(minutes: 30)),
          start.add(const Duration(minutes: 90)),
          80,
        ),
      ]) {
        await LocalDb.putSession({
          'id': id,
          'start_ts': begin.millisecondsSinceEpoch ~/ 1000,
          'end_ts': end.millisecondsSinceEpoch ~/ 1000,
          'type': 'weight_training',
          'status': 'done',
          'created_at': 1,
        });
        await WorkoutClock(
          id,
          begin,
          end: end,
          profile: Profile.fromMap({'weight_kg': kg}),
        ).persist();
      }
      final expected =
          sessionActiveKcal(p: profile, type: 'weight_training', minutes: 60)! +
          sessionActiveKcal(
            p: Profile.fromMap({'weight_kg': 80}),
            type: 'weight_training',
            minutes: 30,
          )!;
      expect(
        (await liftingOn('2026-01-05', profile))?.kcal,
        closeTo(expected, 0.001),
      );
    },
  );
}
