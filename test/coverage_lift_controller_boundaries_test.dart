// Retained live Lift controls: atomic split/variation writes and rest/idle decisions.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/lift_log.dart';
import 'package:whoop_companion/notify/notification_service.dart';
import 'package:whoop_companion/ui2/activity/lift_log_ui.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('lift-controller-boundaries');
  });
  setUp(() async {
    await resetCoverageStore();
    NotificationService.instance.debugRequestPermission = () async => false;
    NotificationService.instance.debugProbePermission = () async => false;
    NotificationService.instance.invalidatePermissionCache();
  });
  tearDown(() async {
    await RestTimer.skip();
    NotificationService.instance.debugRequestPermission = null;
    NotificationService.instance.debugProbePermission = null;
    NotificationService.instance.invalidatePermissionCache();
  });
  tearDownAll(LocalDb.close);
  Future<void> flush(WidgetTester t) async {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  }

  for (final fromSplit in [false, true]) {
    test(
      'COV-47 tracking-only session starts one durable log and refuses changing a logged variation $fromSplit',
      () async {
        final split = LiftSplit(
          id: 'synthetic-split',
          name: 'Synthetic split',
          exercises: [
            LiftSplitExercise(
              name: 'Synthetic press',
              loadMode: LiftLoadMode.total,
            ),
          ],
        );
        await LiftLogDb.saveSplits([split]);
        final ctl = LiftLogController('synthetic-session');
        try {
          await ctl.load();
          expect(ctl.workout, isNull);
          await ctl.startLogging(from: fromSplit ? split : null);
          final id = ctl.workout!.id;
          await ctl.startLogging(from: split);
          expect(ctl.workout!.id, id);
          if (!fromSplit)
            await ctl.addExercise('Synthetic press', LiftLoadMode.total, '');
          final exercise = ctl.workout!.exercises.single;
          await ctl.setVariation(exercise.id, '  Synthetic bar  ');
          expect(ctl.workout!.exercises.single.equipmentNote, 'Synthetic bar');
          await ctl.mutate(
            (w) => w.addSet(exercise.id, reps: 8, load: 20, at: DateTime.now()),
            activity: false,
          );
          await ctl.setVariation(exercise.id, 'Other setup');
          expect(ctl.message, contains('Sets are logged on this variation'));
          expect(
            (await LiftLogDb.forSession(
              'synthetic-session',
            ))!.exercises.single.equipmentNote,
            'Synthetic bar',
          );
          await ctl.addExercise(
            'Synthetic press',
            LiftLoadMode.total,
            'Synthetic bar',
          );
          expect(ctl.message, contains('already in this workout'));
          expect(ctl.workout!.exercises, hasLength(1));
          await ctl.addExercise(
            'Synthetic row',
            LiftLoadMode.stack,
            'Synthetic machine',
          );
          expect(ctl.workout!.exercises, hasLength(2));
          if (fromSplit) {
            expect(ctl.splits.single.exercises, hasLength(2));
            final changed = ctl.splits.single.copy()
              ..name = 'Synthetic renamed';
            await ctl.saveSplits([changed]);
            expect(ctl.split!.name, 'Synthetic renamed');
            expect(ctl.workout!.exercises.first.sets, hasLength(1));
          }
        } finally {
          ctl.dispose();
        }
      },
    );
  }
  testWidgets(
    'COV-47 tracking-only live panel can begin a set log without restarting the session',
    (t) async {
      await localizedPage(
        t,
        const Scaffold(
          body: SingleChildScrollView(
            child: LiftLivePanel(sessionId: 'synthetic-track'),
          ),
        ),
      );
      expect(
        find.text('This workout records time and heart rate only.'),
        findsOneWidget,
      );
      final start = find.byWidgetPredicate(
        (w) => w is BigButton && w.label == 'Log sets',
      );
      await invokeControl(t, t.widget<BigButton>(start).onTap);
      expect(
        await t.runAsync(() => LiftLogDb.forSession('synthetic-track')),
        isNotNull,
      );
      expect(
        find.text('This workout records time and heart rate only.'),
        findsNothing,
      );
    },
  );
  testWidgets(
    'COV-47 live rest extension and skip update the same saved timer',
    (t) async {
      final workout = LiftWorkout(
        sessionId: 'synthetic-rest',
        startedAt: DateTime.now(),
      );
      workout.addExercise(
        name: 'Synthetic press',
        loadMode: LiftLoadMode.total,
      );
      await LiftLogDb.save(workout);
      await t.runAsync(() => RestTimer.start(90, sessionId: 'synthetic-rest'));
      await localizedPage(
        t,
        const Scaffold(
          body: SingleChildScrollView(
            child: LiftLivePanel(sessionId: 'synthetic-rest'),
          ),
        ),
      );
      final before = (await t.runAsync(RestTimer.deadline))!;
      final add = find.byWidgetPredicate(
        (w) => w is Pressable && w.semanticLabel == 'Add 30 seconds',
      );
      await reveal(t, add);
      await invokeControl(t, t.widget<Pressable>(add).onTap);
      expect(
        (await t.runAsync(RestTimer.deadline))!.difference(before).inSeconds,
        inInclusiveRange(29, 30),
      );
      final skip = find.byWidgetPredicate(
        (w) => w is Pressable && w.semanticLabel == 'Skip rest',
      );
      await invokeControl(t, t.widget<Pressable>(skip).onTap);
      expect(await t.runAsync(RestTimer.deadline), isNull);
    },
  );
  for (final choice in ['Finish at last set', 'Finish now', 'Keep going']) {
    testWidgets('COV-47 forgotten Lift $choice keeps the user authoritative', (
      t,
    ) async {
      final at = DateTime.now().subtract(const Duration(hours: 2));
      final last = at.add(const Duration(minutes: 30));
      final workout = LiftWorkout(sessionId: 'synthetic-idle', startedAt: at);
      final exercise = workout.addExercise(
        name: 'Synthetic press',
        loadMode: LiftLoadMode.total,
      );
      workout.addSet(exercise, reps: 8, load: 20, at: last);
      await LiftLogDb.save(workout);
      final ended = <DateTime?>[];
      await localizedPage(
        t,
        Scaffold(
          body: SingleChildScrollView(
            child: LiftLivePanel(
              sessionId: 'synthetic-idle',
              onFinishAt: (end) async => ended.add(end),
            ),
          ),
        ),
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
      await flush(t);
      expect(
        ended,
        choice == 'Keep going'
            ? isEmpty
            : [
                choice == 'Finish now'
                    ? null
                    : DateTime.fromMillisecondsSinceEpoch(
                        last.millisecondsSinceEpoch,
                      ),
              ],
      );
      expect(
        (await t.runAsync(
          () => LiftLogDb.forSession('synthetic-idle'),
        ))!.endedAt,
        isNull,
        reason:
            'the caller owns finishing; displaying the prompt cannot finish a log',
      );
    });
  }
}
