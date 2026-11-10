// Current Home Resume action through a real authored SQLite workout.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/gps/screen_wake.dart';
import 'package:whoop_companion/gps/workout_clock.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/state/units_controller.dart';
import 'package:whoop_companion/ui2/activity/live.dart';
import 'package:whoop_companion/ui2/screens/today_plan.dart';
import 'package:whoop_companion/ui2/screens/workout_screen.dart';
import 'support/audit_visual.dart';
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState app;
  late UnitsController units;
  setUpAll(() async {
    await coverageStore('today-plan-retained-actions');
    await loadAuditFonts();
  });
  setUp(() async {
    await resetCoverageStore();
    LiveDraft.clear();
    ScreenWake.resetForTest();
    app = AppState.forTesting()
      ..user = const Profile(
        ageYears: 30,
        sex: 'f',
        weightKg: 70,
        heightCm: 170,
      ).toMap();
    app.repo = LocalRepositoryImpl(getProfileMap: () => app.user);
    units = UnitsController.seed(UnitSystem.metric);
  });
  tearDown(() async {
    app.dispose();
    units.dispose();
    await WorkoutClock.flushWrites();
    WorkoutClock.current = null;
    LiveDraft.clear();
    await ScreenWake.release();
  });
  tearDownAll(LocalDb.close);

  for (final scale in [1.0, 3.1]) {
    testWidgets(
      'COV-59 Home Resume preserves the live session at ${scale}x text',
      (t) async {
        const id = 'authored-home-resume';
        expect(
          await t.runAsync(
            () => app.startWorkout(workoutId: id, type: 'other'),
          ),
          true,
        );
        final live = app.activeWorkout!;
        final before = await t.runAsync(() => LocalDb.session(id));
        expect(before!['status'], 'live');
        expect(before['end_ts'], isNull);

        await localizedPage(
          t,
          const Scaffold(body: SingleChildScrollView(child: TodayPlanCard())),
          app: app,
          units: units,
          scale: scale,
        );
        expect(find.text('Train'), findsNothing);
        expect(find.text('Resume'), findsOneWidget);
        await t.ensureVisible(find.text('Resume'));
        await t.tap(find.text('Resume'));
        for (var i = 0; i < 5; i++) {
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)),
          );
          await t.pump(const Duration(milliseconds: 100));
        }
        expect(t.takeException(), isNull);
        expect(find.byType(SessionDestination), findsOneWidget);
        expect(find.byType(LiveShell), findsOneWidget);
        expect(app.activeWorkout, same(live));
        expect(LiveDraft.current!.startedAt, live.startTime);
        expect(await t.runAsync(() => LocalDb.session(id)), equals(before));

        Navigator.of(t.element(find.byType(SessionDestination))).pop();
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(find.byType(SessionDestination), findsNothing);
        expect(find.text('Resume'), findsOneWidget);
        expect(app.activeWorkout, same(live));
        expect(await t.runAsync(() => LocalDb.session(id)), equals(before));
        expect(
          await t.runAsync(
            () async => (await LocalDb.instance).query('sessions'),
          ),
          hasLength(1),
        );
        await t.pumpWidget(const SizedBox());
        await t.pumpAndSettle();
      },
    );
  }
}
