// Build 91: the code-only fixes from the Codex audit of 3200c154, each pinned
// with the audit's own synthetic example. Synthetic data only.
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/body_log.dart';
import 'package:openstrap_edge/data/goal_review.dart';
import 'package:openstrap_edge/data/lift_log.dart';
import 'package:openstrap_edge/data/lift_progress.dart';
import 'package:openstrap_edge/data/nutrition_store.dart';
import 'package:openstrap_edge/ui2/screens/food_left.dart';

LiftSet _s(double load, int reps) =>
    LiftSet(reps: reps, load: load, completedAt: DateTime(2026, 10, 1));

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
  test('F03: the best set does not depend on the order sets were logged', () {
    final a = _s(100, 10), b = _s(110, 15), c = _s(120, 1);
    final orders = [
      [a, b, c],
      [a, c, b],
      [b, a, c],
      [b, c, a],
      [c, a, b],
      [c, b, a],
    ];
    for (final o in orders) {
      // 110 x 15 is heavier than 100 x 10 with more reps, so it did more.
      expect(identical(bestSet(o), b), isTrue, reason: '$o');
    }
    // Without a dominating high-rep set, the highest estimate wins either way.
    final d = _s(90, 15);
    expect(identical(bestSet([a, d, c]), a), isTrue);
    expect(identical(bestSet([d, c, a]), a), isTrue);
    // Only high-rep sets: the most reps at the heaviest load.
    expect(identical(bestSet([_s(60, 15), d, _s(90, 12)]), d), isTrue);
  });

  test('F01: an unknown-calorie item makes the fit an "at most"', () {
    const complete = NutrientTotal(1000, 3, 0);
    const partial = NutrientTotal(1000, 3, 1);
    expect(fitIsCeiling(complete), isFalse);
    expect(fitIsCeiling(partial), isTrue);
    expect(fitIsCeiling(complete, otherUnknown: true), isTrue);
    // The amount itself is still worked out from the known calories.
    expect(
      fitAmount(goal: 2000, eaten: partial, kcalPerUnit: 2, unit: 'g'),
      500,
    );
  });

  test('F02: re-portioning an old entry scales what was recorded', () {
    // Logged 100 g at 400 kcal; the saved food was later corrected to 500.
    final e = FoodEntry(
      id: 'e1',
      date: '2026-10-01',
      meal: 'lunch',
      label: 'Granola',
      foodKey: 'my:granola',
      quantity: 100,
      unit: 'g',
      kcal: 400,
      proteinG: 10,
      sugarG: 20,
    );
    final def = <String, Object?>{
      'key': 'my:granola',
      'label': 'Granola',
      'unit': 'g',
      'kcal_100': 500,
      'protein_g_100': 12,
    };
    final at = recordedDef(e, def)!;
    expect(at.base, 100);
    expect(at.def['kcal_100'], 400);
    expect(
      nutrientsFor(at.def, 100).kcal,
      400,
      reason: 'the same amount saves the same calories',
    );
    final more = e.scaledPortion(150 / at.base, newQuantity: 150, newUnit: 'g');
    expect(more.kcal, 600);
    expect(more.proteinG, 15);
    expect(more.sugarG, 30, reason: 'nutrients the saved food lacks survive');
    expect(more.quantity, 150);
    expect(more.date, '2026-10-01');
  });

  test('F06: a week that can no longer qualify pushes the first check back', () {
    // Sunday Oct 18, nothing logged this week, four full weeks needed.
    expect(
      thisWeekCanQualify(
        today: '2026-10-18',
        weights: const [],
        food: const [],
      ),
      isFalse,
    );
    expect(
      firstCheckDate(
        weeks: const [],
        today: '2026-10-18',
        windowWeeks: 2,
        thisWeekCanQualify: false,
      ),
      '2026-11-16',
    );
    // Thursday with three of each logged: four days left can still reach five.
    final days = ['2026-10-12', '2026-10-13', '2026-10-14'];
    expect(
      thisWeekCanQualify(
        today: '2026-10-15',
        weights: [for (final d in days) _w(d)],
        food: [for (final d in days) _f(d)],
      ),
      isTrue,
    );
    // Monday: the whole week is ahead.
    expect(
      thisWeekCanQualify(
        today: '2026-10-19',
        weights: const [],
        food: const [],
      ),
      isTrue,
    );
    expect(
      firstCheckDate(weeks: const [], today: '2026-10-18', windowWeeks: 2),
      '2026-11-09',
      reason: 'when the week can still qualify it counts as the first',
    );
  });
}
