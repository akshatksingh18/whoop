// device_actions.dart — the Dart side of the `openstrap/device_actions` method
// channel. Mirrors the edge_tracking / live_activity bridges: a thin wrapper that
// asks native what it can do (capabilities) and tells it to do one thing (perform).
//
// Native handlers, both registered at engine attach:
//   Android — NativeChannels.kt (`DEVICE_ACTIONS_CHANNEL` + its `perform`).
//   iOS     — the `ActionBridge` enum in ios/Runner/AppDelegate.swift.
// There is no ActionHandler.kt and no ActionBridge.swift; this comment used to name
// both, which is two files' worth of grep that finds nothing.
//
// All actions use no-risk OS APIs (media-key dispatch, system volume, a ringtone +
// vibrate, torch) — no special runtime permissions beyond VIBRATE (a normal
// permission). In-app actions never reach this channel at all; the dispatcher
// handles them in Dart.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class DeviceActions {
  static const _ch = MethodChannel('openstrap/device_actions');

  /// The set of action ids this OS+device can actually perform. The settings UI
  /// uses this to hide unsupported actions (e.g. system volume on iOS). Returns an
  /// empty set if native isn't reachable — the UI then offers only `none`.
  static Future<Set<String>> capabilities() async {
    try {
      final r = await _ch.invokeMethod<List<dynamic>>('capabilities');
      return (r ?? const []).map((e) => e.toString()).toSet();
    } catch (e) {
      debugPrint('[device_actions] capabilities failed: $e');
      return <String>{};
    }
  }

  /// Execute one action by its wire id. Returns true on success. Never throws —
  /// a gesture failing is never worth crashing a background isolate over.
  static Future<bool> perform(String actionId) async {
    try {
      final ok = await _ch.invokeMethod<bool>('perform', {'action': actionId});
      return ok ?? false;
    } catch (e) {
      debugPrint('[device_actions] perform($actionId) failed: $e');
      return false;
    }
  }
}
