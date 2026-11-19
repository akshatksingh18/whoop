// Check that pending Lift edits do not modify exercises or recorded sets.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/lift_log.dart';
import 'package:whoop_companion/ui2/activity/lift_log_ui.dart';

import 'coverage_deep_lift_test.dart' show action, field, ioFrame;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

const sessionId = 'authored-lift-draft';
const exercise = 'Authored press';

void main() {
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('lift-exercise-draft-controls');
  });
  setUp(() async {
    await resetCoverageStore();
    await beginLiftLog(
      LiftSplitChoice(
        LiftSplit(
          name: 'Authored split',
          exercises: [
            LiftSplitExercise(name: exercise, loadMode: LiftLoadMode.total),
          ],
        ),
      ),
      sessionId: sessionId,
      startedAt: DateTime.now(),
    );
  });
  tearDownAll(LocalDb.close);

  Future<void> open(WidgetTester t) async {
    await localizedPage(
      t,
      const Scaffold(
        body: SingleChildScrollView(child: LiftLivePanel(sessionId: sessionId)),
      ),
    );
    await ioFrame(t);
  }

  Future<void> tap(WidgetTester t, Finder f) async {
    await reveal(t, f);
    await t.tap(f);
    await ioFrame(t);
    expect(t.takeException(), isNull);
  }

  Future<LiftWorkout> stored(WidgetTester t) async =>
      (await t.runAsync(() => LiftLogDb.forSession(sessionId)))!;

  testWidgets(
    'empty exercise expands, collapses and keeps its pending set draft',
    (t) async {
      await open(t);
      final original = (await stored(t)).exercises.single;
      final expander = action(exercise);
      expect(find.text('Log set'), findsNothing);
      await tap(t, expander);
      await t.enterText(field('Reps'), '7');
      await tap(t, expander);
      expect(find.text('Log set'), findsNothing);
      await tap(t, expander);
      expect(t.widget<TextField>(field('Reps')).controller!.text, '7');
      final saved = (await stored(t)).exercises.single;
      expect(saved.id, original.id);
      expect(saved.sets, isEmpty);
      expect(saved.equipmentNote, original.equipmentNote);
    },
  );

  testWidgets(
    'Add exercise on the live panel saves setup without an invented set',
    (t) async {
      await open(t);
      final original = (await stored(t)).exercises.single;
      await tap(t, action('Add exercise'));
      await t.enterText(field('Name'), 'Authored added lift');
      await t.enterText(
        field('Variation or setup (optional)'),
        'Authored setup',
      );
      await tap(t, action(LiftLoadMode.total.title));
      await tap(t, find.text('Save'));
      final after = await stored(t);
      expect(after.exercises, hasLength(2));
      expect(after.exercises.first.id, original.id);
      expect(after.exercises.last.name, 'Authored added lift');
      expect(after.exercises.last.loadMode, LiftLoadMode.total);
      expect(after.exercises.last.equipmentNote, 'Authored setup');
      expect(after.setCount, 0);
      expect(action('Authored added lift'), findsOneWidget);
    },
  );

  testWidgets('cancelled Lift variation and removal preserve the logged set', (
    t,
  ) async {
    final w = (await LiftLogDb.forSession(sessionId))!;
    w.addSet(w.exercises.single.id, reps: 7, load: 25, at: DateTime.now());
    await LiftLogDb.save(w);
    await open(t);
    final original = (await stored(t)).exercises.single;

    await tap(t, action('New variation of $exercise'));
    await t.enterText(field('Variation'), 'Authored unsaved variation');
    await tap(t, find.text('Cancel'));
    expect(find.byType(AlertDialog), findsNothing);

    await tap(t, action('Remove $exercise'));
    expect(find.text('Its 1 logged set goes with it.'), findsOneWidget);
    await tap(t, find.text('Keep it'));
    expect(find.text('Remove $exercise?'), findsNothing);
    final after = (await stored(t)).exercises.single;
    expect(after.id, original.id);
    expect(after.equipmentNote, original.equipmentNote);
    expect(after.sets.single.id, original.sets.single.id);
    expect(after.sets.single.reps, 7);
    expect(after.sets.single.load, 25);
  });
}
