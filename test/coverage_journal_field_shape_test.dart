// Existing custom-field form controls; returned specs, no personal-store writes.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/journal_fields.dart';
import 'package:whoop_companion/ui2/screens/custom_journal_field_sheet.dart';
import 'package:whoop_companion/ui2/screens/journal_compose.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/localized_coverage.dart';

void main() {
  setUpAll(loadAuditFonts);
  Finder input(String label) => find.descendant(
    of: find.byWidgetPredicate((w) => w is WhoopTextField && w.label == label),
    matching: find.byType(TextField),
  );
  Future<void> tap(WidgetTester t, String label) async {
    final f = find.widgetWithText(Pressable, label).first;
    await t.ensureVisible(f);
    await t.tap(f);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  }

  for (final kind in ['An amount', 'Minutes']) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        '$kind at ${scale}x keeps chosen step ceiling unit and last-time intent',
        (t) async {
          JournalFieldSpec? result;
          await localizedPage(
            t,
            Builder(
              builder: (c) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    result = await showCustomJournalFieldSheet(
                      c,
                      existingKeys: {},
                    );
                  },
                  child: const Text('Existing field form'),
                ),
              ),
            ),
            scale: scale,
          );
          await t.tap(find.text('Existing field form'));
          await t.pumpAndSettle();
          await t.enterText(
            input('What do you want to track?'),
            '  Authored test field  ',
          );
          await tap(t, kind);
          if (kind == 'Minutes') {
            expect(t.widget<TextField>(input('Unit')).controller!.text, 'min');
          } else {
            await t.enterText(input('Unit'), '  cups  ');
          }
          // A ceiling incompatible with the next step must return to a valid
          // step-derived default before a deliberate final ceiling selection.
          await tap(t, '5');
          await tap(t, '250');
          await tap(t, '100');
          expect(
            t.widget<Pill>(find.widgetWithText(Pill, '2000')).color,
            C.domMind,
          );
          await tap(t, '1000');
          await tap(t, 'Ask when the last one was');
          await tap(t, 'Ask when the last one was');
          await tap(t, 'Ask when the last one was');
          await tap(t, 'Start tracking it');
          expect(result, isNotNull);
          expect(result!.key, 'custom_authored_test_field');
          expect(result!.label, 'Authored test field');
          expect(
            result!.kind,
            kind == 'Minutes'
                ? JournalFieldKind.duration
                : JournalFieldKind.dose,
          );
          expect(result!.unit, kind == 'Minutes' ? 'min' : 'cups');
          expect(result!.max, 1000);
          expect(result!.step, 100);
          expect(result!.hasTime, isTrue);
          expect(result!.custom, isTrue);
          expect(find.text('Existing field form'), findsOneWidget);
        },
      );
    }
  }

  testWidgets('backing out of a completed field form returns no definition', (
    t,
  ) async {
    var completed = false;
    JournalFieldSpec? result;
    await localizedPage(
      t,
      Builder(
        builder: (c) => Scaffold(
          body: TextButton(
            onPressed: () async {
              result = await showCustomJournalFieldSheet(c, existingKeys: {});
              completed = true;
            },
            child: const Text('Existing field form'),
          ),
        ),
      ),
    );
    await t.tap(find.text('Existing field form'));
    await t.pumpAndSettle();
    await t.enterText(input('What do you want to track?'), 'Unsaved field');
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(completed, isTrue);
    expect(result, isNull);
    expect(find.text('Existing field form'), findsOneWidget);
  });
}
