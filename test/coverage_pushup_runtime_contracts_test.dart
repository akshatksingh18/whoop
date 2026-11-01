// Durable foreground/background Pushups contracts, authored days and a scripted iOS handoff.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/home_region.dart';
import 'package:whoop_companion/data/pushups.dart';
import 'package:whoop_companion/data/pushup_reminders.dart';
import 'package:whoop_companion/notify/notification_log.dart';
import 'package:whoop_companion/notify/notification_service.dart';
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  const home = MethodChannel('whoop/home_region');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final service = NotificationService.instance;
  final calls = <MethodCall>[];
  final homeEvents = <Map<String, Object>>[];
  final acknowledgements = <Object?>[];
  List<int> pending = [];
  setUpAll(() async {
    await coverageStore('pushup-runtime-contracts');
  });
  setUp(() async {
    await resetCoverageStore();
    await PushupReminders.clearInbox();
    await PushupReminders.writeMirror(null);
    calls.clear();
    homeEvents.clear();
    acknowledgements.clear();
    pending = [];
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    IOSFlutterLocalNotificationsPlugin.registerWith();
    service.invalidatePermissionCache();
    service.debugProbePermission = () async => true;
    service.debugRequestPermission = () async => true;
    messenger
      ..setMockMethodCallHandler(
        const MethodChannel('flutter_timezone'),
        (_) async => 'America/Chicago',
      )
      ..setMockMethodCallHandler(channel, (c) async {
        calls.add(c);
        return switch (c.method) {
          'initialize' || 'requestPermissions' => true,
          'pendingNotificationRequests' => [
            for (final id in pending)
              {
                'id': id,
                'title': 'Authored',
                'body': '',
                'payload': '/pushups',
              },
          ],
          _ => null,
        };
      })
      ..setMockMethodCallHandler(home, (c) async {
        if (c.method == 'drain') return homeEvents;
        if (c.method == 'ack') {
          acknowledgements.add(c.arguments);
          homeEvents.clear();
        }
        return null;
      });
  });
  tearDown(() async {
    await NotificationLog.instance.entries();
    service.debugProbePermission = null;
    service.debugRequestPermission = null;
    service.invalidatePermissionCache();
    debugDefaultTargetPlatformOverride = null;
    messenger
      ..setMockMethodCallHandler(channel, null)
      ..setMockMethodCallHandler(home, null)
      ..setMockMethodCallHandler(const MethodChannel('flutter_timezone'), null);
  });
  tearDownAll(LocalDb.close);
  NotificationResponse response(String sid, String action) =>
      NotificationResponse(
        notificationResponseType:
            NotificationResponseType.selectedNotificationAction,
        id: 2460,
        actionId: action,
        payload: '/pushups?s=$sid&a=authored-anchor',
      );

  test(
    'starting paused saves its reason and a pause event before reminders can run',
    () async {
      final s = await Pushups.start(paused: true);
      final saved = (await PushupDb.active())!;
      expect(saved.id, s.id);
      expect(saved.state, PushupState.paused);
      expect(saved.pauseReason, kHomeAwayReason);
      expect(saved.events.single.kind, PushupEventKind.pause);
      expect(saved.anchor, isNull);
      expect((await PushupReminders.readMirror())!.state, 'paused');
    },
  );
  test(
    'foreground notification replay counts a set once and keeps a later pause distinct',
    () async {
      final s = await Pushups.start();
      final done = response(s.id, kPushupDoneAction);
      await PushupReminders.onAction(done, background: false);
      await PushupReminders.onAction(done, background: false);
      expect((await PushupDb.active())!.count, 1);
      expect((await PushupDb.active())!.receipts, hasLength(1));
      await PushupReminders.onAction(
        response(s.id, kPushupPauseAction),
        background: false,
      );
      final paused = (await PushupDb.active())!;
      expect(paused.count, 1);
      expect(paused.state, PushupState.paused);
      expect(paused.receipts, hasLength(2));
      expect(await PushupReminders.readInbox(), isEmpty);
    },
  );
  for (final pause in [false, true]) {
    test(
      'background ${pause ? 'Pause changes the mirror' : 'Done rearms the cadence'} before a later idempotent foreground merge',
      () async {
        final s = await Pushups.start();
        calls.clear();
        await PushupReminders.onAction(
          response(s.id, pause ? kPushupPauseAction : kPushupDoneAction),
          background: true,
        );
        expect(
          (await PushupDb.active())!.count,
          0,
          reason: 'The background inbox must not open or mutate the database',
        );
        expect((await PushupReminders.readInbox()).single.sessionId, s.id);
        expect(
          (await PushupReminders.readMirror())!.state,
          pause ? 'paused' : 'running',
        );
        if (!pause) {
          expect(
            calls.where((c) => c.method == 'zonedSchedule'),
            hasLength(NotificationService.maxPushupNudges + 1),
          );
        }
        await Pushups.reconcile();
        await Pushups.reconcile();
        final saved = (await PushupDb.active())!;
        expect(saved.count, pause ? 0 : 1);
        expect(saved.state, pause ? PushupState.paused : PushupState.running);
        expect(saved.receipts, hasLength(1));
        expect(await PushupReminders.readInbox(), isEmpty);
      },
    );
  }
  for (final reconcile in [false, true]) {
    test(
      '${reconcile ? 'relaunch reconciliation' : 'a new Done command'} closes a stale day at its own local midnight',
      () async {
        final now = DateTime.now();
        final yesterday = dayLabelOf(
          DateTime(now.year, now.month, now.day - 1),
        );
        final old = PushupSession(
          id: 'authored-old',
          day: yesterday,
          started: DateTime.parse(yesterday),
          interval: 45,
          state: PushupState.running,
          anchor: DateTime.parse(yesterday).add(const Duration(hours: 15)),
        );
        await PushupDb.save(old);
        if (reconcile) {
          await Pushups.reconcile();
        } else {
          await Pushups.done();
        }
        final saved = (await PushupDb.all()).single;
        expect(saved.state, PushupState.ended);
        expect(
          saved.ended!.millisecondsSinceEpoch ~/ 1000,
          localDayEndSec(yesterday),
        );
        expect(saved.count, 0);
        expect(saved.anchor, isNull);
        expect(await PushupDb.active(), isNull);
      },
    );
  }
  test(
    'manual resume while outside Home suppresses repeated exits until arrival',
    () async {
      await HomeRegion.setHome((lat: 0.0, lon: 0.0, radius: 150.0));
      await HomeRegion.saveAutomation(
        HomeAutomation(presence: HomePresence.outside),
      );
      await Pushups.start(paused: true);
      await Pushups.resume();
      expect((await HomeRegion.automation()).suppressExit, isTrue);
      expect((await PushupDb.active())!.state, PushupState.running);
    },
  );
  test(
    'Home arrival resumes only an automation pause and acknowledges its durable receipt',
    () async {
      await HomeRegion.setHome((lat: 0.0, lon: 0.0, radius: 150.0));
      await HomeRegion.saveAutomation(
        HomeAutomation(presence: HomePresence.outside),
      );
      final s = await Pushups.start(paused: true);
      homeEvents.add({
        'id': 'authored-arrival',
        'kind': 'enter',
        'at': DateTime.now().millisecondsSinceEpoch / 1000,
      });
      await Pushups.reconcile();
      final resumed = (await PushupDb.active())!;
      expect(resumed.id, s.id);
      expect(resumed.state, PushupState.running);
      expect(resumed.pauseReason, isNull);
      expect(resumed.receipts, contains('home:authored-arrival'));
      expect(resumed.events.last.kind, PushupEventKind.resume);
      expect(acknowledgements, [
        ['authored-arrival'],
      ]);
      expect((await HomeRegion.automation()).presence, HomePresence.inside);
    },
  );
  test(
    'a drained native batch reports repair and legacy mirrors use the local day guard',
    () async {
      await Pushups.start();
      expect((await Pushups.status()).health, PushupHealth.repair);
      pending = [
        NotificationService.idPushupRegular,
        NotificationService.idPushupNudgeBase,
        99999,
      ];
      expect(await PushupReminders.pendingInBatch(), 2);
      expect((await Pushups.status()).health, PushupHealth.ok);
      final mirror = (
        session: 'authored',
        day: todayLabel(),
        state: 'running',
        interval: 45,
        startSec: null,
        endSec: null,
      );
      expect(pushupMirrorContains(mirror, DateTime.now()), isTrue);
      expect(pushupMirrorContains(mirror, DateTime(2021, 4, 6)), isFalse);
    },
  );
}
