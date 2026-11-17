// Shared Swipe is used by NutritionScreen._today, including its newest-day
// null Next boundary. Exercise real gestures and accessibility callbacks.
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/ui2/grammar.dart' show Swipe;

void main() {
  for (final newest in [false, true]) {
    for (final scale in [1.0, 3.1]) {
      testWidgets(
        'Food day Swipe ${newest ? 'newest boundary' : 'historical directions'} ${scale}x accepts deliberate movement only',
        (t) async {
          t.view.physicalSize = const Size(430, 932);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.reset);
          final handle = t.ensureSemantics();
          try {
            var previous = 0, next = 0;
            await t.pumpWidget(
              MaterialApp(
                builder: (c, w) => MediaQuery(
                  data: MediaQuery.of(
                    c,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: w!,
                ),
                home: Scaffold(
                  body: Center(
                    child: Swipe(
                      label: 'Day',
                      onPrevious: () => previous++,
                      onNext: newest ? null : () => next++,
                      child: const SizedBox(
                        width: 380,
                        height: 400,
                        child: Center(child: Text('Day body')),
                      ),
                    ),
                  ),
                ),
              ),
            );
            final target = find.byType(Swipe);
            await t.timedDrag(
              target,
              const Offset(90, 0),
              const Duration(seconds: 1),
            );
            await t.pumpAndSettle();
            expect((previous, next), (0, 0));
            await t.fling(target, const Offset(0, -100), 1000);
            await t.pumpAndSettle();
            expect((previous, next), (0, 0));
            await t.fling(target, const Offset(120, 0), 1000);
            await t.pumpAndSettle();
            expect((previous, next), (1, 0));
            await t.fling(target, const Offset(-120, 0), 1000);
            await t.pumpAndSettle();
            expect((previous, next), (1, newest ? 0 : 1));

            final node = t.getSemantics(target);
            expect(node.getSemanticsData().label, contains('Day'));
            expect(
              node.getSemanticsData().hasAction(ui.SemanticsAction.scrollRight),
              true,
            );
            expect(
              node.getSemanticsData().hasAction(ui.SemanticsAction.scrollLeft),
              !newest,
            );
            node.owner!.performAction(node.id, ui.SemanticsAction.scrollRight);
            await t.pump();
            expect(previous, 2);
            if (!newest) {
              node.owner!.performAction(node.id, ui.SemanticsAction.scrollLeft);
              await t.pump();
              expect(next, 2);
            }
            expect(t.takeException(), isNull);
            await t.pumpWidget(const SizedBox());
          } finally {
            handle.dispose();
          }
        },
      );
    }
  }
}
