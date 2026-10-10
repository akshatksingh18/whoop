// The live set logger (build 86) through the real widgets and database: a
// set is durable when it shows, Repeat only prefills, Undo removes the last
// set, and finishing with the session keeps the log on the summary.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/lift_log.dart';
import 'package:openstrap_edge/ui2/activity/lift_log_ui.dart';
import 'package:openstrap_edge/ui2/screens/journal_compose.dart' show OsTextField;
import 'package:openstrap_edge/ui2/ui2.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> _until(WidgetTester t, bool Function() done) async {
  for (var i = 0; i < 100 && !done(); i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pump(const Duration(milliseconds: 50));
  }
  expect(done(), isTrue, reason: 'async UI did not reach the expected state');
}

Widget _app(Widget child) => MaterialApp(
  theme: buildTheme(Brightness.dark),
  home: Scaffold(body: ListView(children: [child])),
);

Finder _field(String label) => find.descendant(
  of: find.byWidgetPredicate((w) => w is OsTextField && w.label == label),
  matching: find.byType(TextField),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.dbName = 'openstrap_lift_ui_test.db';
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  tearDownAll(() async {
    await LocalDb.close();
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  testWidgets('log, repeat and undo a set on the live workout', (t) async {
    t.view.physicalSize = const Size(390, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final start = DateTime.now().subtract(const Duration(minutes: 5));
    await t.runAsync(() => beginLiftLog(
          LiftSplitChoice(LiftSplit(name: 'Chest day', exercises: [
            LiftSplitExercise(name: 'Dumbbell bench press', loadMode: LiftLoadMode.perHand),
          ])),
          sessionId: 'live-1',
          startedAt: start,
        ));
    await t.pumpWidget(_app(const LiftLivePanel(sessionId: 'live-1')));
    await _until(t, () => find.text('Dumbbell bench press').evaluate().isNotEmpty);
    expect(find.text('Chest day'), findsOneWidget);

    // Not started yet: open it, then type and log.
    await t.tap(find.text('Dumbbell bench press'));
    await t.pump();
    await t.enterText(_field('lb/hand'), '50');
    await t.enterText(_field('Reps'), '10');
    await t.tap(find.text('Log set'));
    await _until(t, () => find.text('S1 50 lb/hand × 10').evaluate().isNotEmpty);
    final saved = await t.runAsync(() => LiftLogDb.forSession('live-1'));
    expect(saved!.exercises.single.sets.single.reps, 10, reason: 'durable before shown');

    // Repeat fills the fields; nothing is logged until Log set.
    await t.enterText(_field('lb/hand'), '');
    await t.enterText(_field('Reps'), '');
    await t.tap(find.bySemanticsLabel('Repeat last set'));
    await t.pump();
    expect(find.text('50'), findsWidgets);
    expect(
      (await t.runAsync(() => LiftLogDb.forSession('live-1')))!.setCount,
      1,
      reason: 'a prefill is not a performed set',
    );

    await t.tap(find.bySemanticsLabel('Undo last set'));
    await _until(t, () => find.text('S1 50 lb/hand × 10').evaluate().isEmpty);
    expect((await t.runAsync(() => LiftLogDb.forSession('live-1')))!.setCount, 0);
  });

  testWidgets('a session finished with sets keeps them; with none, no log', (t) async {
    final start = DateTime.now().subtract(const Duration(minutes: 30));
    await t.runAsync(() async {
      await beginLiftLog(LiftChoice.empty, sessionId: 'fin-1', startedAt: start);
      final w = (await LiftLogDb.forSession('fin-1'))!;
      final e = w.addExercise(name: 'Row', loadMode: LiftLoadMode.stack);
      w.addSet(e, reps: 8, load: 70, at: start.add(const Duration(minutes: 3)));
      await LiftLogDb.save(w);
      await finishLiftLogFor('fin-1', start.add(const Duration(minutes: 40)));
      await beginLiftLog(LiftChoice.empty, sessionId: 'fin-2', startedAt: start);
      await finishLiftLogFor('fin-2', start.add(const Duration(minutes: 20)));
    });
    final kept = await t.runAsync(() => LiftLogDb.forSession('fin-1'));
    expect(kept!.isActive, isFalse);
    expect(kept.endedAt!.millisecondsSinceEpoch,
        start.add(const Duration(minutes: 40)).millisecondsSinceEpoch);
    expect(await t.runAsync(() => LiftLogDb.forSession('fin-2')), isNull,
        reason: 'a zero-set log goes; the WHOOP workout itself is untouched');

    await t.pumpWidget(_app(const LiftSummaryCard(sessionId: 'fin-1')));
    await _until(t, () => find.text('Row').evaluate().isNotEmpty);
    expect(find.text('S1 70 lb stack × 8'), findsOneWidget);
  });
}
