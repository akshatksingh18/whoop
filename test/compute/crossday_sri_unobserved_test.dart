// Sleep regularity over authored day bundles: a stretch the stager marks
// unobserved is no evidence of being awake, so it drops out of the pairs
// rather than breaking an otherwise identical schedule.
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/crossday_pipeline.dart';

void main() {
  test('an unobserved stretch is left out of regularity', () {
    const base = 1767225600;
    final rows = <Map<String, dynamic>>[];
    for (var i = 0; i < 4; i++) {
      final start = base + i * 86400;
      rows.add({
        'date': '2026-01-0${i + 1}',
        'worn_min': 1440,
        'day_zone': {'start_ts': start, 'end_ts': start + 86400},
        'hypnogram': [
          {'start': start, 'end': start + 8 * 3600, 'stage': 'light'},
          {
            'start': start + 8 * 3600,
            'end': start + 10 * 3600,
            'stage': i == 1 ? 'unobserved' : 'light',
          },
        ],
      });
    }
    final sri =
        (buildCrossDayBundle(rows, {})['regularity'] as Map)['value'] as Map;
    expect(sri['sri'], 100);
  });
}
