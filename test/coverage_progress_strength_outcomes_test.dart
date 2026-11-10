// The real rolling comparison and its retained overview row use the same lift
// meanings. A heavier-for-fewer tradeoff cannot become 'same' or 'down'.
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/body_log.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/lift_log.dart';
import 'package:whoop_companion/ui2/screens/progress_screen.dart';
import 'coverage_localized_progress_test.dart' show ago;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('progress-strength-outcomes');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  for (final mode in ['one-apart', 'two-apart', 'mixed']) {
    testWidgets(
      'rolling strength $mode keeps comparability and detail navigation honest',
      (t) async {
        final before = LiftWorkout(startedAt: DateTime.parse(ago(10)));
        final after = LiftWorkout(startedAt: DateTime.parse(ago(3)));
        void pair(String name, int reps, double load) {
          final a = before.addExercise(
            name: name,
            loadMode: LiftLoadMode.total,
          );
          final b = after.addExercise(name: name, loadMode: LiftLoadMode.total);
          before.addSet(a, reps: 12, load: 20, at: before.startedAt);
          after.addSet(b, reps: reps, load: load, at: after.startedAt);
        }

        pair('Authored tradeoff', 11, 22);
        if (mode == 'two-apart') pair('Second tradeoff', 13, 18);
        if (mode == 'mixed') {
          pair('Authored improvement', 14, 20);
          pair('Authored same', 12, 20);
          pair('Authored down', 11, 20);
        }
        before.finish(before.startedAt.add(const Duration(minutes: 30)));
        after.finish(after.startedAt.add(const Duration(minutes: 30)));
        final data = ProgressData(
          weights: [],
          measures: [
            for (final (day, waist) in [(10, 32.0), (3, 31.0)])
              BodyMeasure(
                id: 'authored-$day',
                date: ago(day),
                recordedAt: DateTime.parse(ago(day)),
                inches: {'waistNavel': waist},
              ),
          ],
          photos: [],
          lifts: [before, after],
          food: [],
          steps: [],
          sleepMin: [],
          recovery: [],
          sessions: [],
          baseline: ago(30),
          heightCm: 170,
        );
        await localizedPage(t, ProgressScreen(data: data));
        final text = (await readPage(t)).join(' ');
        if (mode == 'mixed') {
          expect(text, contains('1 of 3'));
          expect(
            text,
            contains('improved · 1 same · 1 down · 1 not comparable'),
          );
        } else {
          expect(
            text,
            contains(
              mode == 'one-apart'
                  ? '1 lift, none comparable'
                  : '2 lifts, none comparable',
            ),
          );
          expect(text, isNot(contains('1 down')));
        }
        expect(text, contains('−1 in'));
        await reveal(t, find.text('Strength'));
        await t.tap(find.text('Strength'));
        await t.pumpAndSettle();
        final detail = (await readPage(t)).join(' ');
        expect(detail, contains('Authored tradeoff'));
        expect(detail, contains('Best 20 lb total × 12 → 22 lb total × 11'));
      },
    );
  }
}
