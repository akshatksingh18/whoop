// The BYOK key must survive a background relaunch on a locked phone.
//
// Two TestFlight reports: "I enter my AI API key, it works for a few minutes,
// then after the phone sleeps and wakes it's gone." The key was written with the
// plugin's default `whenUnlocked` accessibility, and this app is relaunched in
// the background constantly (BGProcessingTask, the BLE restore central) — often
// while the phone is locked, when that item cannot be read. `load()` cached the
// empty read as "no key", so the app asked the user to set one up again.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/coach/coach_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stands in for the keychain: records the options every write asks for, and
/// can be told to behave like a locked device.
class _FakeKeychain {
  final Map<String, String> items = {};
  final List<Map<Object?, Object?>> writeOptions = [];
  bool locked = false;
  bool throwOnRead = false;
  bool throwOnWrite = false;
  bool hangReads = false;
  final List<Completer<void>> _hung = [];

  void releaseHung() {
    for (final c in _hung) {
      if (!c.isCompleted) c.complete();
    }
    _hung.clear();
  }

  Future<Object?> handle(MethodCall call) async {
    final args = (call.arguments as Map?) ?? const {};
    switch (call.method) {
      case 'read':
        if (throwOnRead) throw PlatformException(code: 'keychain');
        if (hangReads) {
          final c = Completer<void>();
          _hung.add(c);
          await c.future;
        }
        // A locked keychain does not error — it simply returns nothing, which
        // is indistinguishable from "no key" without the marker.
        if (locked) return null;
        return items[args['key'] as String];
      case 'write':
        if (throwOnWrite) throw PlatformException(code: 'keychain');
        items[args['key'] as String] = args['value'] as String;
        writeOptions.add((args['options'] as Map?) ?? const {});
        return null;
      case 'delete':
        items.remove(args['key'] as String);
        return null;
      case 'containsKey':
        return !locked && items.containsKey(args['key'] as String);
      case 'readAll':
        return locked ? <String, String>{} : items;
      default:
        return null;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  late _FakeKeychain keychain;

  setUp(() {
    keychain = _FakeKeychain();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, keychain.handle);
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('a key is stored so it survives a locked-device relaunch', () async {
    // The accessibility attribute is an Apple-keychain concept, and the plugin
    // picks its option set off defaultTargetPlatform (android under test).
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final cfg = CoachConfig();
    await cfg.save(apiKey: 'sk-test', model: 'gpt-4o');

    expect(keychain.writeOptions, isNotEmpty);
    // `first_unlock`, not the plugin default of `unlocked`: readable from the
    // first unlock after boot, which is what a background relaunch needs.
    expect(
      keychain.writeOptions.last['accessibility'],
      'first_unlock',
      reason: 'a whenUnlocked item is unreadable during a locked relaunch',
    );
  });

  test('a locked keychain does not report the key as missing', () async {
    final saved = CoachConfig();
    await saved.save(apiKey: 'sk-test', model: 'gpt-4o');

    // A fresh process — the background relaunch — with the phone locked.
    keychain.locked = true;
    final relaunched = CoachConfig();
    await relaunched.load();

    expect(relaunched.hasKey, isFalse, reason: 'it genuinely could not read it');
    expect(relaunched.keyUnreadable, isTrue,
        reason: 'but it must not be reported as "no key configured"');

    // The user unlocks and opens the app.
    keychain.locked = false;
    await relaunched.refreshKeyOnResume();
    expect(relaunched.apiKey, 'sk-test');
    expect(relaunched.keyUnreadable, isFalse);
  });

  test('a read that throws does not erase a key already in memory', () async {
    final cfg = CoachConfig();
    await cfg.save(apiKey: 'sk-test', model: 'gpt-4o');
    expect(cfg.apiKey, 'sk-test');

    keychain.throwOnRead = true;
    await cfg.load();

    expect(cfg.apiKey, 'sk-test',
        reason: 'a failed read says nothing about what is stored');
    expect(cfg.keyUnreadable, isTrue);
  });

  test('no key configured still reads as no key, not as unreadable', () async {
    final cfg = CoachConfig();
    await cfg.load();
    expect(cfg.hasKey, isFalse);
    expect(cfg.keyUnreadable, isFalse,
        reason: 'nothing was ever saved — the setup prompt is correct here');
  });

  test('clearing the key clears the marker with it', () async {
    final cfg = CoachConfig();
    await cfg.save(apiKey: 'sk-test');
    await cfg.save(apiKey: '');

    keychain.locked = true;
    final relaunched = CoachConfig();
    await relaunched.load();
    expect(relaunched.keyUnreadable, isFalse,
        reason: 'a deleted key must not leave the app claiming one exists');
  });

  test('a key written before the marker existed is upgraded once', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    // Legacy state: an item in the keychain, no marker in prefs.
    keychain.items['coach_api_key'] = 'sk-legacy';
    SharedPreferences.setMockInitialValues({});

    final cfg = CoachConfig();
    await cfg.load();
    expect(cfg.apiKey, 'sk-legacy');
    expect(keychain.writeOptions.length, 1,
        reason: 'rewritten once to carry the new accessibility');
    expect(keychain.writeOptions.single['accessibility'], 'first_unlock');

    // A second load must NOT write again — the Android Keystore is the
    // documented Samsung hang, and it has no business on every startup.
    await cfg.load();
    expect(keychain.writeOptions.length, 1);
  });

  test('a legacy key with no marker survives a LOCKED relaunch', () async {
    // The population this whole fix exists for: a key saved by an older build,
    // so there is no marker beside it, whose first launch on this build is a
    // background relaunch on a locked phone. Concluding "no key" here and never
    // retrying is exactly the old bug.
    keychain.items['coach_api_key'] = 'sk-legacy';
    keychain.locked = true;

    final cfg = CoachConfig();
    await cfg.load();
    expect(cfg.hasKey, isFalse);
    expect(cfg.keyUndetermined, isTrue,
        reason: 'nothing is established yet, so the retry must stay armed');

    keychain.locked = false;
    await cfg.refreshKeyOnResume();
    expect(cfg.apiKey, 'sk-legacy');
  });

  test('a legacy key whose read THROWS while locked still retries', () async {
    // iOS reports a locked whenUnlocked item as an error rather than an empty
    // read, which is the legacy item's actual behaviour before it is upgraded.
    keychain.items['coach_api_key'] = 'sk-legacy';
    keychain.throwOnRead = true;

    final cfg = CoachConfig();
    await cfg.load();
    expect(cfg.keyUndetermined, isTrue);

    keychain.throwOnRead = false;
    await cfg.refreshKeyOnResume();
    expect(cfg.apiKey, 'sk-legacy');
  });

  test('a foreground read settles "no key" so the retry stops', () async {
    final cfg = CoachConfig();
    await cfg.load(trusted: true);
    expect(cfg.keyUndetermined, isFalse);
    expect(cfg.hasKey, isFalse);
  });

  test('a marker outliving its item is cleared by a foreground read', () async {
    // A device-to-device restore carries SharedPreferences across but not the
    // keychain payload. Without this the app insists forever that a key it
    // cannot produce is still saved, and Retry is the only thing on offer.
    final cfg = CoachConfig();
    await cfg.save(apiKey: 'sk-test');
    keychain.items.clear(); // restored onto a new device

    await cfg.load(trusted: true);
    expect(cfg.keyUnreadable, isFalse);
    expect(cfg.hasKey, isFalse, reason: 'it really is gone — offer setup');
  });

  test('a hung read leaves the retry armed rather than "no key"', () async {
    final saved = CoachConfig();
    await saved.save(apiKey: 'sk-test');

    // A read that never returns (the Samsung Knox keystore hang the startup
    // path is wrapped in a timeout for — a timeout that cannot cancel the call).
    keychain.hangReads = true;
    final relaunched = CoachConfig();
    unawaited(relaunched.load());
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(relaunched.keyUnreadable, isTrue,
        reason: 'the state must be pending BEFORE the read, not after it');
  });

  test('a save during an in-flight load is not clobbered by it', () async {
    keychain.hangReads = true;
    final cfg = CoachConfig();
    unawaited(cfg.load());
    await Future<void>.delayed(const Duration(milliseconds: 10));

    keychain.hangReads = false;
    await cfg.save(apiKey: 'sk-new', model: 'gpt-4o');
    expect(cfg.apiKey, 'sk-new');

    // The stale read finally lands, having started before the save.
    keychain.releaseHung();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(cfg.apiKey, 'sk-new',
        reason: 'a read that predates the save must not apply its result');
  });

  test('a keychain that refuses the write does not report success', () async {
    final cfg = CoachConfig();
    keychain.throwOnWrite = true;
    await expectLater(cfg.save(apiKey: 'sk-test'), throwsA(anything));
    expect(cfg.hasKey, isFalse,
        reason: 'memory must not hold a key that was never persisted');
  });
}
