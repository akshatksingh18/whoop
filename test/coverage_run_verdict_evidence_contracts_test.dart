// Existing fixed narration rules only; no pace/zone/scientific retuning.
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/gps/route_models.dart';
import 'package:whoop_companion/gps/run_analysis.dart';

List<Split> splits(List<int> seconds, {double meters = 1000}) => [
  for (var i = 0; i < seconds.length; i++)
    Split(index: i + 1, meters: meters, durationSec: seconds[i]),
];

void main() {
  test(
    'no zone evidence and fewer than three complete splits produces no verdict',
    () {
      expect(runVerdict(zoneShares: const [], splits: const []), isNull);
      expect(
        runVerdict(zoneShares: List.filled(6, 0), splits: splits([300, 600])),
        isNull,
      );
    },
  );
  for (final secondary in [.149, .15]) {
    test(
      'a secondary zone is named only at the existing15 percent boundary: $secondary',
      () {
        final v = runVerdict(
          zoneShares: [.75, secondary, .25 - secondary, 0, 0, 0],
          splits: const [],
        )!;
        expect(v, startsWith('Mostly recovery (75%)'));
        expect(v.contains(' and '), secondary >= .15);
        if (secondary >= .15) {
          expect(v, contains('endurance (15%)'));
        }
      },
    );
  }
  for (final (spread, wording) in [
    (30, 'Very even pacing'),
    (31, 'Even pacing'),
    (60, 'Even pacing'),
    (61, 'Uneven pacing (61s between fastest and slowest km)'),
  ]) {
    test('pacing spread $spread seconds keeps its existing classification', () {
      final v = runVerdict(
        zoneShares: List.filled(6, 0),
        splits: splits([300, 300 + spread ~/ 2, 300 + spread]),
      )!;
      expect(v, startsWith(wording));
    });
  }
  for (final delta in [-5, -4, 9, 10]) {
    test(
      'finish narration uses the qualified half comparison at $delta seconds',
      () {
        final v = runVerdict(
          zoneShares: List.filled(6, 0),
          splits: splits([300, 300, 300 + delta, 300 + delta]),
        )!;
        expect(v, startsWith('Very even pacing'));
        expect(v.contains('faster second half'), delta <= -5);
        expect(v.contains('slowed in the second half'), delta >= 10);
      },
    );
  }
  for (final meters in [989.0, 990.0]) {
    test(
      'the existing99 percent full-split tolerance is respected at $meters meters',
      () {
        final v = runVerdict(
          zoneShares: List.filled(6, 0),
          splits: splits([300, 300, 300], meters: meters),
        );
        expect(v, meters < 990 ? isNull : 'Very even pacing.');
      },
    );
  }
  test(
    'a slow partial tail cannot invent uneven pacing or a slower second half',
    () {
      expect(
        runVerdict(
          zoneShares: List.filled(6, 0),
          splits: [
            ...splits([300, 300, 300]),
            const Split(index: 4, meters: 300, durationSec: 1200),
          ],
        ),
        'Very even pacing.',
      );
    },
  );
}
