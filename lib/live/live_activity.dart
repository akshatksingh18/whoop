// Local Run/Walk ActivityKit bridge. Missing platform support is harmless.
import 'package:flutter/services.dart';
import '../gps/run_history.dart';

class LiveActivity {
  static const MethodChannel _ch = MethodChannel('openstrap/live_activity');
  static bool _active = false;
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
    if (!(isRunType(type) || isWalkType(type))) return;
    if (_session != id) {
      _session = id;
      _epoch++;
    }
    final epoch = _epoch, previous = _tail;
    final job = () async {
      await previous;
      if (epoch != _epoch) return;
      try {
        _active =
            await _ch.invokeMethod<bool>('update', {
              'id': id,
              'name': isRunType(type) ? 'Running' : 'Walking',
              'elapsed': elapsed,
              'paused': paused,
              'distanceKm': distanceKm,
              'paceSeconds': distanceKm != null && distanceKm >= .05 && !paused
                  ? elapsed / distanceKm
                  : null,
              'hr': hr,
              'zone': hr == null ? null : zone,
              'lastKmSeconds': lastKmSeconds,
            }) ??
            false;
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
