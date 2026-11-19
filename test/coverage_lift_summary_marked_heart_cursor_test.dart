// A real logged set stays marked when the Lift pulse cursor moves.
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/lift_log.dart';
import 'package:whoop_companion/ui2/activity/catalogue.dart';
import 'package:whoop_companion/ui2/activity/summary.dart';
import 'package:whoop_companion/ui2/ui2.dart';

import 'coverage_nutrition_root_test.dart' show io;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('lift-summary-marked-heart-cursor');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  for (final scale in [1.0, 3.1]) {
    testWidgets('Lift pulse cursor keeps saved set markers at scale $scale', (
      t,
    ) async {
      const id = 'authored-lift-summary';
      final start = DateTime(2021, 4, 6, 12);
      final end = start.add(const Duration(minutes: 5));
      final workout = LiftWorkout(sessionId: id, startedAt: start);
      final exercise = workout.addExercise(
        name: 'Authored controlled lift',
        loadMode: LiftLoadMode.total,
      );
      workout.addSet(
        exercise,
        reps: 8,
        load: 25,
        at: start.add(const Duration(minutes: 2)),
      );
      workout.finish(end);
      await LiftLogDb.save(workout);
      await LocalDb.putSession({
        'id': id,
        'type': 'weight_training',
        'start_ts': start.millisecondsSinceEpoch ~/ 1000,
        'end_ts': end.millisecondsSinceEpoch ~/ 1000,
        'status': 'done',
        'source': 'manual',
        'created_at': 1,
      });
      final saved = await LocalDb.session(id);
      final preview = ActivityResult(
        activityByName('Weight training')!,
        sessionId: id,
        start: start,
        duration: end.difference(start),
        hr: const [90, 110, 124, null, 115],
      );
      await localizedPage(t, ActivitySummary(preview), scale: scale);
      await io(t);

      final chart = find.byWidgetPredicate(
        (w) =>
            w is ChartFrame &&
            (w.footnote?.contains('Ticks mark when each set was logged') ??
                false),
      );
      final cursor = find.descendant(
        of: chart,
        matching: find.byType(Scrubber),
      );
      expect(t.widget<ChartFrame>(chart).readout, isNull);
      for (final (fraction, text) in [(.5, '124 bpm'), (.75, 'not recorded')]) {
        await reveal(t, cursor);
        final area = t.getRect(cursor);
        await t.tapAt(
          Offset(area.left + area.width * fraction, area.center.dy),
        );
        await t.pumpAndSettle();
        expect(t.widget<ChartFrame>(chart).readout, contains(text));
        expect(t.widget<Scrubber>(cursor).value, fraction);
      }
      expect(await t.runAsync(() => LocalDb.session(id)), saved);
      final retained = (await t.runAsync(() => LiftLogDb.forSession(id)))!;
      expect(retained.exercises.single.sets.single.reps, 8);
      expect(retained.exercises.single.sets.single.load, 25);
      expect(t.takeException(), isNull);
    });
  }
}
