// The catalogue's `gait` flag decides which sessions show a step count
// (`stepsCounted`). Rhythmic arm work at gait cadence must never show steps,
// and the foot activities must, so both directions are pinned here.

import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/ui2/activity/catalogue.dart';

void main() {
  final catalogueKeys = {for (final a in allActivities) a.typeKey};
  final catalogueGait = {
    for (final a in allActivities)
      if (a.gait) a.typeKey,
  };

  test('exactly the foot activities are gait', () {
    expect(catalogueGait, {
      'walking',
      'running',
      'trail_running',
      'hiking',
      'dog_walking',
      'treadmill',
      'cross_country',
    });
  });

  test('no activity is gait and cycling at once', () {
    for (final a in allActivities) {
      if (a.gait && a.typeKey.contains('cycl')) {
        fail('${a.name} is flagged gait — pedalling is not stepping');
      }
    }
  });

  test('the arm-work activities are all OUT', () {
    for (final k in const [
      'rowing',
      'boxing',
      'martial_arts',
      'elliptical',
      'weight_training',
      'powerlifting',
      'kettlebell',
      'crossfit',
      'hiit',
      'circuit_training',
      'swimming',
      'cycling',
      'indoor_bike',
      'jump_rope',
      'housework',
      'gardening',
      'diy',
    ]) {
      expect(catalogueKeys, contains(k), reason: 'stale test, not stale code');
      expect(catalogueGait, isNot(contains(k)), reason: '$k is not gait');
    }
  });
}
