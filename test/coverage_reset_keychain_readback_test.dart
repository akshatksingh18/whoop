// A successful native delete call is not proof that its key disappeared.
// Exercise the actual reset owner with an authored,in-memory keychain only.
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/notify/notification_service.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/state/prefs.dart';
import 'coverage_data_export_handoff_test.dart' show Keychain;
import 'support/coverage_store.dart';

class _Readback extends Keychain {
  var deletes = 0;
  bool silentRefusal = false, readRefusal = false;
  Completer<void>? reached, release;
  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {
    deletes++;
    if (!silentRefusal) await super.delete(key: key, options: options);
  }

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async {
    if (release case final gate?) {
      if (!reached!.isCompleted) reached!.complete();
      await gate.future;
      release = null;
    }
    if (readRefusal) {
      throw PlatformException(code: 'authored_keychain_readback_refusal');
    }
    return super.read(key: key, options: options);
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;
  const home = MethodChannel('whoop/home_region');
  late FlutterSecureStoragePlatform original;
  late _Readback keys;
  late AppState app;
  final pending = <Future<void>>[];
  setUpAll(() => coverageStore('reset-keychain-readback', fresh: true));
  setUp(() async {
    await resetCoverageStore();
    pending.clear();
    original = FlutterSecureStoragePlatform.instance;
    keys = _Readback()..value = 'authored-local-only-passphrase';
    FlutterSecureStoragePlatform.instance = keys;
    NotificationService.instance.debugCancel = (_) async {};
    messenger.setMockMethodCallHandler(home, (_) async => null);
    await Prefs.saveValues({'authored-retained-until-reset-completes': 'keep'});
    app = AppState.forTesting()
      ..hasBackupPassphrase = true
      ..user = {'weight_kg': 70.0};
    await LocalDb.putSession({
      'id': 'authored-requested-reset',
      'type': 'walking',
      'status': 'done',
      'start_ts': 1617696000,
      'end_ts': 1617696600,
      'created_at': 1,
      'source': 'manual',
    });
  });
  tearDown(() async {
    if (keys.release case final gate? when !gate.isCompleted) gate.complete();
    keys.release = null;
    for (final job in pending) {
      try {
        await job;
      } catch (_) {}
    }
    app.dispose();
    FlutterSecureStoragePlatform.instance = original;
    NotificationService.instance.debugCancel = null;
    messenger.setMockMethodCallHandler(home, null);
  });
  tearDownAll(LocalDb.close);

  Future<void> acknowledgedRetry() async {
    keys.silentRefusal = keys.readRefusal = false;
    await app.resetAllData();
    expect(keys.value, isNull);
    expect(app.hasBackupPassphrase, false);
    expect(app.user, isNull);
    expect(Prefs.getString('authored-retained-until-reset-completes', ''), '');
    expect(await (await LocalDb.instance).query('sessions'), isEmpty);
  }

  for (final refused in ['silent-delete', 'readback']) {
    test(
      'actual reset $refused cannot report completion and a verified retry finishes',
      () async {
        keys.silentRefusal = refused == 'silent-delete';
        keys.readRefusal = refused == 'readback';
        await expectLater(
          app.resetAllData(),
          refused == 'silent-delete'
              ? throwsStateError
              : throwsA(isA<PlatformException>()),
        );
        expect(keys.deletes, 1);
        expect(
          keys.value,
          refused == 'silent-delete'
              ? 'authored-local-only-passphrase'
              : isNull,
        );
        expect(app.hasBackupPassphrase, true);
        expect(app.user, {'weight_kg': 70.0});
        expect(
          Prefs.getString('authored-retained-until-reset-completes', ''),
          'keep',
        );
        // The user explicitly requested deletion:database deletion can already be
        // complete. Keep this partial outcome honest,not a claim of all-data rollback.
        expect(await (await LocalDb.instance).query('sessions'), isEmpty);
        await acknowledgedRetry();
        expect(keys.deletes, 2);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  }
  for (final retained in [false, true]) {
    test(
      'two reset waiters share one held keychain acknowledgement retained=$retained',
      () async {
        keys.silentRefusal = retained;
        keys.reached = Completer<void>();
        final release = keys.release = Completer<void>();
        var finished = 0;
        final first = app.resetAllData();
        pending.add(first);
        final firstResult = retained
            ? expectLater(first, throwsStateError)
            : first.then((_) => finished++);
        await keys.reached!.future.timeout(const Duration(seconds: 5));
        final second = app.resetAllData();
        pending.add(second);
        final secondResult = retained
            ? expectLater(second, throwsStateError)
            : second.then((_) => finished++);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        // The first caller has a cleanup wrapper Future;job sharing is proved
        // by both outcomes and exactly one durable delete,not Future identity.
        expect(keys.deletes, 1);
        expect(finished, 0);
        expect(app.hasBackupPassphrase, true);
        expect(
          Prefs.getString('authored-retained-until-reset-completes', ''),
          'keep',
        );
        release.complete();
        await Future.wait([firstResult, secondResult]);
        expect(keys.deletes, 1);
        if (retained) {
          expect(keys.value, 'authored-local-only-passphrase');
          expect(finished, 0);
          expect(app.hasBackupPassphrase, true);
          await acknowledgedRetry();
        } else {
          expect(finished, 2);
          expect(keys.value, isNull);
          expect(app.hasBackupPassphrase, false);
          expect(app.user, isNull);
        }
        expect(await (await LocalDb.instance).query('sessions'), isEmpty);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  }
}
