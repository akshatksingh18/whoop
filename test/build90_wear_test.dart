import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_analytics/onehz.dart';

void main() {
  test('bridges up to 120 seconds, counts each touched minute once', () {
    expect(recordedWornMinutes([59, 60, 180]), 4);
    expect(recordedWornMinutes([59, 180]), 2);
    expect(recordedWornMinutes([59, 59, 60]), 2);
    expect(recordedWornMinutes([]), 0);
  });
  test('reported states and unsynced tail never infer off-wrist from gaps', () {
    final block = dayWearBlock(
      [10, 60, 500],
      startSec: 0,
      endSec: 900,
      frontierSec: 501,
      offWrist: [
        [180, 300],
        [550, 700],
      ],
      charging: [
        [300, 400],
      ],
    );
    final segments = block['segments'] as List;
    expect(segments.map((s) => s['state']), [
      'missing',
      'worn',
      'missing',
      'off_wrist',
      'charging',
      'missing',
      'worn',
      'pending',
    ]);
    expect(block['worn_min'], recordedWornMinutes([10, 60, 500]));
    expect(block['longest_off_min'], 2);
    expect(segments.last['start'], 501);
    expect(segments.last['end'], 900);
  });
  test('empty, clipped and DST-length windows preserve absent coverage', () {
    expect(
      dayWearBlock(
        [],
        startSec: 0,
        endSec: 82800,
        frontierSec: 0,
      )['coverage_pct'],
      isNull,
    );
    final block = dayWearBlock(
      [-1, 0, 60, 90000],
      startSec: 0,
      endSec: 90000,
      frontierSec: 100000,
    );
    expect(block['worn_min'], 2);
    expect((block['segments'] as List).last['state'], 'missing');
  });
  test('sparse multi-year input is counted without expanding every minute', () {
    final ts = List.generate(2000, (i) => i * 86400);
    expect(recordedWornMinutes(ts), 2000);
  });
}
