// Build 92: the fixes from the Codex audit of Build 91 (40611c52) that have a
// pure or widget-level contract. Synthetic data only.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/body_log.dart';
import 'package:whoop_companion/data/goal_plan.dart';
import 'package:whoop_companion/data/goal_review.dart';
import 'package:whoop_companion/data/nutrition_store.dart';
import 'package:whoop_companion/data/rest_streak.dart';
import 'package:whoop_companion/ui2/screens/food_left.dart';
import 'package:whoop_companion/ui2/theme.dart';

BodyWeightRow _w(String date) => (
  date: date,
  kg: 80,
  atTs: DateTime.parse(date).millisecondsSinceEpoch ~/ 1000,
  unit: 'kg',
  entered: 80,
  source: 'whoop',
  originId: null,
  historyOnly: false,
);

FoodDay _f(String date) => (
  date: date,
  kcal: 2200,
  counts: true,
  protein: null,
  proteinComplete: false,
);

void main() {
  test('7: a short day today is covered while a rest day is left', () {
    // Streak on Oct 13-14; missing Oct 15 would be its first rest.
    expect(restWouldCover({'2026-10-13', '2026-10-14'}, '2026-10-15'), isTrue);
    // Rests on Oct 11-12 already: a third in seven would end it.
    expect(
      restWouldCover({'2026-10-10', '2026-10-13', '2026-10-14'}, '2026-10-15'),
      isFalse,
    );
    // Today already counts, or there is no streak: nothing to cover.
    expect(restWouldCover({'2026-10-14', '2026-10-15'}, '2026-10-15'), isFalse);
    expect(restWouldCover(const {}, '2026-10-15'), isFalse);
  });

  test(
    '5: Log waist and Open Train appear only while their window is open',
    () {
      final days = [
        '2026-10-12',
        '2026-10-13',
        '2026-10-14',
        '2026-10-15',
        '2026-10-16',
      ];
      List<GoalNeed> needs(List<BodyMeasure> measures) {
        final r = goalReview(
          plan: GoalPlan(phase: GoalPhase.recomp, since: '2026-10-10'),
          today: '2026-10-16',
          weights: [for (final d in days) _w(d)],
          measures: measures,
          lifts: const [],
          food: [for (final d in days) _f(d)],
          steps: const [],
          sleepMin: const [],
          recovery: const [],
          sessions: const [],
        );
        return goalNeeds(
          r,
          today: '2026-10-16',
          weights: [for (final d in days) _w(d)],
          food: [for (final d in days) _f(d)],
          measures: measures,
          lifts: const [],
        );
      }

      // Start logged on Oct 16; the end window is Nov 2-8, weeks away.
      final logged = needs([
        BodyMeasure(
          date: '2026-10-16',
          recordedAt: DateTime(2026, 10, 16, 8),
          inches: {BodySite.waistNavel.name: 33.5},
        ),
      ]);
      expect(logged[1].kind, GoalNeedKind.waist);
      expect(logged[1].actNow, isFalse);
      expect(logged[1].sub, contains('End: one in Nov 2–8'));
      // The first lift half (Oct 12-25) is open today.
      expect(logged[2].kind, GoalNeedKind.lift);
      expect(logged[2].actNow, isTrue);
      // No start reading yet, and its window (Oct 5-19) is open: offer it.
      expect(needs(const [])[1].actNow, isTrue);
    },
  );

  testWidgets('4: over the goal with an unknown calorie reads "at least"', (
    t,
  ) async {
    const today = '2026-10-17';
    final day = rollupDay(today, [
      FoodEntry(id: 'a', date: today, meal: 'lunch', label: 'Rice', kcal: 1000),
      FoodEntry(id: 'b', date: today, meal: 'lunch', label: 'Curry'),
    ], today: today);
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(
          body: LeftAfterCard(
            day: day,
            date: today,
            kcalGoal: 2000,
            proteinGoal: null,
            thisKcal: 1100,
            thisProtein: null,
          ),
        ),
      ),
    );
    expect(find.text('Over by at least 100 kcal'), findsOneWidget);
    expect(find.text('Over by 100 kcal'), findsNothing);
  });
}
