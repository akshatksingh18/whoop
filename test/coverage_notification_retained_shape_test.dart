import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whoop_companion/notify/notification_log.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final log = NotificationLog.instance;
  final at = DateTime(2021, 4, 6, 12);
  late DateTime now;

  setUp(() {
    now = at;
    log.clock = () => now;
  });
  tearDown(() => log.clock = DateTime.now);

  for (final invalidHistory in ['{', '{}']) {
    test(
      'an unreadable history survives a read attempt and accepts a later entry: $invalidHistory',
      () async {
        SharedPreferences.setMockInitialValues({'notify.log': invalidHistory});
        final prefs = await SharedPreferences.getInstance();
        await log.markRead('no-entry');
        expect(prefs.getString('notify.log'), invalidHistory);

        await log.record(
          title: 'Authored reminder',
          body: 'Authored reminder body',
          category: 'reminders',
          route: '/body',
        );
        final entry = (await log.entries()).single;
        expect(entry.at, at);
        expect(entry.title, 'Authored reminder');
        expect(entry.body, 'Authored reminder body');
        expect(entry.origin, NotificationOrigin.submitted);
        expect(entry.route, '/body');
        expect(entry.read, isFalse);
        final snapshot = prefs.getString('notify.log');
        expect(jsonDecode(snapshot!) as List, hasLength(1));
        expect((await log.entries()).single.toJson(), entry.toJson());
        expect(prefs.getString('notify.log'), snapshot);
      },
    );
  }

  for (final invalidPlans in ['{', '[]']) {
    test(
      'unreadable plans do not erase submitted history or duplicate a new occurrence: $invalidPlans',
      () async {
        final original = LoggedNotification(
          key: 'authored-original',
          at: at.subtract(const Duration(hours: 1)),
          title: 'Authored earlier reminder',
          body: 'Retained body',
          category: 'reminders',
          route: '/body',
          read: true,
          origin: NotificationOrigin.submitted,
        ).toJson();
        SharedPreferences.setMockInitialValues({
          'notify.log': jsonEncode([original]),
          'notify.plans': invalidPlans,
        });
        final due = at.add(const Duration(hours: 1));
        await log.plan(
          id: 411,
          first: due,
          repeat: PlanRepeat.once,
          title: 'Authored scheduled reminder',
          body: 'Precisely one occurrence',
          category: 'reminders',
          route: '/recap',
        );
        expect((await log.entries()).single.toJson(), original);
        now = due;
        final entries = await log.entries();
        expect(entries, hasLength(2));
        expect(entries.first.at, due);
        expect(entries.first.title, 'Authored scheduled reminder');
        expect(entries.first.origin, NotificationOrigin.scheduled);
        expect(entries.first.route, '/recap');
        expect(entries.last.toJson(), original);
        expect(
          (await log.entries()).map((entry) => entry.toJson()),
          entries.map((entry) => entry.toJson()),
        );
        final prefs = await SharedPreferences.getInstance();
        expect(jsonDecode(prefs.getString('notify.plans')!), isEmpty);
      },
    );
  }
}
