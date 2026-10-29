// Authored measured corrections versus unavailable historical phone evidence.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/streak.dart';
import 'package:whoop_companion/data/calculation_store.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/day_label.dart';

import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('step-goal-correction'));
  setUp(() async {
    await StepGoals.flush();
    await resetCoverageStore();
  });
  tearDown(() async {
    await StepGoals.flush();
    await (await LocalDb.instance).execute(
      'DROP TRIGGER IF EXISTS authored_goal_refusal',
    );
  });
  tearDownAll(LocalDb.close);
  const day = '2021-04-06';
  final at = DateTime.parse('$day 18:00:00');
  Future<String> seed() async {
    final ledger = jsonEncode({
      'from': day,
      'targets': {day: 2000},
      'earned': {day: 1000},
    });
    await CalculationStore.write(StepGoals.key, ledger);
    return ledger;
  }

  Future<void> measure(int steps) => LocalDb.replacePhoneCoverageForDay(day, [
    (
      startTs: localDayStartSec(day)!,
      endTs: localDayStartSec(day)! + 3600,
      steps: steps,
    ),
  ]);
  for (final steps in <int?>[null, 0, 500, 1500]) {
    test(
      'historical goal treats ${steps ?? 'unavailable'} steps as its own evidence state',
      () async {
        await seed();
        if (steps != null) await measure(steps);
        final qualified = await StepGoals.qualifying(at: at);
        final retained = steps == null || steps >= 1000;
        expect(qualified, retained ? {day} : isEmpty);
        final ledger = await StepGoals.read(at: at);
        expect(StepGoals.targetOn(ledger, day), 2000);
        expect(StepGoals.goalOn(ledger, day), retained ? 1000 : 2000);
        expect((ledger['earned'] as Map).containsKey(day), retained);
        expect(StepGoals.busy, false);
        final resolved = await LocalDb.resolvedStepsForDay(day);
        expect(resolved.hasPhoneCoverage, steps != null);
        expect(resolved.total, steps ?? 0);
      },
    );
  }
  test(
    'refused goal correction releases queued reads without replacing the earned ledger',
    () async {
      final before = await seed();
      await measure(0);
      final db = await LocalDb.instance;
      await db.execute(
        "CREATE TRIGGER authored_goal_refusal BEFORE INSERT ON baselines WHEN NEW.key='calculation:steps.goal_history' BEGIN SELECT RAISE(ABORT,'authored goal refusal'); END",
      );
      final failed = StepGoals.qualifying(at: at);
      final queued = StepGoals.read(at: at);
      await expectLater(failed, throwsA(isA<Exception>()));
      expect(jsonEncode(await queued), before);
      expect(await CalculationStore.read(StepGoals.key), before);
      expect(StepGoals.busy, false);
      await db.execute('DROP TRIGGER authored_goal_refusal');
      expect(await StepGoals.qualifying(at: at), isEmpty);
      expect((await StepGoals.read(at: at))['earned'], isEmpty);
      expect(StepGoals.busy, false);
    },
  );
}
