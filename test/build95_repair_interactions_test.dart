// Regression coverage for nested Build 95 interactions. All data is synthetic.
import 'dart:convert';
import 'dart:ui' show Tristate;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/profile.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/lift_log.dart';
import 'package:openstrap_edge/data/local_repository_impl.dart';
import 'package:openstrap_edge/data/pushups.dart';
import 'package:openstrap_edge/data/pushup_reminders.dart';
import 'package:openstrap_edge/gps/workout_clock.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:openstrap_edge/state/prefs.dart';
import 'package:openstrap_edge/ui2/activity/lift_log_ui.dart';
import 'package:openstrap_edge/ui2/activity/catalogue.dart';
import 'package:openstrap_edge/ui2/activity/live.dart';
import 'package:openstrap_edge/ui2/activity/summary.dart';
import 'package:openstrap_edge/ui2/onboarding/profile_setup.dart';
import 'package:openstrap_edge/ui2/profile/settings.dart';
import 'package:openstrap_edge/ui2/screens/log_workout.dart';
import 'package:openstrap_edge/ui2/screens/pushups_screen.dart';
import 'package:openstrap_edge/ui2/screens/workout_screen.dart';
import 'package:openstrap_edge/ui2/ui2.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

Future<void> until(WidgetTester t, bool Function() done) async {
  for (var i = 0; i < 150 && !done(); i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await t.pump(const Duration(milliseconds: 20));
  }
  expect(done(), true);
}

Widget frame(Widget child, [AppState? app]) {
  final body = MaterialApp(theme: buildTheme(Brightness.light), home: child);
  return app == null
      ? body
      : ChangeNotifierProvider.value(value: app, child: body);
}

