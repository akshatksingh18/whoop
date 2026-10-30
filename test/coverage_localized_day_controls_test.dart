// Current detail pages: measured gaps, sensor provenance and day-only navigation.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_analytics/onehz.dart' as ana;
import 'package:whoop_companion/compute/nightly_sweep.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/state/prefs.dart';
import 'package:whoop_companion/ui2/screens/day_steps.dart';
import 'package:whoop_companion/ui2/screens/day_timeline.dart';
import 'package:whoop_companion/ui2/screens/metric_detail.dart';
import 'package:whoop_companion/ui2/screens/sleep_breathing.dart';
import 'package:whoop_companion/ui2/screens/rough_night.dart';
import 'package:whoop_companion/ui2/screens/what_changed.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('localized-day-controls');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  const day = '2021-04-06';
  final at = DateTime(2021, 4, 6).millisecondsSinceEpoch ~/ 1000;
  for (final mode in ['empty', 'learning', 'usual', 'finding']) {
    testWidgets(
      'COV-44 localized change review distinguishes unavailable and usual $mode',
      (t) async {
        await localizedPage(
          t,
          WhatChangedScreen(
            data: WhatChangedData(
              day: day,
              hadToday: mode != 'empty',
              longestHistory: mode == 'learning' ? 1 : 28,
              findings: mode == 'finding'
                  ? const [
                      SweepFinding(
                        key: 'rhr',
                        text:
                            'Synthetic resting heart rate above its own trailing range',
                        z: 3,
                        high: true,
                      ),
                    ]
                  : [],
            ),
          ),
        );
        final text = (await readPage(t)).join(' ');
        expect(
          text,
          contains(switch (mode) {
            'empty' => 'Nothing has landed',
            'learning' => 'Still learning',
            'usual' => 'Nothing stood out',
            _ => 'Synthetic resting heart rate',
          }),
        );
        expect(text, contains('What happened that day'));
        if (mode == 'finding')
          expect(text, contains('Nothing here is a cause'));
      },
    );
  }
  for (final moved in [
    <String>[],
    ['your resting heart rate ran higher'],
    ['your resting heart rate ran higher', 'your HRV ran lower'],
  ]) {
    testWidgets(
      'COV-44 personal rough-night card keeps stats-only controls ${moved.length}',
      (t) async {
        var dismissed = 0;
        await localizedPage(
          t,
          Scaffold(
            body: SingleChildScrollView(
              child: RoughNightCard(
                night: RoughNight(
                  day: day,
                  signs: 2,
                  descriptor: '',
                  moved: moved,
                  knows: const ['Synthetic session already recorded.'],
                ),
                ask: 'never',
                onDismiss: () => dismissed++,
              ),
            ),
          ),
        );
        final text = (await readPage(t)).join(' ');
        expect(text, contains('Nothing to answer'));
        expect(find.text('Tell it what happened'), findsNothing);
        expect(
          find.text('Synthetic session already recorded.'),
          findsOneWidget,
        );
        final close = find.byWidgetPredicate(
          (w) => w is Pressable && w.semanticLabel == 'Dismiss',
        );
        await reveal(t, close);
        await t.tap(close);
        await t.pumpAndSettle();
        expect(dismissed, 1);
        expect(Prefs.getString(kRoughNightDismissed, ''), day);
      },
    );
  }
  for (final mode in ['absent', 'usual', 'higher']) {
    testWidgets(
      'COV-44 localized breathing history keeps non-diagnostic limits $mode',
      (t) async {
        final m = ana.Metric<ana.CvhrDistribution>(
          value: mode == 'absent'
              ? null
              : ana.CvhrDistribution(
                  nightsUsed: 21,
                  nightsExcludedIrregular: 1,
                  nightsExcludedThin: 2,
                  weightedMean: 4.2,
                  recentWeightedMean: 6.1,
                  quartiles: [3.1, 4.0, 5.2],
                  aboveOwnUsual: mode == 'higher',
                ),
          confidence: mode == 'absent' ? 0 : .7,
          tier: 'moderate',
          inputs_used: const [],
        );
        await localizedPage(t, SleepBreathingScreen(data: m));
        if (mode == 'absent') {
          expect((await readPage(t)).join(' '), contains('Not enough nights'));
        } else {
          expect(
            find.text(
              mode == 'higher'
                  ? 'Higher than your usual'
                  : 'Within your usual range',
            ),
            findsOneWidget,
          );
          await t.tap(find.text('What this means'));
          await t.pumpAndSettle();
          final text = (await readPage(t)).join(' ');
          expect(text, contains('cannot rule anything in or out'));
          expect(text, contains('a clinician can test'));
          expect(text, isNot(contains('6.1')));
          expect(text, isNot(contains('4.2')));
        }
      },
    );
  }
  for (final mode in [
    'absent',
    'counter',
    'phone',
    'band',
    'mixed',
    'calories',
  ]) {
    testWidgets(
      'COV-44 localized step details retain measured source and holes $mode',
      (t) async {
        final populated = !['absent', 'counter'].contains(mode);
        final data = DayStepsData(
          day: day,
          spans: populated
              ? [
                  DayStepSpan(
                    startTs: at + 32400,
                    endTs: at + 36000,
                    steps: 1200,
                    fromBand: mode == 'band',
                  ),
                  if (mode == 'mixed')
                    DayStepSpan(
                      startTs: at + 43200,
                      endTs: at + 46800,
                      steps: 800,
                      fromBand: true,
                    ),
                ]
              : [],
          total: mode == 'mixed'
              ? 2000
              : populated
              ? 1200
              : 0,
          phone: ['phone', 'mixed', 'calories'].contains(mode) ? 1200 : 0,
          strap: mode == 'band'
              ? 1200
              : mode == 'mixed'
              ? 800
              : 0,
          dayTotal: mode == 'counter' ? 6012 : null,
          daySource: mode == 'counter' ? 'strap_counter' : null,
          walking: populated ? (kcal: 40, km: 1.2) : null,
          acsmWalking: populated ? 50 : null,
          hourlyWalkingKcal: [
            for (var h = 0; h < 24; h++) h == 9 ? 40.0 : null,
          ],
        );
        await localizedPage(
          t,
          DayStepsDetail(data: data, calories: mode == 'calories'),
        );
        final text = (await readPage(t)).join(' ');
        if (!populated) {
          expect(
            text,
            contains(
              mode == 'counter' ? 'No times behind' : 'No steps counted',
            ),
          );
          if (mode == 'counter') expect(text, contains('6,012'));
        } else {
          expect(text, contains('Run steps counted with runs'));
          await reveal(t, find.byType(Scrubber).first);
          final scrub = t.widget<Scrubber>(find.byType(Scrubber).first);
          expect(scrub.describe(0), contains('not recorded'));
          scrub.onChanged(9.5 / 24);
          await t.pumpAndSettle();
          expect(
            t.widget<ChartFrame>(find.byType(ChartFrame).first).readout,
            contains(mode == 'calories' ? '40' : '1,200'),
          );
        }
      },
    );
  }
  for (final mode in ['empty', 'untimed', 'measured']) {
    testWidgets(
      'COV-44 localized timeline keeps untimed notes off the clock $mode',
      (t) async {
        final data = TimelineData(
          day: day,
          graph: mode != 'measured'
              ? const DayGraph()
              : DayGraph(
                  dayStartSec: at,
                  hr: [
                    for (var i = 0; i < 120; i++)
                      i < 10
                          ? 55.0
                          : i >= 100
                          ? 90.0
                          : null,
                  ],
                  movement: [
                    for (var i = 0; i < 120; i++) i >= 100 ? .8 : null,
                  ],
                  rest: [(0, 10, C.blue)],
                  work: [(100, 120, C.orange)],
                ),
          moments: mode == 'measured'
              ? [
                  Moment(
                    at: at + 6000,
                    title: 'Synthetic cycle',
                    icon: Icons.directions_bike,
                    detail: 'Recorded session',
                  ),
                ]
              : [],
          notes: mode == 'empty'
              ? []
              : [
                  const DayNote(
                    'Synthetic day note',
                    'No time recorded',
                    Icons.notes,
                  ),
                ],
        );
        await localizedPage(t, DayTimelineScreen(data: data));
        final text = (await readPage(t)).join(' ');
        expect(
          text,
          contains(
            mode == 'empty' ? 'Nothing was recorded' : 'Synthetic day note',
          ),
        );
        if (mode != 'empty') expect(text, contains('carry no time of day'));
        if (mode == 'measured') {
          await reveal(t, find.byType(Scrubber).first);
          final scrub = t.widget<Scrubber>(find.byType(Scrubber).first);
          expect(scrub.describe(0), contains('asleep'));
          expect(scrub.describe(.5), contains('not recorded'));
          expect(scrub.describe(1), contains('workout'));
          scrub.onChanged(.5);
          await t.pumpAndSettle();
          expect(find.textContaining('not recorded'), findsWidgets);
        }
      },
    );
  }
  for (final cancel in [false, true]) {
    testWidgets(
      'COV-44 calendar ${cancel ? 'cancel' : 'commit'} selects only saved days',
      (t) async {
        final picked = <String>[];
        await localizedPage(
          t,
          Scaffold(
            body: DayNav(
              day: day,
              days: const ['2021-04-08', '2021-04-06'],
              onDay: picked.add,
            ),
          ),
        );
        final calendar = find.byWidgetPredicate(
          (w) =>
              w is Pressable &&
              w.semanticLabel?.startsWith('Choose a day.') == true,
        );
        await t.tap(calendar);
        await t.pumpAndSettle();
        expect(find.byType(DatePickerDialog), findsOneWidget);
        if (!cancel) await t.tap(find.text('8').last);
        await t.tap(find.text(cancel ? 'Cancel' : 'OK'));
        await t.pumpAndSettle();
        expect(picked, cancel ? isEmpty : ['2021-04-08']);
      },
    );
  }
}
