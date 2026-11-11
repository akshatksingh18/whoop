// Real material time picker and existing view callback;no native alarm claim.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/ui2/profile/alarm.dart';
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/localized_coverage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAuditFonts);
  for (final action in ['cancel', 'create', 'change', 'refused']) {
    testWidgets(
      'complete alarm picker $action keeps the selected wall time and reports the write outcome',
      (t) async {
        final sent = <DateTime>[];
        final old = action == 'create' ? null : DateTime(2021, 4, 6, 7);
        await localizedPage(
          t,
          AlarmScreenView(
            armedAt: old,
            state: old == null ? AlarmArmState.none : AlarmArmState.unknown,
            connected: true,
            onSet: (at) async {
              sent.add(at);
              if (action == 'refused') {
                throw Exception('Authored alarm refusal');
              }
            },
          ),
        );
        final page = find.byType(AlarmScreenView);
        final before = t.widget<AlarmScreenView>(page);
        await t.tap(
          find.text(old == null ? 'Set an alarm' : 'Change the time'),
        );
        await t.pumpAndSettle();
        expect(find.byType(TimePickerDialog), findsOneWidget);
        await t.tap(find.byTooltip('Switch to text input mode'));
        await t.pumpAndSettle();
        expect(find.byType(TextField), findsNWidgets(2));
        await t.enterText(find.byType(TextField).first, '6');
        await t.enterText(find.byType(TextField).last, '42');
        final closingAt = DateTime.now();
        await t.tap(find.text(action == 'cancel' ? 'Cancel' : 'OK'));
        await t.pumpAndSettle();
        expect(find.byType(TimePickerDialog), findsNothing);
        expect(t.widget<AlarmScreenView>(page), same(before));
        expect(before.armedAt, old);
        if (action == 'cancel') {
          expect(sent, isEmpty);
          expect(find.text('Alarm sent to the band'), findsNothing);
        } else {
          expect(sent, hasLength(1));
          expect(sent.single.hour % 12, 6);
          expect(sent.single.minute, 42);
          expect(sent.single.isAfter(closingAt), true);
          expect(
            sent.single.isBefore(closingAt.add(const Duration(hours: 26))),
            true,
          );
          expect(
            find.text('Authored alarm refusal'),
            action == 'refused' ? findsOneWidget : findsNothing,
          );
          expect(
            find.text('Alarm sent to the band'),
            action == 'refused' ? findsNothing : findsOneWidget,
          );
        }
        expect(t.takeException(), isNull);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  }
}
