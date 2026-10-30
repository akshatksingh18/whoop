// Authored iOS plugin replies; verifies Dart handoff and local history, not OS delivery.
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whoop_companion/notify/notification_event.dart';
import 'package:whoop_companion/notify/notification_log.dart';
import 'package:whoop_companion/notify/notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  const zoneChannel = MethodChannel('flutter_timezone');
  final service = NotificationService.instance;
  final calls = <MethodCall>[];
  var refuse = false;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    IOSFlutterLocalNotificationsPlugin.registerWith();
    calls.clear();
    refuse = false;
    service.invalidatePermissionCache();
    service.debugProbePermission = () async => true;
    service.debugRequestPermission = () async => true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      ..setMockMethodCallHandler(zoneChannel, (_) async => 'America/New_York')
      ..setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (refuse) throw PlatformException(code: 'synthetic_refusal');
        return switch (call.method) {
          'initialize' || 'requestPermissions' => true,
          'checkPermissions' => {
            'isEnabled': true,
            'isAlertEnabled': true,
            'isBadgeEnabled': true,
            'isSoundEnabled': true,
          },
          'pendingNotificationRequests' => [
            {'id': 2422, 'title': 'Synthetic', 'body': '', 'payload': '/body'},
          ],
          'getNotificationAppLaunchDetails' => {
            'notificationLaunchedApp': true,
            'notificationResponse': {
              'id': 2422,
              'payload': '/body',
              'notificationResponseType': 0,
            },
          },
          _ => null,
        };
      });
  });
  tearDown(() async {
    await NotificationLog.instance.entries();
    service.debugProbePermission = null;
    service.debugRequestPermission = null;
    service.invalidatePermissionCache();
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      ..setMockMethodCallHandler(channel, null)
      ..setMockMethodCallHandler(zoneChannel, null);
  });
  for (final category in NotifCategory.values) {
    for (final allocated in [false, true]) {
      test(
        'COV-47 $category presentation keeps date, body and identity $allocated',
        () async {
          final event = NotificationEvent(
            category: category,
            title: 'Synthetic event',
            body: allocated ? 'Synthetic detail' : '',
            route: '/heart',
            date: '2021-04-06',
            dedupeKey: 'synthetic-$category',
            osId: allocated ? null : 2422,
          );
          expect(await service.presentEvent(event), true);
          final shown =
              calls.singleWhere((c) => c.method == 'show').arguments as Map;
          expect(shown['id'], allocated ? greaterThan(0) : 2422);
          expect(shown['title'], event.title);
          expect(shown['body'], allocated ? event.body : null);
          expect(shown['payload'], contains('2021-04-06'));
          final log = await NotificationLog.instance.entries();
          expect(log.single.title, event.title);
          expect(log.single.body, event.body);
          expect(log.single.route, shown['payload']);
          expect(log.single.origin, NotificationOrigin.submitted);
        },
      );
    }
  }
  for (final kind in ['daily', 'weekly', 'once', 'pushup', 'rest']) {
    test('COV-47 $kind schedule records only a successful handoff', () async {
      final at = DateTime.now().add(const Duration(days: 2));
      final id = kind == 'rest'
          ? NotificationService.idRestTimer
          : kind == 'pushup'
          ? NotificationService.idPushupRegular
          : NotificationService.idBodyReminder;
      switch (kind) {
        case 'daily':
          expect(
            await service.scheduleDaily(
              id: id,
              category: NotifCategory.reminders,
              title: 'Synthetic',
              body: 'Detail',
              hour: 23,
              minute: 59,
              route: '/body',
              skipToday: true,
              iosCategory: 'synthetic',
            ),
            true,
          );
        case 'weekly':
          expect(
            await service.scheduleWeekly(
              id: id,
              category: NotifCategory.reminders,
              title: 'Synthetic',
              body: 'Detail',
              weekday: DateTime.sunday,
              hour: 9,
              minute: 15,
              route: '/body',
            ),
            true,
          );
        case 'pushup':
          expect(
            await service.schedulePushup(
              id: id,
              title: 'Synthetic',
              body: 'Detail',
              at: at,
              payload: '/pushups',
            ),
            true,
          );
        default:
          await service.scheduleOnce(
            id: id,
            category: NotifCategory.reminders,
            title: 'Synthetic',
            body: 'Detail',
            at: at,
            route: '/body',
          );
      }
      final wire =
          calls.singleWhere((c) => c.method == 'zonedSchedule').arguments
              as Map;
      expect(wire['id'], id);
      expect(wire['timeZoneName'], 'America/New_York');
      final prefs = await SharedPreferences.getInstance();
      final plans = prefs.getString('notify.plans');
      if (kind == 'rest') {
        expect(plans == null || plans == '{}', true);
      } else {
        expect(jsonDecode(plans!), isNotEmpty);
        await service.cancel(id);
        expect(jsonDecode(prefs.getString('notify.plans')!), isEmpty);
      }
      expect(await service.pendingIds(), {2422});
      refuse = true;
      expect(await service.pendingIds(), isNull);
      expect(
        await service.presentEvent(
          const NotificationEvent(
            category: NotifCategory.health,
            title: 'Refused',
            body: '',
            osId: 2422,
            date: '2021-04-06',
            dedupeKey: 'refused',
          ),
        ),
        false,
      );
    });
  }
  test('COV-47 launch replay forwards the actual saved route', () async {
    final routes = <String>[];
    final sub = service.taps.listen(routes.add);
    await service.consumeLaunchRoute();
    await Future<void>.delayed(Duration.zero);
    expect(routes, ['/body']);
    refuse = true;
    await service.consumeLaunchRoute();
    expect(routes, ['/body']);
    await sub.cancel();
  });
}
