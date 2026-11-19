// Real Pushups commands/SQLite with an authored iOS notification handoff.
// This checks page feedback and channel requests, not OS scheduling/delivery.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/pushups.dart';
import 'package:whoop_companion/data/pushup_reminders.dart';
import 'package:whoop_companion/notify/notification_service.dart';
import 'package:whoop_companion/ui2/screens/pushups_screen.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'coverage_pushup_screen_actions_test.dart'
    show command, flush, tap, action;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart' show readPage;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const notifications = MethodChannel(
    'dexterous.com/flutter/local_notifications',
  );
  const settings = MethodChannel('flutter.baseflow.com/geolocator');
  final calls = <MethodCall>[];
  var settingsOpened = 0, pending = 0;
  var refuseSchedule = false, permission = true;
  final service = NotificationService.instance;
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('pushup-reminder-pages');
  });
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    IOSFlutterLocalNotificationsPlugin.registerWith();
    service.debugProbePermission = () async => permission;
    service.debugRequestPermission = () async => permission;
    messenger
      ..setMockMethodCallHandler(
        const MethodChannel('flutter_timezone'),
        (_) async => 'America/Chicago',
      )
      ..setMockMethodCallHandler(
        const MethodChannel('whoop/home_region'),
        (c) async => c.method == 'drain' ? [] : null,
      )
      ..setMockMethodCallHandler(settings, (c) async {
        expect(c.method, 'openAppSettings');
        settingsOpened++;
        return true;
      })
      ..setMockMethodCallHandler(notifications, (c) async {
        calls.add(c);
        if (c.method == 'zonedSchedule') {
          if (refuseSchedule) throw PlatformException(code: 'authored_refusal');
          pending = NotificationService.maxPushupNudges;
        }
        return switch (c.method) {
          'initialize' || 'requestPermissions' => true,
          'pendingNotificationRequests' => [
            for (var i = 0; i < pending; i++)
              {
                'id': NotificationService.idPushupNudgeBase + i,
                'title': 'Authored',
                'body': '',
                'payload': '/pushups',
              },
          ],
          _ => null,
        };
      });
  });
  tearDown(() {
    service.debugProbePermission = null;
    service.debugRequestPermission = null;
    service.invalidatePermissionCache();
    debugDefaultTargetPlatformOverride = null;
    for (final channel in [
      notifications,
      settings,
      const MethodChannel('whoop/home_region'),
      const MethodChannel('flutter_timezone'),
    ]) {
      messenger.setMockMethodCallHandler(channel, null);
    }
  });
  tearDownAll(LocalDb.close);

  // Commands retain a process-wide queue. All page transitions share one
  // owning fake clock, with a fresh authored store between cases.
  testWidgets(
    'notification health, countdown and Home pause pages retain their real saved state',
    (t) async {
      t.view.physicalSize = const Size(430, 1800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        await flush(t);
      });
      for (final state in [
        'repair',
        'long',
        'near',
        'due',
        'home',
        'blocked',
      ]) {
        await t.pumpWidget(const SizedBox());
        await flush(t);
        await t.runAsync(() async {
          await resetCoverageStore();
          await PushupReminders.clearInbox();
          await PushupReminders.writeMirror(null);
        });
        permission = state != 'blocked';
        refuseSchedule = state == 'repair';
        pending = state == 'repair' ? 0 : NotificationService.maxPushupNudges;
        service.invalidatePermissionCache();
        await command(t, () async {
          final s = await Pushups.start(paused: state == 'home');
          if (state != 'home') {
            final now = DateTime.now();
            s.anchor = switch (state) {
              'long' => now.add(const Duration(hours: 2, minutes: 5)),
              'near' => now.add(const Duration(seconds: 45)),
              'due' => now.subtract(const Duration(minutes: 2)),
              _ => now.add(const Duration(minutes: 45)),
            };
            await PushupDb.save(s);
            await PushupReminders.writeMirror(s);
          }
        });
        final saved = (await t.runAsync(PushupDb.active))!;
        await t.pumpWidget(
          MaterialApp(
            theme: buildTheme(Brightness.light),
            home: const PushupsScreen(),
          ),
        );
        await flush(t);
        final all = (await readPage(t)).join(' ');
        expect(saved.count, 0);
        if (state == 'repair') {
          expect(all, contains('Reminders are missing'));
          expect(all, contains('Re-arm reminders'));
          refuseSchedule = false;
          calls.clear();
          await tap(t, action('Re-arm reminders'));
          expect(calls.any((c) => c.method == 'zonedSchedule'), true);
          expect(find.text('Running'), findsOneWidget);
        } else if (state == 'home') {
          expect(all, contains('Paused because you left Home'));
          expect(find.text('Resume'), findsOneWidget);
          expect(saved.pauseReason, kHomeAwayReason);
        } else if (state == 'blocked') {
          expect(all, contains('Reminders are blocked'));
          final before = settingsOpened;
          await tap(t, action('Open Settings'));
          expect(settingsOpened, before + 1);
        } else {
          expect(all, contains('Running'));
          expect(all, contains('(scheduled)'));
          expect(
            all,
            contains(switch (state) {
              'long' => ' h ',
              'near' => 'under a minute',
              _ => 'Reminder due · next nudge',
            }),
          );
        }
        final after = (await t.runAsync(PushupDb.active))!;
        expect(after.id, saved.id);
        expect(
          after.count,
          0,
          reason: 'Reminder state and settings never log a set',
        );
        expect(after.anchor, saved.anchor);
        expect(after.state, saved.state);
      }
      // Widget-test invariants run before the outer test tearDown.
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
