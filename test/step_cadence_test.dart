// The one windows→minutes cadence mapping (lib/compute/step_cadence.dart).
//
// Both energy call sites — DerivationEngine.wakeDayEnergy and the pure
// pipeline's mirror — feed `Calories.dailyEnergy` a per-wake-minute cadence
// built by this ONE function from the day's resolved `live_coverage` spans.
// Two implementations of this mapping is how the day and its early read would
// drift apart (the exact bug class the single wakeDayEnergy pass ended), so
// the contract is pinned here once, for both.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/step_cadence.dart';

void main() {
  // Minute keys are epoch-seconds ~/ 60, same as the wake-series buckets.
  const k = 1000; // an arbitrary minute key; second 60000..60059

  test('a span covering whole minutes reads as its own steps-per-minute', () {
    final cad = cadenceSpmForMinutes(
      [k, k + 1],
      [
        [k * 60, (k + 2) * 60, 220], // 2 min, 220 steps → 110 spm
      ],
    );
    expect(cad, hasLength(2));
    expect(cad[0], closeTo(110.0, 1e-9));
    expect(cad[1], closeTo(110.0, 1e-9));
  });

  test('a minute no span touches is null — unmeasured, not zero', () {
    final cad = cadenceSpmForMinutes(
      [k, k + 5],
      [
        [k * 60, (k + 1) * 60, 100],
      ],
    );
    expect(cad[0], closeTo(100.0, 1e-9));
    expect(cad[1], isNull,
        reason: 'nobody measured minute k+5; null is what keeps the walking '
            'term from pricing a cadence that was never observed');
  });

  test('partial coverage pro-rates DOWN — steps that minute, not the pace',
      () {
    // A span at 120 spm covering only the last 30 s of the minute credits 60
    // steps to it. The minute reads 60 spm — below the moderate floor — so a
    // walk's boundary minute under-bills rather than a half-minute of walking
    // billing a full MET-minute.
    final cad = cadenceSpmForMinutes(
      [k],
      [
        [k * 60 + 30, (k + 1) * 60, 60],
      ],
    );
    expect(cad[0], closeTo(60.0, 1e-9));
  });

  test('overlapping credited spans sum into the same minute', () {
    final cad = cadenceSpmForMinutes(
      [k],
      [
        [k * 60, k * 60 + 30, 30], // 60 spm for the first half
        [k * 60 + 30, (k + 1) * 60, 60], // 120 spm for the second
      ],
    );
    expect(cad[0], closeTo(90.0, 1e-9));
  });

  test('a measured stillness is 0.0, not null', () {
    // The pedometer ran and counted nothing: that is a measurement of not
    // walking, distinct from no pedometer at all. Both refuse to bill (0 is
    // under the floor), but only one claims knowledge.
    final cad = cadenceSpmForMinutes(
      [k],
      [
        [k * 60, (k + 1) * 60, 0],
      ],
    );
    expect(cad[0], 0.0);
  });

  test('degenerate and disjoint spans are skipped, not thrown on', () {
    final cad = cadenceSpmForMinutes(
      [k],
      [
        [k * 60, k * 60, 50], // zero width
        [(k + 9) * 60, (k + 10) * 60, 100], // elsewhere
      ],
    );
    expect(cad[0], isNull);
  });

  test('no spans at all → all null, same length as the keys', () {
    expect(cadenceSpmForMinutes([k, k + 1], const []),
        [null, null]);
  });
}
