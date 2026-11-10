// Actual overdue reminder scheduler with scripted iOS acknowledgement/refusal.
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/pushup_reminders.dart';
import 'package:whoop_companion/data/pushups.dart';
import 'package:whoop_companion/notify/notification_log.dart';
import 'package:whoop_companion/notify/notification_service.dart';
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  const timezone = MethodChannel('flutter_timezone');
  final service = NotificationService.instance;
  final calls = <MethodCall>[];
  final pending = <int>{};
  var refuseFirst = false;
  setUpAll(() => coverageStore('pushup-overdue-cadence', fresh: true));
  setUp(() async {
    await resetCoverageStore();
    calls.clear();
    pending.clear();
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    IOSFlutterLocalNotificationsPlugin.registerWith();
    service.invalidatePermissionCache();
    service.debugProbePermission = () async => true;
    service.debugRequestPermission = () async => true;
    // Select the shipped iOS actuator on the Windows/Linux test host. Delegate
    // to the real registered plugin, retaining its exact channel encoding.
    service.debugCancel = (id) => id == null
        ? FlutterLocalNotificationsPlugin().cancelAll()
        : FlutterLocalNotificationsPlugin().cancel(id);
    messenger
      ..setMockMethodCallHandler(timezone, (_) async => 'America/Chicago')
      ..setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        final args = call.arguments;
        if (call.method == 'zonedSchedule') {
          final id = (args as Map)['id'] as int;
          if (refuseFirst && id == NotificationService.idPushupNudgeBase) {
            throw PlatformException(code: 'authored_refusal');
          }
          pending.add(id);
        } else if (call.method == 'cancel') {
          pending.remove(args as int);
        }
        return switch (call.method) {
          'initialize' || 'requestPermissions' => true,
          _ => null,
        };
      });
  });
  tearDown(() async {
    await NotificationLog.instance.entries();
    service.debugProbePermission = null;
    service.debugRequestPermission = null;
    service.debugCancel = null;
    service.invalidatePermissionCache();
    debugDefaultTargetPlatformOverride = null;
    messenger
      ..setMockMethodCallHandler(channel, null)
      ..setMockMethodCallHandler(timezone, null);
  });
  tearDownAll(LocalDb.close);

  for (final overdue in [35, 185]) {
    for (final refused in [false, true]) {
      test(
        '$overdue-minute saved cadence catches up${refused ? ' after refusal/retry' : ''}',
        () async {
          // A stored running clock can be hours overdue when foreground rearming
          // resumes. Invoke its actual scheduler, without advancing its anchor.
          final before = DateTime.now();
          final anchor = before.subtract(Duration(minutes: overdue));
          final expectedFirst = anchor.add(Duration(minutes: overdue + 5));
          const sid = 'authored-running-session';
          final ids = {
            for (var i = 0; i < NotificationService.maxPushupNudges; i++)
              NotificationService.idPushupNudgeBase + i,
          };
          final allIds = {...ids, NotificationService.idPushupRegular};
          final prefs = await SharedPreferences.getInstance();

          Future<void> verifyAttempt(bool refusal) async {
            calls.clear();
            refuseFirst = refusal;
            expect(await PushupReminders.scheduleBatch(sid, anchor), !refusal);
            final schedules = calls
                .where((c) => c.method == 'zonedSchedule')
                .toList();
            expect(schedules, hasLength(NotificationService.maxPushupNudges));
            final wireIds = <int>{};
            for (var i = 0; i < schedules.length; i++) {
              final wire = schedules[i].arguments as Map;
              wireIds.add(wire['id'] as int);
              final at = DateTime.parse(
                wire['scheduledDateTimeISO8601'] as String,
              );
              expect(
                at.millisecondsSinceEpoch,
                expectedFirst
                    .add(Duration(minutes: kPushupNudgeMinutes * i))
                    .millisecondsSinceEpoch,
              );
              expect(at.isAfter(before), true);
              expect(wire['timeZoneName'], 'America/Chicago');
              expect(wire['matchDateTimeComponents'], isNull);
              final route = Uri.parse(wire['payload'] as String);
              expect(route.path, '/workouts/pushups');
              expect(route.queryParameters, {
                's': sid,
                'a': '${anchor.millisecondsSinceEpoch}',
              });
            }
            expect(wireIds, ids);
            final canceled = calls
                .where((c) => c.method == 'cancel')
                .map((c) => c.arguments as int)
                .toList();
            for (final id in allIds) {
              expect(
                canceled.where((n) => n == id),
                hasLength(refusal ? 2 : 1),
              );
            }
            final plans =
                jsonDecode(prefs.getString('notify.plans') ?? '{}') as Map;
            if (refusal) {
              expect(pending, isEmpty);
              expect(plans, isEmpty);
            } else {
              expect(pending, ids);
              expect(plans.keys.toSet(), ids.map((id) => '$id').toSet());
              for (var i = 0; i < schedules.length; i++) {
                final plan =
                    plans['${NotificationService.idPushupNudgeBase + i}']
                        as Map;
                expect(
                  plan['first'],
                  expectedFirst
                      .add(Duration(minutes: kPushupNudgeMinutes * i))
                      .millisecondsSinceEpoch,
                );
              }
            }
          }

          await verifyAttempt(refused);
          if (refused) await verifyAttempt(false);
        },
      );
    }
  }
}
