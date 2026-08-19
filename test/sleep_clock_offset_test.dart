// SLP-09 / L10 — mid-sleep and sleep onset, stored UNWRAPPED.
//
// The whole reason this is not a plain second-of-day: 23:30 -> 01:30 is a
// two-hour shift that reads as MINUS 22 hours on a wrapped axis, and binary
// segmentation over that series finds a beautiful change-point which is a
// modulo artifact and nothing about the person. These checks are the guard.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/onehz_pipeline.dart';

/// Epoch second of a local wall-clock time on a fixed date.
int _localAt(int hour, int minute, {int day = 15}) =>
    DateTime(2026, 6, day, hour, minute).millisecondsSinceEpoch ~/ 1000;

void main() {
  test('a shift across midnight is a small positive number, not minus 22 h',
      () {
    final before = sleepClockOffsetSec(_localAt(23, 30))!; // bedtime 23:30
    final after = sleepClockOffsetSec(_localAt(1, 30, day: 16))!; // 01:30
    expect(after - before, closeTo(2 * 3600, 1));
    // Both sit on the same continuous stretch of the axis — negative, because
    // both are before the 04:00 anchor.
    expect(before, lessThan(0));
    expect(after, lessThan(0));
  });

  test('the anchor is 04:00 local and either side of it is signed', () {
    expect(sleepClockOffsetSec(_localAt(4, 0)), 0);
    expect(sleepClockOffsetSec(_localAt(3, 0)), -3600);
    expect(sleepClockOffsetSec(_localAt(5, 0)), 3600);
  });

  test('a normal night never lands near the wrap', () {
    // 20:00 through 11:00 is the whole plausible overnight span; the axis is
    // (-12 h, +12 h], so nothing in that range is within an hour of an edge.
    for (final h in [20, 22, 23, 0, 2, 4, 7, 9, 11]) {
      final v = sleepClockOffsetSec(_localAt(h, 0))!.abs();
      expect(v, lessThan(11 * 3600), reason: 'hour $h sits near the wrap');
    }
  });

  test('an absent window is absent, not 04:00', () {
    // 0 is a REAL reading here (exactly 04:00), so absence cannot use it.
    expect(sleepClockOffsetSec(0), isNull);
    expect(sleepClockOffsetSec(-1), isNull);
  });
}
