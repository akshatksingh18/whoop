// Real cursor -> shared notification gate -> iOS channel -> durable cooldown.
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/notify/notification_center.dart';
import 'package:whoop_companion/notify/notification_log.dart';
import 'package:whoop_companion/notify/notification_service.dart';
import 'package:whoop_companion/sync/background_sync.dart';
import 'package:whoop_companion/sync/file_log.dart';
import 'coverage_step_tail_recovery_test.dart' show CheckpointStore;
import 'support/coverage_store.dart';

const _cooldown = 'last_staleness_notified_ms';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final service = NotificationService.instance;
  final center = NotificationCenter.instance;
  final originalSink = center.presentSink;
  final originalStore = SharedPreferencesStorePlatform.instance;
  final calls = <MethodCall>[];
  final promptFlags = <bool>[];
  var refusePresent = false;
  var probes = 0, prompts = 0;
  late SharedPreferences prefs;
  late List<Map<String, Object?>> cursors;

  setUpAll(() => coverageStore('staleness-delivery-contracts', fresh: true));
  setUp(() async {
    await resetCoverageStore();
    calls.clear();
    promptFlags.clear();
    probes = prompts = 0;
    refusePresent = false;
    prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notif_quiet_enabled', false);
    await prefs.setString('authored-unrelated', 'retain');
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await LocalDb.setCursor('rec_ts_hw', '${now - 96 * 3600}');
    await LocalDb.setCursor('authored-recovery', 'retain');
    cursors = await (await LocalDb.instance).query('sync_cursor');
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    IOSFlutterLocalNotificationsPlugin.registerWith();
    service.invalidatePermissionCache();
    service.debugProbePermission = () async {
      probes++;
      return true;
    };
    service.debugRequestPermission = () async {
      prompts++;
      return true;
    };
    center.presentSink = (event, {bool allowPermissionPrompt = true}) {
      promptFlags.add(allowPermissionPrompt);
      return service.presentEvent(
        event,
        allowPermissionPrompt: allowPermissionPrompt,
      );
    };
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'show' && refusePresent) {
        throw PlatformException(code: 'authored_show_refusal');
      }
      return call.method == 'initialize' ? true : null;
    });
  });
  tearDown(() async {
    await NotificationLog.instance.entries();
    await FileLog.write('Authored stale-sync barrier');
    center.presentSink = originalSink;
    service.debugProbePermission = null;
    service.debugRequestPermission = null;
    service.invalidatePermissionCache();
    SharedPreferencesStorePlatform.instance = originalStore;
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
  });
  tearDownAll(LocalDb.close);

  List<MethodCall> getShows() =>
      calls.where((c) => c.method == 'show').toList();
  Future<void> preserved() async {
    expect(await (await LocalDb.instance).query('sync_cursor'), cursors);
    expect(prefs.getString('authored-unrelated'), 'retain');
    expect(await (await LocalDb.instance).query('day_result'), isEmpty);
  }

  Future<void> onePresented(bool foreground, int before, int after) async {
    final wire = getShows().single.arguments as Map;
    expect(wire['title'], "Your band hasn't synced in a while");
    expect(wire['body'], contains('96 hours'));
    expect(wire['payload'], startsWith('/today'));
    expect(promptFlags, [foreground]);
    expect(probes, foreground ? 0 : 1);
    expect(
      prompts,
      foreground ? 1 : 0,
      reason:
          'Headless checks never request permission; foreground keeps its normal request path',
    );
    expect(prefs.getInt(_cooldown), inInclusiveRange(before, after));
    expect(
      (await NotificationLog.instance.entries()).where(
        (e) => e.title == wire['title'],
      ),
      hasLength(1),
    );
    await preserved();
  }

  for (final foreground in [false, true]) {
    for (final expired in [false, true]) {
      test(
        '${foreground ? 'foreground' : 'headless'} stale alert ${expired ? 'expired' : 'new'} cooldown commits after presentation',
        () async {
          if (expired) {
            await prefs.setInt(
              _cooldown,
              DateTime.now()
                  .subtract(const Duration(hours: 49))
                  .millisecondsSinceEpoch,
            );
          }
          final before = DateTime.now().millisecondsSinceEpoch;
          await checkSyncStaleness(allowPermissionPrompt: foreground);
          await onePresented(
            foreground,
            before,
            DateTime.now().millisecondsSinceEpoch,
          );
          final saved = prefs.getInt(_cooldown);
          await checkSyncStaleness(allowPermissionPrompt: foreground);
          expect(getShows(), hasLength(1));
          expect(prefs.getInt(_cooldown), saved);
        },
      );
    }
    test(
      '${foreground ? 'foreground' : 'headless'} refused native presentation releases its claim and retries',
      () async {
        final old = DateTime.now()
            .subtract(const Duration(hours: 49))
            .millisecondsSinceEpoch;
        await prefs.setInt(_cooldown, old);
        refusePresent = true;
        await checkSyncStaleness(allowPermissionPrompt: foreground);
        expect(getShows(), hasLength(1));
        expect(prefs.getInt(_cooldown), old);
        expect(await (await LocalDb.instance).query('notif_fired'), isEmpty);
        expect(await NotificationLog.instance.entries(), isEmpty);
        await preserved();
        refusePresent = false;
        final before = DateTime.now().millisecondsSinceEpoch;
        await checkSyncStaleness(allowPermissionPrompt: foreground);
        expect(getShows(), hasLength(2));
        expect(getShows()[0].arguments, getShows()[1].arguments);
        expect(promptFlags, [foreground, foreground]);
        expect(
          prefs.getInt(_cooldown),
          inInclusiveRange(before, DateTime.now().millisecondsSinceEpoch),
        );
        expect(
          await (await LocalDb.instance).query('notif_fired'),
          hasLength(1),
        );
        expect(await NotificationLog.instance.entries(), hasLength(1));
        await checkSyncStaleness(allowPermissionPrompt: foreground);
        expect(getShows(), hasLength(2));
        await preserved();
      },
    );
    test(
      '${foreground ? 'foreground' : 'headless'} overlapping wakes publish one alert and one cooldown',
      () async {
        final before = DateTime.now().millisecondsSinceEpoch;
        await Future.wait([
          checkSyncStaleness(allowPermissionPrompt: foreground),
          checkSyncStaleness(allowPermissionPrompt: foreground),
        ]);
        await onePresented(
          foreground,
          before,
          DateTime.now().millisecondsSinceEpoch,
        );
        expect(
          await (await LocalDb.instance).query('notif_fired'),
          hasLength(1),
        );
      },
    );
  }

  for (final ahead in [false, true]) {
    test(
      '${ahead ? 'Future' : 'Recent'} cooldown suppresses a re-alert without rewriting it',
      () async {
        final old = DateTime.now()
            .add(Duration(hours: ahead ? 1 : -1))
            .millisecondsSinceEpoch;
        await prefs.setInt(_cooldown, old);
        await checkSyncStaleness();
        expect(getShows(), isEmpty);
        expect(promptFlags, isEmpty);
        expect(prefs.getInt(_cooldown), old);
        expect(await (await LocalDb.instance).query('notif_fired'), isEmpty);
        await preserved();
      },
    );
  }
  for (final foreground in [false, true]) {
    test(
      '${foreground ? 'foreground' : 'headless'} cooldown store refusal preserves the shown alert and releases the check',
      () async {
        final store = CheckpointStore(targetKey: _cooldown);
        store.values.addAll({
          for (final name in prefs.getKeys()) 'flutter.$name': prefs.get(name)!,
        });
        SharedPreferences.setMockInitialValues({});
        SharedPreferencesStorePlatform.instance = store;
        prefs = await SharedPreferences.getInstance();
        await prefs.setBool('notif_quiet_enabled', false);
        await prefs.setString('authored-unrelated', 'retain');
        store.refuseWrite = 'throws';
        final marker = 'AUTHORED_COOLDOWN_REFUSAL_$foreground';
        await FileLog.write(marker);
        await checkSyncStaleness(allowPermissionPrompt: foreground);
        expect(getShows(), hasLength(1));
        expect(store.values['flutter.$_cooldown'], isNull);
        expect(
          await (await LocalDb.instance).query('notif_fired'),
          hasLength(1),
        );
        expect(await NotificationLog.instance.entries(), hasLength(1));
        await FileLog.write('barrier');
        final log = (await File(
          (await FileLog.path())!,
        ).readAsString()).split(marker).last;
        expect(log, contains('[bgsync] staleness check skipped:'));
        store.refuseWrite = null;
        await checkSyncStaleness(allowPermissionPrompt: foreground);
        expect(
          getShows(),
          hasLength(1),
          reason: 'The already-shown same-day claim still prevents duplicates',
        );
        await preserved();
      },
    );
  }
}
