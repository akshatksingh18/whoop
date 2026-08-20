// The trailing slot on an overview row: an arrow, not a sparkline.
//
// The arrow makes two claims the sparkline did not, so both are pinned here:
//
//  · a DIRECTION — which only exists if the move clears half a standard
//    deviation of the metric's own recent baseline, and only if there are
//    enough recorded days to have a baseline at all;
//  · a VERDICT — green or orange, which depends on the metric and not on the
//    direction: resting heart rate falling is good news, HRV falling is not.
//
// And the direction has to be readable without the hue, because roughly one
// man in twelve cannot read the hue.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:openstrap_edge/ui2/ui2.dart';

List<double?> _flat(int n, double v) => List<double?>.filled(n, v);

void main() {
  group('trendOf', () {
    test('a move clear of its own spread is a direction', () {
      expect(trendOf(const [50, 51, 50, 52, 51, 53, 58, 59, 60]),
          Trend.rising);
      expect(trendOf(const [60, 59, 58, 61, 59, 60, 51, 50, 50]),
          Trend.falling);
    });

    test('a move inside its own spread is steady, not a coin flip', () {
      expect(trendOf(const [50, 53, 49, 52, 48, 51, 50, 52, 49]), Trend.steady);
    });

    test('too few recorded days is no answer at all, not a flat arrow', () {
      expect(trendOf(const [50, 51, 50]), isNull);
      expect(trendOf(const []), isNull);
      // Six recorded values behind seven slots: the holes do not count.
      expect(trendOf(const [50, null, 51, null, 50, null, 52, null, 51]),
          isNull);
    });

    test('a baseline that truly sat still still reports a real move', () {
      // MAD/SD of zero is not a reason to abstain — that is the readiness bug
      // this project has already paid for once.
      expect(trendOf([..._flat(6, 50), 55, 55, 55]), Trend.rising);
      expect(trendOf(_flat(12, 50)), Trend.steady);
    });
  });

  group('the row', () {
    Future<P> pump(WidgetTester t, List<Widget> rows,
        {double textScale = 1.0}) async {
      t.view.physicalSize = const Size(390 * 3, 1600 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.light),
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(body: ListView(children: rows)),
        ),
      ));
      await t.pumpAndSettle();
      return P.of(t.element(find.byType(MetricRow).first));
    }

    const rising = <double?>[50, 51, 50, 52, 51, 53, 58, 59, 60];
    const falling = <double?>[60, 59, 58, 61, 59, 60, 51, 50, 50];
    const steady = <double?>[50, 53, 49, 52, 48, 51, 50, 52, 49];

    testWidgets('no sparkline is drawn beside the number', (t) async {
      await pump(t, const [
        MetricRow(LucideIcons.activity, C.green, 'HRV', '64',
            unit: 'ms', series: rising, rising: Rising.good),
      ]);
      expect(find.byType(CustomPaint).evaluate().where((e) {
        final w = e.widget as CustomPaint;
        return w.painter is LineChart;
      }), isEmpty);
    });

    testWidgets('the glyph carries the direction, the hue carries the verdict',
        (t) async {
      final p = await pump(t, const [
        // Up, and up is good here.
        MetricRow(LucideIcons.activity, C.green, 'HRV', '64',
            unit: 'ms', series: rising, rising: Rising.good),
        // Up, and up is bad here — same glyph, different hue.
        MetricRow(LucideIcons.heart, C.red, 'Resting heart rate', '58',
            unit: 'bpm', series: rising, rising: Rising.bad),
        // Down, and down is good here.
        MetricRow(LucideIcons.brain, C.purple, 'Stress', '31',
            unit: '/100', series: falling, rising: Rising.bad),
      ]);
      final up = t
          .widgetList<Icon>(find.byIcon(LucideIcons.arrowUpRight))
          .toList();
      expect(up.length, 2, reason: 'both rose, so both point up');
      expect(up[0].color, p.on(C.green));
      expect(up[1].color, p.on(C.orange));
      final down =
          t.widgetList<Icon>(find.byIcon(LucideIcons.arrowDownRight)).single;
      expect(down.color, p.on(C.green));
    });

    testWidgets('a metric with no settled better direction gets no hue',
        (t) async {
      final p = await pump(t, const [
        MetricRow(LucideIcons.thermometer, C.orange, 'Skin temperature', '+0.3',
            unit: '°', series: rising),
      ]);
      expect(t.widgetList<Icon>(find.byIcon(LucideIcons.arrowUpRight)).single.color,
          p.ink3);
    });

    testWidgets('a move inside the noise is flat and unjudged', (t) async {
      final p = await pump(t, const [
        MetricRow(LucideIcons.activity, C.green, 'HRV', '50',
            unit: 'ms', series: steady, rising: Rising.good),
      ]);
      expect(t.widgetList<Icon>(find.byIcon(LucideIcons.arrowRight)).single.color,
          p.ink3);
    });

    testWidgets('too little history draws nothing and says why', (t) async {
      await pump(t, const [
        MetricRow(LucideIcons.wind, C.teal, 'Respiratory rate', '14.2',
            unit: 'br/min', series: [50, 51, 50], rising: Rising.bad),
      ]);
      for (final i in const [
        LucideIcons.arrowUpRight,
        LucideIcons.arrowDownRight,
        LucideIcons.arrowRight,
      ]) {
        expect(find.byIcon(i), findsNothing);
      }
      // The absence carries its reason where an empty box cannot: a horizontal
      // arrow here would claim a measured "no change".
      expect(
          find.bySemanticsLabel(
              RegExp('no trend yet', caseSensitive: false)),
          findsOneWidget);
    });

    testWidgets('the arrow survives large text at 390 pt', (t) async {
      await pump(t, const [
        MetricRow(LucideIcons.heart, C.red, 'Resting heart rate', '58',
            sub: 'OVERNIGHT', unit: 'bpm', series: rising, rising: Rising.bad),
      ], textScale: 2.0);
      expect(find.byIcon(LucideIcons.arrowUpRight), findsOneWidget);
      expect(find.text('58'), findsOneWidget);
    });
  });
}
