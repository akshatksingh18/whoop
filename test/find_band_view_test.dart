// Widget tests for the find-my-strap board. FindBandView takes plain values,
// so the states that are awkward to produce with a real radio (no link, a
// faint signal, a warm trend) are all reachable here.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ble/proximity_policy.dart';
import 'package:openstrap_edge/ui/find/find_band_screen.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: child);

  ProximityReading reading({
    ProximityZone zone = ProximityZone.near,
    ProximityTrend trend = ProximityTrend.steady,
    double? rssi = -70,
    int samples = 10,
  }) =>
      ProximityReading(
        zone: zone,
        trend: trend,
        samples: samples,
        smoothedRssi: rssi,
        rawRssi: rssi?.round(),
      );

  testWidgets('disconnected says so plainly instead of hunting forever',
      (tester) async {
    await tester.pumpWidget(wrap(
      FindBandView(connected: false, reading: reading()),
    ));
    expect(find.textContaining('Can\'t reach your strap'), findsOneWidget);
    expect(find.text('Buzz now'), findsNothing,
        reason: 'buzzing needs the link the screen just said it lacks');
  });

  testWidgets('connected shows the zone label and the hunt controls',
      (tester) async {
    await tester.pumpWidget(wrap(
      FindBandView(
        connected: true,
        reading: reading(zone: ProximityZone.immediate),
      ),
    ));
    expect(find.text(ProximityZone.immediate.label), findsOneWidget);
    expect(find.text('Buzz now'), findsOneWidget);
    expect(find.text('Keep buzzing'), findsOneWidget);
  });

  testWidgets('the trend is surfaced as the warmer/colder cue', (tester) async {
    await tester.pumpWidget(wrap(
      FindBandView(
        connected: true,
        reading: reading(trend: ProximityTrend.warmer),
      ),
    ));
    // The design system renders gauge sub-labels as uppercase overlines, so
    // assert on the rendered form rather than the raw string.
    expect(find.text(ProximityTrend.warmer.label.toUpperCase()), findsOneWidget);
  });

  testWidgets('signal is reported in dBm, never in metres', (tester) async {
    await tester.pumpWidget(wrap(
      FindBandView(connected: true, reading: reading(rssi: -63.4)),
    ));
    expect(find.textContaining('dBm'), findsOneWidget);
    expect(find.textContaining(' m '), findsNothing);
    expect(find.textContaining('metre'), findsNothing);
  });

  testWidgets('a warming-up reading renders without a fabricated signal',
      (tester) async {
    await tester.pumpWidget(wrap(
      FindBandView(
        connected: true,
        reading: reading(
          zone: ProximityZone.unknown,
          trend: ProximityTrend.unknown,
          rssi: null,
          samples: 1,
        ),
      ),
    ));
    expect(find.text(ProximityZone.unknown.label), findsOneWidget);
    expect(find.textContaining('dBm'), findsNothing,
        reason: 'no smoothed value yet ⇒ no number shown at all');
  });

  testWidgets('buzz now and the auto-buzz toggle are wired', (tester) async {
    var buzzes = 0;
    bool? toggled;
    await tester.pumpWidget(wrap(
      FindBandView(
        connected: true,
        reading: reading(),
        autoBuzz: true,
        onBuzzNow: () => buzzes++,
        onAutoBuzzChanged: (v) => toggled = v,
      ),
    ));

    await tester.tap(find.text('Buzz now'));
    await tester.pump();
    expect(buzzes, 1);

    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    expect(toggled, isFalse);
  });
}
