// The real repeat-field IME action must apply the same creation validation as
// Encrypt, and return the exact accepted passphrase without changing its bytes.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/ui2/onboarding/welcome.dart';
import '../../support/audit_visual.dart' show loadAuditFonts;
import '../../support/localized_coverage.dart';

void main() {
  setUpAll(loadAuditFonts);
  for (final initial in ['short', 'different', 'matching']) {
    testWidgets(
      'backup repeat-field keyboard validates $initial then accepts exact text',
      (t) async {
        String? returned;
        var closed = false;
        await localizedPage(
          t,
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  returned = await askBackupPassphrase(context, creating: true);
                  closed = true;
                },
                child: const Text('Create authored backup'),
              ),
            ),
          ),
        );
        await t.tap(find.text('Create authored backup'));
        await t.pumpAndSettle();
        final fields = find.byType(TextField);
        const exact = ' authored fixture with spaces ';
        await t.enterText(fields.first, initial == 'short' ? 'short' : exact);
        await t.enterText(
          fields.last,
          initial == 'different'
              ? 'different authored fixture'
              : initial == 'short'
              ? 'short'
              : exact,
        );
        await t.testTextInput.receiveAction(TextInputAction.done);
        await t.pumpAndSettle();
        if (initial != 'matching') {
          expect(closed, false);
          expect(returned, isNull);
          expect(
            find.text(
              initial == 'short'
                  ? 'At least 8 characters.'
                  : 'The two do not match.',
            ),
            findsOneWidget,
          );
          expect(
            t.widgetList<TextField>(fields).every((w) => w.obscureText),
            true,
          );
          await t.enterText(fields.first, exact);
          await t.enterText(fields.last, exact);
          await t.testTextInput.receiveAction(TextInputAction.done);
          await t.pumpAndSettle();
        }
        expect(closed, true);
        expect(returned, exact);
        expect(find.byType(AlertDialog), findsNothing);
        expect(t.takeException(), isNull);
      },
    );
  }
}
