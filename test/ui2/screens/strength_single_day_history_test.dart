// A one-day Strength history has its saved sets and no earlier comparison.
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/lift_log.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/data/progress_review.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/screens/progress_routes.dart';
import 'package:whoop_companion/ui2/screens/progress_screen.dart';

import 'body_history_actions_test.dart' show flush;
import '../../support/audit_visual.dart' show loadAuditFonts;
import '../../support/coverage_store.dart';
import '../../support/localized_coverage.dart';

void main() {
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('strength-single-day-history');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  for (final range in [ProgressRange.sinceStart, ProgressRange.all]) {
    testWidgets(
      'Strength ${range.label} retains a single day without a comparison',
      (t) async {
        final date = todayLabel();
        final start = DateTime.parse(date).add(const Duration(hours: 12));
        final repo = LocalRepositoryImpl(getProfileMap: () => {});
        final app = AppState.forTesting()..repo = repo;
        addTearDown(app.dispose);
        final lift = LiftWorkout(startedAt: start);
        final exercise = lift.addExercise(
          name: 'Authored single-day press',
          loadMode: LiftLoadMode.total,
        );
        lift.addSet(exercise, reps: 10, load: 20, at: start);
        lift.finish(start.add(const Duration(minutes: 30)));
        final db = (await t.runAsync(() async {
          await LiftLogDb.save(lift);
          return LocalDb.instance;
        }))!;
        final saved = (await t.runAsync(LiftLogDb.finished))!.single;

        await localizedPage(
          t,
          progressDetailPage(ProgressDest.strength, range: range),
          app: app,
          settle: false,
        );
        await flush(t);
        final text = (await readPage(t)).join(' ');
        expect(text, contains('too early to compare a first and a last week'));
        expect(text, contains('1 workout · 1 set'));
        expect(text, contains('No earlier period to compare'));
        expect(text, contains('No comparable lifts in these periods.'));
        expect(text, isNot(contains('Best ')));
        final after = (await t.runAsync(LiftLogDb.finished))!.single;
        expect(after.toJson(), saved.toJson());
        expect(await t.runAsync(() => db.query('day_result')), isEmpty);
      },
    );
  }
}
