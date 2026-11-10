// Actual Darwin notification plugin IPC;authored replies and preference records.
// Verifies Dart acknowledgement/retention,not physical OS cancellation/delivery.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whoop_companion/notify/notification_log.dart';
import 'package:whoop_companion/notify/notification_service.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final service = NotificationService.instance;
  final log = NotificationLog.instance;
  final now = DateTime(2021, 4, 6, 12);
  final calls = <MethodCall>[];
  late SharedPreferences prefs;
  Object? refusal;
  Completer<void>? held;
  final plans = {
    for (final id in [2422, 2423])
      '$id': {
        'first': DateTime(2021, 4, 7, 12).millisecondsSinceEpoch,
        'repeat': 'once',
        'title': 'Authored plan $id',
        'body': 'Authored future reminder',
        'category': 'reminders',
        'route': '/body',
      },
  };
  final history = [
    LoggedNotification(
      key: 'authored-past-entry',
      at: DateTime(2021, 4, 6, 11),
      title: 'Authored past reminder',
      body: 'Preserve this history',
      category: 'reminders',
      origin: NotificationOrigin.submitted,
    ).toJson(),
  ];
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'notify.plans': jsonEncode(plans),
      'notify.log': jsonEncode(history),
    });
    prefs = await SharedPreferences.getInstance();
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    IOSFlutterLocalNotificationsPlugin.registerWith();
    log.clock = () => now;
    service.debugCancel = null;
    calls.clear();
    refusal = null;
    held = null;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      if (call.method == 'cancel' || call.method == 'cancelAll') {
        if (refusal case final error?) {
          throw error;
        }
        await held?.future;
      }
      return call.method == 'pendingNotificationRequests' ? [] : null;
    });
  });
  tearDown(() {
    log.clock = DateTime.now;
    service.debugCancel = null;
    debugDefaultTargetPlatformOverride = null;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });
  Map<String, dynamic> savedPlans() =>
      jsonDecode(prefs.getString('notify.plans') ?? '{}')
          as Map<String, dynamic>;
  void original() {
    expect(savedPlans(), plans);
    expect(jsonDecode(prefs.getString('notify.log')!), history);
  }

  Future<void> cancel(bool all, {required bool ack, bool? host = true}) => all
      ? service.cancelAll(requireAcknowledgement: ack, isIOS: host)
      : service.cancel(2422, requireAcknowledgement: ack, isIOS: host);
  Future<void> untilSent() async {
    for (
      var n = 0;
      n < 40 && !calls.any((c) => c.method.startsWith('cancel'));
      n++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    expect(calls.where((c) => c.method.startsWith('cancel')), hasLength(1));
  }

  void committed(bool all) {
    if (all) {
      expect(prefs.getString('notify.plans'), isNull);
      expect(prefs.getString('notify.log'), isNull);
    } else {
      expect(savedPlans(), {'2423': plans['2423']});
      expect(jsonDecode(prefs.getString('notify.log')!), history);
    }
  }

  for (final all in [false, true]) {
    for (final ack in all ? [true] : [false, true]) {
      for (final outcome in ['accepted', 'refused', 'missing plugin', 'held']) {
        test(
          'COV-64 native cancel all=$all acknowledgement=$ack outcome=$outcome preserves its owned records',
          () async {
            if (outcome == 'refused') {
              refusal = PlatformException(code: 'authored_cancel_refusal');
            }
            if (outcome == 'missing plugin') {
              refusal = MissingPluginException('authored absent plugin');
            }
            if (outcome == 'held') {
              held = Completer<void>();
            }
            original();
            final action = cancel(all, ack: ack);
            if (refusal != null && ack) {
              await expectLater(
                action,
                throwsA(
                  outcome == 'refused'
                      ? isA<PlatformException>()
                      : isA<MissingPluginException>(),
                ),
              );
            } else if (held != null) {
              await untilSent();
              original();
              held!.complete();
              await action;
            } else {
              await action;
            }
            final sent = calls
                .where((c) => c.method.startsWith('cancel'))
                .single;
            expect(sent.method, all ? 'cancelAll' : 'cancel');
            if (!all) {
              expect(sent.arguments, 2422);
            }
            if (refusal != null) {
              original();
            } else {
              committed(all);
            }
          },
        );
      }
    }
    for (final host in ['explicit other', 'default']) {
      test(
        'COV-64 cancel all=$all host=$host retains the original no-argument platform policy',
        () async {
          await cancel(all, ack: true, host: host == 'default' ? null : false);
          final sent = calls.where((c) => c.method.startsWith('cancel'));
          expect(sent.length, host == 'default' && Platform.isIOS ? 1 : 0);
          committed(all);
        },
      );
    }
  }
}
