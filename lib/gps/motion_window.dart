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

  const MotionWindow(this.start, this.chunkSec, this.steps, this.meters);

  int get totalSteps => steps.fold(0, (a, b) => a + b);

  /// Total distance, or null when the phone gave none for any chunk.
  double? get totalMeters {
    if (meters.every((m) => m == null)) return null;
    return meters.fold<double>(0, (a, m) => a + (m ?? 0));
  }

  /// Minutes with steps in them.
  double get activeMinutes =>
      steps.where((s) => s > 0).length * chunkSec / 60;

  /// Average cadence over the minutes with steps, steps per minute.
  double? get cadence {
    final mins = activeMinutes;
    return mins <= 0 ? null : totalSteps / mins;
  }

  /// Per-kilometre splits from the cumulative distance, each kilometre's
  /// crossing time interpolated inside its chunk. [hrAtMinute] gives each
  /// split's mean heart rate from the band's per-minute curve.
  List<({double km, int sec, int? hr})> splits({double? Function(int minute)? hrAtMinute}) {
    if (totalMeters == null) return const [];
    final out = <({double km, int sec, int? hr})>[];
    var cum = 0.0, lastT = 0.0, nextKm = 1000.0, lastKmM = 0.0;
    int? hrMean(double fromSec, double toSec) {
      if (hrAtMinute == null) return null;
      final v = <double>[];
      for (var m = (fromSec / 60).floor(); m <= ((toSec - 1) / 60).floor(); m++) {
        final h = hrAtMinute(m);
        if (h != null) v.add(h);
      }
      return v.isEmpty ? null : (v.reduce((a, b) => a + b) / v.length).round();
    }

    for (var i = 0; i < meters.length; i++) {
      final m = meters[i] ?? 0;
      final t0 = i * chunkSec.toDouble();
      while (m > 0 && cum + m >= nextKm) {
        final t = t0 + (nextKm - cum) / m * chunkSec;
        out.add((km: 1, sec: (t - lastT).round(), hr: hrMean(lastT, t)));
        lastT = t;
        lastKmM = nextKm;
        nextKm += 1000;
      }
      cum += m;
    }
    final rest = cum - lastKmM;
    final end = meters.length * chunkSec.toDouble();
    if (rest >= 50 && end > lastT) {
      out.add(
          (km: rest / 1000, sec: (end - lastT).round(), hr: hrMean(lastT, end)));
    }
    return out;
  }

  Map<String, Object?> toJson() => {
        's': start.millisecondsSinceEpoch,
        'c': chunkSec,
        'steps': steps,
        'm': meters,
      };

  static MotionWindow? fromJson(Object? j) {
    if (j is! Map) return null;
    final s = j['s'], c = j['c'], st = j['steps'], m = j['m'];
    if (s is! int || c is! int || st is! List || m is! List) return null;
    return MotionWindow(
      DateTime.fromMillisecondsSinceEpoch(s),
      c,
      [for (final x in st) (x as num).toInt()],
      [for (final x in m) x == null ? null : (x as num).toDouble()],
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
    String sessionId, DateTime start, DateTime end) async {
  if (sessionId.isEmpty || !end.isAfter(start)) return null;
  final key = 'motion.$sessionId.${start.millisecondsSinceEpoch ~/ 1000}-'
      '${end.millisecondsSinceEpoch ~/ 1000}';
  SharedPreferences? prefs;
  try {
    prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(key);
    if (saved == 'none') return null;
    if (saved != null) return MotionWindow.fromJson(jsonDecode(saved));
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
      await prefs?.setString(key, 'none');
      return null;
    }
    if (r is! Map) return null;
    final steps = [for (final x in (r['steps'] as List? ?? const [])) (x as num).toInt()];
    final raw = [for (final x in (r['meters'] as List? ?? const [])) (x as num).toDouble()];
    final w = MotionWindow(
      start,
      (r['chunkSec'] as num?)?.toInt() ?? 60,
      steps,
      [for (final m in raw) m < 0 ? null : m],
    );
    // A window with no steps at all: the phone was left behind. Remembered as
    // "none" so the run keeps time and heart rate only.
    if (w.totalSteps == 0) {
      if (!live) await prefs?.setString(key, 'none');
      return null;
    }
    if (!live) await prefs?.setString(key, jsonEncode(w.toJson()));
    return w;
  } on PlatformException catch (e) {
    debugPrint('[motion] $e');
    return null;
  } on MissingPluginException {
    return null;
  }
}
