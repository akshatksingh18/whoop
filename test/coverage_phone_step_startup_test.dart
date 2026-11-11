// Actual launch/profile loading and phone-channel I/O; authored SQLite only.
// This verifies Dart persistence/absence, not CoreMotion or phone acceptance.
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart'
    as os;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whoop_companion/ble/ble_engine.dart';
import 'package:whoop_companion/ble/ios_ble_restore.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/notify/notification_service.dart';
import 'package:whoop_companion/platform/phone_pedometer.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/sync/band_ownership.dart';
import 'package:whoop_companion/sync/ios_bg_task.dart';
import 'coverage_ble_durable_boundary_test.dart' show until;
import 'coverage_gatt_connection_test.dart' show Peripheral;
import 'support/coverage_store.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;
  const notices = MethodChannel('dexterous.com/flutter/local_notifications');
  const timezone = MethodChannel('flutter_timezone');
  final notifications = NotificationService.instance;
  final peripheral = Peripheral();
  final calls = <MethodCall>[];
  AppState? app;
  Completer<void>? held, started;
  var mode = '';
  var expectedTotal = 0, expectedToday = 0;
  int sec(DateTime at) => at.millisecondsSinceEpoch ~/ 1000;
  setUpAll(() async {
    await coverageStore('phone-step-startup', fresh: true);
    os.FlutterBluePlusPlatform.instance = peripheral;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    IOSFlutterLocalNotificationsPlugin.registerWith();
    messenger
      ..setMockMethodCallHandler(timezone, (_) async => 'UTC')
      ..setMockMethodCallHandler(
        notices,
        (call) async => switch (call.method) {
          'initialize' => true,
          'getNotificationAppLaunchDetails' => {
            'notificationLaunchedApp': false,
          },
          'pendingNotificationRequests' => [],
          'checkPermissions' => {'isEnabled': false},
          _ => null,
        },
      )
      ..setMockMethodCallHandler(phoneStepsChannel, (call) async {
        calls.add(call);
        if (call.method == 'authorized') return mode != 'denied';
        if (call.method != 'movementInInterval') {
          throw StateError('unexpected startup sensor call ${call.method}');
        }
        if (held case final gate?) {
          started!.complete();
          await gate.future;
          held = null;
        }
        if (mode == 'refused') {
          throw PlatformException(code: 'authored_sensor_unavailable');
        }
        if (mode == 'null') return null;
        if (mode == 'uncovered') return {'steps': -1};
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final from = args['fromMs'] as int, to = args['toMs'] as int;
        expect(to, greaterThan(from));
        final steps = mode == 'zero' ? 0 : (to - from) ~/ 60000;
        expectedTotal += steps;
        if (dayLabelOf(DateTime.fromMillisecondsSinceEpoch(from)) ==
            todayLabel()) {
          expectedToday += steps;
        }
        return {'steps': steps, 'distance_m': steps * .7};
      });
    await notifications.init();
  });
  setUp(() async {
    await resetCoverageStore();
    BandOwnership.resetForTest();
    BleEngine.resetBandClaimForTest();
    peripheral.trace.clear();
    calls.clear();
    held = started = null;
    expectedTotal = expectedToday = 0;
    notifications.debugProbePermission = () async => false;
    notifications.debugRequestPermission = () async => false;
    notifications.debugCancel = (_) async {};
    notifications.invalidatePermissionCache();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });
  tearDown(() async {
    if (held case final gate? when !gate.isCompleted) gate.complete();
    held = null;
    if (app case final current?) {
      await current.pauseForBackground();
      await current.endSession();
      current.dispose();
      await current.engine.disconnect();
    }
    app = null;
    IosBgTask.foregroundPull = null;
    IosBleRestore.onWake = null;
    IosBleRestore.foregroundActive = false;
    notifications.debugProbePermission = null;
    notifications.debugRequestPermission = null;
    notifications.debugCancel = null;
    notifications.invalidatePermissionCache();
    BandOwnership.resetForTest();
    BleEngine.resetBandClaimForTest();
  });
  tearDownAll(() async {
    messenger
      ..setMockMethodCallHandler(notices, null)
      ..setMockMethodCallHandler(timezone, null)
      ..setMockMethodCallHandler(phoneStepsChannel, null);
    debugDefaultTargetPlatformOverride = null;
    await LocalDb.close();
  });

  for (final scenario in [
    'disabled',
    'denied',
    'uncovered',
    'refused',
    'null',
    'zero',
    'measured',
    'held',
  ]) {
    test(
      'launch sensor $scenario preserves history and distinguishes absence from measured zero',
      () async {
        mode = scenario;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('phone_steps', scenario != 'disabled');
        await prefs.setBool('phone_steps_healthstore_purged', true);
        await prefs.setString(
          'local_profile_json',
          jsonEncode({'kcal_target': 2100}),
        );
        final historical = DateTime(2021, 4, 6, 10);
        await LocalDb.addLiveCoverage(
          sec(historical),
          sec(historical.add(const Duration(minutes: 10))),
          60,
          '2021-04-06',
          source: LocalDb.kStepSourcePhone,
        );
        final db = await LocalDb.instance;
        final before = await db.query('live_coverage', orderBy: 'start_ts');
        if (scenario == 'held') {
          held = Completer<void>();
          started = Completer<void>();
        }
        final current = app = AppState();
        peripheral.engine = current.engine;
        if (scenario == 'held') {
          await started!.future.timeout(const Duration(seconds: 10));
        }
        await until(
          () => current.initialized || current.initError != null,
          attempts: 2000,
        );
        expect(current.initError, isNull);
        expect(current.initialized, true);
        expect(current.isPaired, false);
        expect(current.user?['kcal_target'], 2100);
        expect(current.phoneStepsEnabled, scenario != 'disabled');
        if (scenario == 'held') {
          // Startup remains usable while the previously enabled reader waits.
          expect(current.phoneStepsLastSyncedDays, isNull);
          expect(await db.query('live_coverage', orderBy: 'start_ts'), before);
          held!.complete();
        }
        if (scenario == 'disabled') {
          expect(calls, isEmpty);
          expect(current.phoneStepsLastSyncedDays, isNull);
        } else {
          await until(
            () => current.phoneStepsLastSyncedDays != null,
            attempts: 2000,
          );
          expect(calls.where((c) => c.method == 'authorized'), hasLength(1));
        }
        final read = ['zero', 'measured', 'held'].contains(scenario);
        final after = await db.query('live_coverage', orderBy: 'start_ts');
        expect(after.where((r) => r['day'] == '2021-04-06').toList(), before);
        if (read) {
          expect(current.phoneStepsLastSyncedDays, 2);
          expect(current.phoneStepsLastTotal, expectedTotal);
          expect(await LocalDb.phoneStepsForDay(todayLabel()), expectedToday);
          final added = after.where((r) => r['day'] != '2021-04-06').toList();
          expect(added, isNotEmpty);
          expect(added.map((r) => r['day']).toSet(), hasLength(2));
          expect(
            added.every((r) => r['source'] == LocalDb.kStepSourcePhone),
            true,
          );
          expect(
            added.fold<int>(0, (n, r) => n + (r['steps'] as num).toInt()),
            expectedTotal,
          );
          if (scenario == 'zero') {
            expect(added.every((r) => r['steps'] == 0), true);
          } else {
            expect(expectedTotal, greaterThan(0));
          }
        } else {
          expect(after, before);
          if (scenario != 'disabled') {
            expect(current.phoneStepsLastSyncedDays, 0);
            expect(current.phoneStepsLastTotal, 0);
          }
        }
        expect(prefs.getBool('phone_steps'), scenario != 'disabled');
        expect(calls.where((c) => c.method == 'requestPermission'), isEmpty);
        expect(peripheral.trace, isNot(contains('connect')));
        expect(await db.query('sessions'), isEmpty);
        expect(await db.query('day_result'), isEmpty);
        expect(await db.query('samples'), isEmpty);
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );
  }
}
