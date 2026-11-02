// Authored completed days preserve their original goal and pause history.
// Delete exercises only this isolated fixture, never a personal database.
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/pushups.dart';
import 'package:whoop_companion/ui2/screens/pushups_screen.dart';
import 'coverage_body_history_actions_test.dart' show flush, matchingAction;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('pushup-history-retention');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  PushupSession ended({int? goal}) => PushupSession(
    id: 'authored-ended-day',
    day: '2021-04-06',
    started: DateTime(2021, 4, 6, 9),
    ended: DateTime(2021, 4, 6, 10),
    interval: 30,
    goal: goal,
    state: PushupState.ended,
    events: [
      PushupEvent(
        id: 'authored-pause',
        at: DateTime(2021, 4, 6, 9, 15),
        kind: PushupEventKind.pause,
      ),
      PushupEvent(
        id: 'authored-resume',
        at: DateTime(2021, 4, 6, 9, 35),
        kind: PushupEventKind.resume,
      ),
    ],
  );

  for (final goal in <int?>[null, 4]) {
    testWidgets(
      'a completed zero-set day retains ${goal == null ? 'no goal' : 'its missed goal'} and pause interval',
      (t) async {
        final day = PushupDay.of('2021-04-06', [
          ended(goal: goal),
        ], DateTime(2021, 4, 7, 12))!;
        expect(
          day.status,
          goal == null ? PushupGoalStatus.notSet : PushupGoalStatus.missed,
        );
        expect(day.active, const Duration(minutes: 40));
        expect(day.paused, const Duration(minutes: 20));
        await localizedPage(t, PushupDayScreen(day: day));
        final text = (await readPage(t)).join(' ');
        expect(
          text,
          contains(
            goal == null ? 'No goal that day.' : '4 short of the goal of 4.',
          ),
        );
        expect(text, contains('None logged.'));
        expect(text, contains('Pauses'));
        expect(text, contains('20 min'));
        expect(text, contains('Only sets you marked Done count.'));
      },
    );
  }

  testWidgets(
    'completed-history deletion cancels, refuses and retries while keeping the open day and settings',
    (t) async {
      final db = await LocalDb.instance;
      await PushupDb.setGoal(6);
      await PushupDb.setInterval(45);
      final completed = ended(goal: 4);
      final open = PushupSession(
        id: 'authored-open-day',
        day: '2021-04-07',
        started: DateTime(2021, 4, 7, 9),
        interval: 45,
        goal: 6,
        state: PushupState.paused,
      );
      await PushupDb.save(completed);
      await PushupDb.save(open);
      final before = await db.query('pushup_session', orderBy: 'id');
      await localizedPage(
        t,
        const PushupSettingsScreen(canEditInterval: false),
      );
      await flush(t);
      Future<void> confirm(String choice) async {
        await reveal(t, matchingAction('Delete completed history'));
        await t.tap(matchingAction('Delete completed history'));
        await flush(t);
        await t.tap(find.text(choice).last);
        await flush(t);
      }

      await confirm('Keep it');
      expect(
        await t.runAsync(() => db.query('pushup_session', orderBy: 'id')),
        before,
      );
      await t.runAsync(
        () => db.execute(
          "CREATE TRIGGER authored_history_refusal BEFORE DELETE ON pushup_session BEGIN SELECT RAISE(ABORT,'authored history refusal'); END",
        ),
      );
      try {
        await confirm('Delete');
        expect(
          find.text('Could not delete history. Try again.'),
          findsOneWidget,
        );
        expect(
          await t.runAsync(() => db.query('pushup_session', orderBy: 'id')),
          before,
        );
      } finally {
        await t.runAsync(
          () => db.execute('DROP TRIGGER authored_history_refusal'),
        );
      }
      await confirm('Delete');
      final remaining = (await t.runAsync(() => db.query('pushup_session')))!;
      expect(remaining, [before.singleWhere((row) => row['id'] == open.id)]);
      expect(await t.runAsync(PushupDb.goal), 6);
      expect(await t.runAsync(PushupDb.interval), 45);
      expect(find.text('Could not delete history. Try again.'), findsNothing);
    },
  );
}
