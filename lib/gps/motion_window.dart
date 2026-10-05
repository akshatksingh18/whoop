// The phone's own motion data over one session window: steps and distance per
// minute, from CMPedometer (`PedometerBridge.motionWindow`). Two uses:
//
//  * the exact steps a run took, so maintenance can take them off the day's
//    steps before costing the rest as walking (no double counting);
//  * distance, cadence and splits for a run that was not recorded with GPS,
//    as long as the phone was carried.
//
// The phone only keeps seven days, so the first answer is saved per session
// and window and used from then on.

import 'dart:convert';
import 'workout_clock.dart';
import '../data/calculation_store.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The phone-steps channel (`PedometerBridge` in AppDelegate.swift).
const MethodChannel _channel = MethodChannel('openstrap/phone_steps');

class MotionWindow {
  final DateTime start;
  final int chunkSec;
  final List<int> steps;

  /// Metres per chunk; null where the phone gave steps but no distance.
  final List<double?> meters;

  final List<double>? seconds;
  final List<int>? timesMs;
  const MotionWindow(
    this.start,
    this.chunkSec,
    this.steps,
    this.meters, {
    this.seconds,
    this.timesMs,
  });
  double secondsAt(int i) => seconds != null && i < seconds!.length
      ? seconds![i]
      : chunkSec.toDouble();
  int timeAt(int i) => timesMs != null && i < timesMs!.length
      ? timesMs![i]
      : start.millisecondsSinceEpoch + i * chunkSec * 1000;

  int get totalSteps => steps.fold(0, (a, b) => a + b);

  /// Total distance, or null when the phone gave none for any chunk.
  double? get totalMeters {
    if (meters.every((m) => m == null)) return null;
    return meters.fold<double>(0, (a, m) => a + (m ?? 0));
  }

  /// Minutes with steps in them.
  double get activeMinutes =>
      [
        for (var i = 0; i < steps.length; i++)
          if (steps[i] > 0) secondsAt(i),
      ].fold<double>(0, (a, b) => a + b) /
      60;

  /// Average cadence over the minutes with steps, steps per minute.
  double? get cadence {
    final mins = activeMinutes;
    return mins <= 0 ? null : totalSteps / mins;
  }

  /// Per-kilometre splits from the cumulative distance, each kilometre's
  /// crossing time interpolated inside its chunk. [hrAtMinute] gives each
  /// split's mean heart rate from the band's per-minute curve.
  List<({double km, int sec, int? hr})> splits({
    double? Function(int minute)? hrAtMinute,
  }) {
    if (totalMeters == null) return const [];
    final out = <({double km, int sec, int? hr})>[];
    var cum = 0.0, lastT = 0.0, nextKm = 1000.0, lastKmM = 0.0;
    int? hrMean(double fromSec, double toSec) {
      if (hrAtMinute == null) return null;
      final v = <double>[];
      for (
        var m = (fromSec / 60).floor();
        m <= ((toSec - 1) / 60).floor();
        m++
      ) {
        final h = hrAtMinute(m);
        if (h != null) v.add(h);
      }
      return v.isEmpty ? null : (v.reduce((a, b) => a + b) / v.length).round();
    }

    var elapsed = 0.0;
    for (var i = 0; i < meters.length; i++) {
      final m = meters[i] ?? 0;
      final t0 = elapsed;
      final duration = secondsAt(i);
      while (m > 0 && cum + m >= nextKm) {
        final t = t0 + (nextKm - cum) / m * duration;
        out.add((km: 1, sec: (t - lastT).round(), hr: hrMean(lastT, t)));
        lastT = t;
        lastKmM = nextKm;
        nextKm += 1000;
      }
      cum += m;
      elapsed += duration;
    }
    final rest = cum - lastKmM;
    final end = elapsed;
    if (rest >= 50 && end > lastT) {
      out.add((
        km: rest / 1000,
        sec: (end - lastT).round(),
        hr: hrMean(lastT, end),
      ));
    }
    return out;
  }

