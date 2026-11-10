// Build 89: a past food day counts on its own once it looks finished, the
// calorie card reads eaten / goal with what is left beside it, and the goal
// bar stripes past the goal.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/nutrition_store.dart';
import 'package:whoop_companion/ui2/charts.dart';
import 'package:whoop_companion/ui2/screens/food_calendar.dart';
import 'package:whoop_companion/ui2/screens/nutrition_screen.dart';
import 'package:whoop_companion/ui2/theme.dart';

FoodEntry _e(String id, {double? kcal}) => FoodEntry(
  id: id,
  date: '2026-10-08',
  meal: 'lunch',
  label: id,
  kcal: kcal,
  atTs: DateTime(2026, 10, 8, 13).millisecondsSinceEpoch ~/ 1000,
  confirmed: true,
);

void main() {
  group('automatic day counting', () {
    test('half the goal with energy on every item counts on its own', () {
      final es = [_e('a', kcal: 700), _e('b', kcal: 400)];
      expect(
        dayLogState('2026-10-08', es, today: '2026-10-10', kcalGoal: 2000),
        DayLogState.complete,
      );
    });

    test('under half the goal stays out until counted', () {
      final es = [_e('lunch', kcal: 800)];
      expect(
        dayLogState('2026-10-08', es, today: '2026-10-10', kcalGoal: 2000),
        DayLogState.partial,
      );
      expect(
        dayLogState(
          '2026-10-08',
          es,
          today: '2026-10-10',
          kcalGoal: 2000,
          mark: 'complete',
        ),
        DayLogState.complete,
      );
    });

    test(
      'a food without calories, a missing-food mark or today never auto-counts',
      () {
        expect(
          dayLogState(
            '2026-10-08',
            [_e('a', kcal: 1500), _e('b')],
            today: '2026-10-10',
            kcalGoal: 2000,
          ),
          DayLogState.partial,
        );
        expect(
          dayLogState(
            '2026-10-08',
            [_e('a', kcal: 1500)],
            today: '2026-10-10',
            kcalGoal: 2000,
            mark: 'incomplete',
          ),
          DayLogState.partial,
        );
        expect(
          dayLogState(
            '2026-10-10',
            [_e('a', kcal: 1500)],
            today: '2026-10-10',
            kcalGoal: 2000,
          ),
          DayLogState.inProgress,
        );
      },
    );

    test('no goal set: nothing counts on its own', () {
      autoCountKcalGoal = null;
      expect(
        dayLogState('2026-10-08', [_e('a', kcal: 2500)], today: '2026-10-10'),
        DayLogState.partial,
      );
    });
  });

  testWidgets('the calorie card shows eaten / goal and what is over', (
    t,
  ) async {
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: const Scaffold(body: CalorieCard(eaten: 2663, goal: 2233)),
      ),
    );
    expect(find.text('2,663'), findsOneWidget);
    expect(find.text('Goal 2,233 kcal'), findsOneWidget);
    expect(find.text('430'), findsOneWidget);
    expect(find.text('kcal over'), findsOneWidget);
    final ring =
        t
                .widget<CustomPaint>(
                  find.byKey(const ValueKey('food-balance-ring')),
                )
                .painter!
            as Ring;
    expect(
      ring.v,
      0,
      reason:
          'Above goal means no calories remain; overage is written, not hidden.',
    );
  });

  testWidgets('the week strip marks counted and logged days', (t) async {
    String? opened;
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(
          body: FoodWeekStrip(
            date: '2026-10-13',
            onDay: (d) => opened = d,
            marks: const {
              '2026-10-12': FoodDayMark.counted,
              '2026-10-13': FoodDayMark.logged,
            },
          ),
        ),
      ),
    );
    expect(find.bySemanticsLabel(RegExp('counted')), findsWidgets);
    await t.tap(find.text('12'));
    expect(opened, '2026-10-12');
  });
}
