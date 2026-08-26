// Locale controller — the user's language override (or "System default").
// Persisted on-device via SharedPreferences, mirroring ThemeController /
// UnitsController. Null means follow the OS locale.

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocaleController extends ChangeNotifier {
  static const String _kLocale = 'locale_override'; // language code, e.g. 'es'

  String? _code;
  LocaleController._(this._code);

  factory LocaleController.seed(String? code) => LocaleController._(code);

  static Future<LocaleController> bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    return LocaleController._(prefs.getString(_kLocale));
  }

  /// null = system default.
  String? get code => _code;
  Locale? get locale => _code == null ? null : Locale(_code!);

  Future<void> setCode(String? code) async {
    if (_code == code) return;
    _code = code;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (code == null) {
      await prefs.remove(_kLocale);
    } else {
      await prefs.setString(_kLocale, code);
    }
  }
}
