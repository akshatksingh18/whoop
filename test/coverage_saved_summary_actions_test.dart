// Actual summary actions -> persistent synthetic sessions. No band/native delivery.
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/data/lift_log.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/state/prefs.dart';
import 'package:whoop_companion/ui2/activity/catalogue.dart';
import 'package:whoop_companion/ui2/activity/summary.dart';
import 'package:whoop_companion/ui2/activity/picker.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'support/audit_visual.dart' show loadAuditFonts;

final start = DateTime(2026, 1, 6, 8);
ActivityResult recorded(
  String id, {
  String type = 'General workout',
  DateTime? at,
}) => ActivityResult(
  activityByName(type)!,
  sessionId: id,
  start: at ?? start,
  duration: const Duration(minutes: 12),
  hr: const [110, 115, 120, 125],
  avgHr: 118,
  maxHr: 125,
  calories: 70,
);

class App extends AppState {
  App() : super.forTesting();
  int changes = 0;
  @override
  void publishSessionChange() {
    changes++;
    super.publishSessionChange();
  }
}

Finder action(String label) =>
    find.byWidgetPredicate((w) => w is Pressable && w.semanticLabel == label);
Future<void> flush(WidgetTester t) async {
  for (var i = 0; i < 18; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await t.pump(const Duration(milliseconds: 30));
  }
  await t.pumpAndSettle();
  expect(t.takeException(), isNull);
}

