import 'dart:math' as math;

/// Record presence, independent of optical HR validity. Input is chronological.
/// Gaps of at most two minutes bridge a run; longer gaps carry no wear evidence.
List<List<int>> recordedWearRuns(List<int> timestamps) {
  final runs = <List<int>>[];
  for (final ts in timestamps) {
    if (runs.isEmpty || ts - (runs.last[1] - 1) > 120) {
      runs.add([ts, ts + 1]);
    } else if (ts >= runs.last[1]) {
      runs.last[1] = ts + 1;
    }
  }
  return runs;
}

/// Count touched epoch-minute buckets after bridging, without enumerating them.
int recordedWornMinutes(List<int> timestamps) {
  var count = 0;
  int? lastMinute;
  for (final run in recordedWearRuns(timestamps)) {
    final first = run[0] ~/ 60;
    final last = (run[1] - 1) ~/ 60;
    final next = lastMinute == null ? first : math.max(first, lastMinute + 1);
    if (last >= next) count += last - next + 1;
    lastMinute = last;
  }
  return count;
}

/// Separate measured wear, reported states, missing records and the unsynced tail.
/// [frontierSec] is exclusive: no report beyond it establishes an off-wrist state.
Map<String, dynamic> dayWearBlock(
  List<int> timestamps, {
  required int startSec,
  required int endSec,
  required int frontierSec,
  List<List<int>> offWrist = const [],
  List<List<int>> charging = const [],
}) {
  final end = math.max(startSec, endSec);
  final frontier = frontierSec.clamp(startSec, end).toInt();
  final ts = timestamps.where((t) => t >= startSec && t < frontier).toList();
  final runs = recordedWearRuns(ts);
  List<List<int>> orderedSpans(List<List<int>> input) =>
      input.where((s) => s.length >= 2 && s[1] > s[0]).toList()
        ..sort((a, b) => a[0].compareTo(b[0]));
  final off = orderedSpans(offWrist), charge = orderedSpans(charging);
  final edges = <int>{startSec, end, frontier};
  for (final spans in [runs, off, charge]) {
    for (final span in spans) {
      if (span.length < 2) continue;
      edges.add(span[0].clamp(startSec, end).toInt());
      edges.add(span[1].clamp(startSec, end).toInt());
    }
  }
  final ordered = edges.toList()..sort();
  final positions = <int>[0, 0, 0];
  bool covers(List<List<int>> spans, int channel, int t) {
    var index = positions[channel];
    while (index < spans.length && spans[index][1] <= t) {
      index++;
    }
    positions[channel] = index;
    return index < spans.length && spans[index][0] <= t;
  }

  final segments = <Map<String, dynamic>>[];
  var wornSec = 0, longestOff = 0;
  for (var i = 1; i < ordered.length; i++) {
    final lo = ordered[i - 1], hi = ordered[i];
    if (hi <= lo) continue;
    final recorded = lo < frontier && covers(runs, 0, lo);
    if (recorded) wornSec += hi - lo;
    final state = lo >= frontier
        ? 'pending'
        : covers(charge, 2, lo)
            ? 'charging'
            : covers(off, 1, lo)
                ? 'off_wrist'
                : recorded
                    ? 'worn'
                    : 'missing';
    if (segments.isNotEmpty &&
        segments.last['state'] == state &&
        segments.last['on'] == recorded) {
      segments.last['end'] = hi;
      segments.last['len_min'] = (hi - (segments.last['start'] as int)) / 60;
    } else {
      segments.add({
        'on': recorded,
        'state': state,
        'start': lo,
        'end': hi,
        'len_min': (hi - lo) / 60
      });
    }
    if (state == 'off_wrist') {
      longestOff = math.max(longestOff, hi - (segments.last['start'] as int));
    }
  }
  return {
    'segments': segments,
    'first_on': ts.isEmpty ? null : ts.first,
    'last_on': ts.isEmpty ? null : ts.last + 1,
    'frontier_ts': frontier,
    'longest_off_min': (longestOff / 60).round(),
    'worn_min': recordedWornMinutes(ts),
    'coverage_pct': frontier > startSec
        ? (100 * wornSec / (frontier - startSec)).round().clamp(0, 100)
        : null,
  };
}
