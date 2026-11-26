// Real AppState construction -> loaded native profile -> repository writer.
// Empty authored history,unpaired peripheral;no heavy calculation or radio.
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart'
    as os;
import 'package:whoop_companion/ble/ble_engine.dart';
import 'package:whoop_companion/ble/ios_ble_restore.dart';
import 'package:whoop_companion/compute/streak.dart' show StepGoals;
import 'package:whoop_companion/data/calculation_store.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/profile_history.dart';
import 'package:whoop_companion/notify/notification_service.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/state/prefs.dart';
import 'package:whoop_companion/sync/band_ownership.dart';
import 'package:whoop_companion/sync/ios_bg_task.dart';
import '../ble/gatt_connection_test.dart' show Peripheral;
import '../ble/durable_boundary_test.dart' show until;
import '../support/refusing_prefs_store.dart';
import '../support/coverage_store.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final peripheral = Peripheral();
  final nativeStore = SharedPreferencesStorePlatform.instance;
  final notifications = NotificationService.instance;
  const channel = MethodChannel('whoop/ble_restore');
  setUpAll(() async {
    await coverageStore('cold-profile-repository', fresh: true);
    os.FlutterBluePlusPlatform.instance = peripheral;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (c) async => c.method == 'appState' ? 'background' : null,
    );
  });
  setUp(() async {
    await resetCoverageStore();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    peripheral.mode = 'ready';
    peripheral.trace.clear();
    BandOwnership.resetForTest();
    BleEngine.resetBandClaimForTest();
    IosBleRestore.foregroundActive = false;
    notifications.debugProbePermission = () async => false;
    notifications.debugRequestPermission = () async => false;
    notifications.debugCancel = (_) async {};
    notifications.invalidatePermissionCache();
  });
  tearDown(() async {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    notifications.debugProbePermission = null;
    notifications.debugRequestPermission = null;
    notifications.debugCancel = null;
    notifications.invalidatePermissionCache();
    IosBleRestore.onWake = null;
    IosBleRestore.foregroundActive = false;
    IosBgTask.foregroundPull = null;
    BandOwnership.resetForTest();
    BleEngine.resetBandClaimForTest();
    SharedPreferencesStorePlatform.instance = nativeStore;
    SharedPreferences.resetStatic();
  });
  tearDownAll(() async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    await LocalDb.close();
  });
  for (final scenario in ['empty', 'saved', 'refused', 'throws']) {
    test(
      'cold repository profile $scenario keeps authoritative anchors across goal write and retry',
      () async {
        final profile = <String, dynamic>{
          'age': 30,
          'sex': 'f',
          'height_cm': 170.5,
          'weight_kg': 70.25,
          'kcal_target': 2000,
          'step_goal': 8200,
        };
        final store = RefusingPrefsStore(targetKey: 'local_profile_json')
          ..values.addAll({
            if (scenario != 'empty')
              'flutter.local_profile_json': jsonEncode(profile),
            'flutter.authored-unrelated': 'keep',
          });
        SharedPreferences.setMockInitialValues({});
        SharedPreferencesStorePlatform.instance = store;
        await Prefs.ensureLoaded();
        final app = AppState(isIOS: true);
        peripheral.engine = app.engine;
        try {
          await until(
            () => app.initialized || app.initError != null,
            attempts: 2000,
          );
          expect(app.initError, isNull);
          expect(app.initialized, true);
          expect(app.isPaired, false);
          expect(peripheral.trace.where((s) => s == 'connect'), isEmpty);
          final repo = app.repo!;
          final loaded = await repo.getProfile();
          if (scenario == 'empty') {
            expect(loaded['step_goal'], 8000);
          } else {
            for (final entry in profile.entries) {
              expect(loaded[entry.key], entry.value);
            }
          }
          final db = await LocalDb.instance;
          final originalUser = app.user == null
              ? null
              : Map<String, dynamic>.of(app.user!);
          final keys = ['local_profile_json'];
          final anchors = {for (final k in keys) k: store.values['flutter.$k']};
          final oldHistory = await CalculationStore.read(ProfileHistory.key);
          final oldGoals = await CalculationStore.read(StepGoals.key);
          if (scenario == 'refused' || scenario == 'throws') {
            store.refuseWrite = scenario == 'refused' ? 'false' : 'throws';
            await expectLater(
              repo.setStepGoal(9000),
              throwsA(isA<StateError>()),
            );
            expect(app.user, originalUser);
            expect(await repo.getProfile(), loaded);
            expect({
              for (final k in keys) k: store.values['flutter.$k'],
            }, anchors);
            expect(await CalculationStore.read(ProfileHistory.key), oldHistory);
            expect(await CalculationStore.read(StepGoals.key), oldGoals);
            store.refuseWrite = null;
          }
          expect((await repo.setStepGoal(9000))['step_goal'], 9000);
          final current = await repo.getProfile();
          expect(current['step_goal'], 9000);
          expect(app.user!['step_goal'], 9000);
          if (scenario != 'empty') {
            expect(current['height_cm'], 170.5);
            expect(current['weight_kg'], 70.25);
          }
          current['step_goal'] = 500;
          expect((await repo.getProfile())['step_goal'], 9000);
          final saved =
              jsonDecode(store.values['flutter.local_profile_json'] as String)
                  as Map;
          expect(saved['step_goal'], 9000);
          expect(store.values['flutter.authored-unrelated'], 'keep');
          expect(await db.query('day_result'), isEmpty);
          expect(await db.query('decoded_onehz'), isEmpty);
        } finally {
          app.dispose();
          await app.engine.disconnect();
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      },
    );
  }
}
