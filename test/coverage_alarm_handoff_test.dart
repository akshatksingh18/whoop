// Real alarm controls and state projection with authored command outcomes.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/profile/alarm.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('alarm-handoff');
  });
  setUp(resetCoverageStore);
  final now = DateTime(2021, 4, 6, 8);
  for (final state in AlarmArmState.values) {
    testWidgets(
      'COV-47 localized alarm ${state.name} keeps confirmation separate from send',
      (t) async {
        await localizedPage(
          t,
          AlarmScreenView(
            armedAt: state == AlarmArmState.none
                ? null
                : now.add(const Duration(days: 3)),
            state: state,
            now: now,
          ),
        );
        final text = (await readPage(t)).join(' ');
        expect(text, contains('The band is not connected'));
        if (state == AlarmArmState.none) {
          expect(find.text('ARMED FOR'), findsNothing);
        } else {
          expect(
            text,
            contains(switch (state) {
              AlarmArmState.none => throw StateError('handled above'),
              AlarmArmState.pending => 'Sent',
              AlarmArmState.confirmed => 'The band has this alarm',
              _ => 'We cannot tell',
            }),
          );
        }
        if (state != AlarmArmState.none) expect(text, contains('In 3 days'));
      },
    );
  }
  for (final failed in [false, true]) {
    testWidgets(
      'COV-47 alarm buzz and cancel report actual command result $failed',
      (t) async {
        var buzz = 0, cancel = 0;
        await localizedPage(
          t,
          AlarmScreenView(
            armedAt: now.add(const Duration(hours: 1)),
            state: AlarmArmState.unknown,
            connected: true,
            now: now,
            onTest: () async {
              buzz++;
              if (failed) throw Exception('synthetic buzz refusal');
            },
            onCancel: () async {
              cancel++;
              if (failed) throw Exception('synthetic cancel refusal');
            },
          ),
        );
        final buttons = t
            .widgetList<BigButton>(find.byType(BigButton))
            .toList();
        await invokeControl(t, buttons[1].onTap);
        expect(buzz, 1);
        expect(
          find.text(failed ? 'synthetic buzz refusal' : 'Buzzing the band'),
          findsOneWidget,
        );
        await invokeControl(t, buttons[2].onTap);
        expect(cancel, 1);
        // Advance the first snackbar's exit so the second queued result is visible.
        await t.pump(const Duration(seconds: 5));
        await t.pumpAndSettle();
        expect(
          find.text(failed ? 'synthetic cancel refusal' : 'Alarm cancelled'),
          findsOneWidget,
        );
      },
    );
  }
  testWidgets('COV-47 cancelled alarm time picker sends no command', (t) async {
    var writes = 0;
    await localizedPage(
      t,
      AlarmScreenView(connected: true, onSet: (_) async => writes++),
    );
    await t.tap(find.text('Set an alarm'));
    await t.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(writes, 0);
  });
  testWidgets(
    'COV-47 alarm owner derives empty state without inventing a timestamp',
    (t) async {
      final app = AppState.forTesting();
      addTearDown(app.dispose);
      await localizedPage(t, const AlarmScreen(), app: app);
      final view = t.widget<AlarmScreenView>(find.byType(AlarmScreenView));
      expect(view.state, AlarmArmState.none);
      expect(view.armedAt, isNull);
      expect(view.onSet, isNotNull);
      expect(view.onTest, isNotNull);
      expect(view.onCancel, isNotNull);
    },
  );
}
