// Real saved sessions -> Pushups.status -> current goal/rest guidance,without mutation.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/pushups.dart';
import 'package:whoop_companion/data/pushup_reminders.dart';
import 'package:whoop_companion/ui2/screens/pushups_screen.dart';
import '../../data/pushup_screen_actions_test.dart' show flush;
import '../../support/audit_visual.dart' show loadAuditFonts;
import '../../support/coverage_store.dart';
import '../../support/localized_coverage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('pushup-rest-goal-projection');
  });
  setUp(() async {
    await resetCoverageStore();
    await PushupReminders.clearInbox();
    await PushupReminders.writeMirror(null);
  });
  tearDownAll(LocalDb.close);

  Future<void> seed(String scenario) async {
    final now = DateTime.now();
    final offsets = scenario.startsWith('exhausted') ? [-5, -3, -1] : [-1];
    for (final offset in [...offsets, 0]) {
      final start = DateTime(now.year, now.month, now.day + offset);
      final n = offset != 0
          ? 2
          : scenario.endsWith('zero')
          ? 0
          : scenario == 'reached' || scenario == 'off-two'
          ? 2
          : 1;
      final session = PushupSession(
        id: 'authored-rest-$offset',
        day: dayLabelOf(start),
        started: start,
        ended: offset == 0 ? null : start.add(const Duration(hours: 1)),
        interval: 45,
        goal: offset == 0 && scenario.startsWith('off') ? null : 2,
        state: offset == 0 ? PushupState.paused : PushupState.ended,
        events: [
          for (var i = 0; i < n; i++)
            PushupEvent(
              id: 'authored-event-$offset-$i',
              at: start.add(Duration(seconds: i + 1)),
              kind: PushupEventKind.done,
              source: 'authored-screen',
            ),
        ],
      );
      await PushupDb.save(session);
    }
    // A later preference must not rewrite the active day's captured goal.
    await PushupDb.setGoal(scenario.startsWith('off') ? 0 : 5);
  }

  // Match the existing Pushups command tests:all flows share the process-wide
  // command Future's owning FakeAsync zone;stores reset between named flows.
  testWidgets(
    'real Pushups rest/goal projections preserve fourteen page states',
    (t) async {
      for (final scale in [1.0, 3.1]) {
        for (final scenario in [
          'available-zero',
          'available-one',
          'exhausted-zero',
          'exhausted-one',
          'reached',
          'off-one',
          'off-two',
        ]) {
          await t.pumpWidget(const SizedBox());
          await flush(t);
          await t.runAsync(() async {
            await resetCoverageStore();
            await PushupReminders.clearInbox();
            await PushupReminders.writeMirror(null);
          });
          debugPrint('Authored Pushups projection: $scenario at ${scale}x');
          await t.runAsync(() => seed(scenario));
          final db = await LocalDb.instance;
          final before = await db.query('pushup_session', orderBy: 'id');
          final status = (await t.runAsync(Pushups.status))!;
          final exhausted = scenario.startsWith('exhausted');
          final off = scenario.startsWith('off');
          final zero = scenario.endsWith('zero');
          expect(status.active!.state, PushupState.paused);
          expect(status.active!.goal, off ? isNull : 2);
          expect(status.goal, off ? 0 : 5);
          expect(
            status.today,
            zero
                ? 0
                : scenario == 'reached' || scenario == 'off-two'
                ? 2
                : 1,
          );
          if (!off && scenario != 'reached') {
            expect(status.streaks.current, exhausted ? 3 : 1);
            expect(status.restCoversToday, !exhausted);
          }
          await localizedPage(
            t,
            const PushupsScreen(),
            scale: scale,
            settle: false,
          );
          await flush(t);
          final texts = await readPage(t);
          final expected = off
              ? 'The streak is off. Set a daily goal in Settings.'
              : scenario == 'reached'
              ? 'Reached today.'
              : exhausted
              ? '${zero ? '2 more sets keep' : '1 more set keeps'} the streak. Both rest days this week are used, so a short day ends it.'
              : '${zero ? '2 more sets reach' : '1 more set reaches'} today\'s goal. If today ends short, it is a rest day and the streak continues.';
          expect(texts, contains(expected));
          expect(texts, contains('Sets today'));
          expect(texts, contains('Daily goal'));
          expect(texts, contains('History'));
          if (off) {
            expect(
              texts,
              contains(scenario == 'off-two' ? '2 sets today' : '1 set today'),
            );
          }
          if (!off && scenario != 'reached') {
            expect(texts, contains(zero ? 'No sets yet' : '1 of 2 · 1 to go'));
            expect(texts, isNot(contains('1 of 5 · 4 to go')));
          }
          final after = await db.query('pushup_session', orderBy: 'id');
          expect(after.length, before.length);
          for (final original in before) {
            final saved = after.singleWhere((r) => r['id'] == original['id']);
            if (original['id'] == status.active!.id) {
              // Mounting invokes real reconcile,which rebanks the active row.
              // Its receipt timestamp may advance;all stored content is exact.
              expect(
                saved['updated_at'],
                greaterThanOrEqualTo(original['updated_at'] as int),
              );
              expect(saved, {...original, 'updated_at': saved['updated_at']});
            } else {
              expect(saved, original);
            }
          }
          final reopened = (await t.runAsync(Pushups.status))!;
          expect(reopened.today, status.today);
          expect(reopened.active!.goal, status.active!.goal);
          expect(reopened.streaks, status.streaks);
          expect(reopened.restCoversToday, status.restCoversToday);
          expect(t.takeException(), isNull);
        }
      }
    },
    timeout: const Timeout(Duration(seconds: 180)),
  );
}
