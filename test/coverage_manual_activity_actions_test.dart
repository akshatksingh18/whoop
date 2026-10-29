// Existing manual/review flows over synthetic storage. No band or sensor claims.
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whoop_companion/compute/manual_session.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/state/prefs.dart';
import 'package:whoop_companion/ui2/activity/catalogue.dart';
import 'package:whoop_companion/ui2/screens/log_workout.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'support/audit_visual.dart' show loadAuditFonts;

final start = DateTime(2021, 4, 6, 16);
final end = start.add(const Duration(minutes: 30));
final now = DateTime(2021, 4, 6, 21);
int epoch(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

class Repo extends LocalRepositoryImpl {
  Repo() : super(getProfileMap: () => {});
  String outcome = 'success';
  int calls = 0;
  Completer<void>? gate;
  @override
  Future<Map<String, dynamic>> logManualWorkout({
    required int startTs,
    required int endTs,
    required String type,
  }) async {
    calls++;
    await gate?.future;
    if (outcome == 'failure') throw StateError('synthetic write refusal');
    if (outcome == 'overlap') {
      throw const ManualWindowException(ManualWindowError.overlapsExisting);
    }
    return super.logManualWorkout(startTs: startTs, endTs: endTs, type: type);
  }
}

Future<void> flush(WidgetTester t) async {
  for (var i = 0; i < 20; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await t.pump(const Duration(milliseconds: 30));
  }
  await t.pumpAndSettle();
  expect(t.takeException(), isNull);
}

Future<void> tap(WidgetTester t, String text) async {
  final f = find.text(text);
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await flush(t);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late AppState app;
  late Repo repo;
  late GlobalKey<NavigatorState> nav;
  setUpAll(() async {
    await loadAuditFonts();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    final root = (await Directory(
      'build/coverage-remainder/manual-actions',
    ).create(recursive: true)).absolute;
    LocalDb.dbName = '${root.path}/synthetic.sqlite';
    await LocalDb.close();
    await databaseFactory.deleteDatabase(LocalDb.dbName);
    db = await LocalDb.instance;
  });
  Future<void> suggestion(String id, {String sport = 'yoga'}) =>
      LocalDb.putWorkoutSuggestion({
        'id': id,
        'date': '2021-04-06',
        'start_ts': epoch(start),
        'end_ts': epoch(end),
        'avg_bpm': 110,
        'peak_bpm': 125,
        'duration_min': 30,
        'sport': sport,
        'created_at': 100,
      });
  setUp(() async {
    SharedPreferences.setMockInitialValues({'notif_auto_detect': true});
    await Prefs.ensureLoaded();
    await LocalDb.wipeAll();
    DayClock.install([], []);
    repo = Repo();
    app = AppState.forTesting()..repo = repo;
    nav = GlobalKey<NavigatorState>();
    await suggestion('synthetic-suggestion');
  });
  tearDown(() async {
    if (repo.gate != null && !repo.gate!.isCompleted) repo.gate!.complete();
    final hidden = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE name='synthetic_hidden_suggestions'",
    );
    if (hidden.isNotEmpty) {
      await db.execute(
        'ALTER TABLE synthetic_hidden_suggestions RENAME TO workout_suggestions',
      );
    }
    await db.execute('DROP TRIGGER IF EXISTS synthetic_suggestion_refusal');
    app.dispose();
    DayClock.install([], []);
  });
  tearDownAll(LocalDb.close);
  Future<void> open(WidgetTester t, Widget page) async {
    t.view.physicalSize = const Size(430, 1500);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(
          navigatorKey: nav,
          theme: buildTheme(Brightness.light),
          home: Scaffold(
            body: Builder(
              builder: (c) => TextButton(
                onPressed: () => Navigator.of(
                  c,
                ).push(MaterialPageRoute<void>(builder: (_) => page)),
                child: const Text('Open destination'),
              ),
            ),
          ),
        ),
      ),
    );
    await tap(t, 'Open destination');
    addTearDown(() async {
      await t.pumpWidget(const SizedBox());
      await flush(t);
    });
  }

  Future<List<Map<String, Object?>>> sessions(WidgetTester t) async =>
      (await t.runAsync(() => db.query('sessions')))!;
  Future<List<Map<String, dynamic>>> suggestions(WidgetTester t) async =>
      (await t.runAsync(LocalDb.activeWorkoutSuggestions))!;

  for (final outcome in ['success', 'failure', 'overlap']) {
    testWidgets(
      'detected activity $outcome respects the shared write and dismissal rules',
      (t) async {
        repo.outcome = outcome;
        await open(t, const WorkoutSuggestionScreen());
        expect(find.text('30 min of effort'), findsOneWidget);
        await tap(t, 'Log it');
        expect(repo.calls, 1);
        if (outcome == 'success') {
          final rows = await sessions(t);
          expect(rows, hasLength(1));
          expect(rows.single['start_ts'], epoch(start));
          expect(rows.single['end_ts'], epoch(end));
          expect(rows.single['type'], 'yoga');
          expect(rows.single['strain'], isNull);
          expect(rows.single['calories'], isNull);
          expect(await suggestions(t), isEmpty);
          expect(find.text('Open destination'), findsOneWidget);
        } else if (outcome == 'failure') {
          expect(await sessions(t), isEmpty);
          expect(await suggestions(t), hasLength(1));
          expect(
            find.text('Could not log this one — try again.'),
            findsOneWidget,
          );
          repo.outcome = 'success';
          await tap(t, 'Log it');
          expect(await sessions(t), hasLength(1));
          expect(repo.calls, 2);
        } else {
          expect(await sessions(t), isEmpty);
          expect(await suggestions(t), isEmpty);
          expect(
            find.text('That overlaps a workout already in your log.'),
            findsOneWidget,
          );
        }
      },
    );
  }
  testWidgets(
    'unknown suggestion activity logs other without inventing measured scores',
    (t) async {
      await db.update(
        'workout_suggestions',
        {'sport': 'synthetic-unknown-type'},
        where: 'id = ?',
        whereArgs: ['synthetic-suggestion'],
      );
      await open(t, const WorkoutSuggestionScreen());
      await tap(t, 'Log it');
      final rows = await sessions(t);
      expect(rows.single['type'], 'other');
      expect(rows.single['strain'], isNull);
      expect(rows.single['max_hr'], isNull);
    },
  );
  testWidgets('refused suggestion dismissal retains it and can retry', (
    t,
  ) async {
    await db.execute(
      "CREATE TRIGGER synthetic_suggestion_refusal BEFORE UPDATE OF dismissed ON workout_suggestions BEGIN SELECT RAISE(ABORT,'synthetic dismissal refusal'); END",
    );
    await open(t, const WorkoutSuggestionScreen());
    await tap(t, 'Not a workout');
    expect(
      find.text('Could not dismiss this one — try again.'),
      findsOneWidget,
    );
    expect(await suggestions(t), hasLength(1));
    expect(await sessions(t), isEmpty);
    await t.runAsync(
      () => db.execute('DROP TRIGGER synthetic_suggestion_refusal'),
    );
    await tap(t, 'Not a workout');
    expect(await suggestions(t), isEmpty);
    expect(repo.calls, 0);
  });
  testWidgets(
    'failed suggestion read offers retry rather than reporting an empty list',
    (t) async {
      await db.execute(
        'ALTER TABLE workout_suggestions RENAME TO synthetic_hidden_suggestions',
      );
      await open(t, const WorkoutSuggestionScreen());
      expect(
        find.text('Could not read your detected activity'),
        findsOneWidget,
      );
      expect(find.text('Nothing to review'), findsNothing);
      await t.runAsync(
        () => db.execute(
          'ALTER TABLE synthetic_hidden_suggestions RENAME TO workout_suggestions',
        ),
      );
      await tap(t, 'Try again');
      expect(find.text('30 min of effort'), findsOneWidget);
    },
  );
  testWidgets(
    'disabled detection keeps retained suggestions out of notification review',
    (t) async {
      await Prefs.setBoolAcked('notif_auto_detect', false);
      await open(t, const WorkoutSuggestionScreen());
      expect(find.text('Nothing to review'), findsOneWidget);
      expect(find.text('Log it'), findsNothing);
      expect(await suggestions(t), hasLength(1));
      expect(await sessions(t), isEmpty);
    },
  );
  testWidgets('stale focus falls back to remaining persisted proposals', (
    t,
  ) async {
    await open(t, const WorkoutSuggestionScreen(focusId: 'already-handled'));
    expect(find.text('Log it'), findsOneWidget);
    expect(find.text('30 min of effort'), findsOneWidget);
  });
  testWidgets(
    'adjusting a proposal passes its window and cancel preserves it',
    (t) async {
      await open(t, const WorkoutSuggestionScreen());
      await tap(t, 'Adjust the times');
      final editor = t.widget<LogWorkout>(find.byType(LogWorkout));
      expect(editor.start, start);
      expect(editor.end, end);
      expect(editor.activity?.typeKey, 'yoga');
      nav.currentState!.pop();
      await flush(t);
      expect(await sessions(t), isEmpty);
      expect(await suggestions(t), hasLength(1));
    },
  );
  testWidgets(
    'manual form failure stays editable and retry saves an honestly unscored window',
    (t) async {
      repo.outcome = 'failure';
      await open(
        t,
        LogWorkout(
          start: start,
          end: end,
          now: now,
          spans: const [],
          activity: activityByName('yoga'),
        ),
      );
      await tap(t, 'Log it');
      expect(find.text('Workout not saved'), findsOneWidget);
      expect(find.text('Workout logged'), findsNothing);
      expect(await sessions(t), isEmpty);
      repo.outcome = 'success';
      await tap(t, 'Log it');
      expect(find.text('Workout logged'), findsOneWidget);
      expect(find.textContaining('No heart rate was recorded'), findsOneWidget);
      final rows = await sessions(t);
      expect(rows, hasLength(1));
      expect(rows.single['start_ts'], epoch(start));
      expect(rows.single['calories'], isNull);
      expect(rows.single['strain'], isNull);
    },
  );
  testWidgets('manual activity picker filters and saves the chosen activity', (
    t,
  ) async {
    await open(
      t,
      LogWorkout(start: start, end: end, now: now, spans: const []),
    );
    await tap(t, 'Activity');
    await t.enterText(find.byType(TextField), 'yoga');
    await flush(t);
    await tap(t, 'Yoga');
    await tap(t, 'Log it');
    expect((await sessions(t)).single['type'], 'yoga');
  });
  testWidgets(
    'a pending manual save disables repeats and cannot pop its caller after leaving',
    (t) async {
      repo.gate = Completer<void>();
      await open(
        t,
        LogWorkout(start: start, end: end, now: now, spans: const []),
      );
      await tap(t, 'Log it');
      expect(find.text('Saving…'), findsOneWidget);
      expect(
        t.widget<BigButton>(find.widgetWithText(BigButton, 'Saving…')).onTap,
        isNull,
      );
      expect(repo.calls, 1);
      nav.currentState!.pop();
      await flush(t);
      repo.gate!.complete();
      repo.gate = null;
      await flush(t);
      expect(await sessions(t), hasLength(1));
      expect(find.text('Open destination'), findsOneWidget);
      expect(find.byType(LogWorkout), findsNothing);
    },
  );
}
