// Actual Train and session destinations over synthetic SQLite and route rows.
// Coordinates describe an invented straight line, never a recorded route.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/data/local_repository_impl.dart';
import 'package:openstrap_edge/gps/route_models.dart';
import 'package:openstrap_edge/gps/run_history.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:openstrap_edge/state/prefs.dart';
import 'package:openstrap_edge/state/units_controller.dart';
import 'package:openstrap_edge/ui2/activity/picker.dart';
import 'package:openstrap_edge/ui2/activity/setup.dart';
import 'package:openstrap_edge/ui2/activity/summary.dart';
import 'package:openstrap_edge/ui2/screens/log_workout.dart';
import 'package:openstrap_edge/ui2/screens/workout_screen.dart';
import 'package:openstrap_edge/ui2/ui2.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'support/audit_visual.dart' show loadAuditFonts;

Finder action(String name) =>
    find.byWidgetPredicate((w) => w is Pressable && w.semanticLabel == name);
Future<void> flush(WidgetTester t) async {
  for (var i = 0; i < 28; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await t.pump(const Duration(milliseconds: 25));
  }
  await t.pumpAndSettle();
  expect(t.takeException(), isNull);
}

Future<void> reach(WidgetTester t, Finder f) async {
  final list = find.byType(Scrollable).first;
  t.state<ScrollableState>(list).position.jumpTo(0);
  await t.pumpAndSettle();
  await t.scrollUntilVisible(f, 250, scrollable: list, maxScrolls: 70);
  await t.ensureVisible(f);
  await t.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late AppState app;
  late UnitsController units;
  final now = DateTime.now();
  // A completed window always ends before now, including a run just after
  // midnight. It may belong to the previous calendar week.
  final today = now.subtract(const Duration(hours: 1));
  setUpAll(() async {
    await loadAuditFonts();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    final root = (await Directory(
      'build/coverage-remainder/train-destinations',
    ).create(recursive: true)).absolute;
    LocalDb.dbName = '${root.path}/synthetic.sqlite';
    await LocalDb.close();
    await databaseFactory.deleteDatabase(LocalDb.dbName);
    db = await LocalDb.instance;
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.ensureLoaded();
    DayClock.install([], []);
    await LocalDb.wipeAll();
    runsChanged();
    app = AppState.forTesting()
      ..user = {'age': 30, 'sex': 'f', 'height_cm': 170.0, 'weight_kg': 70.0};
    app.repo = LocalRepositoryImpl(
      getProfileMap: () => app.user,
      onSessionChanged: app.publishSessionChange,
    );
    units = UnitsController.seed(UnitSystem.metric);
  });
  tearDown(() {
    app.dispose();
    units.dispose();
    runsChanged();
  });
  tearDownAll(LocalDb.close);
  Future<void> session(
    String id,
    String type,
    DateTime at, {
    bool private = false,
    bool unknownEnd = false,
    bool route = false,
  }) async {
    final ts = at.millisecondsSinceEpoch ~/ 1000;
    await LocalDb.putSession({
      'id': id,
      'type': type,
      'start_ts': ts,
      'end_ts': ts + 1800,
      'status': 'done',
      'source': 'manual',
      'created_at': ts * 1000,
      'private': private ? 1 : 0,
      'end_ts_fabricated': unknownEnd ? 1 : 0,
      'steps': 2000,
      'strain': 3.2,
    });
    if (route)
      await LocalDb.appendRoutePoints(id, [
        for (var i = 0; i <= 600; i++)
          RoutePoint(
            seq: i,
            tsMs: (ts + i * 3) * 1000,
            lat: 0,
            lng: i * .00009,
            accuracy: 3,
            speed: 3.3,
          ).toRow(id),
      ]);
  }

  Future<void> open(WidgetTester t, Widget page) async {
    t.view.physicalSize = const Size(390, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: app),
          ChangeNotifierProvider.value(value: units),
        ],
        child: MaterialApp(theme: buildTheme(Brightness.light), home: page),
      ),
    );
    addTearDown(() async {
      await t.pumpWidget(const SizedBox());
      await flush(t);
    });
    await flush(t);
  }

  Future<void> tap(WidgetTester t, Finder f) async {
    await reach(t, f);
    await t.tap(f);
    await flush(t);
  }

  for (final tile in ['Run', 'Walk', 'Other', 'Gym', 'Home · bodyweight']) {
    testWidgets(
      'Train $tile opens its real setup or picker without starting a session',
      (t) async {
        await open(t, const WorkoutScreen());
        if (tile == 'Gym' || tile == 'Home · bodyweight') {
          await tap(t, find.text('Lift').first);
          await t.tap(find.text(tile).last);
          await flush(t);
        } else {
          await tap(t, find.text(tile).first);
        }
        if (tile == 'Other') {
          expect(find.byType(ActivityPicker), findsOneWidget);
        } else {
          final setup = t.widget<ActivitySetup>(find.byType(ActivitySetup));
          expect(setup.a.name, switch (tile) {
            'Run' => 'Running',
            'Walk' => 'Walking',
            'Gym' => 'Weight training',
            _ => 'Bodyweight',
          });
        }
        expect(await t.runAsync(() => db.query('sessions')), isEmpty);
        expect(app.activeWorkout, isNull);
        Navigator.of(
          t.element(
            find.byType(tile == 'Other' ? ActivityPicker : ActivitySetup),
          ),
        ).pop();
        await flush(t);
        expect(find.byType(WorkoutScreen), findsOneWidget);
      },
    );
  }
  for (final miles in [false, true]) {
    testWidgets(
      'Train running history, weekly selection and units ${miles ? 'mi' : 'km'} use saved public runs',
      (t) async {
        await session('synthetic-run', 'running', today, route: true);
        await session(
          'synthetic-earlier',
          'running',
          today.subtract(const Duration(days: 8)),
          route: true,
        );
        await session(
          'synthetic-private',
          'running',
          today.subtract(const Duration(days: 1)),
          private: true,
          route: true,
        );
        if (miles) await units.setDistanceUnit('mi');
        await open(t, const WorkoutScreen());
        await reach(t, find.text('Best times'));
        expect(find.text('PREDICTED 5K'), findsOneWidget);
        expect(find.text('1 mile'), findsOneWidget);
        final chart = find.byWidgetPredicate(
          (w) => w is Scrubber && w.label == 'Distance per week',
        );
        await reach(t, chart);
        final scrub = t.widget<Scrubber>(chart);
        final current = scrub.describe(.99);
        expect(current, contains('This week'));
        final monday = DateTime(now.year, now.month, now.day - now.weekday + 1);
        expect(
          current,
          contains(
            today.isBefore(monday)
                ? 'no runs'
                : miles
                ? '3.7 mi'
                : '6.0 km',
          ),
        );
        expect(scrub.describe(0), contains('no runs'));
        await t.tapAt(t.getRect(chart).centerRight - const Offset(2, 0));
        await t.pumpAndSettle();
        expect(find.text(current), findsOneWidget);
        final runs = (await t.runAsync(
          () => loadRuns(app.repo!, includePrivate: false),
        ))!;
        expect(runs.map((r) => r.id), ['synthetic-earlier', 'synthetic-run']);
        // Private sessions remain in history, but are absent from running records.
        expect(await t.runAsync(() => db.query('sessions')), hasLength(3));
      },
    );
  }
  testWidgets('Add a past one returns to Train on cancel without a write', (
    t,
  ) async {
    await open(t, const WorkoutScreen());
    await tap(t, find.text('Add a past one'));
    expect(find.byType(LogWorkout), findsOneWidget);
    Navigator.of(t.element(find.byType(LogWorkout))).pop();
    await flush(t);
    expect(find.byType(WorkoutScreen), findsOneWidget);
    expect(await t.runAsync(() => db.query('sessions')), isEmpty);
  });
  testWidgets(
    'a missing session gives an unavailable destination instead of invented detail',
    (t) async {
      await open(t, const SessionDestination('synthetic-missing'));
      expect(find.text('Session unavailable'), findsOneWidget);
      expect(find.byType(ActivitySummary), findsNothing);
    },
  );
  testWidgets(
    'an interrupted session reaches its time correction and stays unknown after cancel',
    (t) async {
      await session('synthetic-unknown', 'running', today, unknownEnd: true);
      await open(t, const SessionDestination('synthetic-unknown'));
      expect(find.text('Finish time unknown'), findsOneWidget);
      await tap(t, find.text('Fix the times'));
      expect(find.byType(LogWorkout), findsOneWidget);
      expect(
        t.widget<LogWorkout>(find.byType(LogWorkout)).sessionId,
        'synthetic-unknown',
      );
      Navigator.of(t.element(find.byType(LogWorkout))).pop();
      await flush(t);
      expect(find.text('Finish time unknown'), findsOneWidget);
      expect(find.byType(ActivitySummary), findsNothing);
      expect(
        (await t.runAsync(
          () => LocalDb.session('synthetic-unknown'),
        ))!['end_ts_fabricated'],
        1,
      );
    },
  );
  testWidgets(
    'a saved session destination opens its stored identity without asking for effort',
    (t) async {
      await session('synthetic-yoga', 'yoga', today);
      await open(t, const SessionDestination('synthetic-yoga'));
      final summary = t.widget<ActivitySummary>(find.byType(ActivitySummary));
      expect(summary.result.sessionId, 'synthetic-yoga');
      expect(summary.result.activity.name, 'Yoga');
      expect(summary.result.duration.inMinutes, 30);
      expect(summary.justFinished, isFalse);
    },
  );
}
