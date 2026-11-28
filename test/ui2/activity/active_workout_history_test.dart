// An active workout row must use the live route and protect the session.
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/gps/workout_clock.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/activity/live.dart';
import 'package:whoop_companion/ui2/screens/food_picker.dart' show SwipeDelete;
import 'package:whoop_companion/ui2/screens/home_screen.dart' show monthName;
import 'package:whoop_companion/ui2/screens/workout_screen.dart';

import '../screens/workout_history_actions_test.dart' show action;
import '../../support/audit_visual.dart' show loadAuditFonts;
import '../../support/coverage_store.dart';
import '../../support/localized_coverage.dart';

Future<void> waitFor(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    await tester.pump(const Duration(milliseconds: 30));
    if (finder.evaluate().isNotEmpty) return;
  }
  expect(finder, findsOneWidget);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('active-workout-history');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  for (final private in [false, true]) {
    testWidgets(
      'history opens and protects the active workout: $private',
      (t) async {
        final app = AppState.forTesting()
          ..user = {'age': 30, 'sex': 'f', 'weight_kg': 70, 'height_cm': 170};
        app.repo = LocalRepositoryImpl(
          getProfileMap: () => app.user,
          onSessionChanged: app.publishSessionChange,
        );
        addTearDown(() async {
          app.dispose();
          LiveDraft.clear();
          await WorkoutClock.flushWrites();
          WorkoutClock.current = null;
        });
        final now = DateTime.now();
        final savedStart = private
            ? DateTime(now.year, now.month - 1, 15, 12)
            : now.subtract(const Duration(minutes: 40));
        final start = savedStart.millisecondsSinceEpoch ~/ 1000;
        await t.runAsync(() async {
          await SessionStore.put({
            'id': 'saved-walk',
            'type': 'walking',
            'start_ts': start,
            'end_ts': start + 1200,
            'status': 'done',
            'source': 'manual',
            'created_at': start * 1000,
          });
          expect(
            await app.startWorkout(
              workoutId: 'active-yoga',
              type: 'yoga',
              private: private,
            ),
            isTrue,
          );
        });
        final activeRow = await t.runAsync(
          () => SessionStore.byId('active-yoga'),
        );

        await localizedPage(
          t,
          const WorkoutHistoryScreen(),
          app: app,
          settle: false,
        );
        await waitFor(t, action('Open Yoga session'));
        final live = action('Open Yoga session');
        final saved = action('Open Walking session');
        final current = app.activeWorkout!.startTime;
        final earlier = DateTime.fromMillisecondsSinceEpoch(start * 1000);
        if (earlier.month != current.month || earlier.year != current.year) {
          final month = monthName(earlier.month, null);
          final label = earlier.year == current.year
              ? month
              : '$month ${earlier.year}';
          await t.tap(find.text(label));
          await waitFor(t, saved);
        }
        expect(live, findsOneWidget);
        expect(saved, findsOneWidget);
        expect(
          find.ancestor(of: live, matching: find.byType(SwipeDelete)),
          findsNothing,
        );
        expect(
          find.ancestor(of: saved, matching: find.byType(SwipeDelete)),
          findsOneWidget,
        );
        expect(action('Session options'), findsOneWidget);

        final before = await t.runAsync(() async {
          final db = await LocalDb.instance;
          return db.query('sessions', orderBy: 'id');
        });
        expect(before!.first, activeRow);
        expect(before.last['start_ts'], start);
        expect(before.last['end_ts'], start + 1200);

        await t.tap(live);
        await t.pump();
        await waitFor(t, find.byType(LiveFlow));
        expect(t.takeException(), isNull);
        expect(
          t.widget<SessionDestination>(find.byType(SessionDestination)).id,
          'active-yoga',
        );
        expect(find.byType(LiveFlow), findsOneWidget);
        expect(app.activeWorkout?.workoutId, 'active-yoga');
        expect(LiveDraft.current?.private, private);
        expect(
          await t.runAsync(() async {
            final db = await LocalDb.instance;
            return db.query('sessions', orderBy: 'id');
          }),
          before,
        );
      },
      timeout: const Timeout(Duration(seconds: 25)),
    );
  }
}
