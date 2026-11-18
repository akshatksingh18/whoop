// Active Lift recovery: durable skipped links, refused sets and restored rest expiry.
// Authored SQLite/preferences; only native notification/haptic boundaries are substituted.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/lift_log.dart';
import 'package:whoop_companion/notify/notification_service.dart';
import 'package:whoop_companion/ui2/activity/lift_log_ui.dart';
import 'coverage_deep_lift_test.dart' show field, ioFrame;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final notifications = NotificationService.instance;
  const id = 'authored-lift-recovery';
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('lift-recovery-boundaries');
  });
  setUp(() async {
    await resetCoverageStore();
    notifications.debugRequestPermission = () async => false;
    notifications.debugProbePermission = () async => false;
    notifications.debugCancel = (_) async {};
    notifications.invalidatePermissionCache();
    await RestTimer.setDefault(0);
  });
  tearDown(() async {
    await (await LocalDb.instance).execute(
      'DROP TRIGGER IF EXISTS authored_lift_refusal',
    );
    await RestTimer.skip();
    notifications.debugRequestPermission = null;
    notifications.debugProbePermission = null;
    notifications.debugCancel = null;
    notifications.invalidatePermissionCache();
  });
  tearDownAll(LocalDb.close);

  Future<void> refuse() async => (await LocalDb.instance).execute(
    "CREATE TRIGGER authored_lift_refusal BEFORE INSERT ON lift_log BEGIN SELECT RAISE(ABORT,'authored write refusal'); END",
  );
  Future<void> allow() async =>
      (await LocalDb.instance).execute('DROP TRIGGER authored_lift_refusal');
  Future<LiftWorkout> seed(LiftLoadMode mode) async {
    final w = LiftWorkout(
      sessionId: id,
      startedAt: DateTime.fromMillisecondsSinceEpoch(
        DateTime.now().millisecondsSinceEpoch,
      ),
    );
    w.addExercise(
      name: 'Authored press',
      loadMode: mode,
      equipmentNote: 'Authored setup',
    );
    await LiftLogDb.save(w);
    return w;
  }

  Future<void> open(WidgetTester t, double scale) => localizedPage(
    t,
    const Scaffold(
      body: SingleChildScrollView(child: LiftLivePanel(sessionId: id)),
    ),
    scale: scale,
  );

  for (final mode in [LiftLoadMode.total, LiftLoadMode.addedWeight]) {
    for (final denied in [false, true]) {
      test(
        'skipped ${mode.name} split link survives refused re-add=$denied and retries',
        () async {
          final split = LiftSplit(
            id: 'authored-recovery-split',
            name: 'Authored split',
            exercises: [
              LiftSplitExercise(
                name: 'Authored press',
                loadMode: mode,
                equipmentNote: 'Authored setup',
              ),
            ],
          );
          await LiftLogDb.saveSplits([split]);
          await beginLiftLog(
            LiftSplitChoice(split),
            sessionId: id,
            startedAt: DateTime.fromMillisecondsSinceEpoch(
              DateTime.now().millisecondsSinceEpoch,
            ),
          );
          final ctl = LiftLogController(id);
          try {
            await ctl.load();
            final originalId = ctl.workout!.id;
            final link = ctl.workout!.exercises.single.splitExerciseId;
            expect(link, split.exercises.single.id);
            await ctl.removeExercise(
              ctl.workout!.exercises.single.id,
              fromSplit: false,
            );
            expect(ctl.workout!.exercises, isEmpty);
            expect(ctl.workout!.skipped, [link]);
            final prior = (await LiftLogDb.forSession(id))!.toJson();
            final splitsBefore = [
              for (final s in await LiftLogDb.splits()) s.toJson(),
            ];
            if (denied) await refuse();
            await ctl.addExercise('Authored press', mode, 'Authored setup');
            if (denied) {
              expect(ctl.message, isNotNull);
              expect(ctl.workout!.toJson(), prior);
              expect((await LiftLogDb.forSession(id))!.toJson(), prior);
              expect([
                for (final s in await LiftLogDb.splits()) s.toJson(),
              ], splitsBefore);
              await allow();
              await ctl.addExercise('Authored press', mode, 'Authored setup');
            }
            expect(ctl.message, isNull);
            final saved = (await LiftLogDb.forSession(id))!;
            expect(saved.id, originalId);
            expect(saved.skipped, isEmpty);
            expect(saved.exercises, hasLength(1));
            expect(saved.exercises.single.splitExerciseId, link);
            expect(saved.exercises.single.sets, isEmpty);
            expect(saved.exercises.single.loadMode, mode);
            expect(saved.endedAt, isNull);
            expect([
              for (final s in await LiftLogDb.splits()) s.toJson(),
            ], splitsBefore);
          } finally {
            ctl.dispose();
          }
        },
      );
    }
    for (final scale in [1.0, 3.1]) {
      testWidgets(
        'actual ${mode.name} set refusal keeps draft and retries at ${scale}x',
        (t) async {
          final w = await seed(mode);
          await open(t, scale);
          await reveal(t, find.text('Authored press'));
          await t.tap(find.text('Authored press'));
          await ioFrame(t);
          await t.enterText(
            field(
              mode == LiftLoadMode.addedWeight
                  ? 'lb added · blank for bodyweight'
                  : 'lb total',
            ),
            '20',
          );
          await t.enterText(field('Reps'), '8');
          await t.runAsync(refuse);
          final log = find.text('Log set');
          await reveal(t, log);
          await t.tap(log);
          await ioFrame(t);
          expect(
            (await t.runAsync(() => LiftLogDb.forSession(id)))!.setCount,
            0,
          );
          expect(find.byType(SnackBar), findsOneWidget);
          expect(t.widget<TextField>(field('Reps')).controller!.text, '8');
          await t.runAsync(allow);
          await t.tap(log);
          await ioFrame(t);
          final saved = (await t.runAsync(() => LiftLogDb.forSession(id)))!;
          expect(saved.id, w.id);
          expect(saved.startedAt, w.startedAt);
          expect(saved.endedAt, isNull);
          expect(saved.exercises.single.sets, hasLength(1));
          expect(saved.exercises.single.sets.single.reps, 8);
          expect(saved.exercises.single.sets.single.load, 20);
        },
      );
    }
  }
}
