// Local Run/Walk ActivityKit bridge. Missing platform support is harmless.
import 'package:flutter/services.dart';
import '../build_profile.dart';
import '../gps/run_history.dart';

/// Running and walking sessions (treadmill is running) get a lock-screen
/// activity. Other workouts deliberately do not.
///
/// Never in the personal build (build 81): Sideloadly's free signing provisions
/// only the app's own App ID, so iOS kills the extension at launch on a
/// code-signing check and the activity can never draw. The personal IPA no
/// longer embeds the extension; nothing is requested.
bool liveActivityEligible(String? type) =>
    !kPersonalSideload && (isRunType(type) || isWalkType(type));

class LiveActivity {
  static const MethodChannel _ch = MethodChannel('openstrap/live_activity');
  static bool _active = false;

  /// Why the last start/update did or did not reach the lock screen, in the
  /// bridge's words ("started", "Live Activities are off…"). Null off iOS.
  static String? lastReason;
  static bool _ok(Object? r) {
    if (r is Map) {
      lastReason = r['reason']?.toString();
      return r['ok'] == true;
    }
    return r == true;
  }

  /// What iOS reports about Live Activities for this install. Empty off iOS.
  static Future<Map<String, Object?>> status() => _map('status');

  /// Put a one-minute sample on the lock screen and report what happened.
  static Future<Map<String, Object?>> test() => _map('test');

  static Future<Map<String, Object?>> _map(String method) async {
    try {
      final r = await _ch.invokeMethod<Object?>(method);
      return r is Map ? r.cast<String, Object?>() : const {};
    } catch (_) {
      return const {};
    }
  }

  static Future<void> _tail = Future.value();
  static int _epoch = 0;
  static String? _session;
  static bool get isActive => _active;
  static void Function(String id)? onSession;
  static Future<void> listen() async {
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'openSession' && call.arguments is String) {
        onSession?.call(call.arguments as String);
      }
    });
    try {
      final id = await _ch.invokeMethod<String>('pendingSession');
      if (id != null && id.isNotEmpty) onSession?.call(id);
    } catch (_) {
      /* not iOS */
    }
  }

  static Future<void> update({
    required String id,
    required String type,
    required int elapsed,
    required bool paused,
    required double? distanceKm,
    required int? hr,
    int? zone,
    int? lastKmSeconds,
  }) async {
    if (!liveActivityEligible(type)) return;
    if (_session != id) {
      _session = id;
      _epoch++;
    }
    final epoch = _epoch, previous = _tail;
    final job = () async {
      await previous;
      if (epoch != _epoch) return;
      try {
        _active = _ok(
          await _ch.invokeMethod<Object?>('update', {
            'id': id,
            'name': isWalkType(type) ? 'Walking' : 'Running',
            'elapsed': elapsed,
            'paused': paused,
            'distanceKm': distanceKm,
            'paceSeconds': distanceKm != null && distanceKm >= .05 && !paused
                ? elapsed / distanceKm
                : null,
            'hr': hr,
            'zone': hr == null ? null : zone,
            'lastKmSeconds': lastKmSeconds,
          }),
        );
      } catch (_) {
        _active = false;
      }
    }();
    _tail = job;
    await job;
  }

  static Future<void> end() async {
    _epoch++;
    _session = null;
    final previous = _tail;
    final job = () async {
      await previous;
      try {
        await _ch.invokeMethod('end');
      } catch (_) {
        /* unsupported */
      }
      _active = false;
    }();
    _tail = job;
    await job;
  }
}
