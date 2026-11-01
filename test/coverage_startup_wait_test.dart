// A channel that never answers is different from a channel that throws.
import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/state/prefs.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.root);
  final String root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

class _WaitingStore extends SharedPreferencesStorePlatform {
  final entered = Completer<void>(), release = Completer<void>();
  @override
  Future<Map<String, Object>> getAll() async {
    if (!entered.isCompleted) entered.complete();
    await release.future;
    return {};
  }

  @override
  Future<bool> setValue(String type, String key, Object value) async => true;
  @override
  Future<bool> remove(String key) async => true;
  @override
  Future<bool> clear() async => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final root = (await Directory(
      'build/coverage-audit/startup',
    ).create(recursive: true)).absolute;
    PathProviderPlatform.instance = _Paths(root.path);
    LocalDb.dbName = '${root.path}/synthetic.sqlite';
    await LocalDb.close();
    await databaseFactory.deleteDatabase(LocalDb.dbName);
    SharedPreferences.setMockInitialValues({});
    await LocalDb.instance;
  });
  tearDownAll(LocalDb.close);
  test(
    'startup wait becomes retryable and shares the pending initialization',
    () async {
      final original = SharedPreferencesStorePlatform.instance;
      final store = _WaitingStore();
      SharedPreferencesStorePlatform.instance = store;
      SharedPreferences.resetStatic();
      var launchReads = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('flutter_timezone'), (
            call,
          ) async {
            launchReads++;
            throw PlatformException(code: 'synthetic_unavailable');
          });
      final app = AppState.forTesting();
      final init = app.debugInit();
      addTearDown(() async {
        if (!store.release.isCompleted) store.release.complete();
        await init;
        await Future<void>.delayed(const Duration(milliseconds: 100));
        app.dispose();
        SharedPreferencesStorePlatform.instance = original;
        SharedPreferences.resetStatic();
        await Prefs.ensureLoaded();
      });
      await store.entered.future;
      await Future<void>.delayed(const Duration(milliseconds: 6200));
      expect(app.route, AppRoute.failed);
      expect(app.initError, contains('TimeoutException'));
      final retry = app.retryInit();
      store.release.complete();
      await init;
      await retry;
      expect(app.initError, isNull);
      expect(app.initialized, isTrue);
      expect(
        launchReads,
        1,
        reason: 'Retry must not run an overlapping initialization',
      );
    },
  );
}
