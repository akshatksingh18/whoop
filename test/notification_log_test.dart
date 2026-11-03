// The Notifications page's log (Build 95): what was shown stays findable for
// 90 days, scheduled notifications are recorded once their time has passed,
// and a cancel never erases what already fired.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/notify/notification_log.dart';
import 'package:whoop_companion/ui2/screens/notifications_screen.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final log = NotificationLog.instance;
  late DateTime now;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    now = DateTime(2026, 10, 19, 12);
    log.clock = () => now;
    await log.clear();
  });

  test('a shown notification is kept, newest first, and counts as unread',
      () async {
    await log.record(
      title: 'Older',
      body: 'a',
      category: 'reminders',
      at: now.subtract(const Duration(hours: 2)),
    );
    await log.record(title: 'Newer', body: 'b', category: 'health', route: '/x');
    final all = await log.entries();
    expect(all.map((e) => e.title), ['Newer', 'Older']);
    expect(all.first.route, '/x');
    expect(log.unread.value, 2);
    await log.markRead(all.first.key);
    expect(log.unread.value, 1);
    await log.markAllRead();
    expect(log.unread.value, 0);
  });

  test('entries older than 90 days are dropped', () async {
    await log.record(
      title: 'Old',
      body: '',
      category: 'reminders',
      at: now.subtract(const Duration(days: 91)),
    );
    await log.record(title: 'Recent', body: '', category: 'reminders');
    expect((await log.entries()).map((e) => e.title), ['Recent']);
  });

  test('a scheduled notification appears only once its time has passed',
      () async {
    await log.plan(
      id: 7,
      first: now.add(const Duration(hours: 1)),
      repeat: PlanRepeat.once,
      title: 'Lookback',
      body: 'Your week',
      category: 'reminders',
      route: '/recap',
    );
    await log.reconcile();
    expect(await log.entries(), isEmpty);
    now = now.add(const Duration(hours: 2));
    await log.reconcile();
    await log.reconcile(); // recorded once, not again
    final all = await log.entries();
    expect(all, hasLength(1));
    expect(all.single.route, '/recap');
    expect(all.single.at, DateTime(2026, 10, 19, 13));
  });

  test('a daily reminder records each day it fired, and a cancel keeps them',
      () async {
    await log.plan(
      id: 9,
      first: DateTime(2026, 10, 19, 20),
      repeat: PlanRepeat.daily,
      title: 'Evening food check',
      body: '',
      category: 'reminders',
    );
    now = DateTime(2026, 10, 21, 21);
    await log.unplan(9);
    final days = [for (final e in await log.entries()) e.at.day];
    expect(days, [21, 20, 19]);
    now = DateTime(2026, 10, 25, 21);
    await log.reconcile();
    expect(await log.entries(), hasLength(3), reason: 'cancelled is cancelled');
  });

  test('replacing a plan keeps what the old one already showed', () async {
    await log.plan(
      id: 3,
      first: DateTime(2026, 10, 19, 9),
      repeat: PlanRepeat.once,
      title: 'Still working out?',
      body: '',
      category: 'reminders',
    );
    now = DateTime(2026, 10, 19, 10);
    await log.plan(
      id: 3,
      first: DateTime(2026, 10, 19, 11),
      repeat: PlanRepeat.once,
      title: 'Still working out?',
      body: '',
      category: 'reminders',
    );
    expect(await log.entries(), hasLength(1));
  });

  test('a tap from the phone marks the newest matching entry read', () async {
    await log.record(title: 'A', body: '', category: 'reminders', route: '/r');
    await log.markRouteRead('/r');
    expect(log.unread.value, 0);
  });

  testWidgets('the page groups by day and the bell shows the unread count',
      (t) async {
    final today = DateTime.now();
    final entries = [
      LoggedNotification(
        key: 'a',
        at: today,
        title: 'Your week in review',
        body: 'Resting heart rate ran lower.',
        category: 'reminders',
      ),
      LoggedNotification(
        key: 'b',
        at: today.subtract(const Duration(days: 1)),
        title: 'Did you work out?',
        body: '42 minutes of raised heart rate.',
        category: 'health',
        read: true,
      ),
    ];
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: NotificationsScreen(entries: entries),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.text('Your week in review'), findsOneWidget);
    expect(find.textContaining('Kept for 90 days'), findsOneWidget);
    expect(t.takeException(), isNull);

    log.unread.value = 2;
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: const Scaffold(body: Center(child: NotificationsBell())),
      ),
    );
    expect(find.bySemanticsLabel('Notifications, 2 unread'), findsOneWidget);
  });
}
