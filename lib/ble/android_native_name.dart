// android_native_name.dart — the Android `BluetoothDevice.getName()` read the
// gen5 readiness gate requires, as a platform-channel call.
//
// Why not flutter_blue_plus's `platformName`: that is an in-memory cache the
// plugin fills from scan results and connection events. A device rebuilt with
// `BluetoothDevice.fromId()` on a cold process start has an EMPTY cache, so
// gating readiness on it would fail every known-device reconnect that skipped
// scanning. The official gate reads the native `BluetoothDevice.getName()`,
// which the Android stack backs with its own bond/cache storage — so this
// channel asks the platform directly.
//
// Native handler: NativeChannels.kt (`BLE_NATIVE_CHANNEL`), registered on the
// long-lived engine so it also answers during headless background syncs.
// Requires BLUETOOTH_CONNECT on API 31+ — the same runtime permission every
// flutter_blue_plus GATT operation already needs, so by the time a link is
// connected the permission is held; a denial surfaces here as null.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AndroidNativeName {
  static const MethodChannel _ch = MethodChannel('openstrap/ble_native');

  /// The native Android name for [remoteId] (the MAC on Android), or null when
  /// the platform has none — which is exactly the value the readiness gate
  /// compares against. Errors (missing permission, invalid MAC, no adapter)
  /// are logged and reported as null: the gate must never pass on a name we
  /// could not actually read.
  static Future<String?> of(String remoteId) async {
    try {
      return await _ch.invokeMethod<String>('remoteDeviceName', remoteId);
    } catch (e) {
      debugPrint('[ble_native] remoteDeviceName($remoteId) failed: $e');
      return null;
    }
  }
}
