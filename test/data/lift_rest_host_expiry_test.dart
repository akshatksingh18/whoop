// Approved expiry repair:the actual paused/running Lift host with durable state.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/state/prefs.dart';
import 'package:whoop_companion/notify/notification_service.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/lift_log.dart';
import 'package:whoop_companion/data/lift_reminders.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/gps/screen_wake.dart';
import 'package:whoop_companion/gps/workout_clock.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/state/units_controller.dart';
import 'package:whoop_companion/ui2/activity/catalogue.dart';
import 'package:whoop_companion/ui2/activity/live.dart';
import 'package:whoop_companion/ui2/screens/workout_screen.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import '../support/audit_visual.dart';
import '../support/coverage_store.dart';
import '../support/localized_coverage.dart';

void main() {
  final banner = WidgetsApp.debugAllowBannerOverride;
  WidgetsApp.debugAllowBannerOverride = false;
  late AppState app;
  late UnitsController units;
  const id = 'authored-idle-lift';
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('lift-rest-host-expiry', fresh: true);
  });
  setUp(() async {
    await resetCoverageStore();
    LiveDraft.clear();
    units = UnitsController.seed(UnitSystem.metric);
    app = AppState.forTesting()
      ..user = {'age': 30, 'sex': 'f', 'height_cm': 170.0, 'weight_kg': 70.0};
    app.repo = LocalRepositoryImpl(getProfileMap: () => app.user);
    ScreenWake.resetForTest();
    NotificationService.instance.debugProbePermission = () async => false;
    NotificationService.instance.debugRequestPermission = () async => false;
  });
  tearDown(() async {
    await (await LocalDb.instance).execute(
      'DROP TRIGGER IF EXISTS authored_finish_refusal',
    );
    NotificationService.instance.debugProbePermission = null;
    NotificationService.instance.debugRequestPermission = null;
    app.dispose();
    units.dispose();
    await WorkoutClock.flushWrites();
    WorkoutClock.current = null;
    LiveDraft.clear();
    await LiveDraft.retrySave();
    await RestTimer.skip();
    ScreenWake.resetForTest();
  });
  tearDownAll(() async {
    await LocalDb.close();
    WidgetsApp.debugAllowBannerOverride = banner;
  });

  for (final paused in [false, true]) {
    for (final scale in [1.0, 2.0, 3.1]) {
      testWidgets('real Lift host rest expiry paused=$paused at ${scale}x', (
        t,
      ) async {
        final a = activityByName('Weight training')!;
        final start = DateTime.fromMillisecondsSinceEpoch(
          DateTime.now().millisecondsSinceEpoch ~/ 1000 * 1000,
        ).subtract(const Duration(minutes: 10));
        await t.runAsync(() async {
          await SessionStore.put({
            'id': id,
            'type': a.typeKey,
            'start_ts': start.millisecondsSinceEpoch ~/ 1000,
            'status': 'live',
            'created_at': 1,
          });
          app.activeWorkout = LiveWorkoutState(
            startTime: start,
            targetKcal: 300,
            workoutId: id,
            type: a.typeKey,
            profile: const Profile(weightKg: 70),
            met: a.met,
          );
          WorkoutClock.begin(id, start, const Profile(weightKg: 70));
          LiveDraft.begin(a, weightKg: 70, startedAt: start);
          final w = LiftWorkout(sessionId: id, startedAt: start);
          w.addExercise(name: 'Authored press', loadMode: LiftLoadMode.total);
          await LiftLogDb.save(w);
          await WorkoutClock.flushWrites();
          await Prefs.saveValues({
            'lift.rest.deadline': DateTime.now()
                .add(const Duration(seconds: 4))
                .millisecondsSinceEpoch,
          });
        });
        await localizedPage(
          t,
          liveFor(a, weightKg: 70, host: activityHost(app)),
          app: app,
          units: units,
          push: true,
          scale: scale,
        );
        Finder action(String label) => find.byWidgetPredicate(
          (w) => w is Pressable && w.semanticLabel == label,
        );
        expect(action('Skip rest'), findsOneWidget);
        if (paused) {
          await t.tap(action('Pause'));
          await t.pumpAndSettle();
          expect(LiveDraft.current!.pausedAt, isNotNull);
          expect(action('Resume'), findsOneWidget);
          await t.pump(const Duration(seconds: 1));
          await t.pumpAndSettle();
        }
        final saved = await t.runAsync(() => SessionStore.byId(id));
        final lift = (await t.runAsync(
          () => LiftLogDb.forSession(id),
        ))!.toJson();
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 4200)),
        );
        await t.pump(const Duration(seconds: 2));
        expect(await t.runAsync(RestTimer.deadline), isNull);
        expect(await t.runAsync(() => SessionStore.byId(id)), saved);
        expect(
          (await t.runAsync(() => LiftLogDb.forSession(id)))!.toJson(),
          lift,
        );
        expect(action(paused ? 'Resume' : 'Pause'), findsOneWidget);
        expect(action('Skip rest'), findsNothing);
      });
    }
  }
}
