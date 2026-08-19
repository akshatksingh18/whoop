// ChartFrame used `excludeSemantics: true` to stop a screen reader saying the
// bare axis ticks and the doubled header. That worked, and it also deleted
// every descendant semantics node — including `child`, which on the sleep
// screen is the Scrubber. The one interactive control inside a chart was
// therefore invisible to VoiceOver and Switch Control.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

void main() {
  Widget frame(Widget child) => MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(
          body: ChartFrame(
            title: 'Resting heart rate',
            unit: 'bpm',
            xLabels: const ['29 days ago', 'Today'],
            footnote: 'Your usual range is 52-64 bpm.',
            child: child,
          ),
        ),
      );

  testWidgets('an interactive child keeps its semantics', (t) async {
    await t.pumpWidget(frame(
      Semantics(button: true, label: 'Scrub the night', child: const SizedBox.expand()),
    ));
    expect(find.bySemanticsLabel('Scrub the night'), findsOneWidget,
        reason: 'the control inside the chart must stay reachable');
  });

  testWidgets('the decoration is still not read out', (t) async {
    await t.pumpWidget(frame(const SizedBox.expand()));
    // The frame speaks one sentence of its own; the tick labels and footnote
    // must not also be announced as loose text.
    expect(find.bySemanticsLabel('29 days ago'), findsNothing);
    expect(find.bySemanticsLabel('Your usual range is 52-64 bpm.'), findsNothing);
  });
}
