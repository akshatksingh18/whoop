// The live summary drew a band dropout as a continuous line.
//
// `perMinuteHr()` only grew when a minute HAD samples, so a 40-minute session
// with a ten-minute dropout produced a 30-entry list. The summary that opens
// the moment you press stop maps index to x, so minute 9 was joined straight
// to minute 21 and every later reading was drawn ten minutes early — while the
// same session reopened from History was dense and showed the gap correctly.
// Two paths, one session, two different pictures.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/state/app_state.dart' show LiveWorkoutState;

LiveWorkoutState _session() =>
    LiveWorkoutState(startTime: DateTime.now(), targetKcal: 300, age: 30);

void main() {
  test('a dropout is a hole, and the index stays the session minute', () {
    final w = _session();
    // Ten minutes of samples, ten minutes of nothing, then ten more.
    for (var m = 0; m < 10; m++) {
      w.elapsed = Duration(minutes: m);
      w.accrueHr(140);
    }
    for (var m = 20; m < 30; m++) {
      w.elapsed = Duration(minutes: m);
      w.accrueHr(150);
    }

    final dense = w.perMinuteHrDense();
    expect(dense.length, 30,
        reason: 'index is the session minute, so the list spans the session');
    expect(dense.sublist(0, 10), everyElement(140.0));
    expect(dense.sublist(10, 20), everyElement(isNull),
        reason: 'the band recorded nothing here; a value would be invented');
    expect(dense[29], 150.0);
  });

  test('statistics ignore the holes rather than averaging zeros in', () {
    final w = _session();
    w.elapsed = Duration.zero;
    w.accrueHr(100);
    w.elapsed = const Duration(minutes: 9);
    w.accrueHr(200);

    // Ten slots, two readings.
    expect(w.perMinuteHrDense().length, 10);
    expect(w.perMinuteHr(), [100.0, 200.0]);
    // Mean over the readings is 150. Over ten slots with nulls read as zero it
    // would be 30, which is the failure this guards.
    final v = w.perMinuteHr();
    expect(v.reduce((a, b) => a + b) / v.length, 150.0);
  });
}
