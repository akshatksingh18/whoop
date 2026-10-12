// B88-12 (C4): a "not measured" metric says why in plain words.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/body_log.dart' show BodyLogError;
import 'package:openstrap_edge/models/metric.dart' show whyFromNote;
import 'package:openstrap_edge/ui2/screens/progress_screen.dart'
    show tapeReading;

void main() {
  test('HRV qualification note reads as a sentence with its counts', () {
    expect(
      whyFromNote('hrv_not_qualified:windows=3,need=6,thin=40'),
      'Not measured: 3 of 6 needed 5-minute windows had enough clean, '
      'gap-free beats.',
    );
  });

  test('stress and irregular-rhythm gates explain themselves', () {
    expect(
      whyFromNote('stress_not_qualified:beats_sec=600,need=1200'),
      contains('10 minutes'),
    );
    expect(
      whyFromNote('stress_not_qualified:windows=1,need=3,gapped=2'),
      contains('1 of 3'),
    );
    expect(
      whyFromNote('irregular_not_qualified:covered_sec=5400,need=10800'),
      contains('1.5 hours'),
    );
    expect(
      whyFromNote('strain_target_withheld:uncalibrated_quiet_baseline'),
      startsWith('No strain target'),
    );
  });

  test('C6: a second tape reading is averaged; a far-apart pair is refused', () {
    expect(tapeReading('Waist', '34.5'), 34.5);
    expect(tapeReading('Waist', '34.5 34.75'), 34.625);
    expect(tapeReading('Waist', '34,5/34,75'), 34.625);
    expect(() => tapeReading('Waist', '34 35'), throwsA(isA<BodyLogError>()));
    expect(() => tapeReading('Waist', 'abc'), throwsA(isA<BodyLogError>()));
  });
}
