// The run screen renders from a recorded track: map fallback, headline
// numbers, verdict, splits, linked charts, at normal and large text, without
// overflowing.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/profile.dart';
import 'package:openstrap_edge/gps/route_models.dart';
import 'package:openstrap_edge/gps/run_analysis.dart' show runMix;
import 'package:openstrap_edge/ui2/activity/catalogue.dart';
import 'package:openstrap_edge/ui2/activity/run_detail.dart' show RunVerdictCard;
import 'package:openstrap_edge/ui2/activity/summary.dart';
import 'package:openstrap_edge/ui2/theme.dart';

ActivityResult demoRun() {
  const mPerDegLat = 111195.0;
  final start = DateTime(2026, 10, 3, 6, 18);
  final t0 = start.millisecondsSinceEpoch;
  final pts = <RoutePoint>[];
  var lat = 29.9, lng = -95.6;
  for (var i = 0; i <= 2100; i++) {
    final speed = 2.3 + 0.3 * ((i ~/ 300) % 3); // three paces
    // A square-ish loop so the shape is not a line.
    final leg = (i ~/ 525) % 4;
    final d = speed / mPerDegLat;
    if (leg == 0) lat += d;
    if (leg == 1) lng += d;
    if (leg == 2) lat -= d;
    if (leg == 3) lng -= d;
    pts.add(RoutePoint(
        seq: i, tsMs: t0 + i * 1000, lat: lat, lng: lng, alt: 47 + (i % 7) * 0.4));
  }
  final run = allActivities.firstWhere((a) => a.name == 'Running');
  return ActivityResult(
    run,
    start: start,
    duration: const Duration(minutes: 35, seconds: 1),
    avgHr: 151,
    maxHr: 175,
    hr: [for (var m = 0; m <= 35; m++) 140.0 + (m % 9)],
    zoneMinutes: const [3, 7, 16, 9, 0],
    distanceKm: 5.06,
    movingSec: 2100,
    track: pts,
    mix: runMix(pts),
    route: [
      for (final p in pts)
        Offset((p.lng + 95.6) * 400 + 0.2, 0.8 - (p.lat - 29.9) * 400),
    ],
    splits: const [
      KmSplit(1, 402, avgHr: 140),
      KmSplit(1, 420, avgHr: 152),
      KmSplit(1, 452, avgHr: 144),
      KmSplit(1, 425, avgHr: 159),
      KmSplit(1, 408, avgHr: 155),
      KmSplit(0.06, 33, avgHr: 171),
    ],
  );
}

Widget frame(Widget child, double scale) => MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: MediaQuery(
        data: MediaQueryData(
            size: const Size(390, 1400), textScaler: TextScaler.linear(scale)),
        child: child,
      ),
    );

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('run screen at ${scale}x', (t) async {
      t.view.physicalSize = const Size(390 * 3, 1400 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(frame(
          ActivitySummary(demoRun(),
              profile: const Profile(
                  ageYears: 23, weightKg: 80.5, heightCm: 186.69, sex: 'm')),
          scale));
      await t.pumpAndSettle();
      expect(find.text('Moving time'), findsOneWidget);
      // Heart rate (~427 kcal) and distance (~290 kcal) are more than 50
      // apart, so both are shown.
      expect(find.text('From distance'), findsOneWidget);
      expect(find.text('From heart rate'), findsOneWidget);
      // Below the calorie card; at 2x text it starts off screen.
      final page = find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down);
      await t.scrollUntilVisible(find.byType(RunVerdictCard), 200,
          scrollable: page.first);
      expect(find.textContaining('Mostly').evaluate().isNotEmpty ||
          find.textContaining('pacing').evaluate().isNotEmpty, isTrue);
      await t.scrollUntilVisible(find.text('Moving time'), -400,
          scrollable: page.first);
      await t.tap(find.text('Splits'));
      await t.pumpAndSettle();
      expect(find.text('KM'), findsOneWidget);
      await t.ensureVisible(find.text('Graphs', skipOffstage: false));
      await t.pumpAndSettle();
      await t.tap(find.text('Graphs'));
      await t.pumpAndSettle();
      expect(find.text('Pace'), findsWidgets);
      expect(t.takeException(), isNull);
    });
  }
}
