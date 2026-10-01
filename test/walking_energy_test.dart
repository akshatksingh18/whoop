// Walking energy: shown beside steps, never added to the calorie totals.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/profile.dart';

void main() {
  const me = Profile(heightCm: 175, weightKg: 75, sex: 'm');

  test('10,000 steps at 175 cm / 75 kg is about 7.3 km and 272 kcal', () {
    final w = walkingEnergy(10000, me)!;
    expect(w.km, closeTo(7.2625, 1e-9)); // 0.415 × 1.75 m stride
    expect(w.kcal, closeTo(272.34, 0.01)); // 0.5 kcal/kg/km net
  });

  test('no estimate without height, weight or steps', () {
    expect(walkingEnergy(8000, const Profile(weightKg: 75)), isNull);
    expect(walkingEnergy(8000, const Profile(heightCm: 175)), isNull);
    expect(walkingEnergy(0, me), isNull);
    expect(walkingEnergy(null, me), isNull);
  });
}
