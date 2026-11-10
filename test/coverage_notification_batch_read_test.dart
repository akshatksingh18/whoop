// Real Mark all read action and preference serialization. Store latency/failure
// is scripted at the existing preference boundary; no OS delivery is claimed.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:whoop_companion/notify/notification_log.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/screens/notifications_screen.dart';

import 'coverage_notification_page_write_boundary_test.dart' show NoticeStore;
import 'coverage_nutrition_root_test.dart' show io;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/localized_coverage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final history = NotificationLog.instance;
  late SharedPreferencesStorePlatform original;
  late NoticeStore store;
  late AppState app;
  late List<Map<String, dynamic>> saved;
  setUpAll(loadAuditFonts);
  setUp(() {
    original = SharedPreferencesStorePlatform.instance;
    store = NoticeStore();
    SharedPreferencesStorePlatform.instance = store;
    SharedPreferences.resetStatic();
    app = AppState.forTesting();
    history.clock = () => DateTime(2021, 4, 6, 12);
    saved = [
      for (var i = 0; i < 3; i++)
        LoggedNotification(
          key: 'authored-$i',
          at: DateTime(2021, 4, 6, 9 + i),
          title: 'Authored notice $i',
          body: 'Preserve body $i',
          category: 'reminders',
          route: '/food/day?day=2021-04-05',
          read: i == 0,
        ).toJson(),
    ];
    store.values['flutter.notify.log'] = jsonEncode(saved);
  });
  tearDown(() {
    app.dispose();
    history.clock = DateTime.now;
    SharedPreferencesStorePlatform.instance = original;
    SharedPreferences.resetStatic();
  });
  Future<void> open(WidgetTester t) async {
    await t.runAsync(history.entries);
    await localizedPage(
      t,
      const NotificationsScreen(),
      app: app,
      settle: false,
    );
    await io(t);
    expect(find.text('Mark all read'), findsOneWidget);
    expect(history.unread.value, 2);
  }

  VoidCallback action(WidgetTester t) => t
      .widget<TextButton>(find.widgetWithText(TextButton, 'Mark all read'))
      .onPressed!;
  Future<void> exactSaved(WidgetTester t, {required bool allRead}) async {
    SharedPreferences.resetStatic();
    final entries = (await t.runAsync(history.entries))!;
    expect(entries, hasLength(3));
    for (final e in entries) {
      final before = saved.singleWhere((r) => r['k'] == e.key);
      final expected = {...before};
      if (allRead || before['read'] == true) {
        expected['read'] = true;
      } else {
        expected.remove('read');
      }
      expect(e.toJson(), expected);
    }
    expect(history.unread.value, allRead ? 0 : 2);
    expect(t.takeException(), isNull);
  }

  for (final throwing in [false, true]) {
    testWidgets(
      'Mark all read ${throwing ? 'exception' : 'refusal'} preserves every notice and can retry',
      (t) async {
        await open(t);
        final nav = app.navRequest.value, route = app.screenRequest.value;
        store.refuse = !throwing;
        store.throwing = throwing;
        await invokeControl(t, action(t));
        await io(t);
        expect(
          find.text('Could not mark them read. Try again.'),
          findsOneWidget,
        );
        expect(find.text('Mark all read'), findsOneWidget);
        await exactSaved(t, allRead: false);
        store.refuse = store.throwing = false;
        await invokeControl(t, action(t));
        await io(t);
        expect(find.text('Mark all read'), findsNothing);
        await exactSaved(t, allRead: true);
        expect(app.navRequest.value, nav);
        expect(app.screenRequest.value, route);
      },
    );
  }
  for (final outcome in ['success', 'refusal', 'exception']) {
    testWidgets(
      'leaving during Mark all read $outcome never updates the disposed page or opens a route',
      (t) async {
        await open(t);
        store.started = false;
        store.held = Completer<void>();
        store.refuse = outcome == 'refusal';
        store.throwing = outcome == 'exception';
        final callback = action(t) as dynamic;
        final Future<void> pending = callback();
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)),
        );
        expect(store.started, true);
        final nav = app.navRequest.value, route = app.screenRequest.value;
        await t.pumpWidget(const SizedBox());
        await t.pumpAndSettle();
        store.held!.complete();
        await t.runAsync(() => pending);
        await io(t);
        await exactSaved(t, allRead: outcome == 'success');
        expect(app.navRequest.value, nav);
        expect(app.screenRequest.value, route);
      },
    );
  }
}