  /// Clip measured chunks with cumulative rounding, preserving their duration.
  /// Sub-minute distance is apportioned within the measured chunk, never across gaps.
  MotionWindow within(List<ActiveWindow> windows) {
    final counts = <int>[],
        distances = <double?>[],
        durations = <double>[],
        times = <int>[];
    for (var i = 0; i < steps.length; i++) {
      final lo = timeAt(i), hi = lo + (secondsAt(i) * 1000).round();
      if (hi <= lo) continue;
      for (final w in windows) {
        final a = w.start.millisecondsSinceEpoch.clamp(lo, hi),
            b = w.end.millisecondsSinceEpoch.clamp(lo, hi);
        if (b <= a) continue;
        counts.add(
          (steps[i] * (b - lo) / (hi - lo)).round() -
              (steps[i] * (a - lo) / (hi - lo)).round(),
        );
        distances.add(
          meters[i] == null ? null : meters[i]! * (b - a) / (hi - lo),
        );
        durations.add((b - a) / 1000);
        times.add(a);
      }
    }
    return MotionWindow(
      start,
      chunkSec,
      counts,
      distances,
      seconds: durations,
      timesMs: times,
    );
  }

  Map<String, Object?> toJson() => {
    's': start.millisecondsSinceEpoch,
    'c': chunkSec,
    'steps': steps,
    'm': meters,
    'seconds': seconds,
    'times': timesMs,
  };

  static MotionWindow? fromJson(Object? j) {
    if (j is! Map) return null;
    final s = j['s'], c = j['c'], st = j['steps'], m = j['m'];
    if (s is! int ||
        c is! int ||
        c <= 0 ||
        st is! List ||
        m is! List ||
        m.length != st.length) {
      return null;
    }
    if (st.any((x) => x is! num || !x.isFinite || x < 0) ||
        m.any((x) => x != null && (x is! num || !x.isFinite || x < 0))) {
      return null;
    }
    final sec = j['seconds'], times = j['times'];
    if (sec != null &&
        (sec is! List ||
            sec.length != st.length ||
            sec.any((x) => x is! num || !x.isFinite || x <= 0 || x > c))) {
      return null;
    }
    if (times != null &&
        (times is! List ||
            times.length != st.length ||
            times.any((x) => x is! num || !x.isFinite))) {
      return null;
    }
    return MotionWindow(
      DateTime.fromMillisecondsSinceEpoch(s),
      c,
      [for (final x in st) (x as num).toInt()],
      [for (final x in m) x == null ? null : (x as num).toDouble()],
      seconds: sec is List
          ? [for (final x in sec) (x as num).toDouble()]
          : null,
      timesMs: times is List
          ? [for (final x in times) (x as num).toInt()]
          : null,
    );
  }
}

