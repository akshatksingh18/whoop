// The reset's acknowledged cancellation must retain state on adapter failure.
import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whoop_companion/notify/notification_log.dart';
import 'package:whoop_companion/notify/notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final service = NotificationService.instance;
  final oldCancel = service.debugCancel;
  final plans = jsonEncode({
    '2422': {
      'first': 1617714000000,
      'repeat': 'once',
      'title': 'Authored reminder',
      'body': 'Authored future reminder',
      'category': 'reminders',
      'route': '/body',
    },
  });
  final log = jsonEncode([
    LoggedNotification(
      key: 'authored-retained',
      at: DateTime.fromMillisecondsSinceEpoch(1617714000000),
      title: 'Authored history',
      body: 'Preserve this history',
      category: 'reminders',
      origin: NotificationOrigin.submitted,
    ).toJson(),
  ]);
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'notify.plans': plans,
      'notify.log': log,
      'authored-unrelated': 'keep',
    }),
  );
  tearDown(() => service.debugCancel = oldCancel);
  for (final kind in ['missing-plugin', 'platform', 'timeout']) {
    test(
      'strict iOS reset cancellation retains its records after $kind and retries',
      () async {
        final prefs = await SharedPreferences.getInstance();
        final error = switch (kind) {
          'missing-plugin' => MissingPluginException(
            'authored missing adapter',
          ),
          'platform' => PlatformException(code: 'authored_cancel_failure'),
          _ => TimeoutException('authored cancellation timeout'),
        };
        var calls = 0;
        service.debugCancel = (id) async {
          expect(id, isNull);
          calls++;
          throw error;
        };
        await expectLater(
          service.cancelAll(requireAcknowledgement: true, isIOS: true),
          throwsA(same(error)),
        );
        expect(calls, 1);
        expect(prefs.getString('notify.plans'), plans);
        expect(prefs.getString('notify.log'), log);
        expect(prefs.getString('authored-unrelated'), 'keep');
        service.debugCancel = (id) async {
          expect(id, isNull);
          calls++;
        };
        await service.cancelAll(requireAcknowledgement: true, isIOS: true);
        expect(calls, 2);
        expect(prefs.getString('notify.plans'), isNull);
        expect(prefs.getString('notify.log'), isNull);
        expect(prefs.getString('authored-unrelated'), 'keep');
      },
    );
  }
}
