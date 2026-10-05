// The restored across-nights breathing-pattern screen: it names no condition,
// keeps a non-diagnostic aggregate and dated measured readouts, never reassures.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_analytics/onehz.dart' as ana;
import 'package:openstrap_edge/ui2/screens/sleep_breathing.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

ana.Metric<ana.CvhrDistribution> _m(ana.CvhrDistribution? v) => ana.Metric(
    value: v, confidence: v == null ? 0 : .7, tier: 'moderate', inputs_used: const []);

const _dist = ana.CvhrDistribution(
  nightsUsed: 21,
  nightsExcludedIrregular: 0,
  nightsExcludedThin: 2,
  weightedMean: 4.2,
  recentWeightedMean: 6.1,
  quartiles: [3.1, 4.0, 5.2],
  aboveOwnUsual: true,
);

Future<void> _pump(WidgetTester t, ana.Metric<ana.CvhrDistribution> m) async {
  t.view.physicalSize = const Size(390 * 3, 2400 * 3);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: buildTheme(Brightness.light),
    home: SleepBreathingScreen(data: m),
  ));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('too few nights says so instead of a finding', (t) async {
    await _pump(t, _m(null));
    expect(find.textContaining('Not enough nights'), findsOneWidget);
  });

  testWidgets('the across-nights card carries no index and ends in a clinician',
      (t) async {
    await _pump(t, _m(_dist));
    // The caveats are folded under one line now; open them.
    await t.tap(find.text('What this means'));
    await t.pumpAndSettle();
    final text = t
        .widgetList<Text>(find.byType(Text))
        .map((w) => w.data ?? '')
        .join('\n');
    expect(text, contains('21 nights'));
    expect(text, contains('Higher than your usual'));
    expect(text, contains('a clinician can test'));
    // No per-night rate or mean is printed.
    expect(text, isNot(contains('6.1')));
    expect(text, isNot(contains('4.2')));
    expect(text.toLowerCase(), isNot(contains('apnea')));
  });
}
