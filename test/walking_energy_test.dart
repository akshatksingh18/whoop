// Daily maintenance as a floor: BMR + step calories + 10% of food logged.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/profile.dart';

void main() {
  // Akshat's own validation case.
  const me = Profile(ageYears: 23, weightKg: 80.5, heightCm: 186.69, sex: 'm');

  test('matches the agreed test case', () {
    expect(bmrMifflin(me), closeTo(1861.8, 0.1));
    expect(stepCalories(15000, 80.5), closeTo(395.4, 0.1));
    final m = maintenance(me, steps: 15000, eatenKcal: 2500)!;
    expect(m.food, closeTo(250, 1e-9));
    expect(m.total, closeTo(2507.2, 0.2));
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

  test('the steps breakdown keeps its stride distance', () {
    const p = Profile(heightCm: 175, weightKg: 75, sex: 'm');
    final w = walkingEnergy(10000, p)!;
    expect(w.km, closeTo(7.2625, 1e-9));
    expect(w.kcal, closeTo(stepCalories(10000, 75)!, 1e-9));
    expect(walkingEnergy(8000, const Profile(weightKg: 75)), isNull);
  });
}
