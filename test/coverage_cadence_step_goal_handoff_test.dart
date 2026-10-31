// Ordinary foreground cadence, real SQLite and the existing goal ledger.
// Only native notification permission/cancellation is substituted.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whoop_companion/compute/streak.dart';
import 'package:whoop_companion/data/calculation_store.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/notify/notification_prefs.dart';
import 'package:whoop_companion/notify/notification_service.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/sync/paired_device.dart';
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final svc = NotificationService.instance;
  late AppState app;
  late String day;
  setUpAll(() => coverageStore('cadence-step-goal'));
  setUp(() async {
    await StepGoals.flush();
    await resetCoverageStore();
    svc.debugCancel = (_) async {};
    svc.debugProbePermission = () async => false;
    svc.debugRequestPermission = () async => false;
    svc.invalidatePermissionCache();
    await const NotificationPrefs(remindersEnabled: false).save();
    day = todayLabel();
    app = AppState.forTesting()
      ..paired = PairedDevice('authored-cadence-band', 'gen4')
      ..user = {'step_goal': 1000};
  });
  tearDown(() async {
    app.dispose();
    await StepGoals.flush();
    // Let the public cadence's independent, best-effort schema/staleness reads
    // finish before resetting this tiny authored database for the next case.
    await Future<void>.delayed(const Duration(milliseconds: 60));
    svc.debugCancel = null;
    svc.debugProbePermission = null;
    svc.debugRequestPermission = null;
    svc.invalidatePermissionCache();
  });
  tearDownAll(LocalDb.close);
  Future<void> seed(int steps, {bool earned = false}) async {
    await CalculationStore.write(
      StepGoals.key,
      jsonEncode({
        'from': day,
        'targets': {day: 1000},
        'earned': {if (earned) day: 1000},
      }),
    );
    final start = localDayStartSec(day)!;
    await LocalDb.replacePhoneCoverageForDay(day, [
      (startTs: start, endTs: start + 3600, steps: steps),
    ]);
  }

  for (final steps in [999, 1000, 1500]) {
    test(
      'COV-48 foreground cadence qualifies measured $steps against the saved goal only',
      () async {
        await seed(steps);
        final db = await LocalDb.instance;
        final raw = await db.query('live_coverage');
        await app.runCadenceChecks();
        expect(StepGoals.busy, false);
        final ledger = await StepGoals.read();
        expect(ledger['targets'], {day: 1000});
        expect(ledger['earned'], steps >= 1000 ? {day: 1000} : isEmpty);
        final committed = await LocalDb.baseline(
          'calculation:${StepGoals.key}',
        );
        await app.runCadenceChecks();
        expect(
          await LocalDb.baseline('calculation:${StepGoals.key}'),
          committed,
        );
        expect(await db.query('live_coverage'), raw);
        expect((await LocalDb.resolvedStepsForDay(day)).total, steps);
        expect(StepGoals.busy, false);
      },
    );
  }

  test(
    'COV-48 cadence refused award preserves the ledger and cache until explicit retry',
    () async {
      await seed(1500);
      final db = await LocalDb.instance;
      final before = await LocalDb.baseline('calculation:${StepGoals.key}');
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(StepGoals.key);
      await db.execute(
        "CREATE TRIGGER authored_cadence_award_refusal BEFORE INSERT ON baselines "
        "WHEN NEW.key='calculation:steps.goal_history' BEGIN "
        "SELECT RAISE(ABORT,'authored cadence award refusal'); END",
      );
      try {
        await app.runCadenceChecks();
        expect(await LocalDb.baseline('calculation:${StepGoals.key}'), before);
        expect(prefs.getString(StepGoals.key), cached);
        expect(StepGoals.busy, false);
      } finally {
        await db.execute('DROP TRIGGER authored_cadence_award_refusal');
      }
      await app.runCadenceChecks();
      expect((await StepGoals.read())['earned'], {day: 1000});
      expect((await LocalDb.resolvedStepsForDay(day)).total, 1500);
      expect(StepGoals.busy, false);
    },
  );

  test(
    'COV-48 cadence unavailable step read preserves an earned day and retries after recovery',
    () async {
      await seed(1500, earned: true);
      final db = await LocalDb.instance;
      final before = await LocalDb.baseline('calculation:${StepGoals.key}');
      final raw = await db.query('live_coverage');
      await db.execute(
        'ALTER TABLE live_coverage RENAME TO authored_coverage_retained',
      );
      try {
        await app.runCadenceChecks();
        expect(await LocalDb.baseline('calculation:${StepGoals.key}'), before);
        expect(await db.query('authored_coverage_retained'), raw);
        expect(StepGoals.busy, false);
      } finally {
        await db.execute(
          'ALTER TABLE authored_coverage_retained RENAME TO live_coverage',
        );
      }
      await app.runCadenceChecks();
      expect(await LocalDb.baseline('calculation:${StepGoals.key}'), before);
      expect(await db.query('live_coverage'), raw);
      expect((await StepGoals.read())['earned'], {day: 1000});
      expect((await LocalDb.resolvedStepsForDay(day)).total, 1500);
      expect(StepGoals.busy, false);
    },
  );
}
