import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_analytics/onehz.dart' as ana;
import 'package:openstrap_edge/ble/live_cadence.dart';

// Per-minute counts are RAW (pre-gain). The gait band is tested against the RAW
// minute and `StepParams.gain` is applied once, to the median, at the end —
// see the ordering note in live_cadence.dart. The gain defaults to 1.00, so a
// raw minute and its reported cadence are the same number today; the tests
// below are written so they still say something if a per-user gain is ever set.
void main() {
  test('a session that never walked has no cadence — null, not 0', () {
    expect(sessionCadenceSpm(const []), isNull);
    expect(sessionCadenceSpm(const [0, 0, 0, 0, 0]), isNull);
  });

  test('one or two gait-like minutes is an anecdote, not a cadence', () {
    expect(sessionCadenceSpm(const [0, 100, 0, 0]), isNull);
    expect(sessionCadenceSpm(const [100, 99, 0]), isNull);
  });

  test('a steady walk reports the median gait minute', () {
    expect(sessionCadenceSpm(const [100, 100, 100, 100]), 100);
  });

  test('still minutes do not drag the cadence down', () {
    // 40 min of a session, 5 of them walking at ~100 spm. steps ÷ duration
    // would say ~13 spm, which is nobody's cadence.
    final minutes = <int>[
      for (var i = 0; i < 35; i++) 0,
      100,
      100,
      100,
      100,
      100
    ];
    expect(sessionCadenceSpm(minutes), 100);
  });

  test('sub-gait and impossible minutes are excluded, not clamped', () {
    // 20 spm (a few steps in an otherwise still minute) and 250 spm (not a
    // human walking) are both dropped. Only the three real minutes remain —
    // exactly the minimum.
    expect(sessionCadenceSpm(const [20, 250, 90, 100, 110]), 100);
    // Drop one of the three and there is no longer enough to report.
    expect(sessionCadenceSpm(const [20, 250, 90, 100]), isNull);
  });

  test('even minute counts take the mean of the two middle minutes', () {
    // 90/100/110/120 → mean of the middle two = 105.
    expect(sessionCadenceSpm(const [90, 100, 110, 120]), 105);
  });

  test('THE GATE TESTS THE RAW MINUTE, not the gained one', () {
    // The bug: the gain used to be applied BEFORE the 60–200 spm test, so the
    // band was stretched by whatever the gain was. At the old 1.11 a raw 54
    // read 60 and entered the median while a raw 181 read 201 and was thrown
    // out — an 11% wider window at both ends than kMinCadenceSpm /
    // kMaxCadenceSpm claim. These are the exact boundary minutes: they must be
    // decided by the raw number, whatever the gain is.
    expect(sessionCadenceSpm(const [54, 55, 56, 57]), isNull,
        reason: 'below 60 raw is not a gait minute at any gain');
    expect(sessionCadenceSpm(const [201, 205, 210, 220]), isNull);
    expect(sessionCadenceSpm(const [60, 60, 60]), isNotNull);
    expect(sessionCadenceSpm(const [200, 200, 200]), isNotNull);
    // And the boundary constants are what decide it.
    expect(kMinCadenceSpm, 60);
    expect(kMaxCadenceSpm, 200);
  });

  test('the gain lands on the answer exactly once', () {
    // With the default 1.00 this is an identity; the point is that the reported
    // cadence is the median times the gain, applied once, at the end.
    expect(ana.StepParams.gain, 1.00);
    expect(sessionCadenceSpm(const [100, 100, 100]),
        (100 * ana.StepParams.gain).round());
  });
}
