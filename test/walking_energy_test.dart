// Daily maintenance as a budgeting estimate: BMR + step calories + the
// low-end digestion cost of the food logged (build 84).

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/profile.dart';

void main() {
  // Akshat's own validation case.
  const me = Profile(ageYears: 23, weightKg: 80.5, heightCm: 186.69, sex: 'm');

  test('matches the agreed test case', () {
    expect(bmrMifflin(me), closeTo(1861.8125, 1e-9));
    expect(stepCalories(15000, 80.5), closeTo(395.381, 0.001));
    // 2,500 kcal with 180 g protein, 250 g carbs, 87 g fat (todo.md, build 84).
    final cost = digestionKcal(
      kcal: 2500,
      proteinG: 180,
      carbsG: 250,
      fatG: 87,
    );
    expect(cost, closeTo(144 + 50, 1e-9));
    final m = maintenance(
      me,
      steps: 15000,
      eatenKcal: 2500,
      digestionKcal: cost,
    )!;
    expect(m.food, closeTo(194.0, 1e-9));
    expect(m.total, closeTo(2451.19, 0.01));
  });

  group('digestion at the low end of each range', () {
    test('the documented table', () {
      // A 15/50/35% day: 93.75 g protein, 312.5 g carbs.
      expect(
        digestionKcal(kcal: 2500, proteinG: 93.75, carbsG: 312.5, fatG: 875 / 9),
        closeTo(137.5, 1e-9),
      );
      // Whey scoop.
      expect(
        digestionKcal(kcal: 120, proteinG: 24, carbsG: 3, fatG: 1.5),
        closeTo(19.8, 1e-9),
      );
      // Quick add with no macros: unknown composition at 5%.
      expect(digestionKcal(kcal: 500), closeTo(25.0, 1e-9));
      // Only protein logged: the unexplained 220 kcal at 5%.
      expect(digestionKcal(kcal: 300, proteinG: 20), closeTo(27.0, 1e-9));
      // Olive oil.
      expect(
        digestionKcal(kcal: 120, proteinG: 0, carbsG: 0, fatG: 14),
        closeTo(0.0, 1e-9),
      );
      // Label rounding: 26 g protein in 100 kcal caps at 20% of the kcal.
      expect(
        digestionKcal(kcal: 100, proteinG: 26, carbsG: 0, fatG: 0),
        closeTo(20.0, 1e-9),
      );
    });

    test('no kcal, no cost; without macros the eaten kcal is unknown food', () {
      expect(digestionKcal(kcal: null, proteinG: 30), 0);
      expect(digestionKcal(kcal: 0), 0);
      final m = maintenance(me, steps: 15000, eatenKcal: 2500)!;
      expect(m.food, closeTo(125.0, 1e-9));
    });
  });

  test('food adds nothing until food is logged', () {
    final m = maintenance(me, steps: 15000)!;
    expect(m.food, 0);
    expect(m.total, closeTo(2257.2, 0.2));
  });

  test('women use -161 and an unknown sex the midpoint', () {
    const f = Profile(ageYears: 30, weightKg: 60, heightCm: 165, sex: 'f');
    expect(bmrMifflin(f), closeTo(10 * 60 + 6.25 * 165 - 150 - 161, 1e-9));
    const x = Profile(ageYears: 30, weightKg: 60, heightCm: 165);
    expect(bmrMifflin(x), closeTo(10 * 60 + 6.25 * 165 - 150 - 78, 1e-9));
  });

  test('no number without the inputs it needs', () {
    expect(bmrMifflin(const Profile(weightKg: 80, heightCm: 180)), isNull);
    expect(maintenance(const Profile(weightKg: 80)), isNull);
    expect(stepCalories(0, 80), 0); // Measured stillness is zero active energy.
    expect(stepCalories(1000, null), isNull);
  });

  test('the steps breakdown keeps its estimated step-length distance', () {
    const p = Profile(heightCm: 175, weightKg: 75, sex: 'm');
    final w = walkingEnergy(10000, p)!;
    expect(w.km, closeTo(7.2625, 1e-9));
    expect(w.kcal, closeTo(stepCalories(10000, 75)!, 1e-9));
    final withoutHeight = walkingEnergy(8000, const Profile(weightKg: 75))!;
    expect(withoutHeight.kcal, stepCalories(8000, 75));
    expect(withoutHeight.km, isNull);
  });
}
