// The Sleep screen's judgement layer, below the fold.
//
// The goldens capture the top of the screen — the viewport is 1400 pt and the
// answer, the hypnogram and the stages fill it. Everything the screen actually
// DECIDES lives further down: which comparison verdict a measure earns, whether
// last night was extreme enough to mention, and whether there is enough history
// to say either. This pumps the whole page into a tall viewport and reads it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/models/metric.dart';
import 'package:openstrap_edge/ui2/screens/screens.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

final _onset = DateTime(2026, 5, 19, 23, 7).millisecondsSinceEpoch ~/ 1000;

Map<String, dynamic> _night({
  int tst = 443,
  int deep = 85,
  bool elevated = false,
}) => {
      'duration_min': tst,
      'in_bed_min': 486,
      'awake_min': 20,
      'efficiency': .91,
      'onset_ts': _onset,
      'wake_ts': _onset + 486 * 60,
      'light_min': 170,
      'deep_min': deep,
      'rem_min': 95,
      'hypnogram': [
        {'t': _onset, 'stage': 'light'},
        {'t': _onset + 3600, 'stage': 'deep'},
        {'t': _onset + 7200, 'stage': 'rem'},
        {'t': _onset + 486 * 60, 'stage': 'awake'},
      ],
      'nocturnal': {
        'sleeping_hr_avg': 52,
        'sleeping_hr_min': 46,
        'vs_baseline_bpm': elevated ? 4.6 : 0.4,
        'elevated': elevated,
      },
    };

List<double> _flat(int n, double v) => List<double>.filled(n, v);

/// The whole page, in a viewport tall enough to build every section — a
/// `RenderFlex` overflow anywhere below the fold fails the pump.
Future<void> _pump(WidgetTester t, SleepData d, {double scale = 1}) async {
  t.view.physicalSize = Size(390 * 3, 5200 * 3 * scale);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
    child: MaterialApp(
      theme: buildTheme(Brightness.light),
      home: SleepDetail(data: d),
    ),
  ));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('a measure inside the middle half of your nights is typical',
      (t) async {
    await _pump(
      t,
      SleepData(
        day: '2026-05-20',
        night: _night(),
        tstHistory: [for (var i = 0; i < 20; i++) 400 + i * 5],
        deepHistory: _flat(20, 85),
        effHistory: _flat(20, 91),
      ),
    );
    expect(find.text('Time asleep'), findsOneWidget);
    expect(find.textContaining('Typical for you'), findsWidgets);
  });

  testWidgets('a short night is measured against the median, not the band edge',
      (t) async {
    await _pump(
      t,
      SleepData(
        day: '2026-05-20',
        // 60 minutes under a history that never moves.
        night: _night(tst: 340),
        tstHistory: _flat(20, 400),
      ),
    );
    expect(find.textContaining('1h 00m shorter than usual'), findsOneWidget);
  });

  testWidgets('an extreme night and an elevated sleeping heart rate are called '
      'out; nothing else is', (t) async {
    await _pump(
      t,
      SleepData(
        day: '2026-05-20',
        night: _night(deep: 120, elevated: true),
        tstHistory: _flat(20, 440),
        deepHistory: [for (var i = 0; i < 20; i++) 60 + i.toDouble()],
        effHistory: _flat(20, 91),
      ),
    );
    expect(find.text('Unusual last night'), findsOneWidget);
    expect(find.text('Most deep sleep lately'), findsOneWidget);
    expect(find.text('Sleeping heart rate ran high'), findsOneWidget);
    // Detection against the user's own baseline is never a diagnosis, and the
    // card has to say so on the card.
    expect(find.textContaining('not a diagnosis'), findsOneWidget);
    expect(find.textContaining('Nothing stood out'), findsNothing);
  });

  testWidgets('an ordinary night says so rather than manufacturing a finding',
      (t) async {
    await _pump(
      t,
      SleepData(
        day: '2026-05-20',
        night: _night(),
        tstHistory: [for (var i = 0; i < 20; i++) 400 + i * 5],
        deepHistory: [for (var i = 0; i < 20; i++) 70 + i.toDouble()],
        effHistory: _flat(20, 91),
      ),
    );
    expect(find.textContaining('Nothing stood out'), findsOneWidget);
  });

  testWidgets('with no history the screen compares nothing and claims nothing',
      (t) async {
    await _pump(
      t,
      SleepData(
        day: '2026-05-20',
        night: _night(elevated: true),
        tstHistory: const [430, 465, 410],
      ),
    );
    // Too little history to compare against. The section stays, carrying the
    // COUNT — absent-but-expected says when it arrives — but it must not claim
    // a comparison it cannot make.
    expect(find.textContaining('3 of 7 nights so far'), findsOneWidget);
    expect(find.textContaining('Typical for you'), findsNothing);
    // The extremes need history; the nocturnal detection carries its own
    // baseline, so the section is present for that alone.
    expect(find.text('Your shortest night lately'), findsNothing);
    expect(find.text('Sleeping heart rate ran high'), findsOneWidget);
  });

  for (final scale in const [2.0, 3.1]) {
    testWidgets('every section survives ${scale}x text', (t) async {
      await _pump(
        t,
        SleepData(
          day: '2026-05-20',
          night: _night(deep: 120, elevated: true),
          timeline: {
            'hr': [
              for (var i = 0; i < 60; i++)
                {'t': _onset + i * 480, 'v': 52 + (i % 11) - 5},
            ],
          },
          need: const Metric(
              value: 462, unit: 'min', confidence: .7, tier: MetricTier.estimate),
          bedtime: const Metric(
              value: 1360, confidence: .7, tier: MetricTier.estimate),
          tstHistory: _flat(20, 440),
          deepHistory: [for (var i = 0; i < 20; i++) 60 + i.toDouble()],
          effHistory: _flat(20, 91),
          onsetHistory: [
            for (var i = 0; i < 20; i++) _onset - (i + 1) * 86400 - 900,
          ],
        ),
        scale: scale,
      );
      expect(find.text('Unusual last night'), findsOneWidget);
    });
  }

  testWidgets('tonight is one takeaway, not six numbers', (t) async {
    await _pump(
      t,
      SleepData(
        day: '2026-05-20',
        night: _night(),
        need: const Metric(
            value: 462, unit: 'min', confidence: .7, tier: MetricTier.estimate),
        debt: const Metric(
            value: 22, unit: 'min', confidence: .7, tier: MetricTier.estimate),
        bedtime:
            const Metric(value: 1360, confidence: .7, tier: MetricTier.estimate),
      ),
    );
    expect(find.text('lights out'), findsOneWidget);
    expect(find.textContaining('Your need is 7h 42m'), findsOneWidget);
    expect(find.textContaining('22m down'), findsOneWidget);
  });
}
