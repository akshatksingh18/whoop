import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ble/live_cadence.dart';

// Per-minute counts are RAW (pre-gain); the ×1.11 AN-2554 gain is applied
// inside sessionCadenceSpm, so these inputs are ~raw and the expectations are
// the gained cadence.
void main() {
  test('a session that never walked has no cadence — null, not 0', () {
    expect(sessionCadenceSpm(const []), isNull);
    expect(sessionCadenceSpm(const [0, 0, 0, 0, 0]), isNull);
  });

  test('one or two gait-like minutes is an anecdote, not a cadence', () {
    expect(sessionCadenceSpm(const [0, 100, 0, 0]), isNull);
    expect(sessionCadenceSpm(const [100, 99, 0]), isNull);
  });

  test('a steady walk reports the median gait minute, gain applied', () {
    // 100 raw ≈ 111 spm.
    expect(sessionCadenceSpm(const [100, 100, 100, 100]), 111);
  });

  test('still minutes do not drag the cadence down', () {
    // 40 min of a session, 5 of them walking at ~111 spm. steps ÷ duration
    // would say ~14 spm, which is nobody's cadence.
    final minutes = <int>[for (var i = 0; i < 35; i++) 0, 100, 100, 100, 100, 100];
    expect(sessionCadenceSpm(minutes), 111);
  });

  test('sub-gait and impossible minutes are excluded, not clamped', () {
    // 20 raw ≈ 22 spm (a few steps in an otherwise still minute) and 250 raw
    // ≈ 278 spm (not a human walking) are both dropped. Only the three real
    // minutes remain — exactly the minimum.
    expect(sessionCadenceSpm(const [20, 250, 90, 100, 110]), 111);
    // Drop one of the three and there is no longer enough to report.
    expect(sessionCadenceSpm(const [20, 250, 90, 100]), isNull);
  });

  test('even minute counts take the mean of the two middle minutes', () {
    // raw 90/100/110/120 → 100/111/122/133; median of the middle two = 116.5
    // → 117.
    expect(sessionCadenceSpm(const [90, 100, 110, 120]), 117);
  });
}
