// The real notification page must commit read state before navigating.
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
import 'coverage_nutrition_root_test.dart' show io;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/localized_coverage.dart';

class NoticeStore extends SharedPreferencesStorePlatform {
  final values = <String, Object>{};
  bool refuse = false, throwing = false;
  Completer<void>? held;
  bool started = false;
  @override
  Future<Map<String, Object>> getAll() async => Map.of(values);
  @override
  Future<bool> clear() async {
    values.clear();
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    values.remove(key);
    return true;
  }

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key == 'flutter.notify.log') {
      started = true;
      if (held != null) await held!.future;
      if (throwing) throw StateError('authored write refusal');
      if (refuse) return false;
    }
    values[key] = value;
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final history = NotificationLog.instance;
  late NoticeStore store;
  late SharedPreferencesStorePlatform original;
  late AppState app;
  setUpAll(loadAuditFonts);
  setUp(() async {
    original = SharedPreferencesStorePlatform.instance;
    store = NoticeStore();
    SharedPreferencesStorePlatform.instance = store;
    SharedPreferences.resetStatic();
    history.clock = () => DateTime(2021, 4, 6, 12);
    app = AppState.forTesting();
  });
  tearDown(() {
    app.dispose();
    history.clock = DateTime.now;
    SharedPreferencesStorePlatform.instance = original;
    SharedPreferences.resetStatic();
  });
  Future<void> open(
    WidgetTester t, {
    String? route = '/food/day?day=2021-04-05',
  }) async {
    final notice = LoggedNotification(
      key: 'authored',
      at: history.clock(),
      title: 'Authored notice',
      body: 'Keep this body',
      category: 'reminders',
      route: route,
    );
    store.values['flutter.notify.log'] = jsonEncode([notice.toJson()]);
    await t.runAsync(history.entries);
    await localizedPage(
      t,
      const NotificationsScreen(),
      app: app,
      settle: false,
    );
    await io(t);
    expect(find.text('Authored notice'), findsOneWidget);
  }

  Pressable row(WidgetTester t) => t.widget<Pressable>(
    find.byWidgetPredicate(
      (w) =>
          w is Pressable &&
          (w.semanticLabel?.startsWith('Unread. Authored notice.') ?? false),
    ),
  );

  for (final throwing in [false, true]) {
    testWidgets(
      'page write ${throwing ? 'exception' : 'refusal'} blocks navigation and retries durably',
      (t) async {
        await open(t);
        final nav = app.navRequest.value, screen = app.screenRequest.value;
        store.refuse = !throwing;
        store.throwing = throwing;
        await invokeControl(t, row(t).onTap);
        await io(t);
        expect(find.text('Could not mark it read. Try again.'), findsOneWidget);
        expect(app.navRequest.value, nav);
        expect(app.screenRequest.value, screen);
        final refused = await t.runAsync(history.entries);
        expect(refused!.single.read, isFalse);
        expect(refused.single.body, 'Keep this body');
        store.refuse = store.throwing = false;
        await invokeControl(t, row(t).onTap);
        await io(t);
        expect(app.navRequest.value, 6);
        expect(app.screenRequest.value, '/food/day?day=2021-04-05');
        SharedPreferences.resetStatic();
        final saved = await t.runAsync(history.entries);
        expect(saved!.single.read, isTrue);
        expect(saved.single.body, 'Keep this body');
      },
    );
  }

  testWidgets(
    'notice without a route records read state without inventing a destination',
    (t) async {
      await open(t, route: null);
      final nav = app.navRequest.value, screen = app.screenRequest.value;
      await invokeControl(t, row(t).onTap);
      await io(t);
      expect(app.navRequest.value, nav);
      expect(app.screenRequest.value, screen);
      expect((await t.runAsync(history.entries))!.single.read, isTrue);
    },
  );

  testWidgets(
    'leaving during the read write never opens a route from the disposed page',
    (t) async {
      await open(t);
      store.started = false;
      store.held = Completer<void>();
      final callback = row(t).onTap as dynamic;
      final Future<void> completing = callback();
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      expect(store.started, isTrue);
      final nav = app.navRequest.value, screen = app.screenRequest.value;
      await t.pumpWidget(const SizedBox());
      store.held!.complete();
      await t.runAsync(() => completing);
      await io(t);
      expect(app.navRequest.value, nav);
      expect(app.screenRequest.value, screen);
      expect((await t.runAsync(history.entries))!.single.read, isTrue);
    },
  );
}
