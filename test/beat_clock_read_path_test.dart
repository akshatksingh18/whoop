// The beat clock, end to end through the read path.
//
// `decoded_rr` carries two time columns. `rr_ts_ms` is `rec_ts * 1000` — a
// whole-second staircase that says every beat inside one record happened at the
// same millisecond. `beat_ts_ms` is where the beat actually was. Until now the
// read path took the staircase and the measured column was write-only.
//
// The contract this file pins:
//   1. The INTERVAL series does not move — same values, same order — so
//      `hrvTime(nn)` with no time axis is bit-identical. If THAT moves,
//      something other than the clock changed. (RMSSD/pNNx as production calls
//      them, `hrvTime(nn, nnTimesMs: …)`, DO shift a little: the axis decides
//      which successive pairs count as contiguous. Measured at +0.03% RMSSD /
//      +0.6% pNN50 over a real 6 h block. SDNN never pairs, so it never moves.)
//   2. The TIME AXIS does move — that is the whole point.
//   3. A NULL `beat_ts_ms` (every row banked before the column existed, every
//      source with no sub-second) falls back to the staircase. Never fabricated.
//   4. A beat whose second has no `decoded_onehz` row still reaches the
//      substrate, on a second of its own with ABSENT sensors.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_analytics/onehz.dart';
import 'package:openstrap_edge/compute/derive_prepare.dart';

const _t0 = 1780000000;

Map<String, dynamic> _frame(int recTs) => {
  'rec_ts': recTs,
  'hr': 58,
  'ax': 0.0,
  'ay': 0.0,
  'az': 1.0,
  'spo2_red_raw': 1000,
  'spo2_ir_raw': 1000,
  'skin_temp_raw': 2000,
  'device_family': 'gen4',
};

Map<String, dynamic> _beat(int recTs, int index, int rrMs, {int? beatTsMs}) => {
  'rec_ts': recTs,
  'beat_index': index,
  'rr_ts_ms': recTs * 1000,
  'rr_ms': rrMs,
  'beat_ts_ms': beatTsMs,
};

/// A minute of records with two beats each, placed by the strap's own
/// sub-second anchor — which drifts, the way a real 32 kHz RTC does, so the
/// gap between one record's last beat and the next record's first is a real
/// sub-second quantity and not a multiple of 1,000 ms.
({List<Map<String, dynamic>> frames, List<Map<String, dynamic>> beats})
_night() {
  final frames = <Map<String, dynamic>>[];
  final beats = <Map<String, dynamic>>[];
  for (var s = 0; s < 60; s++) {
    final recTs = _t0 + s;
    frames.add(_frame(recTs));
    // The record's own sub-second (32 kHz RTC), drifting the way a real one
    // does rather than sitting on the whole second.
    final anchorMs = recTs * 1000 + (s * 37) % 1000;
    // Two beats: the last at the anchor, the earlier one its interval before.
    final rrLate = 900 + (s % 5) * 10;
    final rrEarly = 920 + (s % 3) * 10;
    beats.add(_beat(recTs, 0, rrEarly, beatTsMs: anchorMs - rrLate));
    beats.add(_beat(recTs, 1, rrLate, beatTsMs: anchorMs));
  }
  return (frames: frames, beats: beats);
}

void main() {
  test('beat_ts_ms reaches the substrate and rr_ms is untouched', () {
    final n = _night();
    final measured = substrateFromDecodedPage(n.frames, n.beats);
    final staircase = substrateFromDecodedPage(n.frames, [
      for (final b in n.beats) {...b}..['beat_ts_ms'] = null,
    ]);

    // 1. INTERVALS ARE IDENTICAL — same values, same order.
    expect(measured.rrMs, staircase.rrMs);
    final mc = correctRr(measured.rrMs, rrTsMs: measured.rrTsMs);
    final sc = correctRr(staircase.rrMs, rrTsMs: staircase.rrTsMs);
    // The CLEANED interval series too — the Lipponen-Tarvainen correction
    // rejects on interval shape, not on where the beat sits.
    expect(mc.nn, sc.nn);
    // …so time-domain HRV off the intervals alone is bit-identical. SDNN stays
    // identical even WITH the axis, because it never pairs.
    final mHrv = hrvTime(mc.nn), sHrv = hrvTime(sc.nn);
    expect(mHrv.value?.rmssd, sHrv.value?.rmssd);
    expect(mHrv.value?.pnn50, sHrv.value?.pnn50);
    expect(
      hrvTime(mc.nn, nnTimesMs: mc.nnTimesMs).value?.sdnn,
      hrvTime(sc.nn, nnTimesMs: sc.nnTimesMs).value?.sdnn,
    );

    // 2. THE AXIS MOVED. The staircase pins both beats of a record to the same
    //    millisecond; the measured clock separates them by their own interval.
    expect(staircase.rrTsMs[0], staircase.rrTsMs[1]);
    expect(
      measured.rrTsMs[1] - measured.rrTsMs[0],
      measured.rrMs[1],
      reason: 'the spacing IS the interval',
    );
    expect(measured.rrTsMs, isNot(staircase.rrTsMs));

    // EVERY inter-record gap is a whole second on the staircase — which is the
    // reason a sub-second dropout is unrepresentable there, not merely
    // undetected. On the measured clock the same gaps are real.
    final crossings = [for (var r = 1; r < 60; r++) r * 2]; // first beat of r
    for (final i in crossings) {
      expect(staircase.rrTsMs[i] - staircase.rrTsMs[i - 1], 1000);
    }
    expect(
      crossings
          .where((i) => measured.rrTsMs[i] - measured.rrTsMs[i - 1] != 1000)
          .length,
      crossings.length,
      reason: 'no measured crossing lands on a whole second by accident',
    );
  });

  test('a NULL beat_ts_ms falls back to rr_ts_ms — never fabricated', () {
    final sub = substrateFromDecodedPage(
      [_frame(_t0)],
      [_beat(_t0, 0, 900), _beat(_t0, 1, 910)],
    );
    expect(sub.rrTsMs, [_t0 * 1000.0, _t0 * 1000.0]);
  });

  test('a beat with no 1 Hz frame still becomes a second, sensors absent', () {
    // Exactly what gen4 historical R10-lite writes: an R-R block with no
    // decoded_onehz row (db.dart _queueDecodedOneHz). It used to be dropped.
    final sub = substrateFromDecodedPage(
      [_frame(_t0), _frame(_t0 + 2)],
      [
        _beat(_t0, 0, 900, beatTsMs: _t0 * 1000 + 400),
        _beat(_t0 + 1, 0, 910, beatTsMs: (_t0 + 1) * 1000 + 300),
        _beat(_t0 + 2, 0, 905, beatTsMs: (_t0 + 2) * 1000 + 200),
      ],
    );
    expect(sub.tsSec, [_t0, _t0 + 1, _t0 + 2], reason: 'union, still ascending');
    expect(sub.rrMs.length, 3, reason: 'the orphan beat survived');
    // The beat-only second carries no measurement — the absent sentinels only.
    expect(sub.accelPresentAt(1), isFalse);
    expect(sub.hr[1], 0);
    expect(sub.skinTemp[1], 0);
    // …and the frame-backed seconds are untouched.
    expect(sub.accelPresentAt(0), isTrue);
    expect(sub.hr[0], 58);
  });
}
