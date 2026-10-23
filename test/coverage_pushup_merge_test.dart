// Synthetic pending deliveries -> durable receipts -> cleanup/retry.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:openstrap_edge/app.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/data/pushups.dart';
import 'package:openstrap_edge/data/pushup_reminders.dart';
import 'package:openstrap_edge/state/prefs.dart';
import 'package:openstrap_edge/sync/file_log.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.root);
  final String root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late Database db;
  late PushupSession session;
  setUpAll(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    IOSFlutterLocalNotificationsPlugin.registerWith();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dexterous.com/flutter/local_notifications'),
          (call) async {
            return call.method == 'initialize' ? true : null;
          },
        );
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    root = (await Directory(
      'build/coverage-audit/pushup-merge',
    ).create(recursive: true)).absolute;
    PathProviderPlatform.instance = _Paths(root.path);
    LocalDb.dbName = '${root.path}/synthetic.sqlite';
    await LocalDb.close();
    await databaseFactory.deleteDatabase(LocalDb.dbName);
    db = await LocalDb.instance;
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.ensureLoaded();
    await LocalDb.wipeAll();
    await PushupReminders.clearInbox();
    session = PushupSession(
      day: todayLabel(),
      started: DateTime.now().subtract(const Duration(minutes: 1)),
      interval: 45,
      state: PushupState.paused,
    );
    await PushupDb.save(session);
  });
  tearDown(() async {
    await db.execute('DROP TRIGGER IF EXISTS synthetic_pushup_refusal');
    await PushupReminders.clearInbox();
    await FileLog.write('Synthetic merge test cleanup');
  });
  tearDownAll(() async {
    await LocalDb.close();
    debugDefaultTargetPlatformOverride = null;
  });

  Future<void> deliver(int id) => PushupReminders.onAction(
    NotificationResponse(
      notificationResponseType:
          NotificationResponseType.selectedNotificationAction,
      id: id,
      actionId: kPushupDoneAction,
      payload: '/pushups?s=${session.id}&a=$id',
    ),
    background: true,
  );

  test(
    'legacy and new deliveries merge once, including replay after cleanup',
    () async {
      final old = PushupAction(
        id: 'legacy',
        kind: 'done',
        sessionId: session.id,
        at: DateTime.now(),
      );
      await File(
        '${root.path}/pushups_inbox.json',
      ).writeAsString(jsonEncode([old.toJson()]));
      await Future.wait([deliver(1), deliver(2), deliver(2)]);
      await Pushups.reconcile();
      expect((await PushupDb.active())!.count, 3);
      expect(await PushupReminders.readInbox(), isEmpty);
      await deliver(2);
      await Pushups.reconcile();
      expect((await PushupDb.active())!.count, 3);
      expect(await PushupReminders.readInbox(), isEmpty);
    },
  );

  test('failed receipt commit retains every delivery for retry', () async {
    await Future.wait([deliver(1), deliver(2)]);
    await db.execute(
      "CREATE TRIGGER synthetic_pushup_refusal BEFORE INSERT ON pushup_session BEGIN SELECT RAISE(ABORT,'synthetic refusal'); END",
    );
    await expectLater(Pushups.reconcile(), throwsA(isA<DatabaseException>()));
    expect(await PushupReminders.readInbox(), hasLength(2));
    expect((await PushupDb.active())!.count, 0);
    await db.execute('DROP TRIGGER synthetic_pushup_refusal');
    await Pushups.reconcile();
    expect((await PushupDb.active())!.count, 2);
    expect(await PushupReminders.readInbox(), isEmpty);
  });

  test(
    'lifecycle reconciliation retains unreadable actions and logs the failure',
    () async {
      final file = File('${root.path}/pushups_inbox.json');
      await file.writeAsString('{synthetic unreadable');
      await reconcilePushupsForWake();
      await FileLog.write('barrier');
      expect(await file.readAsString(), '{synthetic unreadable');
      expect(
        await File((await FileLog.path())!).readAsString(),
        contains('Pushups wake reconciliation failed'),
      );
    },
  );
}
