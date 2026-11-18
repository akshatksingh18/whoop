// Stored session -> actual startup recovery -> idle watch -> shared durable gate.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/data/calculation_store.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/lift_log.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/gps/screen_wake.dart';
import 'package:whoop_companion/gps/workout_clock.dart';
import 'package:whoop_companion/notify/notification_center.dart';
import 'package:whoop_companion/notify/notification_event.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const id = 'authored-recovered-idle';
  const profile = Profile(ageYears: 30, sex: 'f', weightKg: 70, heightCm: 170);
  final center = NotificationCenter.instance;
  final original = center.presentSink;
  final seen = <NotificationEvent>[];
  final apps = <AppState>[];
  var allow = true;
  late DateTime start;
  setUpAll(() => coverageStore('recovered-idle-notification', fresh: true));
  setUp(() async {
    await resetCoverageStore();
    seen.clear();
    allow = true;
    start = DateTime.now().subtract(const Duration(minutes: 30));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notif_quiet_enabled', false);
    center.presentSink = (event, {bool allowPermissionPrompt = true}) async {
      seen.add(event);
      return allow;
    };
    await LocalDb.putSession({
      'id': id,
      'start_ts': start.millisecondsSinceEpoch ~/ 1000,
      'status': 'live',
      'type': 'other',
      'source': 'manual',
      'private': 1,
      'rpe': 7,
      'created_at': 1,
    });
    await WorkoutClock(
      id,
      start,
      profile: profile,
      results: {'authored-evidence': 'retain'},
    ).persist();
  });
  tearDown(() async {
    for (final app in apps) {
      app.dispose();
    }
    apps.clear();
    await WorkoutClock.flushWrites();
    WorkoutClock.current = null;
    center.presentSink = original;
    await ScreenWake.release();
  });
  tearDownAll(LocalDb.close);
  Future<AppState> recover() async {
    final app = AppState.forTesting()..user = profile.toMap();
    apps.add(app);
    app.repo = LocalRepositoryImpl(getProfileMap: () => app.user);
    await app.debugReconcileOrphanedLiveWorkout();
    expect(app.activeWorkout!.workoutId, id);
    expect(app.activeWorkout!.currentHr, isNull);
    return app;
  }

  Future<void> until(bool Function() ready, AppState app) async {
    for (var i = 0; i < 100 && !ready(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(ready(), true, reason: app.logLines.join('\n'));
  }

  bool fired(AppState app) =>
      app.logLines.any((s) => s.contains('[workout] idle nudge fired for $id'));
  void dispose(AppState app) {
    apps.remove(app);
    app.dispose();
  }

  Future<void> preserved(Map<String, dynamic>? row, String? clock) async {
    expect(await LocalDb.session(id), row);
    expect(await CalculationStore.read('workout.clock.$id'), clock);
    expect(WorkoutClock.current!.end, isNull);
    expect(WorkoutClock.current!.profile!.weightKg, 70);
    expect(WorkoutClock.current!.results['authored-evidence'], 'retain');
  }

  for (final lift in ['none', 'finished']) {
    for (final permission in [false, true]) {
      test(
        '$lift Lift Log with presentation=$permission preserves the live session and restart dedupe',
        () async {
          if (lift == 'finished') {
            await LiftLogDb.save(
              LiftWorkout(
                id: 'authored-finished-log',
                startedAt: start,
                endedAt: start.add(const Duration(minutes: 10)),
                sessionId: id,
              ),
            );
          }
          final row = await LocalDb.session(id);
          final clock = await CalculationStore.read('workout.clock.$id');
          final logs = await (await LocalDb.instance).query('lift_log');
          final app = await recover();
          allow = permission;
          app.debugTickWorkout();
          await until(() => seen.length == 1, app);
          if (permission) {
            await until(() => fired(app), app);
          }
          final event = seen.single;
          expect(event.dedupeKey, '$id:workout_idle');
          expect(event.title, 'Still working out?');
          expect(event.body, contains('20 minutes'));
          expect(event.route, contains(id));
          // The ask must never finalize the session, invent HR, or alter its log.
          await preserved(row, clock);
          await Future<void>.delayed(const Duration(milliseconds: 30));
          final claimed = await (await LocalDb.instance).query('notif_fired');
          expect(claimed, permission ? hasLength(1) : isEmpty);
          app.debugTickWorkout();
          await Future<void>.delayed(const Duration(milliseconds: 30));
          expect(seen, hasLength(1));
          dispose(app);
          final resumed = await recover();
          allow = true;
          resumed.debugTickWorkout();
          if (!permission) {
            await until(() => fired(resumed), resumed);
          }
          await Future<void>.delayed(const Duration(milliseconds: 50));
          expect(seen, hasLength(permission ? 1 : 2));
          expect(
            await (await LocalDb.instance).query('notif_fired'),
            hasLength(1),
          );
          expect(await (await LocalDb.instance).query('lift_log'), logs);
          await preserved(row, clock);
        },
      );
    }
  }
  test(
    'an active Lift Log confirms the idle watch without sending the duplicate ask',
    () async {
      await LiftLogDb.save(
        LiftWorkout(id: 'authored-active-log', startedAt: start, sessionId: id),
      );
      final row = await LocalDb.session(id);
      final clock = await CalculationStore.read('workout.clock.$id');
      final logs = await (await LocalDb.instance).query('lift_log');
      final app = await recover();
      app.debugTickWorkout();
      await (await LocalDb.instance).query('lift_log');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(app.activeWorkout!.idleWatch.lastAskAt, isNotNull);
      expect(
        app.activeWorkout!.idleWatch.onTick(
          DateTime.now().add(const Duration(hours: 1)),
          hr: null,
          gate: null,
        ),
        false,
      );
      expect(seen, isEmpty);
      expect(await (await LocalDb.instance).query('notif_fired'), isEmpty);
      expect(await (await LocalDb.instance).query('lift_log'), logs);
      await preserved(row, clock);
    },
  );
  test(
    'a refused Lift Log read is isolated and the retained session can ask after recovery',
    () async {
      final row = await LocalDb.session(id);
      final clock = await CalculationStore.read('workout.clock.$id');
      final db = await LocalDb.instance;
      final app = await recover();
      await db.execute(
        'ALTER TABLE lift_log RENAME TO authored_retained_lift_log',
      );
      try {
        app.debugTickWorkout();
        await until(
          () => app.logLines.any(
            (s) => s.contains('[workout] idle nudge skipped:'),
          ),
          app,
        );
        expect(seen, isEmpty);
        expect(await db.query('notif_fired'), isEmpty);
        await preserved(row, clock);
      } finally {
        await db.execute(
          'ALTER TABLE authored_retained_lift_log RENAME TO lift_log',
        );
      }
      dispose(app);
      final resumed = await recover();
      resumed.debugTickWorkout();
      await until(() => fired(resumed), resumed);
      expect(seen, hasLength(1));
      expect(await db.query('notif_fired'), hasLength(1));
      await preserved(row, clock);
    },
  );
}