/// The saved answer for this window, or a fresh one from the phone (saved for
/// next time). Null when the phone was not counting, the window is older than
/// the phone keeps, motion access is off, or this is not an iPhone.
///
/// A window the phone can no longer answer is remembered as "none" so it is
/// not asked about on every open.
Future<MotionWindow?> motionWindow(
  String sessionId,
  DateTime start,
  DateTime end, {
  bool cacheResult = false,
}) async {
  if (sessionId.isEmpty || !end.isAfter(start)) return null;
  final key =
      'motion.$sessionId.${start.millisecondsSinceEpoch ~/ 1000}-'
      '${end.millisecondsSinceEpoch ~/ 1000}';
  SharedPreferences? prefs;
  try {
    prefs = await SharedPreferences.getInstance();
    final saved = await CalculationStore.read(key);
    if (saved == 'none' &&
        start.isBefore(DateTime.now().subtract(const Duration(days: 7)))) {
      return null;
    }
    if (saved == 'none') await CalculationStore.remove(key);
    if (saved != null && saved != 'none') {
      final w = MotionWindow.fromJson(jsonDecode(saved));
      if (w != null) {
        if (w.seconds != null) return w;
        return MotionWindow(
          w.start,
          w.chunkSec,
          w.steps,
          w.meters,
          seconds: [
            for (var i = 0; i < w.steps.length; i++)
              (end.difference(start).inMilliseconds / 1000 - i * w.chunkSec)
                  .clamp(0, w.chunkSec)
                  .toDouble(),
          ],
        );
      }
    }
  } catch (_) {
    // A store that cannot be read is asked again below.
  }
  if (defaultTargetPlatform != TargetPlatform.iOS) return null;
  // Still in progress: answer it, but do not save a window that will grow.
  final live = end.isAfter(DateTime.now().subtract(const Duration(minutes: 2)));
  try {
    final r = await _channel.invokeMethod<Object?>('motionWindow', {
      'fromMs': start.millisecondsSinceEpoch,
      'toMs': end.millisecondsSinceEpoch,
      'chunkSec': 60,
    });
    if (r == -1) {
      if (start.isBefore(DateTime.now().subtract(const Duration(days: 7)))) {
        await prefs?.setString(key, 'none');
      }
      return null;
    }
    if (r is! Map) return null;
    final chunkSec = (r['chunkSec'] as num?)?.toInt() ?? 60;
    if (chunkSec <= 0 || r['steps'] is! List || r['meters'] is! List) {
      return null;
    }
    final raw = r['meters'] as List;
    final st = r['steps'] as List;
    final seconds = [
      for (var i = 0; i < st.length; i++)
        (end.difference(start).inMilliseconds / 1000 - i * chunkSec)
            .clamp(0, chunkSec)
            .toDouble(),
    ];
    final w = MotionWindow.fromJson({
      's': start.millisecondsSinceEpoch,
      'c': chunkSec,
      'steps': st,
      'm': [
        for (final m in raw)
          if (m is num && m.isFinite) m < 0 ? null : m else m,
      ],
      'seconds': seconds,
    });
    if (w == null) return null;
    // A window with no steps at all: the phone was left behind. Remembered as
    // "none" so the run keeps time and heart rate only.
    // Confirmed zero is usable evidence; the shared source resolver decides
    // whether a dense wrist-only interval can supplement it.
    if (!live || cacheResult) {
      await CalculationStore.write(key, jsonEncode(w.toJson()));
    }
    return w;
  } on PlatformException catch (e) {
    debugPrint('[motion] $e');
    return null;
  } on MissingPluginException {
    return null;
  }
}

/// Pauses stay in daily movement, but are excluded from this session.
Future<MotionWindow?> sessionMotionWindow(
  String id,
  DateTime start,
  DateTime end,
) async {
  final completed = WorkoutClock.read(id, start).end != null;
  final clock = WorkoutClock.read(id, start, end: end);
  final steps = <int>[],
      meters = <double?>[],
      seconds = <double>[],
      times = <int>[];
  final windows = <ActiveWindow>[];
  for (final active in clock.windows()) {
    var at = active.start;
    while (at.isBefore(active.end)) {
      final midnight = DateTime(at.year, at.month, at.day + 1);
      final stop = midnight.isBefore(active.end) ? midnight : active.end;
      windows.add((start: at, end: stop));
      at = stop;
    }
  }
  for (final active in windows) {
    final w = await motionWindow(
      id,
      active.start,
      active.end,
      cacheResult: completed,
    );
    if (w == null) {
      return null; // A partial answer must not claim full coverage.
    }
    for (var i = 0; i < w.steps.length; i++) {
      steps.add(w.steps[i]);
      meters.add(i < w.meters.length ? w.meters[i] : null);
      seconds.add(w.secondsAt(i));
      times.add(w.timeAt(i));
    }
  }
  return steps.isEmpty
      ? null
      : MotionWindow(
          start,
          60,
          steps,
          meters,
          seconds: seconds,
          timesMs: times,
        );
}
