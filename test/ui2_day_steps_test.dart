// THE DAY STEPS SCREEN — the spans, and the one line about the sensors.
//
// Three things this screen may not get wrong, all of them honesty rather than
// layout:
//   * a stretch names the device that counted it, and never the wrong one;
//   * the accuracy line appears ONCE and says the right thing for the sensors
//     that actually counted — a day the phone carried alone must not be told
//     about wrists;
//   * a day whose count came off the strap's on-chip counter has no times
//     behind it, and must say THAT rather than "no steps" over a tile showing
//     thousands.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/screens/day_steps.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

/// Local 09:00 on an arbitrary day, as epoch seconds.
final _nine = DateTime(2026, 8, 17, 9).millisecondsSinceEpoch ~/ 1000;

DayStepSpan _span(
  int fromMin,
  int toMin,
  int steps, {
  bool band = false,
  String? activity,
}) => DayStepSpan(
  startTs: _nine + fromMin * 60,
  endTs: _nine + toMin * 60,
  steps: steps,
  fromBand: band,
  activity: activity,
);

Future<void> _pump(WidgetTester t, DayStepsData d, {double scale = 1}) async {
  t.view.physicalSize = Size(390 * 3, 3000 * 3 * scale);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: MaterialApp(
        theme: buildTheme(Brightness.light),
        home: DayStepsDetail(data: d),
      ),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  testWidgets('a mixed day names both devices, without a list of stretches', (
    t,
  ) async {
    await _pump(
      t,
      DayStepsData(
        spans: [
          _span(0, 60, 1200),
          _span(240, 300, 3240, band: true, activity: 'walking'),
        ],
        total: 4440,
        strap: 3240,
        phone: 1200,
        bandLabel: 'WHOOP 4',
      ),
    );
    // Both devices named in the totals; the long per-stretch list is gone.
    expect(find.text('WHOOP 4'), findsWidgets);
    expect(find.text('Your phone'), findsWidgets);
    expect(find.textContaining('1:00 PM – 2:00 PM'), findsNothing);
    expect(find.text('Through the day'), findsNothing);
    // ONE accuracy line, and it names both failure directions.
    expect(find.textContaining('the two miscount differently'), findsOneWidget);
  });

  testWidgets('a phone-only day is never told about wrists', (t) async {
    await _pump(
      t,
      DayStepsData(spans: [_span(0, 60, 1200)], total: 1200, phone: 1200),
    );
    expect(find.textContaining('had it on you for'), findsOneWidget);
    expect(find.textContaining('wrist'), findsNothing);
    // One sensor is not a legend.
    expect(find.text('WHOOP 4'), findsNothing);
  });

  testWidgets('a day counted only by the strap\'s on-chip counter says the '
      'TIMES are missing, not the steps', (t) async {
    await _pump(
      t,
      const DayStepsData(dayTotal: 6012, daySource: 'strap_counter'),
    );
    expect(find.textContaining('No times behind'), findsOneWidget);
    expect(find.textContaining('6,012'), findsOneWidget);
    expect(find.textContaining('No steps counted'), findsNothing);
  });

  testWidgets('every stretch survives 3.1x text', (t) async {
    // The pump itself is the assertion: a `RenderFlex` overflow fails it. A
    // clock range is a long row name, and the row shipped its steps unit off
    // the right edge at this scale before it was removed.
    await _pump(
      t,
      DayStepsData(
        spans: [
          _span(0, 60, 1200),
          _span(240, 300, 3240, band: true, activity: 'walking'),
        ],
        total: 4440,
        strap: 3240,
        phone: 1200,
        bandLabel: 'WHOOP 4',
      ),
      scale: 3.1,
    );
  });

  test('an hour gets one bar, in the colour of the sensor that counted most '
      'of it', () {
    // 09:00–10:00 phone (600), with a strap walk 09:10–09:40 (900) inside it.
    final (band, phone) = hourlySteps([
      _span(0, 60, 600),
      _span(10, 40, 900, band: true),
    ]);
    expect(
      band[9],
      closeTo(1500, .5),
      reason: 'the hour still shows every step counted in it',
    );
    expect(
      phone[9],
      isNull,
      reason: 'two bars would hide one behind the other',
    );
    expect(band[10], isNull, reason: 'an uncovered hour is a hole, not a zero');
  });
}