Finder press(String label) =>
    find.byWidgetPredicate((w) => w is Pressable && w.semanticLabel == label);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.dbName = 'build95_interactions_synthetic.db';
    await databaseFactory.deleteDatabase(
      p.join(await getDatabasesPath(), LocalDb.dbName),
    );
    db = await LocalDb.instance;
    tzdata.initializeTimeZones();
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.ensureLoaded();
    await LocalDb.wipeAll();
    LiveDraft.clear();
    await LiveDraft.retrySave();
    WorkoutClock.current = null;
  });
  tearDownAll(() async {
    await LocalDb.close();
    await databaseFactory.deleteDatabase(
      p.join(await getDatabasesPath(), LocalDb.dbName),
    );
  });
  test('DST-relative dates use day labels rather than 24-hour durations', () {
    final zone = tz.getLocation('America/Chicago');
    expect(
      dayLabel(
        tz.TZDateTime(zone, 2026, 3, 8, 12),
        now: tz.TZDateTime(zone, 2026, 3, 9, 12),
      ),
      'Yesterday',
    );
    expect(
      dayLabel(
        tz.TZDateTime(zone, 2026, 11, 1, 12),
        now: tz.TZDateTime(zone, 2026, 11, 2, 12),
      ),
      'Yesterday',
    );
  });
  testWidgets(
    'unknown activity keeps its identity and reachable detail without a MET',
    (t) async {
      final at =
          DateTime.now()
              .subtract(const Duration(hours: 1))
              .millisecondsSinceEpoch ~/
          1000;
      await t.runAsync(
        () => LocalDb.putSession({
          'id': 'synthetic-unknown',
          'start_ts': at,
          'end_ts': at + 600,
          'status': 'done',
          'type': 'archived_synthetic_activity',
          'created_at': 1,
        }),
      );
      final app = AppState.forTesting()..user = {'weight_kg': 70.0};
      app.repo = LocalRepositoryImpl(getProfileMap: () => app.user);
      addTearDown(app.dispose);
      await t.pumpWidget(
        frame(const SessionDestination('synthetic-unknown'), app),
      );
      await until(t, () => find.byType(ActivitySummary).evaluate().isNotEmpty);
      final result = t
          .widget<ActivitySummary>(find.byType(ActivitySummary))
          .result;
      expect(result.activity.typeKey, 'archived_synthetic_activity');
      expect(result.activity.met, isNull);
      expect(result.calories, isNull);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'unknown finish opens a repair and cannot price the fabricated window',
    (t) async {
      final at =
          DateTime.now()
              .subtract(const Duration(hours: 8))
              .millisecondsSinceEpoch ~/
          1000;
      await t.runAsync(
        () => LocalDb.putSession({
          'id': 'synthetic-orphan',
          'start_ts': at,
          'end_ts': at + 8 * 3600,
          'end_ts_fabricated': 1,
          'duration_min': 480,
          'calories': 999,
          'strain': 19,
          'type': 'swimming',
          'status': 'done',
          'private': 1,
          'created_at': 1,
        }),
      );
      final app = AppState.forTesting()..user = {'weight_kg': 70.0};
      final repo = LocalRepositoryImpl(getProfileMap: () => app.user);
      app.repo = repo;
      addTearDown(app.dispose);
      await t.pumpWidget(
        frame(const SessionDestination('synthetic-orphan'), app),
      );
      await until(
        t,
        () => find.text('Finish time unknown').evaluate().isNotEmpty,
      );
      expect(find.byType(ActivitySummary), findsNothing);
      final rows = await t.runAsync(() => repo.getWorkouts(range: 'all'));
      final row = (rows!['workouts'] as List).single;
      expect(row['end_ts_fabricated'], true);
      expect(row['calories'], isNull);
      expect(row['duration_min'], isNull);
      expect(row['strain'], isNull);
      await t.runAsync(
        () => repo.setWorkoutWindow(
          'synthetic-orphan',
          startTs: at,
          endTs: at + 600,
        ),
      );
      expect(
        (await t.runAsync(
          () => LocalDb.session('synthetic-orphan'),
        ))!['end_ts_fabricated'],
        0,
      );
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'stopped sessions offer save retry and cannot imply continued recording',
    (t) async {
      await t.runAsync(() async {
        final start = DateTime.now().subtract(const Duration(minutes: 3));
        final clock = WorkoutClock.begin(
          'synthetic-stopped',
          start,
          const Profile(),
        );
        clock.finish(start.add(const Duration(minutes: 2)));
        await clock.persist();
        LiveDraft.begin(storedActivity('swimming'), private: true);
      });
      await t.pumpWidget(
        frame(liveFor(storedActivity('swimming'), private: true)),
      );
      expect(find.text('Stopped · save pending'), findsOneWidget);
      expect(find.widgetWithText(BigButton, 'Retry save'), findsOneWidget);
      expect(press('Resume'), findsNothing);
      expect(press('Pause'), findsNothing);
      expect(LiveDraft.current!.elapsedSec, 120);
      await t.pumpWidget(const SizedBox.shrink());
      WorkoutClock.current = null;
      LiveDraft.clear();
      var cleared = false;
      final clear = LiveDraft.retrySave().then((_) => cleared = true);
      await until(t, () => cleared);
      await clear;
    },
  );
  testWidgets(
    'split editor exposes failed persistence and retries the retained draft',
    (t) async {
      await t.runAsync(
        () => LiftLogDb.saveSplits([
          LiftSplit(id: 'synthetic-split', name: 'Synthetic split'),
        ]),
      );
      await t.pumpWidget(frame(const LiftSplitsScreen()));
      await until(t, () => find.text('Synthetic split').evaluate().isNotEmpty);
      await t.tap(find.text('Synthetic split'));
      await t.pumpAndSettle();
      await t.runAsync(
        () => db.execute(
          "CREATE TRIGGER synthetic_split_fail BEFORE INSERT ON baselines BEGIN SELECT RAISE(ABORT,'synthetic failure'); END",
        ),
      );
      try {
        await t.tap(find.text('Rename'));
        await t.pumpAndSettle();
        await t.enterText(
          find.byType(TextField).last,
          'Updated synthetic split',
        );
        await t.tap(find.widgetWithText(BigButton, 'Save'));
        await t.pump();
        await until(
          t,
          () => find.text('Changes not saved').evaluate().isNotEmpty,
        );
        expect(
          (await t.runAsync(LiftLogDb.splits))!.single.name,
          'Synthetic split',
        );
        await t.runAsync(() => db.execute('DROP TRIGGER synthetic_split_fail'));
        await t.tap(find.text('Retry'));
        await until(t, () => find.text('Changes not saved').evaluate().isEmpty);
        expect(
          (await t.runAsync(LiftLogDb.splits))!.single.name,
          'Updated synthetic split',
        );
      } finally {
        await t.runAsync(
          () => db.execute('DROP TRIGGER IF EXISTS synthetic_split_fail'),
        );
        await t.pumpWidget(const SizedBox.shrink());
      }
    },
  );
  testWidgets('dismissing away-from-Home does not start a Pushups day', (
    t,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'pushups.home.boundary',
      jsonEncode({'lat': 0.0, 'lon': 0.0, 'radius': 150.0}),
    );
    await prefs.setString(
      'pushups.home.state',
      jsonEncode(HomeAutomation(presence: HomePresence.outside).toJson()),
    );
    t.view.physicalSize = const Size(650, 1400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(frame(const PushupsScreen()));
    await until(t, () => find.text('Start my day').evaluate().isNotEmpty);
    await t.tap(find.text('Start my day'));
    await t.pumpAndSettle();
    expect(find.text("You're away from Home"), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect((await t.runAsync(Pushups.status))!.active, isNull);
    await t.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('Home rechecks permissions when returning from Settings', (
    t,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'pushups.home.boundary',
      jsonEncode({'lat': 0.0, 'lon': 0.0, 'radius': 150.0}),
    );
    var allowed = false;
    const channel = MethodChannel('openstrap/home_region');
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'status'
          ? {
              'authorization': allowed ? 'always' : 'denied',
              'monitoring': true,
              'monitored': true,
              'backgroundRefresh': 'available',
            }
          : call.method == 'currentLocation'
          ? {'lat': 0.0, 'lon': 0.0, 'accuracy': 10.0}
          : null,
    );
    addTearDown(
      () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await t.pumpWidget(frame(const HomeSetupScreen()));
    await until(t, () => find.text('Not working').evaluate().isNotEmpty);
    allowed = true;
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await until(t, () => find.text('Working').evaluate().isNotEmpty);
    await t.ensureVisible(press('Use my current location as Home'));
    await t.tap(press('Use my current location as Home'));
    await until(t, () => press('250 metres').evaluate().isNotEmpty);
    expect(t.widget<Pressable>(press('150 metres')).selected, true);
    await t.tap(press('250 metres'));
    await t.pump();
    expect(t.widget<Pressable>(press('250 metres')).selected, true);
    expect(t.widget<Pressable>(press('150 metres')).selected, false);
    await t.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'profile choices expose selected semantics in setup and editing',
    (t) async {
      final semantics = t.ensureSemantics();
      for (final view in [
        ProfileSetupView(initial: const {'sex': 'f'}, onSave: (_) async {}),
        EditProfileView(initial: const {'sex': 'f'}, onSave: (_) async {}),
      ]) {
        await t.pumpWidget(frame(view));
        await t.pumpAndSettle();
        expect(t.widget<Pressable>(press('Female')).selected, true);
        expect(t.widget<Pressable>(press('Male')).selected, false);
        expect(
          t
              .getSemantics(press('Female'))
              .getSemanticsData()
              .flagsCollection
              .isSelected,
          Tristate.isTrue,
        );
      }
      await t.pumpWidget(const SizedBox.shrink());
      semantics.dispose();
    },
  );
  testWidgets('Pushups choices expose their selected setting', (t) async {
    await t.pumpWidget(
      frame(const PushupSettingsScreen(canEditInterval: true)),
    );
    await until(t, () => press('45 min').evaluate().isNotEmpty);
    expect(t.widget<Pressable>(press('45 min')).selected, true);
    expect(t.widget<Pressable>(press('30 min')).selected, false);
    await t.pumpWidget(const SizedBox.shrink());
  });
}
