// Actual top-level callback -> durable inbox -> real SQLite reconciliation.
// Does not certify an iOS background isolate or physical notification delivery.
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/pushup_reminders.dart';
import 'package:whoop_companion/data/pushups.dart';
import 'package:whoop_companion/sync/file_log.dart';
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const notification = MethodChannel(
    'dexterous.com/flutter/local_notifications',
  );
  late PushupSession session;
  late Directory root;
  setUpAll(() => coverageStore('pushup-background-entry', fresh: true));
  setUp(() async {
    await resetCoverageStore();
    root = await getApplicationSupportDirectory();
    await PushupReminders.clearInbox();
    await PushupReminders.writeMirror(null);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    IOSFlutterLocalNotificationsPlugin.registerWith();
    messenger.setMockMethodCallHandler(
      notification,
      (call) async => call.method == 'initialize' ? true : null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('flutter_timezone'),
      (_) async => 'UTC',
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('whoop/home_region'),
      (call) async => call.method == 'drain' ? [] : null,
    );
    session = PushupSession(
      id: 'authored-background-session',
      day: todayLabel(),
      started: DateTime.now().subtract(const Duration(minutes: 1)),
      interval: 45,
      state: PushupState.paused,
    );
    await PushupDb.save(session);
  });
  tearDown(() async {
    final blocked = File('${root.path}/pushups_inbox');
    if (await blocked.exists()) await blocked.delete();
    await (await LocalDb.instance).execute(
      'DROP TRIGGER IF EXISTS authored_entry_refusal',
    );
    await PushupReminders.clearInbox();
    await FileLog.write('Authored background entry barrier');
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(notification, null);
    messenger.setMockMethodCallHandler(
      const MethodChannel('flutter_timezone'),
      null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('whoop/home_region'),
      null,
    );
  });
  tearDownAll(LocalDb.close);
  NotificationResponse response(String kind, {String? sid, String? payload}) =>
      NotificationResponse(
        notificationResponseType:
            NotificationResponseType.selectedNotificationAction,
        id: 2460,
        actionId: kind,
        payload: payload ?? '/pushups?s=${sid ?? session.id}&a=authored-anchor',
      );

  for (final kind in [kPushupDoneAction, kPushupPauseAction]) {
    test(
      'COV-65 top-level $kind persists before merge and deduplicates replay',
      () async {
        final delivery = response(kind);
        final before = (await PushupDb.active())!.toJson();
        await pushupNotificationBackground(delivery);
        await pushupNotificationBackground(delivery);
        expect(
          (await PushupDb.active())!.toJson(),
          before,
          reason:
              'A background delivery records an inbox item,not a premature SQLite completion',
        );
        final inbox = await PushupReminders.readInbox();
        expect(inbox, hasLength(1));
        expect(inbox.single.sessionId, session.id);
        expect(inbox.single.kind, kind == kPushupDoneAction ? 'done' : 'pause');
        await Pushups.reconcile();
        final saved = (await PushupDb.active())!;
        expect(saved.count, kind == kPushupDoneAction ? 1 : 0);
        expect(saved.state, PushupState.paused);
        expect(saved.receipts, contains(inbox.single.id));
        expect(await PushupReminders.readInbox(), isEmpty);
        await pushupNotificationBackground(delivery);
        await Pushups.reconcile();
        expect((await PushupDb.active())!.toJson(), saved.toJson());
        expect(await PushupReminders.readInbox(), isEmpty);
      },
    );
  }
  test(
    'COV-65 callback for an older session cannot edit current day',
    () async {
      final before = (await PushupDb.active())!.toJson();
      await pushupNotificationBackground(
        response(kPushupDoneAction, sid: 'authored-old-session'),
      );
      expect(
        (await PushupReminders.readInbox()).single.sessionId,
        'authored-old-session',
      );
      await Pushups.reconcile();
      expect((await PushupDb.active())!.toJson(), before);
      expect(await PushupReminders.readInbox(), isEmpty);
    },
  );
  test(
    'COV-65 callback without a session retains store and has no inbox action',
    () async {
      final before = (await PushupDb.active())!.toJson();
      await pushupNotificationBackground(
        response(kPushupDoneAction, payload: '/pushups'),
      );
      expect(await PushupReminders.readInbox(), isEmpty);
      expect((await PushupDb.active())!.toJson(), before);
    },
  );
  test(
    'COV-65 refused inbox file leaves state untouched and permits identical retry',
    () async {
      final blocked = File('${root.path}/pushups_inbox');
      await blocked.writeAsString('authored collision retained');
      final before = (await PushupDb.active())!.toJson();
      final delivery = response(kPushupDoneAction);
      await pushupNotificationBackground(delivery);
      expect(await blocked.readAsString(), 'authored collision retained');
      expect((await PushupDb.active())!.toJson(), before);
      await blocked.delete();
      await pushupNotificationBackground(delivery);
      expect(await PushupReminders.readInbox(), hasLength(1));
      await Pushups.reconcile();
      expect((await PushupDb.active())!.count, 1);
      expect(await PushupReminders.readInbox(), isEmpty);
    },
  );
  test(
    'COV-65 callback receipt survives refused SQLite merge and applies once on retry',
    () async {
      final db = await LocalDb.instance;
      await pushupNotificationBackground(response(kPushupDoneAction));
      final action = (await PushupReminders.readInbox()).single;
      await db.execute(
        "CREATE TRIGGER authored_entry_refusal BEFORE INSERT ON pushup_session BEGIN SELECT RAISE(ABORT,'authored receipt refusal'); END",
      );
      await expectLater(Pushups.reconcile(), throwsA(isA<DatabaseException>()));
      expect((await PushupDb.active())!.count, 0);
      expect((await PushupReminders.readInbox()).single.id, action.id);
      await db.execute('DROP TRIGGER authored_entry_refusal');
      await Pushups.reconcile();
      final saved = (await PushupDb.active())!;
      expect(saved.count, 1);
      expect(saved.receipts.where((id) => id == action.id), hasLength(1));
      expect(await PushupReminders.readInbox(), isEmpty);
      await Pushups.reconcile();
      expect((await PushupDb.active())!.count, 1);
    },
  );
}
