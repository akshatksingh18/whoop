// Real picker results after their owning editor has left the navigation stack.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/activity/catalogue.dart';
import 'package:openstrap_edge/ui2/screens/log_workout.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

void main() {
  for (final label in ['Date', 'Started', 'Ended', 'Activity']) {
    testWidgets('$label ignores a late picker result after the editor closes', (
      t,
    ) async {
      t.view.physicalSize = const Size(1170, 3000);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final nav = GlobalKey<NavigatorState>();
      late Route<void> editor;
      await t.pumpWidget(
        MaterialApp(
          navigatorKey: nav,
          theme: buildTheme(Brightness.light),
          home: Scaffold(
            body: TextButton(
              onPressed: () {
                editor = MaterialPageRoute<void>(
                  builder: (_) => LogWorkout(
                    now: DateTime(2026, 8, 19, 21),
                    spans: const [],
                  ),
                );
                nav.currentState!.push(editor);
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await t.tap(find.text('Open'));
      await t.pumpAndSettle();
      await t.tap(find.text(label));
      await t.pumpAndSettle();
      nav.currentState!.removeRoute(editor);
      await t.pumpAndSettle();
      if (label == 'Date') {
        nav.currentState!.pop(DateTime(2026, 8, 18));
      } else if (label == 'Activity') {
        nav.currentState!.pop(quickStart.last);
      } else {
        nav.currentState!.pop(const TimeOfDay(hour: 18, minute: 20));
      }
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.text('Open'), findsOneWidget);
    });
  }
}