Future<void> tap(WidgetTester t, Finder f) async {
  final scrolls = find.byType(Scrollable);
  if (scrolls.evaluate().isNotEmpty) {
    await t.ensureVisible(f);
    await t.pumpAndSettle();
  }
  await t.tap(f);
  await flush(t);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late App app;
  setUpAll(() async {
    await loadAuditFonts();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    final root = (await Directory(
      'build/coverage-remainder/summary-actions',
    ).create(recursive: true)).absolute;
    LocalDb.dbName = '${root.path}/synthetic.sqlite';
    await LocalDb.close();
    await databaseFactory.deleteDatabase(LocalDb.dbName);
    db = await LocalDb.instance;
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.ensureLoaded();
    await LocalDb.wipeAll();
    app = App();
    app.repo = LocalRepositoryImpl(
      getProfileMap: () => app.user,
      onSessionChanged: app.publishSessionChange,
    );
    await LocalDb.putSession({
      'id': 'synthetic',
      'type': 'general_workout',
      'start_ts': start.millisecondsSinceEpoch ~/ 1000,
      'end_ts':
          start.add(const Duration(minutes: 44)).millisecondsSinceEpoch ~/ 1000,
      'status': 'done',
      'source': 'manual',
      'created_at': start.millisecondsSinceEpoch,
    });
  });
  tearDown(() async {
    await db.execute('DROP TRIGGER IF EXISTS synthetic_session_refusal');
    app.dispose();
  });
  tearDownAll(LocalDb.close);
  Future<void> open(WidgetTester t, {bool finished = true}) async {
    t.view.physicalSize = const Size(390, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(
          theme: buildTheme(Brightness.light),
          home: Builder(
            builder: (c) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(c).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ActivitySummary(
                      recorded('synthetic'),
                      justFinished: finished,
                    ),
                  ),
                ),
                child: const Text('Open summary'),
              ),
            ),
          ),
        ),
      ),
    );
    await tap(t, find.text('Open summary'));
    addTearDown(() async {
      await t.pumpWidget(const SizedBox());
      await flush(t);
    });
  }

  Future<void> showRating(WidgetTester t) async {
    await t.scrollUntilVisible(
      action('Rate this effort 7 of 10'),
      250,
      maxScrolls: 20,
      scrollable: find.byType(Scrollable).last,
    );
    await t.pumpAndSettle();
  }

  Future<Map<String, dynamic>?> row(WidgetTester t) async => (await t.runAsync(
    () => db.query('sessions', where: 'id=?', whereArgs: ['synthetic']),
  ))!.firstOrNull;

  testWidgets(
    'RPE has no default; an explicit rating persists and retires its prompt',
    (t) async {
      await open(t);
      await showRating(t);
      expect((await row(t))!['rpe'], isNull);
      await tap(t, action('Rate this effort 7 of 10'));
      expect((await row(t))!['rpe'], 7);
      expect(app.changes, 1);
      expect(action('Rate this effort 7 of 10'), findsNothing);
      expect(t.widget<SessionStats>(find.byType(SessionStats)).r.rpe, 7);
    },
  );
  testWidgets('a refused RPE stays unrated and the same action can retry', (
    t,
  ) async {
    await db.execute(
      "CREATE TRIGGER synthetic_session_refusal BEFORE UPDATE ON sessions BEGIN SELECT RAISE(ABORT,'synthetic refusal'); END",
    );
    await open(t);
    await showRating(t);
    await tap(t, action('Rate this effort 7 of 10'));
    expect((await row(t))!['rpe'], isNull);
    expect(app.changes, 0);
    expect(action('Rate this effort 7 of 10'), findsOneWidget);
    await t.runAsync(
      () => db.execute('DROP TRIGGER synthetic_session_refusal'),
    );
    await tap(t, action('Rate this effort 7 of 10'));
    expect((await row(t))!['rpe'], 7);
  });
  testWidgets('a deleted session cannot report a successful RPE save', (
    t,
  ) async {
    await open(t);
    await showRating(t);
    await t.runAsync(
      () => db.delete('sessions', where: 'id=?', whereArgs: ['synthetic']),
    );
    await tap(t, action('Rate this effort 7 of 10'));
    expect(app.changes, 0);
    expect(action('Rate this effort 7 of 10'), findsOneWidget);
    expect(t.widget<SessionStats>(find.byType(SessionStats)).r.rpe, isNull);
  });
  testWidgets('Not now records a skip without writing a rating', (t) async {
    await open(t);
    await showRating(t);
    await tap(t, find.text('Not now'));
    expect((await row(t))!['rpe'], isNull);
    expect(Prefs.getInt('workout.rpe_skips', 0), 1);
    expect(app.changes, 0);
    expect(action('Rate this effort 7 of 10'), findsNothing);
  });
  testWidgets('history opens do not ask for a retrospective rating', (t) async {
    await open(t, finished: false);
    final pos = t.state<ScrollableState>(find.byType(Scrollable).last).position;
    pos.jumpTo(pos.maxScrollExtent);
    await t.pumpAndSettle();
    expect(action('Rate this effort 7 of 10'), findsNothing);
    expect((await row(t))!['rpe'], isNull);
  });
  for (final remove in [false, true]) {
    testWidgets(
      'summary deletion ${remove ? 'commits and returns' : 'cancels without mutation'}',
      (t) async {
        await open(t, finished: false);
        await tap(t, action('Delete this workout'));
        await tap(t, find.text(remove ? 'Delete' : 'Keep it').last);
        expect(await row(t), remove ? isNull : isNotNull);
        expect(
          find.byType(ActivitySummary),
          remove ? findsNothing : findsOneWidget,
        );
      },
    );
  }
  testWidgets('failed deletion stays on the summary, then succeeds on retry', (
    t,
  ) async {
    await db.execute(
      "CREATE TRIGGER synthetic_session_refusal BEFORE DELETE ON sessions BEGIN SELECT RAISE(ABORT,'synthetic refusal'); END",
    );
    await open(t, finished: false);
    await tap(t, action('Delete this workout'));
    await tap(t, find.text('Delete').last);
    expect(await row(t), isNotNull);
    expect(
      find.text('The workout was not deleted. Please try again.'),
      findsOneWidget,
    );
    await t.runAsync(
      () => db.execute('DROP TRIGGER synthetic_session_refusal'),
    );
    await tap(t, action('Delete this workout'));
    await tap(t, find.text('Delete').last);
    expect(await row(t), isNull);
    expect(find.byType(ActivitySummary), findsNothing);
  });
  for (final failure in [false, true]) {
    testWidgets(
      'activity correction ${failure ? 'refuses then retries' : 'saves the selected type'}',
      (t) async {
        await open(t, finished: false);
        await tap(t, action('Change activity type'));
        expect(find.byType(ActivityPicker), findsOneWidget);
        await t.enterText(find.byType(TextField), 'Yoga');
        await t.pumpAndSettle();
        if (failure)
          await t.runAsync(
            () => db.execute(
              "CREATE TRIGGER synthetic_session_refusal BEFORE UPDATE ON sessions BEGIN SELECT RAISE(ABORT,'synthetic refusal'); END",
            ),
          );
        await tap(t, find.text('Yoga').last);
        if (failure) {
          expect(find.byType(ActivityPicker), findsOneWidget);
          expect((await row(t))!['type'], 'general_workout');
          await t.runAsync(
            () => db.execute('DROP TRIGGER synthetic_session_refusal'),
          );
          await tap(t, find.text('Yoga').last);
        }
        expect((await row(t))!['type'], 'yoga');
        expect(app.changes, 1);
        expect(find.byType(ActivitySummary), findsNothing);
      },
    );
  }
  testWidgets(
    'cancelling activity correction returns to the same saved summary',
    (t) async {
      await open(t, finished: false);
      await tap(t, action('Change activity type'));
      Navigator.of(t.element(find.byType(ActivityPicker))).pop();
      await flush(t);
      expect(find.byType(ActivitySummary), findsOneWidget);
      expect((await row(t))!['type'], 'general_workout');
      expect(app.changes, 0);
    },
  );
  testWidgets(
    'a late saved-end read belongs only to the result that requested it',
    (t) async {
      final entered = Completer<void>(), release = Completer<void>();
      final held = db.transaction((txn) async {
        await txn.rawQuery('SELECT 1');
        entered.complete();
        await release.future;
      });
      await entered.future;
      final current = ValueNotifier(recorded('synthetic'));
      addTearDown(current.dispose);
      try {
        await t.pumpWidget(
          MaterialApp(
            theme: buildTheme(Brightness.light),
            home: ValueListenableBuilder<ActivityResult>(
              valueListenable: current,
              builder: (_, r, _) => ActivitySummary(r),
            ),
          ),
        );
        await t.pumpAndSettle();
        current.value = recorded('not-saved', at: DateTime(2026, 1, 7, 9));
        await t.pumpAndSettle();
        release.complete();
        await t.runAsync(() => held);
        await flush(t);
        expect(find.textContaining('8:44'), findsNothing);
        expect(t.takeException(), isNull);
      } finally {
        if (!release.isCompleted) release.complete();
        await t.runAsync(() => held);
      }
      await t.pumpWidget(const SizedBox());
      await flush(t);
    },
  );

  for (final held in [false, true]) {
    testWidgets(
      '${held ? 'late' : 'already displayed'} lift marks do not enter a replacement non-lift result',
      (t) async {
        await LiftLogDb.save(
          LiftWorkout(
            id: 'synthetic-log',
            sessionId: 'synthetic',
            startedAt: start,
            endedAt: start.add(const Duration(minutes: 12)),
            exercises: [
              LiftExercise(
                name: 'Synthetic press',
                sets: [
                  LiftSet(
                    reps: 8,
                    load: 20,
                    completedAt: start.add(const Duration(minutes: 2)),
                  ),
                ],
              ),
            ],
          ),
        );
        final entered = Completer<void>(), release = Completer<void>();
        final wait = held
            ? db.transaction((tx) async {
                await tx.rawQuery('SELECT 1');
                entered.complete();
                await release.future;
              })
            : Future<void>.value();
        if (held) await entered.future;
        final current = ValueNotifier(
          recorded('synthetic', type: 'Weight training'),
        );
        addTearDown(current.dispose);
        try {
          await t.pumpWidget(
            MaterialApp(
              theme: buildTheme(Brightness.light),
              home: ValueListenableBuilder<ActivityResult>(
                valueListenable: current,
                builder: (_, r, _) => ActivitySummary(r),
              ),
            ),
          );
          await flush(t);
          if (!held)
            expect(
              find.textContaining('Ticks mark when each set'),
              findsOneWidget,
            );
          current.value = recorded('not-saved');
          await t.pumpAndSettle();
          if (held) release.complete();
          await t.runAsync(() => wait);
          await flush(t);
          expect(find.textContaining('Ticks mark when each set'), findsNothing);
        } finally {
          if (held && !release.isCompleted) release.complete();
          await t.runAsync(() => wait);
        }
        await t.pumpWidget(const SizedBox());
        await flush(t);
      },
    );
  }

  testWidgets('a committed late rating cannot rate a replacement workout', (
    t,
  ) async {
    final current = ValueNotifier(recorded('synthetic'));
    addTearDown(current.dispose);
    await t.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(
          theme: buildTheme(Brightness.light),
          home: ValueListenableBuilder<ActivityResult>(
            valueListenable: current,
            builder: (_, r, _) => ActivitySummary(r, justFinished: true),
          ),
        ),
      ),
    );
    await flush(t);
    await showRating(t);
    final entered = Completer<void>(), release = Completer<void>();
    final held = db.transaction((tx) async {
      await tx.rawQuery('SELECT 1');
      entered.complete();
      await release.future;
    });
    await entered.future;
    try {
      await t.tap(action('Rate this effort 7 of 10'));
      await t.pump();
      current.value = recorded('synthetic-other', type: 'Yoga');
      await t.pumpAndSettle();
      release.complete();
      await t.runAsync(() => held);
      await flush(t);
      expect((await row(t))!['rpe'], 7);
      expect(app.changes, 1);
      final shown = t.widget<SessionStats>(find.byType(SessionStats)).r;
      expect(shown.sessionId, 'synthetic-other');
      expect(shown.rpe, isNull);
    } finally {
      if (!release.isCompleted) release.complete();
      await t.runAsync(() => held);
      await t.pumpWidget(const SizedBox());
      await flush(t);
    }
  });
}
