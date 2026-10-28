// The real targets sheet, using scripted permission/scheduler acknowledgements.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/notify/notification_service.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/state/prefs.dart';
import 'package:whoop_companion/ui2/screens/nutrition_screen.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'coverage_progress_owned_controls_test.dart' show checked;
import 'coverage_food_calendar_recovery_test.dart' show flush, control;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final service = NotificationService.instance;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final calls = <MethodCall>[];
  late AppState app;
  bool permission = true, refuseSchedule = false, refuseCancel = false;
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('food-reminder-controls');
  });
  setUp(() async {
    await resetCoverageStore();
    await Prefs.saveValues({'food.day_reminder': false});
    app = AppState.forTesting()..user = {'kcal_target': 2000};
    calls.clear();
    permission = true;
    refuseSchedule = refuseCancel = false;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    IOSFlutterLocalNotificationsPlugin.registerWith();
    service.invalidatePermissionCache();
    service.debugProbePermission = () async => permission;
    service.debugRequestPermission = () async => permission;
    service.debugCancel = (id) async {
      calls.add(MethodCall('cancel', id));
      if (refuseCancel) throw StateError('synthetic cancellation refusal');
    };
    messenger.setMockMethodCallHandler(
      const MethodChannel('flutter_timezone'),
      (_) async => 'America/Chicago',
    );
    messenger.setMockMethodCallHandler(channel, (c) async {
      calls.add(c);
      if (c.method == 'zonedSchedule' && refuseSchedule) {
        throw PlatformException(code: 'synthetic-refusal');
      }
      return switch (c.method) {
        'initialize' || 'requestPermissions' => true,
        'pendingNotificationRequests' => <Map<String, Object>>[],
        _ => null,
      };
    });
  });
  tearDown(() {
    app.dispose();
    service.debugProbePermission = null;
    service.debugRequestPermission = null;
    service.debugCancel = null;
    service.invalidatePermissionCache();
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(
      const MethodChannel('flutter_timezone'),
      null,
    );
    debugDefaultTargetPlatformOverride = null;
  });
  tearDownAll(LocalDb.close);

  Future<void> open(WidgetTester t) async {
    await localizedPage(
      t,
      Scaffold(
        body: Builder(
          builder: (c) => TextButton(
            onPressed: () => editNutritionGoals(c),
            child: const Text('Open authored targets'),
          ),
        ),
      ),
      app: app,
    );
    await t.tap(find.text('Open authored targets'));
    await flush(t);
    expect(control('Evening check off'), findsOneWidget);
  }

  Future<void> toggle(WidgetTester t, bool on) async {
    final c = control('Evening check ${on ? 'on' : 'off'}');
    await reveal(t, c);
    await invokeControl(t, t.widget<Pressable>(c).onTap);
    await flush(t);
  }

  Future<bool?> enabled(WidgetTester t) async => (await t.runAsync(
    SharedPreferences.getInstance,
  ))!.getBool('food.day_reminder');

  checked(
    'denied evening permission keeps Off and typed calorie target untouched; later grant retries',
    (t) async {
      permission = false;
      await open(t);
      await toggle(t, false);
      expect(
        find.textContaining('Notifications are off for this app'),
        findsOneWidget,
      );
      expect(control('Evening check off'), findsOneWidget);
      expect(await enabled(t), false);
      expect(calls.where((c) => c.method == 'zonedSchedule'), isEmpty);
      permission = true;
      service.invalidatePermissionCache();
      await toggle(t, false);
      expect(await enabled(t), true);
      expect(control('Evening check on'), findsOneWidget);
      expect(app.user!['kcal_target'], 2000);
    },
  );
  checked(
    'unacknowledged evening schedule rolls back Off and a successful retry can be disabled',
    (t) async {
      refuseSchedule = true;
      await open(t);
      await toggle(t, false);
      expect(
        find.text('The evening check could not change. Try again.'),
        findsOneWidget,
      );
      expect(await enabled(t), false);
      expect(control('Evening check off'), findsOneWidget);
      refuseSchedule = false;
      await toggle(t, false);
      expect(await enabled(t), true);
      await toggle(t, true);
      expect(await enabled(t), false);
      expect(control('Evening check off'), findsOneWidget);
      expect(calls.where((c) => c.method == 'cancel'), isNotEmpty);
      expect(app.user!['kcal_target'], 2000);
    },
  );
  checked(
    'refused cancellation keeps the prior evening choice and retries without changing targets',
    (t) async {
      await open(t);
      await toggle(t, false);
      refuseCancel = true;
      await toggle(t, true);
      expect(
        find.text('The evening check could not change. Try again.'),
        findsOneWidget,
      );
      expect(await enabled(t), true);
      expect(control('Evening check on'), findsOneWidget);
      refuseCancel = false;
      await toggle(t, true);
      expect(await enabled(t), false);
      expect(app.user!['kcal_target'], 2000);
    },
  );
}
