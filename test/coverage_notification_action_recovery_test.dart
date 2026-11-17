// Scripted iOS callbacks reach the real action router and authored SQLite data.
// Plugin replies do not establish notification delivery or phone acceptance.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/food_day_reminder.dart';
import 'package:whoop_companion/data/home_region.dart';
import 'package:whoop_companion/data/nutrition_store.dart';
import 'package:whoop_companion/data/pushup_reminders.dart';
import 'package:whoop_companion/data/pushups.dart';
import 'package:whoop_companion/notify/notification_service.dart';

import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  const timezone = MethodChannel('flutter_timezone');
  const home = MethodChannel('whoop/home_region');
  final service = NotificationService.instance;
  final routes = <String>[], logs = <String>[];
  final calls = <MethodCall>[];
  bool? permission = false, requestResult = false;
  var refusePermissionRead = false;
  late StreamSubscription<String> subscription;
  late DebugPrintCallback previousPrint;
  setUpAll(() async {
    await coverageStore('notification-action-recovery');
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    IOSFlutterLocalNotificationsPlugin.registerWith();
    messenger
      ..setMockMethodCallHandler(timezone, (_) async => 'UTC')
      ..setMockMethodCallHandler(
        home,
        (call) async => call.method == 'drain' ? [] : null,
      )
      ..setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'checkPermissions' && refusePermissionRead) {
          throw PlatformException(code: 'authored_permission_refusal');
        }
        return switch (call.method) {
          'initialize' => true,
          'requestPermissions' => requestResult,
          'checkPermissions' =>
            permission == null ? null : {'isEnabled': permission},
          'pendingNotificationRequests' => [],
          _ => null,
        };
      });
    await service.init();
    subscription = service.taps.listen(routes.add);
    previousPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      if (message != null) logs.add(message);
    };
  });
  setUp(() async {
    await resetCoverageStore();
    await PushupReminders.clearInbox();
    await PushupReminders.writeMirror(null);
    routes.clear();
    logs.clear();
    calls.clear();
    permission = false;
    requestResult = false;
    refusePermissionRead = false;
    service.invalidatePermissionCache();
    service.debugRequestPermission = () async => false;
    service.debugProbePermission = () async => false;
    service.debugCancel = (_) async {};
  });
  tearDown(() async {
    await (await LocalDb.instance).execute(
      'DROP TRIGGER IF EXISTS authored_action_refusal',
    );
  });
  tearDownAll(() async {
    await subscription.cancel();
    debugPrint = previousPrint;
    service.debugRequestPermission = null;
    service.debugProbePermission = null;
    service.debugCancel = null;
    service.invalidatePermissionCache();
    debugDefaultTargetPlatformOverride = null;
    messenger
      ..setMockMethodCallHandler(channel, null)
      ..setMockMethodCallHandler(timezone, null)
      ..setMockMethodCallHandler(home, null);
    await LocalDb.close();
  });

  Future<List<Object>> deliver({
    String? action,
    String? route,
    int id = 2460,
  }) async {
    final escaped = <Object>[];
    await runZonedGuarded(() async {
      final reply = Completer<void>();
      // The plugin owns the callback registration; do not call a private router.
      // ignore: deprecated_member_use
      messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('didReceiveNotificationResponse', {
            'notificationId': id,
            'actionId': action,
            'payload': route,
            'notificationResponseType': 1,
          }),
        ),
        (_) => reply.complete(),
      );
      await reply.future;
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }, (error, _) => escaped.add(error));
    return escaped;
  }

  for (final route in <String?>[null, '', '/food?date=2021-04-06']) {
    test('ordinary notification callback retains route $route', () async {
      expect(await deliver(route: route), isEmpty);
      expect(routes, route == null || route.isEmpty ? isEmpty : [route]);
      expect(await (await LocalDb.instance).query('food_day_mark'), isEmpty);
      expect(await PushupDb.all(), isEmpty);
    });
  }
  test(
    'iOS permission handoff prompts once and rechecks a foreground revocation',
    () async {
      service.debugRequestPermission = null;
      service.debugProbePermission = null;
      expect(await service.ensurePermission(allowPrompt: false), false);
      expect(calls.where((c) => c.method == 'requestPermissions'), isEmpty);
      requestResult = true;
      expect(await service.ensurePermission(), true);
      expect(await service.ensurePermission(), true);
      final request = calls.singleWhere(
        (c) => c.method == 'requestPermissions',
      );
      expect(request.arguments, {
        'alert': true,
        'badge': true,
        'sound': true,
        'provisional': false,
        'critical': false,
      });
      service.invalidatePermissionCache();
      expect(await service.ensurePermission(allowPrompt: false), false);
      expect(
        calls.where((c) => c.method == 'requestPermissions'),
        hasLength(1),
      );
    },
  );
  for (final reply in <bool?>[null, false]) {
    test(
      'iOS denied request $reply can recover through a live grant without reprompting',
      () async {
        service.debugRequestPermission = null;
        service.debugProbePermission = null;
        requestResult = reply;
        expect(await service.ensurePermission(), false);
        expect(await service.ensurePermission(), false);
        permission = true;
        expect(await service.ensurePermission(), true);
        expect(
          calls.where((c) => c.method == 'requestPermissions'),
          hasLength(1),
        );
        expect(
          calls.where((c) => c.method == 'checkPermissions'),
          hasLength(2),
        );
      },
    );
  }
  test(
    'missing and refused iOS permission replies fail closed and remain retryable',
    () async {
      service.debugProbePermission = null;
      permission = null;
      expect(await service.hasPermission(), false);
      refusePermissionRead = true;
      expect(await service.hasPermission(), false);
      refusePermissionRead = false;
      permission = true;
      expect(await service.hasPermission(), true);
      expect(calls.where((c) => c.method == 'requestPermissions'), isEmpty);
    },
  );
  test('Food Not yet neither marks a day nor opens its payload', () async {
    expect(await deliver(action: kFoodNotYetAction, route: '/food'), isEmpty);
    expect(routes, isEmpty);
    expect(await (await LocalDb.instance).query('food_day_mark'), isEmpty);
  });
  test(
    'refused Food completion is observed and its next action can retry',
    () async {
      final db = await LocalDb.instance;
      await NutritionDb.setDayMark(db, '2021-04-06', 'incomplete');
      final before = await db.query('food_day_mark');
      await db.execute(
        "CREATE TRIGGER authored_action_refusal BEFORE INSERT ON food_day_mark BEGIN SELECT RAISE(ABORT,'authored Food refusal'); END",
      );
      expect(
        await deliver(action: kFoodCompleteAction, route: '/food'),
        isEmpty,
      );
      expect(await db.query('food_day_mark'), before);
      expect(
        logs.where((s) => s.contains('authored Food refusal')),
        hasLength(1),
      );
      expect(routes, ['/food']);
      await db.execute('DROP TRIGGER authored_action_refusal');
      expect(
        await deliver(action: kFoodCompleteAction, route: '/food'),
        isEmpty,
      );
      final saved = await NutritionDb.dayMarks(db, '2021-04-06', strict: true);
      expect(saved['2021-04-06'], 'incomplete');
      expect(saved.values.where((s) => s == 'complete'), hasLength(1));
      expect(routes, ['/food', '/food']);
    },
  );
  for (final action in [kPushupDoneAction, kPushupPauseAction]) {
    test(
      'refused $action preserves the day and its identical delivery retries once',
      () async {
        final session = await Pushups.start();
        final db = await LocalDb.instance;
        final before = await db.query('pushup_session');
        final mirror = await PushupReminders.readMirror();
        await db.execute(
          "CREATE TRIGGER authored_action_refusal BEFORE INSERT ON pushup_session BEGIN SELECT RAISE(ABORT,'authored Pushups refusal'); END",
        );
        final route = '/pushups?s=${session.id}&a=authored-anchor';
        expect(await deliver(action: action, route: route), isEmpty);
        expect(await db.query('pushup_session'), before);
        expect(await PushupReminders.readMirror(), mirror);
        expect(
          logs.where((s) => s.contains('authored Pushups refusal')),
          hasLength(1),
        );
        expect(routes, isEmpty, reason: 'Done and Pause do not navigate');
        await db.execute('DROP TRIGGER authored_action_refusal');
        expect(await deliver(action: action, route: route), isEmpty);
        expect(await deliver(action: action, route: route), isEmpty);
        final saved = (await PushupDb.active())!;
        expect(saved.id, session.id);
        expect(saved.count, action == kPushupDoneAction ? 1 : 0);
        expect(
          saved.state,
          action == kPushupPauseAction
              ? PushupState.paused
              : PushupState.running,
        );
        expect(saved.receipts, hasLength(1));
        expect(routes, isEmpty);
        expect((await HomeRegion.automation()).presence, HomePresence.unknown);
      },
    );
  }
}
