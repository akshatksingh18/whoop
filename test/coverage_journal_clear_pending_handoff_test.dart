// Real editor gestures and SQLite rollback;only the command's timing is held.
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/journal_fields.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/screens/journal_compose.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'coverage_journal_edit_ownership_test.dart' show flush, real;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

const _day = '2021-04-06', _other = '2021-04-01';

class _HeldRepo extends LocalRepositoryImpl {
  _HeldRepo() : super(getProfileMap: () => {});
  Completer<void> release = Completer<void>();
  int writes = 0;
  @override
  Future<List<String>> saveJournalEdit(
    String date, {
    required Map<String, JournalMetricValue?> changes,
    required Map<String, JournalMetricValue> base,
    List<String>? tags,
    List<String>? baseTags,
    String? note,
    String? baseNote,
  }) async {
    writes++;
    await release.future;
    return super.saveJournalEdit(
      date,
      changes: changes,
      base: base,
      tags: tags,
      baseTags: baseTags,
      note: note,
      baseNote: baseNote,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('journal-clear-pending');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  for (final scale in [1.0, 3.1]) {
    for (final refuse in [false, true]) {
      testWidgets('Journal clear/refusal=$refuse saves once at ${scale}x', (
        t,
      ) async {
        final repo = _HeldRepo();
        final app = AppState.forTesting()..repo = repo;
        final db = await LocalDb.instance;
        addTearDown(() async {
          if (!repo.release.isCompleted) repo.release.complete();
          await t.runAsync(
            () =>
                db.execute('DROP TRIGGER IF EXISTS authored_refuse_mood_clear'),
          );
          app.dispose();
        });
        await LocalDb.putJournal(
          _day,
          '["travel","workout"]',
          'Retained authored note',
        );
        await LocalDb.putJournalMetrics(_day, {
          'mood': const JournalMetricValue(3),
          'caffeine_mg': const JournalMetricValue(0, atMinuteOfDay: 0),
        });
        await LocalDb.putJournal(_other, '["rest day"]', 'Other authored note');
        final before = await db.query('journal');
        final metrics = await db.query('journal_metric');
        if (refuse) {
          await db.execute(
            "CREATE TRIGGER authored_refuse_mood_clear BEFORE DELETE ON journal_metric WHEN OLD.date = '$_day' AND OLD.field = 'mood' BEGIN SELECT RAISE(ABORT, 'authored refusal'); END",
          );
        }
        Future<void> open() async {
          await t.pumpWidget(const SizedBox());
          await t.pumpAndSettle();
          await localizedPage(
            t,
            const JournalCompose(date: _day),
            app: app,
            scale: scale,
            push: true,
          );
          await flush(t);
        }

        await open();
        final mood = find.byWidgetPredicate(
          (w) =>
              w is Pressable &&
              w.semanticLabel == 'Mood 3 of 5, selected. Activate to clear.',
        );
        await reveal(t, mood);
        await t.tap(mood);
        await t.pumpAndSettle();
        expect(t.widget<MoodPicker>(find.byType(MoodPicker)).value, isNull);
        final tag = find.widgetWithText(Pressable, 'travel');
        await reveal(t, tag);
        await t.tap(tag);
        await t.pumpAndSettle();
        final save = find.widgetWithText(BigButton, 'Save');
        await reveal(t, save);
        await t.tap(save);
        await t.pumpAndSettle();
        expect(repo.writes, 1);
        expect(
          t.widget<BigButton>(find.widgetWithText(BigButton, 'Saving')).onTap,
          isNull,
        );
        expect(await real(t, () => db.query('journal')), before);
        expect(await real(t, () => db.query('journal_metric')), metrics);
        repo.release.complete();
        await flush(t);
        if (refuse) {
          expect(
            find.text('Could not save. Nothing was changed; try again.'),
            findsOneWidget,
          );
          expect(await real(t, () => db.query('journal')), before);
          expect(await real(t, () => db.query('journal_metric')), metrics);
          await real(
            t,
            () => db.execute('DROP TRIGGER authored_refuse_mood_clear'),
          );
          // At large text the transient refusal notice covers the bottom Save
          // button. Let the real notice expire before the next gesture.
          await t.pump(const Duration(seconds: 5));
          await t.pumpAndSettle();
          await reveal(t, save);
          await t.tap(save);
          await flush(t);
        }
        expect(repo.writes, refuse ? 2 : 1);
        expect(find.byType(JournalCompose), findsNothing);
        final saved = await real(t, () => LocalDb.journalMetricsForDay(_day));
        expect(saved.containsKey('mood'), false);
        expect(
          saved['caffeine_mg'],
          const JournalMetricValue(0, atMinuteOfDay: 0),
        );
        final rows = await real(t, () => LocalDb.journalRows(date: _day));
        expect(jsonDecode(rows.single['tags_json'] as String), ['workout']);
        expect(rows.single['note'], 'Retained authored note');
        expect(
          await real(
            t,
            () => db.query('journal', where: 'date = ?', whereArgs: [_other]),
          ),
          before.where((r) => r['date'] == _other).toList(),
        );
        await open();
        expect(t.widget<MoodPicker>(find.byType(MoodPicker)).value, isNull);
        expect(await real(t, () => LocalDb.journalMetricsForDay(_day)), saved);
        expect(t.takeException(), isNull);
      });
    }
  }
}
