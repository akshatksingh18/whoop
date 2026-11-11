// Bell navigation uses the actual durable history reader; a read is never a mark.
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
import 'package:whoop_companion/ui2/ui2.dart';
import 'coverage_notification_page_write_boundary_test.dart' show NoticeStore;
import 'coverage_nutrition_root_test.dart' show io;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/localized_coverage.dart';

class _Reads extends NoticeStore {
  bool fail = false;
  Completer<void>? readStarted, release;
  @override
  Future<Map<String, Object>> getAll() async {
    if (release case final gate?) {
      readStarted!.complete();
      await gate.future;
      release = null;
    }
    if (fail) throw StateError('authored history read refusal');
    return Map.of(values);
  }
}

void main() {
  // Bell navigation starts the serialized preference reader without awaiting
  // it. Keep its I/O continuations on the real clock, with explicit frames.
  LiveTestWidgetsFlutterBinding().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  final history = NotificationLog.instance;
  late SharedPreferencesStorePlatform original;
  late _Reads store;
  late AppState app;
  late Map<String, Object> saved;
  setUpAll(loadAuditFonts);
  setUp(() {
    original = SharedPreferencesStorePlatform.instance;
    store = _Reads();
    SharedPreferencesStorePlatform.instance = store;
    SharedPreferences.resetStatic();
    history.clock = () => DateTime(2021, 4, 6, 12);
    app = AppState.forTesting();
    store.values['flutter.notify.log'] = jsonEncode([
      for (var i = 0; i < 2; i++)
        LoggedNotification(
          key: 'authored-bell-$i',
          at: DateTime(2021, 4, 6, 9 + i),
          title: 'Authored notice $i',
          body: 'Preserve body $i',
          category: 'reminders',
          route: '/food/day?day=2021-04-05',
        ).toJson(),
    ]);
  });
  tearDown(() async {
    store.release?.complete();
    store.release = null;
    store.fail = false;
    await history.entries();
    app.dispose();
    history.clock = DateTime.now;
    SharedPreferencesStorePlatform.instance = original;
    SharedPreferences.resetStatic();
  });
  Future<void> bell(WidgetTester t, {double scale = 1}) => localizedPage(
    t,
    const Scaffold(body: Center(child: NotificationsBell())),
    app: app,
    scale: scale,
  );
  Future<void> open(WidgetTester t) async {
    await t.tap(find.byType(NotificationsBell));
    await io(t);
    expect(find.byType(NotificationsScreen), findsOneWidget);
  }

  Future<void> warm(WidgetTester t) async {
    await t.runAsync(history.entries);
    saved = Map.of(store.values);
    expect(history.unread.value, 2);
  }

  for (final read in [false, true]) {
    for (final scale in [1.0, 3.1]) {
      testWidgets(
        'bell read=$read scale=$scale opens history without consuming unread evidence',
        (t) async {
          await warm(t);
          if (read) {
            await t.runAsync(history.markAllRead);
            saved = Map.of(store.values);
          }
          await bell(t, scale: scale);
          expect(history.unread.value, read ? 0 : 2);
          await open(t);
          expect(find.text('Authored notice 0'), findsOneWidget);
          expect(find.text('Authored notice 1'), findsOneWidget);
          expect(history.unread.value, read ? 0 : 2);
          expect(store.values, saved);
          expect(app.navRequest.value, -1);
          Navigator.of(t.element(find.byType(NotificationsScreen))).pop();
          await io(t);
          expect(find.byType(NotificationsBell), findsOneWidget);
          expect(find.byType(NotificationsScreen), findsNothing);
          expect(store.values, saved);
        },
        timeout: const Timeout(Duration(seconds: 45)),
      );
    }
  }
  for (final repeated in [false, true]) {
    testWidgets(
      'cold history read refusal retries${repeated ? ' repeatedly' : ''} without marking history read',
      (t) async {
        await warm(t);
        store.fail = true;
        SharedPreferences.resetStatic();
        await bell(t);
        await open(t);
        expect(find.text('Notifications could not load'), findsOneWidget);
        expect(history.unread.value, 2);
        expect(store.values, saved);
        final failure = find.byWidgetPredicate(
          (w) => w is StatusCard && w.fix == 'Retry',
        );
        if (repeated) {
          await invokeControl(t, t.widget<StatusCard>(failure).onFix);
          expect(find.text('Notifications could not load'), findsOneWidget);
          expect(store.values, saved);
        }
        store.fail = false;
        await invokeControl(t, t.widget<StatusCard>(failure).onFix);
        await io(t);
        expect(find.text('Notifications could not load'), findsNothing);
        expect(find.text('Authored notice 0'), findsOneWidget);
        expect(find.text('Authored notice 1'), findsOneWidget);
        expect(history.unread.value, 2);
        expect(store.values, saved);
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );
  }
  for (final refused in [false, true]) {
    testWidgets(
      'leaving a held history ${refused ? 'refusal' : 'read'} cannot reopen or mark anything',
      (t) async {
        await warm(t);
        SharedPreferences.resetStatic();
        store.readStarted = Completer<void>();
        final release = store.release = Completer<void>();
        await bell(t);
        await t.tap(find.byType(NotificationsBell));
        for (
          var frame = 0;
          frame < 20 && find.byType(NotificationsScreen).evaluate().isEmpty;
          frame++
        ) {
          await t.pump(const Duration(milliseconds: 50));
        }
        await t.runAsync(() => store.readStarted!.future);
        expect(find.byType(NotificationsScreen), findsOneWidget);
        Navigator.of(t.element(find.byType(NotificationsScreen))).pop();
        await t.pump(const Duration(milliseconds: 400));
        store.fail = refused;
        release.complete();
        await io(t);
        expect(find.byType(NotificationsScreen), findsNothing);
        expect(find.byType(NotificationsBell), findsOneWidget);
        expect(find.text('Notifications could not load'), findsNothing);
        expect(history.unread.value, 2);
        expect(app.navRequest.value, -1);
        expect(store.values, saved);
        store.fail = false;
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );
  }
}
