// gesture_settings.dart — the persisted band-gesture → action mapping, plus the
// per-platform set of supported actions. Same persistence pattern as ThemeController
// (SharedPreferences) and same ChangeNotifier shape so the settings UI rebuilds and
// the dispatcher reads a live value.

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../platform/device_actions.dart';
import 'device_action.dart';

class GestureSettings extends ChangeNotifier {
  static const _kDoubleTap = 'gesture_double_tap';

  /// What a double-tap currently does. Defaults to nothing — opt-in, so we never
  /// surprise a user (or pay the iOS bg keep-alive cost) until they pick an action.
  DeviceAction doubleTap = DeviceAction.none;

  /// Actions offerable on THIS platform: `none` always, plus whatever native says
  /// it can do. Until bootstrap() runs we only know `none`.
  Set<DeviceAction> supported = {DeviceAction.none};

  /// Load the saved mapping and query native capabilities. Call once at startup.
  Future<void> bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    doubleTap = DeviceActionX.fromId(prefs.getString(_kDoubleTap)) ?? DeviceAction.none;

    final caps = await DeviceActions.capabilities();
    supported = {
      DeviceAction.none,
      // In-app actions act on our own app, so they're offerable everywhere.
      ...DeviceAction.values.where((a) => a.isInApp),
      // Native actions: only what this platform reported it can do.
      ...caps.map(DeviceActionX.fromId).whereType<DeviceAction>(),
    };

    // If a previously-chosen action isn't supported here (e.g. settings synced from
    // an Android backup onto an iPhone), fall back to none rather than silently
    // mapping to something unsupported.
    if (!supported.contains(doubleTap)) {
      doubleTap = DeviceAction.none;
      await prefs.setString(_kDoubleTap, doubleTap.id);
    }
    notifyListeners();
  }

  Future<void> setDoubleTap(DeviceAction action) async {
    if (action == doubleTap) return;
    doubleTap = action;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDoubleTap, action.id);
    notifyListeners();
  }

}
