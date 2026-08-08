// CoachConfig — local, BYOK settings for the AI coach. The API key is stored in
// the platform keychain/keystore (flutter_secure_storage); base URL + model in
// SharedPreferences. NOTHING here ever touches our backend — the key stays on the
// device and the app calls the OpenAI-compatible provider directly.

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CoachConfig extends ChangeNotifier {
  static const _kBaseUrl = 'coach_base_url';
  static const _kModel = 'coach_model';
  static const _kKey = 'coach_api_key'; // secure storage

  /// Set whenever a key is written, cleared when it is deleted. The keychain
  /// itself cannot answer "is there a key I currently can't read?" — a locked
  /// device and an empty keychain both read as nothing — so the answer is kept
  /// here, where it is always readable.
  ///
  /// THREE states, not two. ABSENT (null) means nobody has established the
  /// answer yet, which is where every install that predates this marker starts:
  /// their key is in the keychain with no marker beside it. Treating absent as
  /// "no key" would fail that user exactly as the old code did — a locked
  /// background relaunch reads nothing, concludes there is no key, and never
  /// retries. Absent therefore stays UNDETERMINED until a read happens with the
  /// app in the foreground, where the device is unlocked by definition.
  static const _kKeyPresent = 'coach_api_key_present';

  static const String defaultBaseUrl = 'https://api.openai.com/v1';

  /// FIRST-UNLOCK, not the plugin's default WHEN-UNLOCKED.
  ///
  /// This app is relaunched in the background constantly — BGProcessingTask, the
  /// BLE restore central waking on a link drop — and those relaunches routinely
  /// happen while the phone is LOCKED, i.e. exactly when a `whenUnlocked` item
  /// cannot be read. That read then returned nothing, `load()` cached the
  /// nothing as "no key", and by the time the user opened the app their key had
  /// silently vanished ("works for a few minutes, then it's gone after
  /// sleep/wake" — two TestFlight reports). `first_unlock` keeps the item
  /// readable from the first unlock after boot onwards, which is what a
  /// background-heavy app needs. The key still never leaves the device.
  static const _apple = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock,
  );
  static const _macos = MacOsOptions(
    accessibility: KeychainAccessibility.first_unlock,
  );

  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  String _baseUrl = defaultBaseUrl;
  String _model = '';
  String? _key; // cached in-memory after load

  /// True when a key IS stored but this process could not read it (a locked
  /// keychain, a wedged keystore). Distinct from "no key configured", which the
  /// user can fix by pasting one — this one fixes itself on the next unlocked
  /// read, and telling them to set a key up again would be wrong.
  bool _keyUnreadable = false;
  bool get keyUnreadable => _keyUnreadable;

  /// True while it is still unknown whether a key is stored — an install that
  /// predates the marker, read while the keychain was unavailable. Not shown to
  /// the user (there may genuinely be no key); it only keeps the resume retry
  /// eligible so a legacy key appears by itself once the phone is unlocked.
  bool _keyUndetermined = false;
  bool get keyUndetermined => _keyUndetermined;

  /// Bumped by every [save]. A [load] that started before a save must not apply
  /// its stale result afterwards: the startup load is unawaited and a slow
  /// keystore read can still be in flight when the user pastes a key, and its
  /// late `_key = null` would wipe the key they just saved out of the session.
  int _generation = 0;

  String get baseUrl => _baseUrl;
  String get model => _model;
  String? get apiKey => _key;
  bool get hasKey => _key != null && _key!.isNotEmpty;
  bool get configured => hasKey && _baseUrl.isNotEmpty && _model.isNotEmpty;

  /// Normalised base, no trailing slash.
  String get apiBase {
    var b = _baseUrl.trim();
    while (b.endsWith('/')) {
      b = b.substring(0, b.length - 1);
    }
    return b;
  }

  /// [trusted] marks a read taken with the app in the FOREGROUND, i.e. with the
  /// device unlocked — the only condition under which an EMPTY read is real
  /// evidence about what is stored.
  Future<void> load({bool trusted = false}) async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString(_kBaseUrl) ?? defaultBaseUrl;
    _model = prefs.getString(_kModel) ?? '';
    final marker = prefs.getBool(_kKeyPresent); // null = undetermined
    final generation = _generation;

    // Pending BEFORE the read, not after. The startup read is wrapped in a
    // timeout that cannot cancel the underlying call, and the Android Keystore
    // can hang outright — if the answer is only recorded once the read returns,
    // a read that never returns leaves the app looking like "no key configured"
    // with the resume retry permanently disabled.
    _keyUnreadable = marker == true && !hasKey;
    _keyUndetermined = marker == null;

    try {
      final read = await _secure.read(
        key: _kKey,
        iOptions: _apple,
        mOptions: _macos,
      );
      // A save landed while this read was in flight — it knows more than we do.
      if (generation != _generation) return;
      if (read != null && read.isNotEmpty) {
        _key = read;
        _keyUnreadable = false;
        _keyUndetermined = false;
        // Upgrade an item written before this class asked for `first_unlock`:
        // accessibility is set at WRITE time, so an existing key keeps the old
        // attribute until it is written again. Keyed on the marker so this
        // happens exactly once — a write on every load would put the Android
        // Keystore (the documented Samsung Knox hang) on the startup path for
        // no reason.
        if (marker != true) {
          await _secure.write(
            key: _kKey,
            value: read,
            iOptions: _apple,
            mOptions: _macos,
          );
          await prefs.setBool(_kKeyPresent, true);
        }
      } else if (trusted) {
        // Foreground, so the keychain is readable and an empty answer is the
        // truth: there is no key. This is also the ONLY way out of a marker that
        // outlived its item — a device-to-device restore carries
        // SharedPreferences across but not the keychain payload, and without
        // this the app would insist forever that a key it cannot produce is
        // still saved.
        _key = null;
        _keyUnreadable = false;
        _keyUndetermined = false;
        if (marker != false) await prefs.setBool(_kKeyPresent, false);
      } else if (marker == true) {
        // Backgrounded and empty: the keychain was unavailable, NOT the user
        // having no key. Keep whatever is cached and say why.
        _keyUnreadable = true;
        _keyUndetermined = false;
      } else if (marker == null) {
        // Nothing recorded either way, and this read proves nothing. Stay
        // retry-eligible so a legacy key surfaces on the next foreground.
        _key = null;
        _keyUndetermined = true;
      } else {
        _key = null;
        _keyUnreadable = false;
        _keyUndetermined = false;
      }
    } catch (_) {
      // A read that THREW tells us nothing about the stored key, so it must not
      // overwrite one we already hold in memory. iOS surfaces a locked
      // `whenUnlocked` item this way rather than as an empty read, so this is
      // the legacy-install path, not an edge case.
      if (generation != _generation) return;
      _keyUnreadable = marker == true;
      _keyUndetermined = marker == null;
    }
    notifyListeners();
  }

  /// Re-read the key when the answer is still outstanding — it is known to
  /// exist but was unreadable, or nothing has been established yet. Cheap no-op
  /// otherwise, so it is safe on every resume, which is exactly when a phone
  /// that was locked during a background relaunch becomes readable again.
  Future<void> refreshKeyOnResume() async {
    if (!_keyUnreadable && !_keyUndetermined) return;
    await load(trusted: true);
  }

  /// Throws if the keychain refuses the write or delete — a caller that reports
  /// "saved" on a key that never reached storage is the same silent loss this
  /// class exists to stop.
  Future<void> save({String? baseUrl, String? model, String? apiKey}) async {
    final prefs = await SharedPreferences.getInstance();
    if (baseUrl != null) {
      _baseUrl = baseUrl.trim().isEmpty ? defaultBaseUrl : baseUrl.trim();
      await prefs.setString(_kBaseUrl, _baseUrl);
    }
    if (model != null) {
      _model = model.trim();
      await prefs.setString(_kModel, _model);
    }
    if (apiKey != null) {
      _generation++;
      final k = apiKey.trim();
      // The keychain FIRST, and the in-memory copy only once it succeeded. The
      // other order leaves memory holding a key that was never persisted (lost
      // at the next launch, with no marker to even flag it as missing), or
      // hiding one that is still stored.
      if (k.isEmpty) {
        await _secure.delete(key: _kKey, iOptions: _apple, mOptions: _macos);
        // The marker follows the keychain, and its own failure is not worth
        // failing the save: a stale `true` costs a retry, never a lost key.
        try {
          await prefs.setBool(_kKeyPresent, false);
        } catch (_) {/* re-established by the next load */}
      } else {
        await _secure.write(
          key: _kKey,
          value: k,
          iOptions: _apple,
          mOptions: _macos,
        );
        try {
          await prefs.setBool(_kKeyPresent, true);
        } catch (_) {/* re-established by the next load */}
      }
      _key = k.isEmpty ? null : k;
      _keyUnreadable = false;
      _keyUndetermined = false;
    }
    notifyListeners();
  }
}
