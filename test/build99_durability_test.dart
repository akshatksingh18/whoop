// Synthetic boundary fixtures only; no personal data or platform permissions.
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:openstrap_edge/data/auto_backup.dart';
import 'package:openstrap_edge/data/backup_passphrase.dart';
import 'package:openstrap_edge/data/calculation_store.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/home_region.dart';
import 'package:openstrap_edge/data/profile_history.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:openstrap_edge/state/prefs.dart';
import 'package:openstrap_edge/sync/paired_device.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.root);
  final String root;
  @override
  Future<String?> getTemporaryPath() async => root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
}

class _Storage extends SharedPreferencesStorePlatform {
  final values = <String, Object>{};
  final refused = <String>{};
  bool refuseClear = false;
  Completer<void>? holdMirror;
  final mirrorStarted = Completer<void>();
  @override
  Future<Map<String, Object>> getAll() async => Map.of(values);
  @override
  Future<bool> clear() async {
    if (refuseClear) return false;
    values.clear();
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    if (refused.contains(key)) return false;
    values.remove(key);
    return true;
  }

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key == 'flutter.synthetic.ordered' && holdMirror != null) {
      if (!mirrorStarted.isCompleted) mirrorStarted.complete();
      await holdMirror!.future;
    }
    if (refused.contains(key)) return false;
    values[key] = value;
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late _Storage store;
  late SharedPreferencesStorePlatform original;
  var monitors = 0;
  var refuseStop = false;
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final dir = Directory('build/research-local/build99-durability').absolute;
    await dir.create(recursive: true);
    PathProviderPlatform.instance = _Paths(dir.path);
    LocalDb.dbName = p.join(dir.path, 'synthetic.sqlite');
    await LocalDb.close();
    await databaseFactory.deleteDatabase(LocalDb.dbName);
    db = await LocalDb.instance;
  });
  setUp(() async {
    original = SharedPreferencesStorePlatform.instance;
    store = _Storage();
    SharedPreferencesStorePlatform.instance = store;
    SharedPreferences.resetStatic();
    await Prefs.ensureLoaded();
    await LocalDb.wipeAll();
    monitors = 0;
    refuseStop = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('openstrap/home_region'),
          (call) async {
            if (call.method == 'monitor') monitors++;
            if (call.method == 'stop' && refuseStop) {
              throw PlatformException(code: 'synthetic_stop_failed');
            }
            return null;
          },
        );
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          null,
        );
    SharedPreferencesStorePlatform.instance = original;
    SharedPreferences.resetStatic();
    await Prefs.ensureLoaded();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('openstrap/home_region'),
          null,
        );
  });
  tearDownAll(() async {
    await LocalDb.close();
    await databaseFactory.deleteDatabase(LocalDb.dbName);
  });

  test(
    'profile rollback preserves authoritative history without its mirror',
    () async {
      final originalHistory = jsonEncode({
        'baseline': {'weight_kg': 70, 'height_cm': 180, 'age': 30, 'sex': 'm'},
        '2026-09-01': {
          'weight_kg': 69,
          'height_cm': 180,
          'age': 30,
          'sex': 'm',
        },
      });
      await LocalDb.putBaseline(
        '${CalculationStore.prefix}${ProfileHistory.key}',
        originalHistory,
      );
      store.refused.add('flutter.local_profile_json');
      final app = AppState.forTesting()
        ..user = {'weight_kg': 70, 'height_cm': 180, 'age': 30, 'sex': 'm'};
      addTearDown(app.dispose);
      await expectLater(app.updateProfile({'weight_kg': 71}), throwsStateError);
      expect(
        (await LocalDb.baseline(
          '${CalculationStore.prefix}${ProfileHistory.key}',
        ))?['payload_json'],
        originalHistory,
      );
      expect(app.user!['weight_kg'], 70);
    },
  );

  test(
    'failed calculation-cache removal cannot resurrect a deleted value',
    () async {
      await CalculationStore.write('synthetic.removal', 'retained');
      store.refused.add('flutter.synthetic.removal');
      await expectLater(
        CalculationStore.remove('synthetic.removal'),
        throwsStateError,
      );
      SharedPreferences.resetStatic();
      expect(await CalculationStore.read('synthetic.removal'), 'retained');
      store.refused.clear();
      await CalculationStore.remove('synthetic.removal');
      SharedPreferences.resetStatic();
      expect(await CalculationStore.read('synthetic.removal'), isNull);
    },
  );

  test('backup Off is not reported saved when storage refuses it', () async {
    store.values['flutter.backup.cadence'] = 'daily';
    SharedPreferences.resetStatic();
    await Prefs.ensureLoaded();
    store.refused.add('flutter.backup.cadence');
    final app = AppState.forTesting();
    addTearDown(app.dispose);
    await expectLater(
      app.setBackupCadence(BackupCadence.off),
      throwsStateError,
    );
    expect(app.backupCadence, BackupCadence.daily);
  });

  test(
    'calculation read mirror cannot complete after a successful removal',
    () async {
      await LocalDb.putBaseline(
        '${CalculationStore.prefix}synthetic.ordered',
        'retained',
      );
      store.holdMirror = Completer<void>();
      final reading = CalculationStore.read('synthetic.ordered');
      await store.mirrorStarted.future;
      final removing = CalculationStore.remove('synthetic.ordered');
      store.holdMirror!.complete();
      expect(await reading, 'retained');
      await removing;
      SharedPreferences.resetStatic();
      expect(await CalculationStore.read('synthetic.ordered'), isNull);
    },
  );

  test(
    'reset keychain deletion reports refusal and verifies a successful retry',
    () async {
      var secret = 'synthetic-passphrase';
      var refuse = true;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            (call) async {
              if (call.method == 'delete' && refuse)
                throw PlatformException(code: 'synthetic_keychain_refusal');
              if (call.method == 'delete') secret = '';
              if (call.method == 'read') return secret.isEmpty ? null : secret;
              return null;
            },
          );
      await expectLater(
        BackupPassphrase.clear(),
        throwsA(isA<PlatformException>()),
      );
      expect(secret, 'synthetic-passphrase');
      refuse = false;
      await BackupPassphrase.clear();
      expect(secret, isEmpty);
    },
  );

  test(
    'forget refuses failed mirror deletion before dropping database identity',
    () async {
      await PairedDevice.save(
        'synthetic-band',
        'Synthetic',
        generation: 'gen4',
      );
      store.refused.add('flutter.paired_remote_id');
      await expectLater(PairedDevice.clear(), throwsStateError);
      SharedPreferences.resetStatic();
      expect((await PairedDevice.load())?.remoteId, 'synthetic-band');
      store.refused.clear();
      await PairedDevice.clear();
      SharedPreferences.resetStatic();
      expect(await PairedDevice.load(), isNull);
    },
  );

  test(
    'Home never starts monitoring after refused location persistence',
    () async {
      store.refused.add('flutter.pushups.home.boundary');
      await expectLater(
        HomeRegion.setHome((lat: 12.34, lon: 45.67, radius: 150)),
        throwsStateError,
      );
      expect(monitors, 0);
    },
  );

  test('Home clear retains its retry state when native stop fails', () async {
    await HomeRegion.setHome((lat: 12.34, lon: 45.67, radius: 150));
    refuseStop = true;
    await expectLater(HomeRegion.clear(), throwsA(isA<PlatformException>()));
    expect(await HomeRegion.boundary(), isNotNull);
  });

  test(
    'reset reports refused preference deletion instead of claiming complete',
    () async {
      store.values['flutter.synthetic.private-setting'] = 'retained';
      SharedPreferences.resetStatic();
      await Prefs.ensureLoaded();
      store.refuseClear = true;
      final app = AppState.forTesting();
      addTearDown(app.dispose);
      await expectLater(app.resetAllData(), throwsStateError);
      expect(store.values['flutter.synthetic.private-setting'], 'retained');
      expect(await db.query('sessions'), isEmpty);
    },
  );
}
