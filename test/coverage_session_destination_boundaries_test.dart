// Shared session entry points read the real synthetic store and retained draft.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/gps/workout_clock.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/activity/catalogue.dart';
import 'package:whoop_companion/ui2/activity/live.dart';
import 'package:whoop_companion/ui2/activity/summary.dart';
import 'package:whoop_companion/ui2/screens/log_workout.dart';
import 'package:whoop_companion/ui2/screens/workout_screen.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

const profile = Profile(ageYears: 30, sex: 'f', heightCm: 170, weightKg: 70);
Finder surface(String s) =>
    find.byWidgetPredicate((w) => w is Surface && w.semanticLabel == s);
Future<void> io(WidgetTester t) async {
  for (var i = 0; i < 12; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    await t.pump(const Duration(milliseconds: 25));
  }
  await t.pumpAndSettle();
  expect(t.takeException(), isNull);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState app;
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('session-destination');
  });
  setUp(() async {
    await resetCoverageStore();
    LiveDraft.clear();
    await LiveDraft.retrySave();
    app = AppState.forTesting()..user = profile.toMap();
    app.repo = LocalRepositoryImpl(getProfileMap: () => app.user);
  });
  tearDown(() async {
    app.dispose();
    app.activeWorkout = null;
    LiveDraft.clear();
    await LiveDraft.retrySave();
    await WorkoutClock.flushWrites();
  });
  tearDownAll(LocalDb.close);
  Future<void> open(WidgetTester t, Widget w) async {
    await localizedPage(t, w, app: app, settle: false);
    await io(t);
  }

  Future<void> saved({String type = 'running', bool unknownEnd = false}) =>
      LocalDb.putSession({
        'id': 'synthetic-session',
        'type': type,
        'start_ts': DateTime(2021, 4, 6, 8).millisecondsSinceEpoch ~/ 1000,
        'end_ts': DateTime(2021, 4, 6, 8, 20).millisecondsSinceEpoch ~/ 1000,
        'created_at': 1,
        'status': 'done',
        'source': 'manual',
        'end_ts_fabricated': unknownEnd ? 1 : 0,
        'calories': 80,
        'calories_basis': 'active',
      });
  testWidgets(
    'an active-session link without a running session falls back to Train',
    (t) async {
      await open(t, const SessionDestination(null));
      expect(find.byType(WorkoutScreen), findsOneWidget);
      expect(find.text('Train'), findsWidgets);
      expect(app.activeWorkout, isNull);
    },
  );
  for (final retained in [false, true]) {
    testWidgets(
      'active destination ${retained ? 'reuses' : 'reconstructs'} the owning live draft',
      (t) async {
        final start = DateTime.now().subtract(const Duration(minutes: 10));
        app.activeWorkout = LiveWorkoutState(
          startTime: start,
          targetKcal: 0,
          workoutId: 'synthetic-live',
          type: 'general_workout',
          profile: profile,
        );
        await LocalDb.putSession({
          'id': 'synthetic-live',
          'type': 'general_workout',
          'start_ts': start.millisecondsSinceEpoch ~/ 1000,
          'created_at': 1,
          'status': 'live',
          'source': 'manual',
          'private': 1,
        });
        if (retained) {
          LiveDraft.begin(
            activityByName('General workout')!,
            private: false,
            weightKg: 71,
            startedAt: start,
          )..data['synthetic-note'] = 'kept';
          await LiveDraft.retrySave();
        }
        await open(t, const SessionDestination(null));
        expect(find.byType(LiveMeasured), findsOneWidget);
        final draft = LiveDraft.current!;
        expect(draft.startedAt, start);
        expect(draft.private, !retained);
        expect(draft.weightKg, retained ? 71 : 70);
        if (retained) expect(draft.data['synthetic-note'], 'kept');
        expect(
          (await t.runAsync(
            () => LocalDb.session('synthetic-live'),
          ))!['status'],
          'live',
        );
      },
    );
  }
  testWidgets('Train offers Resume instead of creating a second session', (
    t,
  ) async {
    app.activeWorkout = LiveWorkoutState(
      startTime: DateTime.now(),
      targetKcal: 0,
      workoutId: 'synthetic-live',
      type: 'general_workout',
      profile: profile,
    );
    await open(t, const WorkoutScreen());
    expect(surface('Resume General workout'), findsOneWidget);
    final text = (await readPage(t)).join(' ');
    expect(text, contains('In progress · started'));
    await reveal(t, surface('Resume General workout'));
    await t.tap(surface('Resume General workout'));
    await io(t);
    expect(find.byType(SessionDestination), findsOneWidget);
    expect(find.byType(LiveMeasured), findsOneWidget);
    expect(app.activeWorkout!.workoutId, 'synthetic-live');
  });
  testWidgets(
    'a transient session read failure keeps Retry and recovers the saved result',
    (t) async {
      await saved();
      final db = await LocalDb.instance;
      await db.execute(
        'ALTER TABLE sessions RENAME TO synthetic_held_sessions',
      );
      try {
        await open(t, const SessionDestination('synthetic-session'));
        expect(find.text('Session could not load'), findsOneWidget);
      } finally {
        await db.execute(
          'ALTER TABLE synthetic_held_sessions RENAME TO sessions',
        );
      }
      final retry = find.byWidgetPredicate(
        (w) => w is StatusCard && w.what == 'Session could not load',
      );
      await invokeControl(t, t.widget<StatusCard>(retry).onFix);
      await io(t);
      expect(find.byType(ActivitySummary), findsOneWidget);
      expect(find.text('Session could not load'), findsNothing);
    expect(t.widget<ActivitySummary>(find.byType(ActivitySummary)).result.calories, isNull,
      reason: 'A saved arbitrary calorie number cannot replace absent route inputs');
      expect(
        (await t.runAsync(
          () => LocalDb.session('synthetic-session'),
        ))!['calories'],
        isNull,
      );
    },
  );
  testWidgets(
    'unknown finish routes to the existing correction without inventing a duration',
    (t) async {
      await saved(unknownEnd: true);
      await open(t, const SessionDestination('synthetic-session'));
      final card = find.byWidgetPredicate(
        (w) => w is StatusCard && w.what == 'Finish time unknown',
      );
      expect(card, findsOneWidget);
      expect(find.byType(ActivitySummary), findsNothing);
      t.widget<StatusCard>(card).onFix!();
      await io(t);
      final form = t.widget<LogWorkout>(find.byType(LogWorkout));
      expect(form.sessionId, 'synthetic-session');
      expect(form.start, form.end);
      Navigator.of(t.element(find.byType(LogWorkout))).pop();
      await io(t);
      expect(card, findsOneWidget);
      expect(
        (await t.runAsync(
          () => LocalDb.session('synthetic-session'),
        ))!['end_ts_fabricated'],
        1,
      );
    },
  );
}
