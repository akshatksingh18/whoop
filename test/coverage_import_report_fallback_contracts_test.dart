// Public report component without a localization provider: every fallback must
// retain the same committed/refused/missing distinctions as its localized host.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/ui2/onboarding/welcome.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/localized_coverage.dart' show localizedPage;

void main() {
  setUpAll(loadAuditFonts);
  testWidgets(
    'the localized out-of-order report keeps date-order recovery distinct from corruption',
    (t) async {
      await localizedPage(
        t,
        const Scaffold(
          body: SingleChildScrollView(
            child: ImportReport(
              ImportOutcome(
                source: 'Authored source',
                days: 2,
                strandedDays: 2,
                lateRows: 2,
              ),
            ),
          ),
        ),
      );
      final report = t.widgetList<StatusCard>(find.byType(StatusCard)).single;
      expect(report.fix, 'Export again in date order');
      expect(report.why, contains('2 days arrived out of order'));
      expect(report.why, contains('2 rows arrived after'));
      expect(report.why, isNot(contains('corrupted')));
      expect(find.text('2 days imported'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  final cases = <(String, ImportOutcome, List<String>)>[
    (
      'read failure',
      const ImportOutcome(
        source: 'Authored source',
        error: 'Authored read refusal',
      ),
      [
        'Authored source could not be read',
        'Authored read refusal',
        'Try another file',
      ],
    ),
    (
      'empty',
      const ImportOutcome(source: 'Authored source'),
      ['Nothing was imported', 'there was nothing in it'],
    ),
    (
      'all refused',
      const ImportOutcome(
        source: 'Authored source',
        rejectedRows: ['line 1: invalid'],
      ),
      ['Nothing was imported', 'Every row was refused: line 1: invalid.'],
    ),
    (
      'partial read with no commit',
      const ImportOutcome(
        source: 'Authored source',
        readError: 'Authored empty read refusal',
      ),
      ['Nothing was imported', 'Authored empty read refusal'],
    ),
    (
      'one day and journal',
      const ImportOutcome(source: 'Authored source', days: 1, journalRows: 1),
      ['1 day imported', '1 journal day replaced'],
    ),
    (
      'plural days and journal',
      const ImportOutcome(source: 'Authored source', days: 2, journalRows: 2),
      ['2 days imported', '2 journal days replaced'],
    ),
    (
      'journal only',
      const ImportOutcome(source: 'Authored source', journalRows: 2),
      ['2 journal days written'],
    ),
    (
      'one restored record',
      const ImportOutcome(source: 'Authored source', records: 1),
      ['1 record restored'],
    ),
    (
      'one workout and skipped day',
      const ImportOutcome(
        source: 'Authored source',
        workouts: 1,
        skippedDays: 1,
      ),
      ['1 workout', '1 day already measured here and left alone'],
    ),
    (
      'plural workouts and skips',
      const ImportOutcome(
        source: 'Authored source',
        workouts: 2,
        skippedDays: 2,
      ),
      ['2 workouts', '2 days already measured here and left alone'],
    ),
    (
      'landed but no summaries',
      const ImportOutcome(
        source: 'Authored source',
        days: 1,
        rollupError: 'Authored rollup refusal',
        readError: 'Authored partial refusal',
      ),
      [
        '1 day imported',
        'The days landed, the summaries did not',
        'Every imported row is in the database',
        'Authored rollup refusal',
        'The rest imported. Authored partial refusal',
      ],
    ),
    (
      'out of order and late',
      const ImportOutcome(
        source: 'Authored source',
        days: 1,
        strandedDays: 1,
        lateRows: 1,
      ),
      [
        '1 day imported',
        '1 day arrived out of order',
        '1 row arrived after',
        'Export again in date order',
      ],
    ),
    (
      'corrupt subset',
      const ImportOutcome(
        source: 'Authored source',
        records: 2,
        corruptTables: {'authored_table'},
      ),
      [
        '2 records restored',
        'authored_table could not be read',
        'Every other table imported normally',
        'Try another file',
      ],
    ),
  ];
  for (final (name, outcome, requiredText) in cases) {
    testWidgets(
      'report fallback $name preserves exact success and failure provenance',
      (t) async {
        t.view.physicalSize = const Size(430, 2200);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        await t.pumpWidget(
          MaterialApp(
            theme: buildTheme(Brightness.light),
            home: Scaffold(
              body: SingleChildScrollView(child: ImportReport(outcome)),
            ),
          ),
        );
        await t.pumpAndSettle();
        final text = t
            .widgetList<Text>(find.byType(Text))
            .map((w) => w.data ?? '')
            .join(' ');
        for (final expected in requiredText) {
          expect(text, contains(expected));
        }
        if (outcome.error != null || outcome.nothingLanded) {
          expect(find.byType(StatusCard), findsOneWidget);
          expect(text, isNot(contains('day imported')));
          expect(text, isNot(contains('record restored')));
        }
        expect(t.takeException(), isNull);
      },
    );
  }
  for (final landed in [false, true]) {
    testWidgets(
      'report ${landed ? 'partial' : 'all'} refusals cap details at six and retain the remainder count',
      (t) async {
        final rejected = [for (var i = 1; i <= 8; i++) 'line $i refused'];
        await t.pumpWidget(
          MaterialApp(
            theme: buildTheme(Brightness.light),
            home: Scaffold(
              body: SingleChildScrollView(
                child: ImportReport(
                  ImportOutcome(
                    source: 'Authored source',
                    days: landed ? 1 : 0,
                    rejectedRows: rejected,
                  ),
                ),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        final text = t
            .widgetList<Text>(find.byType(Text))
            .map((w) => w.data ?? '')
            .join(' ');
        expect(text, contains('line 1 refused'));
        expect(text, contains('line 6 refused; and 2 more.'));
        expect(text, isNot(contains('line 7 refused')));
        expect(
          text,
          contains(landed ? '8 rows were refused' : 'Every row was refused'),
        );
        expect(text.contains('1 day imported'), landed);
        expect(t.takeException(), isNull);
      },
    );
  }
}
