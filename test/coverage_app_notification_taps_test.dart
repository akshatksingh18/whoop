// Scripted iOS responses -> real AppState subscription -> routing and read state.
// Only authored preferences/rows; no OS notification-delivery claim.
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart'
    as os;
import 'package:whoop_companion/ble/ble_engine.dart';
import 'package:whoop_companion/ble/ios_ble_restore.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/notify/notification_log.dart';
import 'package:whoop_companion/notify/notification_service.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/sync/band_ownership.dart';
import 'package:whoop_companion/sync/ios_bg_task.dart';
import 'coverage_ble_durable_boundary_test.dart' show until;
import 'coverage_gatt_connection_test.dart' show Peripheral;
import 'support/coverage_store.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  const timezone = MethodChannel('flutter_timezone');
  final notifications = NotificationService.instance;
  final history = NotificationLog.instance;
  final peripheral = Peripheral();
  late AppState app;
  setUpAll(() async {
    await coverageStore('app-notification-taps');
    await resetCoverageStore();
    os.FlutterBluePlusPlatform.instance = peripheral;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    IOSFlutterLocalNotificationsPlugin.registerWith();
    messenger
      ..setMockMethodCallHandler(timezone, (_) async => 'UTC')
      ..setMockMethodCallHandler(
        channel,
        (call) async => switch (call.method) {
          'initialize' => true,
          'getNotificationAppLaunchDetails' => {
            'notificationLaunchedApp': false,
          },
          'pendingNotificationRequests' => [],
          'checkPermissions' => {'isEnabled': false},
          _ => null,
        },
      );
    await notifications.init();
    await history.entries();
  });
  setUp(() async {
    await resetCoverageStore();
    BandOwnership.resetForTest();
    BleEngine.resetBandClaimForTest();
    peripheral.trace.clear();
    notifications.debugProbePermission = () async => false;
    notifications.debugRequestPermission = () async => false;
    notifications.debugCancel = (_) async {};
    notifications.invalidatePermissionCache();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    app = AppState();
    peripheral.engine = app.engine;
    await until(() => app.initialized || app.initError != null, attempts: 2000);
    expect(app.initError, isNull);
  });
  tearDown(() async {
    await app.pauseForBackground();
    await app.endSession();
    app.dispose();
    await app.engine.disconnect();
    await history.entries();
    IosBgTask.foregroundPull = null;
    IosBleRestore.onWake = null;
    IosBleRestore.foregroundActive = false;
    notifications.debugProbePermission = null;
    notifications.debugRequestPermission = null;
    notifications.debugCancel = null;
    notifications.invalidatePermissionCache();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    BandOwnership.resetForTest();
    BleEngine.resetBandClaimForTest();
  });
  tearDownAll(() async {
    messenger
      ..setMockMethodCallHandler(channel, null)
      ..setMockMethodCallHandler(timezone, null);
    debugDefaultTargetPlatformOverride = null;
    await LocalDb.close();
  });

  Future<void> deliver(String route) async {
    final reply = Completer<void>();
    // Use the plugin's registered callback, not the private tap router.
    // ignore: deprecated_member_use
    messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('didReceiveNotificationResponse', {
          'notificationId': 2460,
          'payload': route,
          'notificationResponseType': 0,
        }),
      ),
      (_) => reply.complete(),
    );
    await reply.future;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  for (final c in [
    (route: '/today', tab: 0, screen: null),
    (route: '/body', tab: 3, screen: null),
    (route: '/workouts/pushups', tab: 4, screen: '/workouts/pushups'),
    (route: '/status', tab: 0, screen: '/status'),
    (
      route: '/food/day?day=2021-04-06',
      tab: 6,
      screen: '/food/day?day=2021-04-06',
    ),
    (route: '/retired-link', tab: 0, screen: null),
  ]) {
    test(
      'real app notification tap ${c.route} routes and marks only its history',
      () async {
        await history.record(
          title: 'Other authored notice',
          body: '',
          category: 'reminders',
          route: '/untapped',
        );
        await history.record(
          title: 'Tapped authored notice',
          body: 'Keep this body',
          category: 'reminders',
          route: c.route,
        );
        final before = await history.entries();
        expect(before.where((e) => e.read), isEmpty);
        await deliver(c.route);
        expect(app.navRequest.value, c.tab);
        expect(app.screenRequest.value, c.screen);
        final after = await history.entries();
        expect(after, hasLength(2));
        final tapped = after.singleWhere(
          (e) => e.title == 'Tapped authored notice',
        );
        expect(tapped.read, true);
        expect(tapped.route, c.route);
        expect(tapped.body, 'Keep this body');
        expect(
          after.singleWhere((e) => e.title == 'Other authored notice').read,
          false,
        );
        expect(peripheral.trace, isNot(contains('connect')));
        await deliver(c.route);
        expect((await history.entries()).where((e) => e.read), hasLength(1));
      },
    );
  }
  for (final state in [AppLifecycleState.paused, AppLifecycleState.hidden]) {
    test(
      'real startup lifecycle $state retains background ownership until foreground',
      () async {
        await app.endSession();
        app.dispose();
        await app.engine.disconnect();
        binding.handleAppLifecycleStateChanged(state);
        app = AppState();
        peripheral.engine = app.engine;
        await until(
          () => app.initialized || app.initError != null,
          attempts: 2000,
        );
        expect(app.initError, isNull);
        expect(app.engine.isForegroundActive(), false);
        await app.openSession();
        expect(app.engine.isForegroundActive(), true);
        expect(peripheral.trace, isNot(contains('connect')));
        await app.pauseForBackground();
        expect(app.engine.isForegroundActive(), false);
      },
    );
  }
}
