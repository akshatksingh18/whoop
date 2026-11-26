// An in-memory preference backend that can refuse, or hold, writes and
// removes of one key, so tests reach the app's real refusal paths.
import 'dart:async';

import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class RefusingPrefsStore extends SharedPreferencesStorePlatform {
  RefusingPrefsStore({this.targetKey = ''});

  /// The key (without the `flutter.` prefix) whose writes and removes can be
  /// refused or held.
  String targetKey;
  final values = <String, Object>{};

  /// `'throws'` throws, `'false'` reports failure, null succeeds.
  String? refuseWrite, refuseRemove;

  /// When set, the next write of [targetKey] completes [reached] and waits
  /// for [held] before it lands.
  Completer<void>? held, reached;

  @override
  Future<Map<String, Object>> getAll() async => Map.of(values);

  @override
  Future<bool> clear() async {
    values.clear();
    return true;
  }

  @override
  Future<bool> remove(String name) async {
    if (name == 'flutter.$targetKey') {
      if (refuseRemove == 'throws') {
        throw StateError('synthetic preference remove refusal');
      }
      if (refuseRemove == 'false') return false;
    }
    values.remove(name);
    return true;
  }

  @override
  Future<bool> setValue(String type, String name, Object value) async {
    if (name == 'flutter.$targetKey') {
      final gate = held;
      if (gate != null) {
        held = null;
        reached!.complete();
        await gate.future;
      }
      if (refuseWrite == 'throws') {
        throw StateError('synthetic preference write refusal');
      }
      if (refuseWrite == 'false') return false;
    }
    values[name] = value;
    return true;
  }
}
