// Actual retained Lift controls over authored preference refusals and SQLite.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/lift_log.dart';
import 'package:whoop_companion/notify/notification_service.dart';
import 'package:whoop_companion/state/prefs.dart';
import 'package:whoop_companion/ui2/activity/lift_log_ui.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'coverage_deep_lift_test.dart' show action, ioFrame;
import 'coverage_step_tail_recovery_test.dart' show CheckpointStore;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferencesStorePlatform original;
  late CheckpointStore store;
  late LiftWorkout workout;
  final notifications = NotificationService.instance;
  final cancelled = <int?>[];
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('lift-timer-refusals');
  });
  setUp(() async {
    await resetCoverageStore();
    original = SharedPreferencesStorePlatform.instance;
    store = CheckpointStore(targetKey: 'lift.rest.deadline');
    SharedPreferencesStorePlatform.instance = store;
    SharedPreferences.resetStatic();
    await Prefs.ensureLoaded();
    cancelled.clear();
    notifications.debugProbePermission = () async => false;
    notifications.debugRequestPermission = () async => false;
    notifications.debugCancel = (id) async => cancelled.add(id);
    notifications.invalidatePermissionCache();
    workout = LiftWorkout(
      sessionId: 'authored-rest',
      startedAt: DateTime.now(),
    );
    workout.addExercise(name: 'Authored press', loadMode: LiftLoadMode.total);
    await LiftLogDb.save(workout);
  });
  tearDown(() async {
    store.refuseWrite = store.refuseRemove = null;
    await RestTimer.skip();
    notifications.debugProbePermission = null;
    notifications.debugRequestPermission = null;
    notifications.debugCancel = null;
    notifications.invalidatePermissionCache();
    SharedPreferencesStorePlatform.instance = original;
    SharedPreferences.resetStatic();
    await Prefs.ensureLoaded();
  });
  tearDownAll(LocalDb.close);

  Future<void> open(WidgetTester t) => localizedPage(
    t,
    const Scaffold(
      body: SingleChildScrollView(
        child: LiftLivePanel(sessionId: 'authored-rest'),
      ),
    ),
  );
  Future<void> unchanged(WidgetTester t) async {
    final saved = (await t.runAsync(
      () => LiftLogDb.forSession('authored-rest'),
    ))!;
    expect(saved.setCount, 0);
    expect(
      saved.startedAt.millisecondsSinceEpoch,
      workout.startedAt.millisecondsSinceEpoch,
    );
    expect(saved.endedAt, isNull);
  }

  for (final failure in ['false', 'throws']) {
    for (final operation in ['extend', 'skip', 'default']) {
      testWidgets(
        'Lift $operation preference $failure keeps saved state and retries',
        (t) async {
          await t.runAsync(() => RestTimer.setDefault(60));
          if (operation != 'default') {
            await t.runAsync(
              () => RestTimer.start(90, sessionId: 'authored-rest'),
            );
          }
          final before = await t.runAsync(RestTimer.deadline);
          await open(t);
          if (operation == 'default') {
            store.targetKey = 'lift.rest.default_sec';
            await t.tap(action('Rest timer'));
            await t.pumpAndSettle();
            store.refuseWrite = failure;
            await t.tap(action('90 seconds'));
            await ioFrame(t);
            expect(
              find.text('Could not save the rest timer setting. Try again.'),
              findsOneWidget,
            );
            expect(await t.runAsync(RestTimer.defaultSec), 60);
            store.refuseWrite = null;
            await t.tap(action('Rest timer'));
            await t.pumpAndSettle();
            await t.tap(action('90 seconds'));
            await ioFrame(t);
            expect(await t.runAsync(RestTimer.defaultSec), 90);
          } else {
            final control = action(
              operation == 'extend' ? 'Add 30 seconds' : 'Skip rest',
            );
            await reveal(t, control);
            if (operation == 'extend') {
              store.refuseWrite = failure;
            } else {
              store.refuseRemove = failure;
            }
            await invokeControl(t, t.widget<Pressable>(control).onTap);
            expect(
              find.text(
                operation == 'extend'
                    ? 'Could not extend the rest timer. Try again.'
                    : 'The alert was cancelled, but the timer state could not save. Try Skip again.',
              ),
              findsOneWidget,
            );
            expect(await t.runAsync(RestTimer.deadline), before);
            if (operation == 'skip') {
              expect(cancelled, contains(NotificationService.idRestTimer));
            }
            store.refuseWrite = store.refuseRemove = null;
            await invokeControl(t, t.widget<Pressable>(control).onTap);
            final after = await t.runAsync(RestTimer.deadline);
            if (operation == 'extend') {
              expect(
                after!.difference(before!).inSeconds,
                inInclusiveRange(29, 30),
              );
            } else {
              expect(after, isNull);
            }
          }
          await unchanged(t);
          await t.pumpWidget(const SizedBox());
          await t.pumpAndSettle();
        },
      );
    }
    test(
      'set remains saved when its rest timer preference $failure is refused',
      () async {
        await RestTimer.setDefault(60);
        final controller = LiftLogController('authored-rest');
        try {
          await controller.load();
          store.refuseWrite = failure;
          await controller.logSet(
            workout.exercises.single.id,
            reps: 8,
            load: 20,
          );
          expect(
            controller.message,
            'Set saved. The rest timer could not start; try it again.',
          );
          final saved = (await LiftLogDb.forSession('authored-rest'))!;
          expect(saved.setCount, 1);
          expect(await RestTimer.deadline(), isNull);
          store.refuseWrite = null;
          await RestTimer.start(60, sessionId: 'authored-rest');
          expect(await RestTimer.deadline(), isNotNull);
          expect((await LiftLogDb.forSession('authored-rest'))!.setCount, 1);
        } finally {
          controller.dispose();
        }
      },
    );
  }
}
