// Approved duration repair through the real Lift host/save/refusal/retry path.
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
import '../sync/history_watchdog_budget_test.dart' show driveHistory;
import '../support/audit_visual.dart' show loadAuditFonts;
import '../support/coverage_store.dart';
import '../support/localized_coverage.dart';

void main() {
  late AppState app;
  late UnitsController units;
  const id = 'authored-idle-lift';
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('lift-authoritative-finish', fresh: true);
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

  for (final scenario in ['ordinary', 'paused', 'reopened']) {
    for (final refuse in [false, true]) {
      testWidgets(
        'Lift $scenario last-set duration survives real save refusal=$refuse and retry',
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
            if (scenario == 'paused') {
              chosenClock.setPaused(
                true,
                start.add(const Duration(minutes: 10)),
              );
              chosenClock.setPaused(
                false,
                start.add(const Duration(minutes: 15)),
              );
            }
            final lift = LiftWorkout(sessionId: id, startedAt: start);
            final e = lift.addExercise(
              name: 'Authored press',
              loadMode: LiftLoadMode.total,
            );
            lift.addSet(e, reps: 8, load: 20, at: last);
            await LiftLogDb.save(lift);
            await WorkoutClock.flushWrites();
            final db = await LocalDb.instance;
            if (refuse) {
              await db.execute(
                "CREATE TRIGGER authored_finish_refusal BEFORE INSERT ON sessions WHEN NEW.status='done' BEGIN SELECT RAISE(ABORT,'authored finish refusal'); END",
              );
            }
          });
          await localizedPage(
            t,
            liveFor(a, weightKg: 70, host: activityHost(app)),
            app: app,
            units: units,
            push: true,
          );
          if (scenario == 'reopened') {
            final minimise = find.byWidgetPredicate(
              (w) => w is Pressable && w.semanticLabel == 'Minimise',
            );
            await reveal(t, minimise);
            await t.tap(minimise);
            await t.pumpAndSettle();
            expect(find.byType(LiveShell), findsNothing);
            LiveDraft.debugForget();
            final context = t.element(find.text('Closed test page'));
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    liveFor(a, weightKg: 70, host: activityHost(app)),
              ),
            );
            await t.pumpAndSettle();
            await t.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 80)),
            );
            await t.pumpAndSettle();
          }
          final button = find.byWidgetPredicate(
            (w) => w is BigButton && w.label.startsWith('Finish at '),
          );
          await reveal(t, button);
          await invokeControl(t, t.widget<BigButton>(button).onTap);
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
          final summary = t.widget<ActivitySummary>(
            find.byType(ActivitySummary),
          );
          final db = (await t.runAsync(() => LocalDb.instance))!;
          final row = (await t.runAsync(() => LocalDb.session(id)))!;
          final log = (await t.runAsync(() => LiftLogDb.forSession(id)))!;
          expect(chosenClock.end, last);
          expect(
            summary.result.duration,
            Duration(minutes: scenario == 'paused' ? 25 : 30),
            reason:
                'chosen last-set duration must survive an unsaved summary as well',
          );
          if (!refuse) {
            expect(row['status'], 'done');
            expect(row['end_ts'], last.millisecondsSinceEpoch ~/ 1000);
            expect(log.endedAt, last);
          } else {
            expect(row['status'], 'live');
            expect(summary.onRetrySave, isNotNull);
            expect(LiveDraft.current, isNotNull);
            await t.runAsync(
              () => db.execute('DROP TRIGGER authored_finish_refusal'),
            );
            final retry = t.widget<StatusCard>(
              find.byWidgetPredicate(
                (w) =>
                    w is StatusCard &&
                    w.what == 'This session is not saved yet',
              ),
            );
            late Future<void> retryWork;
            await t.runAsync(() async {
              final dynamic callback = retry.onFix;
              retryWork = callback() as Future<void>;
              await Future<void>.delayed(const Duration(milliseconds: 5));
            });
            await driveHistory(t, retryWork);
            for (
              var i = 0;
              i < 30 &&
                  find
                      .text('This session is not saved yet')
                      .evaluate()
                      .isNotEmpty;
              i++
            ) {
              await t.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 30)),
              );
              await t.pumpAndSettle();
            }
            final saved = (await t.runAsync(() => LocalDb.session(id)))!;
            expect(saved['status'], 'done');
            expect(saved['end_ts'], last.millisecondsSinceEpoch ~/ 1000);
            expect(saved['duration_min'], scenario == 'paused' ? 25 : 30);
            expect(
              (await t.runAsync(() => LiftLogDb.forSession(id)))!.endedAt,
              last,
            );
            expect(app.activeWorkout, isNull);
            expect(LiveDraft.current, isNull);
            expect(find.text('This session is not saved yet'), findsNothing);
          }
          await t.pumpWidget(const SizedBox());
          await t.pumpAndSettle();
        },
      );
    }
  }
}
