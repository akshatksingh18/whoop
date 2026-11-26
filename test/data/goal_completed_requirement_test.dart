// Recomposition can have one verified requirement while the review still waits.
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whoop_companion/data/body_log.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/goal_plan.dart';
import 'package:whoop_companion/data/lift_log.dart';
import 'package:whoop_companion/ui2/screens/progress_screen.dart';
import 'package:whoop_companion/ui2/ui2.dart';

import '../ui2/screens/localized_progress_test.dart' show ago, progress;
import '../support/audit_visual.dart' show loadAuditFonts;
import '../support/coverage_store.dart';
import '../support/localized_coverage.dart';

void main() {
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('goal-completed-requirement');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  testWidgets(
    'a matched lift is marked done while waist evidence remains incomplete',
    (t) async {
      final today = DateTime.parse(todayLabel());
      final thisMonday = DateTime(
        today.year,
        today.month,
        today.day - today.weekday + 1,
      );
      DateTime fromMonday(int days) =>
          DateTime(thisMonday.year, thisMonday.month, thisMonday.day - days, 9);
      final evidence = progress(true);
      LiftWorkout at(DateTime date) {
        final lift = LiftWorkout(startedAt: date);
        final exercise = lift.addExercise(
          name: 'Authored press',
          loadMode: LiftLoadMode.total,
        );
        lift.addSet(exercise, reps: 10, load: 20, at: date);
        lift.finish(date.add(const Duration(minutes: 18)));
        return lift;
      }

      final waistDate = fromMonday(20);
      final d = ProgressData(
        weights: evidence.weights,
        food: evidence.food,
        measures: [
          BodyMeasure(
            id: 'authored-start-waist',
            date: dayLabelOf(waistDate),
            recordedAt: waistDate,
            inches: {'waistNavel': 32},
          ),
        ],
        lifts: [at(fromMonday(13)), at(fromMonday(1))],
        photos: [],
        steps: [],
        sleepMin: [],
        recovery: [],
        sessions: [],
        baseline: ago(60),
        heightCm: 170,
        goalChosen: true,
        goal: GoalPlan(phase: GoalPhase.recomp, since: ago(45)),
      );
      await localizedPage(t, ProgressScreen(data: d));
      final text = (await readPage(t)).join(' ');
      expect(text, contains('Not judged yet'));
      await reveal(t, find.text('FIRST CHECK'));
      final goal = find.byWidgetPredicate(
        (w) =>
            w is Surface &&
            (w.semanticLabel?.startsWith('Goal Recomposition.') ?? false),
      );
      expect(
        t.widget<Surface>(goal).semanticLabel,
        contains('The same lift twice: done.'),
      );
      expect(
        t.widget<Surface>(goal).semanticLabel,
        contains('Waist at both ends: under way.'),
      );
      expect(
        find.descendant(
          of: goal,
          matching: find.byIcon(LucideIcons.circleCheck),
        ),
        findsWidgets,
      );
      expect((await LiftLogDb.finished()), isEmpty);
    },
  );
}
