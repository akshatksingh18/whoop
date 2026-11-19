// Real shipped Lift idle decisions through the host,clock,SQLite and summary.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:whoop_companion/ui2/activity/summary.dart';
import 'package:whoop_companion/ui2/screens/workout_screen.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  late AppState app;
  late UnitsController units;
  const id = 'authored-idle-lift';
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('idle-lift-host-controls', fresh: true);
  });
  setUp(() async {
    await resetCoverageStore();
    LiveDraft.clear();
    units = UnitsController.seed(UnitSystem.metric);
    app = AppState.forTesting()
      ..user = {'age': 30, 'sex': 'f', 'height_cm': 170.0, 'weight_kg': 70.0};
    app.repo = LocalRepositoryImpl(getProfileMap: () => app.user);
    ScreenWake.resetForTest();
  });
  tearDown(() async {
    await (await LocalDb.instance).execute(
      'DROP TRIGGER IF EXISTS authored_finish_refusal',
    );
    app.dispose();
    units.dispose();
    await WorkoutClock.flushWrites();
    WorkoutClock.current = null;
    LiveDraft.clear();
    await LiveDraft.retrySave();
    await RestTimer.skip();
    ScreenWake.resetForTest();
  });
  tearDownAll(LocalDb.close);

  for (final choice in ['Finish at last set', 'Finish now', 'Keep going']) {
    testWidgets(
      'real Lift idle $choice preserves chosen window and saved log',
      (t) async {
        final start = DateTime.fromMillisecondsSinceEpoch(
          DateTime.now().millisecondsSinceEpoch ~/ 1000 * 1000,
        ).subtract(const Duration(hours: 2));
        late WorkoutClock chosenClock;
        final last = start.add(const Duration(minutes: 30));
        final a = activityByName('Weight training')!;
        await t.runAsync(() async {
          await LocalDb.putSession({
            'id': id,
            'type': a.typeKey,
            'start_ts': start.millisecondsSinceEpoch ~/ 1000,
            'status': 'live',
            'private': 0,
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
          chosenClock = WorkoutClock.begin(
            id,
            start,
            const Profile(weightKg: 70),
          );
          LiveDraft.begin(a, weightKg: 70, startedAt: start);
          final lift = LiftWorkout(sessionId: id, startedAt: start);
          final e = lift.addExercise(
            name: 'Authored press',
            loadMode: LiftLoadMode.total,
          );
          lift.addSet(e, reps: 8, load: 20, at: last);
          await LiftLogDb.save(lift);
          await WorkoutClock.flushWrites();
        });
        await localizedPage(
          t,
          liveFor(a, weightKg: 70, host: activityHost(app)),
          app: app,
          units: units,
          push: true,
        );
        final button = find.byWidgetPredicate(
          (w) =>
              w is BigButton &&
              (choice == 'Finish at last set'
                  ? w.label.startsWith('Finish at ')
                  : w.label == choice),
        );
        await reveal(t, button);
        await invokeControl(t, t.widget<BigButton>(button).onTap);
        if (choice == 'Keep going') {
          expect(find.byType(ActivitySummary), findsNothing);
          expect(find.byType(LiveShell), findsOneWidget);
          expect(chosenClock.end, isNull);
          expect(LiveDraft.current, isNotNull);
          expect(app.activeWorkout!.workoutId, id);
          final stillLive = (await t.runAsync(() => LocalDb.session(id)))!;
          expect(stillLive['status'], 'live');
          expect(
            (await t.runAsync(() => LiftLogDb.forSession(id)))!.endedAt,
            isNull,
          );
          expect(find.text('Still working out?'), findsNothing);
          await t.pumpWidget(const SizedBox());
          await t.pumpAndSettle();
          return;
        }
        for (
          var i = 0;
          i < 30 && find.byType(ActivitySummary).evaluate().isEmpty;
          i++
        ) {
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await t.pumpAndSettle();
        }
        expect(find.byType(ActivitySummary), findsOneWidget);
        final summary = t.widget<ActivitySummary>(find.byType(ActivitySummary));
        final row = (await t.runAsync(() => LocalDb.session(id)))!;
        final log = (await t.runAsync(() => LiftLogDb.forSession(id)))!;
        final end = chosenClock.end!;
        if (choice == 'Finish at last set') {
          expect(end, last);
          expect(summary.result.duration, const Duration(minutes: 30));
        } else {
          expect(end.difference(start).inSeconds, inInclusiveRange(7200, 7230));
          expect(summary.result.duration, chosenClock.activeDuration());
        }
        expect(row['status'], 'done');
        expect(row['end_ts'], end.millisecondsSinceEpoch ~/ 1000);
        expect(
          log.endedAt,
          DateTime.fromMillisecondsSinceEpoch(
            end.millisecondsSinceEpoch ~/ 1000 * 1000,
          ),
        );
        expect(log.exercises.single.sets.single.reps, 8);
        expect(log.exercises.single.sets.single.load, 20);
        expect(summary.result.sessionId, id);
        expect(summary.onRetrySave, isNull);
        expect(app.activeWorkout, isNull);
        expect(LiveDraft.current, isNull);
        expect(
          (await t.runAsync(
            () => (LocalDb.instance).then((db) => db.query('sessions')),
          ))!,
          hasLength(1),
        );
        await t.pumpWidget(const SizedBox());
        await t.pumpAndSettle();
      },
    );
  }
}
