// Build 86 food repairs (B86-07, B86-08, B86-09): serving equivalents both
// ways from explicit conversions only, a per-entry snapshot so editing a food
// cannot rewrite an old portion, personal labels matched ignoring case, and
// the warning colour tied to maintenance rather than the diet goal.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/nutrition_store.dart';
import 'package:openstrap_edge/ui2/screens/nutrition_screen.dart'
    show IntakeStatus, intakeStatus;

Map<String, Object?> _whey({double scoop = 30}) => {
  'key': 'whey',
  'label': 'Whey',
  'unit': 'g',
  'measures_json': jsonEncode([
    {'l': 'scoop', 'a': scoop},
  ]),
};

void main() {
  group('portions both ways', () {
    test('a named serving shows its weight', () {
      expect(portionWithWeight(2, 'scoop', _whey()), '2 scoops · 60 g');
    });

    test('a weighed portion shows its named serving, fractions included', () {
      expect(portionWithWeight(45, 'g', _whey()), '45 g · 1.5 scoops');
    });

    test('no conversion, no invented equivalent', () {
      final oil = {'key': 'oil', 'label': 'Oil', 'unit': 'ml'};
      expect(portionWithWeight(10, 'ml', oil), '10 ml');
      // No density is assumed between ml and g.
      expect(portionWithWeight(10, 'g', oil), '10 g');
    });
  });

  group('conversion snapshot', () {
    test('an entry keeps the serving it was logged with', () {
      final e = entryFromFood(
        _whey(),
        45,
        id: 'e1',
        date: '2026-10-10',
        meal: 'breakfast',
        amount: 45,
        unit: 'g',
      );
      expect(e.conv, isNotEmpty);
      // The food is edited afterwards: a scoop is now 40 g.
      final edited = _whey(scoop: 40);
      expect(
        portionWithWeight(45, 'g', conversionDef(e, edited)),
        '45 g · 1.5 scoops',
      );
      // And deleted: the snapshot still answers.
      expect(
        portionWithWeight(45, 'g', conversionDef(e, null)),
        '45 g · 1.5 scoops',
      );
    });

    test('a legacy entry without a snapshot reads the current food', () {
      const e = FoodEntry(
        id: 'old',
        date: '2026-10-01',
        meal: 'lunch',
        label: 'Whey',
        quantity: 40,
      );
      expect(
        portionWithWeight(40, 'g', conversionDef(e, _whey(scoop: 40))),
        '40 g · 1 scoop',
      );
    });

    test('the snapshot survives the database row round trip', () {
      final e = entryFromFood(
        _whey(),
        30,
        id: 'e2',
        date: '2026-10-10',
        meal: 'snacks',
      );
      final back = FoodEntry.fromRow(e.toRow(0));
      expect(back.conv, e.conv);
      expect(back.copyTo('2026-10-11', 'lunch', newId: 'e3').conv, e.conv);
    });
  });

  group('personal labels', () {
    test('labels dedupe ignoring case and keep the first spelling', () {
      final defs = [
        {'category': 'Pre-workout'},
        {'category': 'pre-workout '},
        {'category': 'Breakfast'},
        {'category': ''},
      ];
      expect(foodLabelsIn(defs), ['Breakfast', 'Pre-workout']);
      expect(foodCategoriesIn(defs), [
        'Breakfast',
        'Pre-workout',
        kUncategorised,
      ]);
    });
  });

  group('a day you mark yourself', () {
    FoodEntry e(String date, int hour, {double? kcal = 500}) => FoodEntry(
      id: '$date-$hour',
      date: date,
      meal: 'lunch',
      label: 'x',
      kcal: kcal,
      atTs:
          DateTime.parse(
            date,
          ).add(Duration(hours: hour)).millisecondsSinceEpoch ~/
          1000,
      confirmed: true,
    );
    test('complete wins over the evening guess, today included', () {
      final noEvening = [e('2026-10-08', 12)];
      expect(
        dayLogState('2026-10-08', noEvening, today: '2026-10-10'),
        DayLogState.partial,
      );
      expect(
        dayLogState(
          '2026-10-08',
          noEvening,
          today: '2026-10-10',
          mark: 'complete',
        ),
        DayLogState.complete,
      );
      expect(
        dayLogState(
          '2026-10-10',
          [e('2026-10-10', 9)],
          today: '2026-10-10',
          mark: 'complete',
        ),
        DayLogState.complete,
      );
    });
    test(
      'incomplete leaves a day out; unknown calories are never complete',
      () {
        final evening = [e('2026-10-08', 19)];
        expect(
          dayLogState(
            '2026-10-08',
            evening,
            today: '2026-10-10',
            mark: 'incomplete',
          ),
          DayLogState.partial,
        );
        expect(
          dayLogState(
            '2026-10-08',
            [e('2026-10-08', 19, kcal: null)],
            today: '2026-10-10',
            mark: 'complete',
          ),
          DayLogState.partial,
        );
      },
    );
  });

  group('intake colour follows maintenance, not the goal', () {
    test('over goal but within maintenance is not a warning', () {
      expect(intakeStatus(2300, 2600), IntakeStatus.withinMaintenance);
      expect(intakeStatus(2600, 2600), IntakeStatus.withinMaintenance);
    });

    test('above maintenance warns', () {
      expect(intakeStatus(2700, 2600), IntakeStatus.aboveMaintenance);
    });

    test('unknown maintenance is neutral, never green', () {
      expect(intakeStatus(2300, null), IntakeStatus.unknown);
      expect(intakeStatus(null, 2600), IntakeStatus.unknown);
    });
  });
}
