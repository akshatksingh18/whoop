// A visible second split edit is retained while its first save is held.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/calculation_store.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/lift_log.dart';
import 'package:whoop_companion/ui2/activity/lift_log_ui.dart';
import 'package:whoop_companion/ui2/ui2.dart';

import '../screens/body_history_actions_test.dart' show flush;
import '../../data/journal_weight_handoff_test.dart' show until;
import '../../support/audit_visual.dart' show loadAuditFonts;
import '../../support/coverage_store.dart';
import '../../support/localized_coverage.dart';

class _HoldingController extends LiftLogController {
  _HoldingController(super.sessionId);
  final release = Completer<void>();
  final submissions = <List<String>>[];

  @override
  Future<void> saveSplits(List<LiftSplit> next) async {
    submissions.add(next.single.exercises.map((item) => item.name).toList());
    if (submissions.length == 1) await release.future;
    await super.saveSplits(next);
  }
}

void main() {
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('lift-split-queued-draft', fresh: true);
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  const initial = ['Authored row', 'Authored press', 'Authored curl'];
  const combined = ['Authored curl', 'Authored row', 'Authored press'];

  for (final refuse in [false, true]) {
    testWidgets(
      'two rapid reorder actions preserve the latest split draft after refusal: $refuse',
      (t) async {
        final controller = _HoldingController('authored-held-session');
        addTearDown(() {
          if (!controller.release.isCompleted) controller.release.complete();
          controller.dispose();
        });
        final split = LiftSplit(
          id: 'authored-held-split',
          name: 'Authored reorder routine',
          exercises: [
            for (final name in initial)
              LiftSplitExercise(name: name, loadMode: LiftLoadMode.total),
          ],
        );
        final db = (await t.runAsync(() async {
          await LiftLogDb.saveSplits([split]);
          await controller.load();
          final db = await LocalDb.instance;
          if (refuse) {
            await db.execute("""
            CREATE TRIGGER authored_split_refusal BEFORE INSERT ON baselines
            WHEN NEW.key = '${CalculationStore.prefix}${LiftLogDb.splitsKey}'
            BEGIN SELECT RAISE(ABORT, 'authored split refusal'); END
          """);
          }
          return db;
        }))!;
        Future<List<String>> savedOrder() async => (await LiftLogDb.splits())
            .single
            .exercises
            .map((item) => item.name)
            .toList();

        await localizedPage(
          t,
          LiftSplitsScreen(controller: controller),
          push: true,
        );
        await flush(t);
        await t.tap(find.text(split.name));
        await flush(t);

        final move = find.byWidgetPredicate(
          (w) => w is Pressable && w.semanticLabel == 'Move Authored curl up',
        );
        await reveal(t, move);
        await t.tap(move);
        await until(t, () => controller.submissions.length == 1);
        expect(controller.submissions.single, [
          'Authored row',
          'Authored curl',
          'Authored press',
        ]);
        // Recover the current action after the first reorder changes its index.
        await t.pump();
        await t.ensureVisible(move);
        await t.tap(move);
        await t.pump();
        expect(controller.submissions, hasLength(1));
        expect(await t.runAsync(savedOrder), initial);

        controller.release.complete();
        await until(
          t,
          () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
        );
        final status = find.widgetWithText(StatusCard, 'Changes not saved');
        if (refuse) {
          expect(status, findsOneWidget);
          expect(await t.runAsync(savedOrder), initial);
          expect(controller.submissions, hasLength(1));
          await t.runAsync(
            () => db.execute('DROP TRIGGER authored_split_refusal'),
          );
          await t.tap(find.text('Retry'));
          await until(t, () => status.evaluate().isEmpty);
        }
        expect(status, findsNothing);
        expect(controller.submissions, hasLength(2));
        expect(controller.submissions.last, combined);
        expect(await t.runAsync(savedOrder), combined);
        expect((await t.runAsync(LiftLogDb.splits))!.single.id, split.id);
        expect(find.text('Authored curl'), findsOneWidget);
      },
    );
  }
}
