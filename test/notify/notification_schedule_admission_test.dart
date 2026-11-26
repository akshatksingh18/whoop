// An immediate device alert cannot become a standing iOS schedule.
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whoop_companion/notify/notification_log.dart';
import 'package:whoop_companion/notify/notification_event.dart';
import 'package:whoop_companion/notify/notification_service.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final service = NotificationService.instance;
  final log = NotificationLog.instance;
  final when = DateTime(2021, 4, 7, 12);
  const title = 'Authored device alert';
  const body = 'Authored low-battery event';
  const category = NotifCategory.device;
  const id = NotificationService.idLowBattery;
  late SharedPreferences prefs;
  late Map<String, Object> before;
  final calls = <MethodCall>[];
  var permissionReads = 0;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    calls.clear();
    permissionReads = 0;
    service.invalidatePermissionCache();
    service.debugProbePermission = () async {
      permissionReads++;
      return false;
    };
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      return null;
    });
    await log.plan(
      id: NotificationService.idBodyReminder,
      first: when,
      repeat: PlanRepeat.weekly,
      title: 'Authored standing reminder',
      body: 'Retain the existing plan',
      category: NotifCategory.reminders.name,
      route: '/body',
    );
    before = {for (final k in prefs.getKeys()) k: prefs.get(k)!};
    expect(
      jsonDecode(prefs.getString('notify.plans')!),
      contains(NotificationService.idBodyReminder.toString()),
    );
  });

  tearDown(() {
    service.debugProbePermission = null;
    service.debugCancel = null;
    service.invalidatePermissionCache();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  for (final schedule in ['once', 'daily', 'weekly', 'pushup']) {
    test(
      '$schedule scheduling refuses an immediate-only slot before permission',
      () async {
        switch (schedule) {
          case 'once':
            await service.scheduleOnce(
              id: id,
              category: category,
              title: title,
              body: body,
              at: when,
            );
          case 'daily':
            expect(
              await service.scheduleDaily(
                id: id,
                category: category,
                title: title,
                body: body,
                hour: 12,
                minute: 0,
              ),
              isFalse,
            );
          case 'weekly':
            expect(
              await service.scheduleWeekly(
                id: id,
                category: category,
                title: title,
                body: body,
                weekday: DateTime.wednesday,
                hour: 12,
                minute: 0,
              ),
              isFalse,
            );
          case 'pushup':
            expect(
              await service.schedulePushup(
                id: id,
                title: title,
                body: body,
                at: when,
                payload: '/pushups',
              ),
              isFalse,
            );
        }
        expect(permissionReads, 0);
        expect(calls, isEmpty);
        expect({for (final k in prefs.getKeys()) k: prefs.get(k)}, before);
      },
    );
  }

  test('a refused cancelAll throws and retains history and plans', () async {
    await log.record(title: title, body: body, category: category.name);
    final history = prefs.getString('notify.log');
    expect(history, isNotNull);
    final cancelled = <int?>[];
    service.debugCancel = (target) async {
      cancelled.add(target);
      throw PlatformException(code: 'authored_cancel_refusal');
    };
    await expectLater(service.cancelAll(), throwsA(isA<PlatformException>()));
    expect(cancelled, [null]);
    expect(prefs.getString('notify.log'), history);
    expect(prefs.getString('notify.plans'), before['notify.plans']);
  });
}
