// Focused body/goal/trend contracts over synthetic dated inputs, no navigation journey.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/body_log.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/goal_plan.dart';
import 'package:whoop_companion/data/progress_review.dart';
import 'package:whoop_companion/ui2/screens/health_screen.dart';
import 'package:whoop_companion/ui2/screens/progress_screen.dart';
import 'package:whoop_companion/ui2/screens/progress_routes.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

String ago(int n) {
  final now = DateTime.now();
  return dayLabelOf(DateTime(now.year, now.month, now.day - n));
}

ProgressData progress(bool enough) => ProgressData(
  weights: [
    if (enough)
      for (var i = 60; i >= 0; i--)
        (
          date: ago(i),
          kg: 70 + i * .02,
          atTs: localDayStartSec(ago(i))!,
          unit: 'kg',
          entered: null,
          source: 'synthetic',
          originId: null,
          historyOnly: false,
        ),
  ],
  measures: [
    if (enough)
      for (final i in [0, 14, 28, 56])
        BodyMeasure(
          id: 'synthetic-$i',
          date: ago(i),
          recordedAt: DateTime(2021, 4, 6),
          inches: {'waistNavel': 32 + i * .01, 'neck': 15},
        ),
  ],
  photos: [],
  lifts: [],
  food: [
    if (enough)
      for (var i = 60; i >= 0; i--)
        (
          date: ago(i),
          kcal: 2000.0,
          counts: i % 5 != 0,
          protein: 120.0,
          proteinComplete: i % 5 != 0,
        ),
  ],
  steps: [
    if (enough)
      for (var i = 60; i >= 0; i--) (date: ago(i), value: 5000.0),
  ],
  sleepMin: [],
  recovery: [],
  sessions: [],
  baseline: enough ? ago(60) : null,
  heightCm: enough ? 170 : null,
  user: const {
    'age': 30,
    'sex': 'f',
    'height_cm': 170,
    'weight_kg': 70,
    'kcal_target': 2000,
  },
);
void main() {
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('localized-progress');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  for (final phase in GoalPhase.values) {
    testWidgets('COV-44 goal draft persists selected phase ${phase.name}', (
      t,
    ) async {
      await localizedPage(
        t,
        GoalScreen(plan: GoalPlan(phase: phase), kg: 70),
        push: true,
      );
      var content = await readPage(t);
      expect(content.join(' '), contains('What the review will aim for'));
      final button = find.byType(BigButton).last;
      await invokeControl(t, t.widget<BigButton>(button).onTap);
      final saved = await GoalPlan.read();
      expect(saved.phase, phase);
      expect(saved.since, todayLabel());
      expect(saved.holdKg, phase == GoalPhase.maintain ? 70 : isNull);
    });
  }
  for (final enough in [false, true]) {
    for (final dest in [
      ProgressDest.overview,
      ProgressDest.weight,
      ProgressDest.waist,
      ProgressDest.strength,
      ProgressDest.food,
      ProgressDest.training,
      ProgressDest.recovery,
    ]) {
      testWidgets(
        'COV-44 dated Progress ${dest.name} keeps evidence and empty states $enough',
        (t) async {
          final d = progress(enough);
          await localizedPage(
            t,
            Scaffold(
              body: dest == ProgressDest.overview
                  ? ProgressScreen(data: d)
                  : progressDetailPage(
                      dest,
                      initial: d,
                      range: ProgressRange.threeMonths,
                    ),
            ),
          );
          final content = await readPage(t);
          expect(content, isNotEmpty);
          expect(content.join(' '), isNot(contains('NaN')));
          if (!enough)
            expect(
              content.join(' ').toLowerCase(),
              anyOf(
                contains('no '),
                contains('not '),
                contains('log '),
                contains('add '),
              ),
            );
          if (enough && dest == ProgressDest.weight)
            expect(content.join(' '), contains('70'));
        },
      );
    }
  }
  for (final warm in [false, true]) {
    testWidgets(
      'COV-44 localized Trends preserves chart gaps and breathing coverage $warm',
      (t) async {
        final now = DateTime.now();
        final d = HealthData(
          charts: {
            if (warm)
              for (final (key, value) in [
                ('recovery', 70.0),
                ('sleep', 420.0),
                ('hrv', 50.0),
                ('resting_hr', 55.0),
                ('steps', 5000.0),
                ('step_kcal', 200.0),
                ('step_kcal_acsm', 250.0),
                ('resp_rate', 15.0),
                ('wear', 1200.0),
                ('strain', 8.0),
              ])
                key: [
                  for (var i = 0; i < 30; i++)
                    if (i != 3)
                      (
                        t:
                            DateTime(
                              now.year,
                              now.month,
                              now.day - i,
                              12,
                            ).millisecondsSinceEpoch ~/
                            1000,
                        v: value,
                      ),
                ],
          },
        );
        await localizedPage(t, Scaffold(body: HealthScreen(data: d)));
        final content = await readPage(t);
        expect(content.join(' '), contains('Trends'));
        expect(content.join(' '), contains('Steps'));
        expect(d.breathingShown, warm);
        final pins = find.text('Pin favourites');
        await reveal(t, pins);
        await t.tap(pins);
        await t.pumpAndSettle();
        expect(find.text('Pin up to three'), findsOneWidget);
        final choice = find.byWidgetPredicate(
          (w) => w is Pressable && w.semanticLabel == 'HRV',
        );
        await t.tap(choice);
        await t.pumpAndSettle();
        expect(
          find.byWidgetPredicate(
            (w) => w is Pressable && w.semanticLabel == 'HRV, pinned',
          ),
          findsOneWidget,
        );
      },
    );
  }
}
