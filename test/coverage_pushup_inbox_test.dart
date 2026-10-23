import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:openstrap_edge/data/pushup_reminders.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.root);
  final String root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  setUp(() async {
    final parent = await Directory(
      'build/coverage-audit/pushup-inbox',
    ).create(recursive: true);
    root = await parent.createTemp('synthetic-');
    PathProviderPlatform.instance = _Paths(root.absolute.path);
  });
  tearDown(() async => root.delete(recursive: true));

  test(
    'simultaneous background actions all remain durable without a database',
    () async {
      await Future.wait([
        for (var i = 0; i < 12; i++)
          PushupReminders.onAction(
            NotificationResponse(
              notificationResponseType:
                  NotificationResponseType.selectedNotificationAction,
              id: i,
              actionId: kPushupDoneAction,
              payload: '/pushups?s=synthetic-session&a=$i',
            ),
            background: true,
          ),
      ]);
      final actions = await PushupReminders.readInbox();
      expect(actions, hasLength(12));
      expect(actions.map((a) => a.id).toSet(), hasLength(12));
    },
  );

  test(
    'a legacy inbox and new actions are read together after upgrading',
    () async {
      final legacy = {
        'id': 'legacy',
        'kind': 'done',
        'session': 'synthetic-session',
        'at': DateTime(2026, 1, 1).millisecondsSinceEpoch,
      };
      await File(
        '${root.path}/pushups_inbox.json',
      ).writeAsString(jsonEncode([legacy]));
      await PushupReminders.onAction(
        const NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotificationAction,
          id: 1,
          actionId: kPushupDoneAction,
          payload: '/pushups?s=synthetic-session&a=1',
        ),
        background: true,
      );
      expect(
        (await PushupReminders.readInbox()).map((a) => a.id),
        contains('legacy'),
      );
      expect(await PushupReminders.readInbox(), hasLength(2));
    },
  );

  test('duplicate deliveries retain the earliest action once', () async {
    const response = NotificationResponse(
      notificationResponseType:
          NotificationResponseType.selectedNotificationAction,
      id: 1,
      actionId: kPushupDoneAction,
      payload: '/pushups?s=synthetic-session&a=1',
    );
    await PushupReminders.onAction(response, background: true);
    final first = (await PushupReminders.readInbox()).single.at;
    await PushupReminders.onAction(response, background: true);
    final inbox = await PushupReminders.readInbox();
    expect(inbox, hasLength(1));
    expect(inbox.single.at, first);
  });

  test(
    'reset clears only the owned inbox, including unfinished staging',
    () async {
      final dir = await Directory('${root.path}/pushups_inbox').create();
      await File('${dir.path}/unfinished.tmp').writeAsString('synthetic');
      await File('${root.path}/pushups_inbox.json').writeAsString('[]');
      final unrelated = File('${root.path}/unrelated.txt');
      await unrelated.writeAsString('keep');
      expect(await PushupReminders.readInbox(), isEmpty);
      await PushupReminders.clearInbox();
      expect(await dir.exists(), isFalse);
      expect(await File('${root.path}/pushups_inbox.json').exists(), isFalse);
      expect(await unrelated.readAsString(), 'keep');
    },
  );

  test(
    'an unreadable inbox is an explicit error and is retained for recovery',
    () async {
      final file = File('${root.path}/pushups_inbox.json');
      await file.writeAsString('{unfinished');
      await expectLater(PushupReminders.readInbox(), throwsFormatException);
      expect(await file.readAsString(), '{unfinished');
    },
  );
}
