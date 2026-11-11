// Retained goal requirements and their actual actions. These authored records
// do not change the calorie policy or imply that a partial review can judge.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/body_log.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/goal_plan.dart';
import 'package:whoop_companion/data/lift_log.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/screens/progress_screen.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'coverage_localized_progress_test.dart' show progress, ago;
import 'coverage_body_history_actions_test.dart' show flush;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('goal-waiting-actions');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  ProgressData data({bool partial = false}) {
    final p = progress(true);
    final lift = LiftWorkout(startedAt: DateTime.parse(todayLabel()));
    final exercise = lift.addExercise(
      name: 'Authored press',
      loadMode: LiftLoadMode.total,
    );
    lift.addSet(exercise, reps: 12, load: 20, at: lift.startedAt);
    lift.finish(lift.startedAt.add(const Duration(minutes: 30)));
    return ProgressData(
      weights: p.weights,
      food: p.food,
      measures: [
        if (partial)
          BodyMeasure(
            id: 'authored-first-waist',
            date: todayLabel(),
            recordedAt: DateTime.now(),
            inches: {'waistNavel': 32},
          ),
      ],
      lifts: [if (partial) lift],
      photos: [],
      steps: [],
      sleepMin: [],
      recovery: [],
      sessions: [],
      baseline: ago(60),
      heightCm: 170,
      goalChosen: true,
      goal: GoalPlan(phase: GoalPhase.recomp, since: ago(30)),
    );
  }

  testWidgets(
    'partly started goal opens Train without inventing another lift or accepting the review',
    (t) async {
      final app = AppState.forTesting();
      addTearDown(app.dispose);
      await localizedPage(
        t,
        ProgressScreen(data: data(partial: true)),
        app: app,
      );
      final text = (await readPage(t)).join(' ');
      expect(text, contains('Not judged yet'));
      expect(text, contains('1 of 2 halves'));
      await reveal(t, find.text('Open Train'));
      await t.tap(find.text('Open Train'));
      await t.pumpAndSettle();
      expect(app.navRequest.value, 4);
      expect(await LiftLogDb.finished(), isEmpty);
      expect(await BodyLogDb.measures(), isEmpty);
    },
  );
  testWidgets(
    'waiting waist action opens its measurement fields and cancel retains the goal',
    (t) async {
      final app = AppState.forTesting();
      addTearDown(app.dispose);
      final d = data();
      await localizedPage(t, ProgressScreen(data: d), app: app);
      await reveal(t, find.text('Log waist'));
      await t.tap(find.text('Log waist'));
      await flush(t);
      expect(find.byType(BodyEntryScreen), findsOneWidget);
      expect(
        t.widget<BodyEntryScreen>(find.byType(BodyEntryScreen)).showTape,
        true,
      );
      Navigator.of(t.element(find.byType(BodyEntryScreen))).pop();
      await flush(t);
      expect(find.byType(ProgressScreen), findsOneWidget);
      expect(await BodyLogDb.measures(), isEmpty);
      expect(await BodyLogDb.weights(), isEmpty);
      expect(d.goal.phase, GoalPhase.recomp);
      expect(app.navRequest.value, -1);
    },
  );
  testWidgets(
    'one waist end and one lift half stay under way in the accessible waiting card',
    (t) async {
      await localizedPage(t, ProgressScreen(data: data(partial: true)));
      final text = (await readPage(t)).join(' ');
      expect(text, contains('Not judged yet'));
      expect(text, contains('1 of 2 ends'));
      expect(text, contains('1 of 2 halves'));
      await reveal(t, find.text('FIRST CHECK'));
      final card = t
          .widgetList<Surface>(find.byType(Surface))
          .singleWhere(
            (w) => w.semanticLabel?.startsWith('Goal Recomposition.') ?? false,
          );
      expect(card.semanticLabel, contains('Waist at both ends: under way.'));
      expect(card.semanticLabel, contains('The same lift twice: under way.'));
      expect(
        card.semanticLabel,
        contains('Weigh-ins and food, every week: under way.'),
      );
      expect(card.semanticLabel, isNot(contains('The same lift twice: done.')));
    },
  );
}
