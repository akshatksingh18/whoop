import '../types.dart';
import '../sleep/van_hees.dart' show zAngle;

/// van Hees 2015 angle convention, adapted to the retained 1 Hz vectors.
/// Each five-minute cell reports whether its observed arm-angle range exceeds
/// five degrees. A static sensor gain error cancels in the angle ratio.
List<Map<String, dynamic>> armAngleRestlessness(List<AccelSample> samples) {
  final ranges = <int, ({double low, double high, int count})>{};
  for (final sample in samples) {
    if (!sample.valid ||
        !sample.x.isFinite ||
        !sample.y.isFinite ||
        !sample.z.isFinite ||
        (sample.x == 0 && sample.y == 0 && sample.z == 0)) continue;
    final bucket = sample.tsMs ~/ 300000;
    final angle = zAngle(sample.x, sample.y, sample.z);
    final previous = ranges[bucket];
    ranges[bucket] = previous == null
        ? (low: angle, high: angle, count: 1)
        : (
            low: angle < previous.low ? angle : previous.low,
            high: angle > previous.high ? angle : previous.high,
            count: previous.count + 1
          );
  }
  final keys = ranges.keys.toList()..sort();
  return [
    for (final key in keys)
      if (ranges[key]!.count >= 2)
        {
          't': key * 300,
          'density': ranges[key]!.high - ranges[key]!.low > 5 ? 1.0 : 0.0,
          'angle_range_deg': ranges[key]!.high - ranges[key]!.low,
          'observed_samples': ranges[key]!.count,
        }
  ];
}
