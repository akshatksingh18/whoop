// Real center -> service -> authored iOS method-channel replies. This verifies
// scheduling requests and local evidence, not physical OS notification delivery.
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/notify/notification_center.dart';
import 'package:whoop_companion/notify/notification_prefs.dart';
import 'package:whoop_companion/notify/notification_report.dart';
import 'package:whoop_companion/notify/notification_service.dart';
import 'package:whoop_companion/notify/tap_router.dart';
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  const zoneChannel = MethodChannel('flutter_timezone');
  final center = NotificationCenter.instance,
      service = NotificationService.instance;
  final calls = <MethodCall>[];
  var granted = true, refuse = false, prompts = 0, zoneReads = 0;
  setUpAll(() => coverageStore('center-schedule-boundaries'));
  setUp(() async {
    await resetCoverageStore();
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    IOSFlutterLocalNotificationsPlugin.registerWith();
    calls.clear();
    granted = true;
    refuse = false;
    prompts = zoneReads = 0;
    service.invalidatePermissionCache();
    service.debugProbePermission = () async => granted;
    service.debugRequestPermission = () async {
      prompts++;
      return granted;
    };
    service.debugCancel = (id) async => calls.add(MethodCall('cancel', id));
    messenger.setMockMethodCallHandler(zoneChannel, (_) async {
      zoneReads++;
      return 'America/Chicago';
    });
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'zonedSchedule' && refuse)
        throw PlatformException(code: 'authored schedule refusal');
      return switch (call.method) {
        'initialize' => true,
        _ => null,
      };
    });
  });
  tearDown(() {
    service.debugProbePermission = null;
    service.debugRequestPermission = null;
    service.debugCancel = null;
    service.invalidatePermissionCache();
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(zoneChannel, null);
  });
  tearDownAll(LocalDb.close);
  List<Map> scheduled() => [
    for (final c in calls)
      if (c.method == 'zonedSchedule') c.arguments as Map,
  ];
  Future<Map> plans() async {
    final p = await SharedPreferences.getInstance();
    return jsonDecode(p.getString('notify.plans') ?? '{}') as Map;
  }

  for (final (hours, ids) in <(int?, List<int>)>[
    (null, []),
    (0, []),
    (24, []),
    (36, [NotificationService.idSigningExpiry24]),
    (48, [NotificationService.idSigningExpiry24]),
    (
      72,
      [
        NotificationService.idSigningExpiry48,
        NotificationService.idSigningExpiry24,
      ],
    ),
  ]) {
    test(
      'signing expiry $hours hours cancels both old warnings then schedules only future marks',
      () async {
        final now = DateTime.now().toUtc();
        final expiry = hours == null ? null : now.add(Duration(hours: hours));
        await center.scheduleSigningExpiryAlerts(expiry, now: now);
        expect(calls.take(2).map((c) => c.method), ['cancel', 'cancel']);
        expect(calls.take(2).map((c) => c.arguments), [
          NotificationService.idSigningExpiry48,
          NotificationService.idSigningExpiry24,
        ]);
        final wire = scheduled();
        expect(wire.map((w) => w['id']), ids);
        expect((await plans()).length, ids.length);
        for (final w in wire) {
          expect(w['payload'], kRouteStatus);
          expect(w['timeZoneName'], 'America/Chicago');
          expect(w['body'], contains('Refresh it with Sideloadly'));
          expect(
            w['title'],
            w['id'] == NotificationService.idSigningExpiry48
                ? 'WHOOP signing ends in 2 days'
                : 'WHOOP signing ends tomorrow',
          );
        }
        expect(zoneReads, ids.isEmpty ? 0 : 1);
        expect(prompts, 0);
      },
    );
  }
  for (final failure in ['denied', 'refused']) {
    test(
      'signing $failure never records a successful scheduling handoff and a later retry works',
      () async {
        granted = failure != 'denied';
        refuse = failure == 'refused';
        final now = DateTime.now();
        final expiry = now.add(const Duration(days: 7));
        await center.scheduleSigningExpiryAlerts(expiry, now: now);
        expect(await plans(), isEmpty);
        expect(scheduled().length, failure == 'denied' ? 0 : 2);
        granted = true;
        refuse = false;
        service.invalidatePermissionCache();
        calls.clear();
        await center.scheduleSigningExpiryAlerts(expiry, now: now);
        expect(scheduled(), hasLength(2));
        expect(await plans(), hasLength(2));
        expect(prompts, 0);
      },
    );
  }
  for (final mode in [
    'disabled',
    'quiet-week',
    'denied',
    'allowed',
    'refused',
  ]) {
    test(
      'weekly $mode cancels stale scheduling and retains the exact finding only when one exists',
      () async {
        granted = mode != 'denied';
        refuse = mode == 'refused';
        const finding = 'Authored weekly finding; original wording.';
        final firstDay = todayLabel();
        await center.scheduleStandingReminders(
          NotificationPrefs(remindersEnabled: mode != 'disabled'),
          weeklyFinding: mode == 'quiet-week' ? null : finding,
        );
        expect(calls.first.method, 'cancel');
        expect(calls.first.arguments, NotificationService.idWeeklyRecap);
        final eligible = mode != 'disabled' && mode != 'quiet-week';
        final handedOff = mode == 'allowed';
        expect(scheduled().length, eligible && mode != 'denied' ? 1 : 0);
        expect((await plans()).length, handedOff ? 1 : 0);
        final rows = await (await LocalDb.instance).query(
          'baselines',
          where: 'key LIKE ?',
          whereArgs: ['calculation:${NotificationReport.prefix}%'],
        );
        expect(rows.length, eligible ? 1 : 0);
        if (eligible) {
          final id = (rows.single['key'] as String).substring(
            'calculation:${NotificationReport.prefix}'.length,
          );
          final report = await NotificationReport.read(id);
          expect(report!['title'], 'Your week in review');
          expect(report['body'], finding);
          expect({firstDay, todayLabel()}, contains(report['day']));
        }
        if (handedOff) {
          final request = scheduled().single;
          expect(request['id'], NotificationService.idWeeklyRecap);
          expect(request['body'], finding);
          expect(
            {
              firstDay,
              todayLabel(),
            }.any((d) => (request['payload'] as String).contains(d)),
            true,
          );
          expect(request['payload'], contains('id='));
          expect(request['timeZoneName'], 'America/Chicago');
        }
        expect(prompts, 0);
      },
    );
  }
}
