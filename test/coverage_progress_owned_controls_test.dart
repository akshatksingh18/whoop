// Retained body entry, photo history and reminder contracts with authored inputs.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whoop_companion/data/body_log.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/notify/notification_service.dart';
import 'package:whoop_companion/ui2/screens/progress_screen.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'coverage_body_history_actions_test.dart' show App, flush;
import 'coverage_localized_progress_test.dart' show progress;
import 'coverage_body_photo_controls_test.dart' show action;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

Finder surface(String label) =>
    find.byWidgetPredicate((w) => w is Surface && w.semanticLabel == label);
void checked(String name, WidgetTesterCallback body) =>
    testWidgets(name, (t) async {
      try {
        await body(t);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final service = NotificationService.instance;
  late App app;
  bool permission = true, refuseSchedule = false, refuseCancel = false;
  final calls = <MethodCall>[];
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('progress-owned-controls');
  });
  setUp(() async {
    await resetCoverageStore();
    app = App()..user = {'weight_kg': 70, 'height_cm': 170};
    permission = true;
    refuseSchedule = refuseCancel = false;
    calls.clear();
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
      if (c.method == 'zonedSchedule' && refuseSchedule ||
          c.method == 'cancel' && refuseCancel) {
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
  Future<void> open(WidgetTester t, Widget page) async {
    await localizedPage(t, page, app: app, settle: false);
    await flush(t);
  }

  Future<void> settings(WidgetTester t) async =>
      open(t, BodySettingsScreen(data: progress(true)));
  Future<void> toggle(WidgetTester t, bool on) async {
    final f = surface('Weekly reminder ${on ? 'on' : 'off'}');
    await reveal(t, f);
    await invokeControl(t, t.widget<Surface>(f).onTap);
    await flush(t);
  }

  for (final settingsLink in [false, true]) {
    checked(
      'Progress ${settingsLink ? 'settings' : 'body entry'} link returns to the owning page on cancel',
      (t) async {
        await open(t, ProgressScreen(data: progress(false)));
        await t.tap(
          settingsLink
              ? find.byTooltip('Body settings')
              : find.text('Add body entry'),
        );
        await flush(t);
        expect(
          find.byType(settingsLink ? BodySettingsScreen : BodyEntryScreen),
          findsOneWidget,
        );
        Navigator.of(
          t.element(
            find.byType(settingsLink ? BodySettingsScreen : BodyEntryScreen),
          ),
        ).pop();
        await flush(t);
        expect(find.byType(ProgressScreen), findsOneWidget);
        expect((await t.runAsync(BodyLogDb.weights))!, isEmpty);
      },
    );
  }
  checked(
    'Progress photo history opens its saved comparison without losing authored records',
    (t) async {
      final photo = await t.runAsync(
        () => BodyLogDb.addPhoto(
          img.encodeJpg(img.Image(width: 8, height: 12)),
          date: '2021-04-06',
          pose: 'front',
        ),
      );
      final d = progress(false);
      await open(
        t,
        ProgressScreen(
          data: ProgressData(
            weights: d.weights,
            measures: d.measures,
            photos: [photo!],
            lifts: [],
            food: [],
            steps: [],
            sleepMin: [],
            recovery: [],
            sessions: [],
            baseline: null,
            heightCm: null,
          ),
        ),
      );
      final strip = find.byWidgetPredicate(
        (w) => w is Surface && w.semanticLabel?.contains('photo') == true,
      );
      await reveal(t, strip);
      t.widget<Surface>(strip).onTap!();
      await flush(t);
      expect(
        t
            .widget<PhotoCompareScreen>(find.byType(PhotoCompareScreen))
            .photos
            .single
            .id,
        photo.id,
      );
      expect(find.byType(Image), findsWidgets);
      expect((await t.runAsync(BodyLogDb.photos))!.single.id, photo.id);
    },
  );
  checked(
    'denied reminder permission keeps Off; a later grant can enable and change its time',
    (t) async {
      permission = false;
      await settings(t);
      await toggle(t, false);
      expect(
        find.textContaining('Notifications are off for WHOOP'),
        findsOneWidget,
      );
      expect(surface('Weekly reminder off'), findsOneWidget);
      expect(calls.where((c) => c.method == 'zonedSchedule'), isEmpty);
      permission = true;
      service.invalidatePermissionCache();
      await toggle(t, false);
      expect(surface('Weekly reminder on'), findsOneWidget);
      await invokeControl(
        t,
        t.widget<Pressable>(action('Remind at 9:00')).onTap,
      );
      await flush(t);
      final prefs = (await t.runAsync(SharedPreferences.getInstance))!;
      expect(prefs.getInt('body.reminder.hour'), 9);
      expect(prefs.getBool('body.reminder'), true);
      expect(calls.where((c) => c.method == 'zonedSchedule'), hasLength(2));
      await toggle(t, true);
      expect(prefs.getBool('body.reminder'), false);
    },
  );
  checked(
    'refused scheduling restores Off and retries rather than claiming a reminder',
    (t) async {
      refuseSchedule = true;
      await settings(t);
      await toggle(t, false);
      expect(
        find.textContaining('could not be confirmed on your iPhone'),
        findsOneWidget,
      );
      expect(surface('Weekly reminder off'), findsOneWidget);
      expect(
        (await t.runAsync(
          SharedPreferences.getInstance,
        ))!.getBool('body.reminder'),
        false,
      );
      expect(calls.where((c) => c.method == 'cancel'), isNotEmpty);
      refuseSchedule = false;
      await toggle(t, false);
      expect(surface('Weekly reminder on'), findsOneWidget);
    },
  );
  checked(
    'failed schedule and failed rollback explicitly leave native status unconfirmed',
    (t) async {
      refuseSchedule = refuseCancel = true;
      await settings(t);
      await toggle(t, false);
      expect(
        find.text('Reminder status is unconfirmed. Retry your choice below.'),
        findsOneWidget,
      );
      expect(surface('Weekly reminder off'), findsOneWidget);
      expect(
        (await t.runAsync(
          SharedPreferences.getInstance,
        ))!.getBool('body.reminder'),
        false,
      );
    },
  );
}
