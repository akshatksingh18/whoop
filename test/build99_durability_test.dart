// Synthetic boundary fixtures only; no personal data or platform permissions.
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
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
import 'package:openstrap_edge/data/food_day_reminder.dart';
import 'package:openstrap_edge/data/profile_history.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:openstrap_edge/state/prefs.dart';
import 'package:openstrap_edge/sync/paired_device.dart';
import 'package:openstrap_edge/gps/run_voice.dart';
import 'package:openstrap_edge/notify/notification_service.dart';
import 'package:openstrap_edge/notify/notification_log.dart';
import 'package:openstrap_edge/ui2/screens/progress_screen.dart';
import 'package:openstrap_edge/ui2/ui2.dart';
import 'support/audit_visual.dart';

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
    await loadAuditFonts();
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
    NotificationService.instance.debugCancel = null;
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

  test(
    'voice setting refuses a failed write and survives a cold read',
    () async {
      store.refused.add('flutter.run.voice');
      await expectLater(setRunVoiceOn(false), throwsStateError);
      SharedPreferences.resetStatic();
      await Prefs.ensureLoaded();
      expect(runVoiceOn, isTrue);
      store.refused.clear();
      await setRunVoiceOn(false);
      SharedPreferences.resetStatic();
      await Prefs.ensureLoaded();
      expect(runVoiceOn, isFalse);
    },
  );

  test('failed notification cancellation keeps its plan until retry', () async {
    final svc = NotificationService.instance;
    await NotificationLog.instance.plan(
      id: NotificationService.idBodyReminder,
      first: DateTime.now().add(const Duration(days: 1)),
      repeat: PlanRepeat.weekly,
      title: 'Synthetic',
      body: 'Synthetic',
      category: 'reminders',
    );
    svc.debugCancel = (_) async =>
        throw PlatformException(code: 'synthetic_cancel_refused');
    await expectLater(
      svc.cancel(
        NotificationService.idBodyReminder,
        requireAcknowledgement: true,
      ),
      throwsA(isA<PlatformException>()),
    );
    expect(
      jsonDecode(
            (await SharedPreferences.getInstance()).getString('notify.plans')!,
          )
          as Map,
      contains('${NotificationService.idBodyReminder}'),
    );
    svc.debugCancel = (_) async {};
    await svc.cancel(
      NotificationService.idBodyReminder,
      requireAcknowledgement: true,
    );
    expect(
      jsonDecode(
            (await SharedPreferences.getInstance()).getString('notify.plans')!,
          )
          as Map,
      isEmpty,
    );
  });

  test('reset reports refused native notification cancellation', () async {
    NotificationService.instance.debugCancel = (_) async =>
        throw PlatformException(code: 'synthetic_cancel_refused');
    final app = AppState.forTesting();
    addTearDown(app.dispose);
    await expectLater(app.resetAllData(), throwsA(isA<PlatformException>()));
  });

  test(
    'Food reminder Off reports native refusal and retains the previous choice',
    () async {
      store.values['flutter.food.day_reminder'] = true;
      SharedPreferences.resetStatic();
      await Prefs.ensureLoaded();
      NotificationService.instance.debugCancel = (_) async =>
          throw PlatformException(code: 'synthetic_cancel_refused');
      await expectLater(
        FoodDayReminder.setEnabled(false),
        throwsA(isA<PlatformException>()),
      );
      expect(await FoodDayReminder.enabled(), isTrue);
    },
  );

  // Keep real SQLite interactions in one Flutter fake-clock zone. Splitting
  // these across widget-test zones can strand the FFI lock on Windows.
  testWidgets('Body nested states retain choices and drafts', (t) async {
    for (final scale in [1.0, 3.1]) {
      store.values['flutter.body.reminder'] = true;
      SharedPreferences.resetStatic();
      await Prefs.ensureLoaded();
      NotificationService.instance.debugCancel = (_) async =>
          throw PlatformException(code: 'synthetic_cancel_refused');
      final data = ProgressData(
        weights: [],
        measures: [],
        photos: [],
        lifts: [],
        food: [],
        steps: [],
        sleepMin: [],
        recovery: [],
        sessions: [],
        baseline: null,
        heightCm: null,
      );
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        RepaintBoundary(
          key: auditCaptureKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildTheme(Brightness.light),
            builder: (c, child) => MediaQuery(
              data: MediaQuery.of(
                c,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: BodySettingsScreen(data: data),
          ),
        ),
      );
      Future<void> settle() async {
        for (var i = 0; i < 15; i++) {
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 15)),
          );
          await t.pump(const Duration(milliseconds: 30));
        }
      }

      await settle();
      await t.scrollUntilVisible(
        find.text('Weekly reminder'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await t.tap(find.text('Weekly reminder'));
      await settle();
      expect(t.takeException(), isNull);
      t.state<ScrollableState>(find.byType(Scrollable).first).position.jumpTo(0);
      await t.pumpAndSettle();
      expect(find.text('Check reminder'), findsOneWidget);
      expect(
        (await SharedPreferences.getInstance()).getBool('body.reminder'),
        isTrue,
      );
      await captureAuditScroll(t, 'body_reminder_failure_${scale}x');
      await t.pumpWidget(const SizedBox());
    }
    await (() async {
      await t.runAsync(
        () => db.execute(
          'ALTER TABLE body_weight RENAME TO synthetic_weight_hold',
        ),
      );
      var restored = false;
      try {
        await t.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildTheme(Brightness.light),
            home: const BodyEntryScreen(unit: 'kg'),
          ),
        );
        Future<void> settle() async {
          for (var i = 0; i < 15; i++) {
            await t.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 15)),
            );
            await t.pump(const Duration(milliseconds: 30));
          }
        }

        await settle();
        expect(t.takeException(), isNull);
        expect(find.text('This day could not be read'), findsOneWidget);
        await t.enterText(find.byType(TextField).first, '71.2');
        await t.runAsync(
          () => db.execute(
            'ALTER TABLE synthetic_weight_hold RENAME TO body_weight',
          ),
        );
        restored = true;
        await t.ensureVisible(find.text('Retry loading'));
        await t.tap(find.text('Retry loading'));
        await settle();
        expect(find.text('This day could not be read'), findsNothing);
        expect(find.text('71.2'), findsOneWidget);
        await t.pumpWidget(const SizedBox());
      } finally {
        if (!restored)
          await t.runAsync(
            () => db.execute(
              'ALTER TABLE synthetic_weight_hold RENAME TO body_weight',
            ),
          );
      }
    })();
    await (() async {
      final camera = Completer<Object?>();
      var calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('openstrap/camera'), (
            call,
          ) {
            calls++;
            return camera.future;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('openstrap/camera'),
              null,
            ),
      );
      await t.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          home: const BodyEntryScreen(unit: 'kg'),
        ),
      );
      for (var i = 0; i < 10; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 15)),
        );
        await t.pump(const Duration(milliseconds: 30));
      }
      await t.scrollUntilVisible(
        find.text('Photos'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await t.tap(find.text('Photos'));
      await t.pump();
      await t.ensureVisible(find.text('Camera · Front'));
      await t.tap(find.text('Camera · Front'));
      await t.pump();
      expect(calls, 1);
      await t.pumpWidget(const SizedBox());
      camera.completeError(PlatformException(code: 'synthetic_camera_refused'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    })();
  });
}
