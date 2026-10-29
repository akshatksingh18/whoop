// B88-06: food totals never count an unknown as zero, a past food day counts
// only when marked complete (D13), and the food/weight maintenance estimate
// is robust to one water swing and carries an honest range.

import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/nutrition_store.dart';
import 'package:whoop_companion/ui2/screens/food_diary.dart' show mealTotals;

FoodEntry _e(String id, {double? kcal, double? protein}) => FoodEntry(
  id: id,
  date: '2026-10-08',
  meal: 'lunch',
  label: id,
  kcal: kcal,
  proteinG: protein,
  atTs: DateTime(2026, 10, 8, 20).millisecondsSinceEpoch ~/ 1000,
  confirmed: true,
);

List<({String date, double kg})> _weighIns(Map<int, double> byDay) => [
  for (final e in byDay.entries)
    (
      date:
          '2026-09-${(1 + e.key).toString().padLeft(2, '0')}',
      kg: e.value,
    ),
];

void main() {
  group('D13: explicit completion', () {
    test('a dinner-only past day with energy is partial until marked', () {
      final es = [_e('dinner', kcal: 900, protein: 50)];
      expect(
        dayLogState('2026-10-08', es, today: '2026-10-10'),
        DayLogState.partial,
      );
      expect(
        dayLogState('2026-10-08', es, today: '2026-10-10', mark: 'complete'),
        DayLogState.complete,
      );
    });
  });

  group('meal totals', () {
    test('an item without calories makes the total a floor, never zero', () {
      expect(
        mealTotals([
          _e('a', kcal: 500, protein: 30),
          _e('b', protein: 10),
        ]),
        'at least 500 kcal · P 40 · C – · F – · Fb –',
      );
      expect(
        mealTotals([_e('a', kcal: 500, protein: 30), _e('b', kcal: 200)]),
        '700 kcal · P ≥30 · C – · F – · Fb –',
      );
      expect(mealTotals([_e('bare')]), 'kcal not tracked');
    });
  });

  group('food/weight maintenance', () {
    test('one end-of-window water swing no longer moves it hundreds of kcal',
        () {
      // Eight flat readings over 14 days, the last one +1 kg. Least squares
      // moved the estimate by about 321 kcal/day; the median slope stays 0.
      final w = _weighIns({
        0: 80, 2: 80, 4: 80, 6: 80, 8: 80, 10: 80, 12: 80, 14: 81,
      });
      final m = measuredMaintenance(w, List.filled(14, 2200.0))!;
      expect(m.kcal, closeTo(2200, 1e-6));
      // The swing still widens the range, past the shown limit.
      expect(m.shown, isFalse);
    });

    test('steady daily readings give a narrow range that is shown', () {
      final w = _weighIns({
        for (var i = 0; i < 28; i++) i: 82.0 - 0.05 * i,
      });
      final m = measuredMaintenance(w, List.filled(27, 2000.0))!;
      expect(m.kcal, closeTo(2000 + 0.05 * kKcalPerKg, 1e-6));
      expect(m.low, lessThanOrEqualTo(m.kcal));
      expect(m.high, greaterThanOrEqualTo(m.kcal));
      expect(m.shown, isTrue);
    });

    test('needs three weigh-ins in each half of the span', () {
      // Eight readings, but only two in the second half.
      final w = _weighIns({
        0: 80, 1: 80, 2: 80, 3: 80, 4: 80, 5: 80, 13: 80, 14: 80,
      });
      expect(measuredMaintenance(w, List.filled(14, 2200.0)), isNull);
    });
  });
}
