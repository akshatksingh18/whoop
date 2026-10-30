// Real AppState wiring with synthetic stores and no radio or native acceptance.
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/ble/ble_engine.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/notify/notification_center.dart';
import 'package:whoop_companion/notify/notification_event.dart';
import 'package:whoop_companion/notify/notification_prefs.dart';
import 'package:whoop_companion/notify/notification_service.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/sync/ios_bg_task.dart';
import 'package:whoop_companion/sync/paired_device.dart';
import 'package:whoop_companion/sync/sync_policy.dart' show RestoreWakeOutcome;
import 'package:whoop_companion/ble/ios_ble_restore.dart';
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final service = NotificationService.instance;
  final center = NotificationCenter.instance;
  final oldSink = center.presentSink;
  final events = <NotificationEvent>[];
  setUpAll(() => coverageStore('app-wiring'));
  setUp(() async {
    await resetCoverageStore();
    events.clear();
    center.presentSink = (e, {bool allowPermissionPrompt = true}) async {
      events.add(e);
      return true;
    };
    service.debugProbePermission = () async => false;
    service.debugRequestPermission = () async => false;
    service.debugCancel = (_) async {};
    service.invalidatePermissionCache();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('whoop/ble_restore'),
          (c) async => c.method == 'appState' ? 'active' : null,
        );
  });
  tearDown(() {
    center.presentSink = oldSink;
    service.debugProbePermission = null;
    service.debugRequestPermission = null;
    service.debugCancel = null;
    service.invalidatePermissionCache();
    IosBgTask.foregroundPull = null;
    IosBleRestore.onWake = null;
    BleEngine.resetBandClaimForTest();
  });
  tearDownAll(LocalDb.close);
  test(
    'COV-48 real startup preserves legacy-only sample freshness without inventing decoded sensors',
    () async {
      final db = await LocalDb.instance;
      const ts = 1617700000;
      await db.insert('samples', {
        'ts': ts,
        'counter': 41,
        'hr': 68,
        'device_id': '',
        'ts_ms': ts * 1000,
      });
      final before = await db.query('samples');
      final app = AppState();
      try {
        for (
          var i = 0;
          i < 300 && !app.initialized && app.initError == null;
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(app.initError, isNull);
        expect(app.initialized, true);
        expect(app.lastSynced, isNotNull);
        expect(app.lastSynced!.tsEpoch, ts);
        expect(app.lastSynced!.counter, 41);
        expect(app.lastSynced!.hr, 68);
        expect(app.lastSynced!.ax, isNull);
        expect(app.lastSynced!.rrIntervalsMs, isEmpty);
        expect(await db.query('samples'), before);
        expect(await db.query('decoded_onehz'), isEmpty);
        expect(await LocalDb.getCursor('rec_ts_hw'), isNull);
        expect(
          app.engine.deriveDataStaleness(),
          greaterThan(const Duration(days: 365)),
        );
      } finally {
        await app.pauseForBackground();
        app.dispose();
        await app.engine.disconnect();
      }
    },
  );
  test(
    'COV-47 battery forecast uses configured evening rather than the host test hour',
    () async {
      final now = DateTime.now(),
          nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final minute = now.hour * 60 + now.minute;
      await NotificationPrefs(
        quietEnabled: false,
        quietStartMin: (minute + 60) % 1440,
        quietEndMin: (minute + 600) % 1440,
      ).save();
      for (var i = 0; i < 5; i++) {
        await LocalDb.insertBandBatterySample(
          ts: nowSec - (4 - i) * 3600,
          batteryPct: 35.0 - i * 5,
          charging: false,
          wristOn: true,
          source: 'device_state',
        );
      }
      final app = AppState.forTesting();
      try {
        app.engine.state
          ..batteryPct = 15
          ..charging = false
          ..wristOn = true;
        app.engine.onState(app.engine.state);
        for (
          var i = 0;
          i < 100 &&
              !events.any((e) => e.dedupeKey.endsWith(':battery_overnight'));
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        final event = events.singleWhere(
          (e) => e.dedupeKey.endsWith(':battery_overnight'),
        );
        expect(event.title, 'Charge your strap before bed');
        expect(event.route, '/profile');
        expect(event.date, todayLabel());
        expect(event.body, isNotEmpty);
        for (var i = 0; i < 5; i++) app.engine.onState(app.engine.state);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(
          events.where((e) => e.dedupeKey == event.dedupeKey),
          hasLength(1),
        );
      } finally {
        app.dispose();
        await app.engine.disconnect();
      }
    },
  );
  test(
    'COV-47 real app callbacks keep high-rate frames ephemeral and publish durable cursor data',
    () async {
      final app = AppState();
      try {
        for (
          var i = 0;
          i < 200 && !app.initialized && app.initError == null;
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(app.initError, isNull);
        expect(app.initialized, true);
        await app
            .openSession(); // unpaired foreground, no BLE connection attempted
        final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final r10 = Uint8List(685)
          ..[0] = 0x2b
          ..[1] = 10;
        ByteData.sublistView(r10).setUint32(7, ts, Endian.little);
        for (var i = 0; i < 100; i++)
          ByteData.sublistView(r10).setInt16(485 + i * 2, 4096, Endian.little);
        final imu = Uint8List(84)..[0] = 0x33;
        ByteData.sublistView(imu).setUint32(4, ts, Endian.little);
        for (var i = 0; i < 10; i++)
          ByteData.sublistView(imu).setInt16(64 + i * 2, 4096, Endian.little);
        String hex(Uint8List b) =>
            b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
        app.engine.onLiveFrame!(0x2b, hex(r10), ts);
        app.engine.onLiveFrame!(0x33, hex(imu), ts);
        app.engine.onLiveFrame!(
          0x2b,
          hex(r10),
          ts,
        ); // the established IMU source owns subsequent motion
        app.engine.onLiveFrame!(0x33, 'malformed', null);
        final db = await LocalDb.instance;
        final names = (await db.query(
          'sqlite_master',
          columns: ['name'],
          where: "type = 'table'",
        )).map((r) => r['name']).toSet();
        for (final table in ['raw_records', 'raw_archive', 'decoded_onehz']) {
          if (names.contains(table)) expect(await db.query(table), isEmpty);
        }
        expect(await LocalDb.getCursorInt('rec_ts_hw'), isNull);
        await LocalDb.setCursor('rec_ts_hw', '$ts');
        final before = app.insightsRevision.value;
        app.engine.onDataStored!();
        for (var i = 0; i < 100 && app.insightsRevision.value == before; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(app.insightsRevision.value, greaterThan(before));
        expect(await LocalDb.getCursorInt('rec_ts_hw'), ts);
        expect(app.engine.deriveDataStaleness().inSeconds, lessThan(5));
        expect(await IosBleRestore.onWake!(), RestoreWakeOutcome.notHandled);
      } finally {
        await app.pauseForBackground();
        app.dispose();
        await app.engine.disconnect();
      }
    },
  );
  test(
    'COV-47 route requests retain exact dated screens and profile gates',
    () async {
      final app = AppState.forTesting();
      try {
        for (final (route, tab, screen) in [
          ('/profile', 0, '/profile'),
          ('/heart?date=2021-04-06', 1, '/heart?date=2021-04-06'),
          ('/food?date=2021-04-06', 6, null),
          ('/workouts/pushups', 4, '/workouts/pushups'),
          ('/unknown', 0, null),
        ]) {
          app.openRoute(route);
          expect(app.navRequest.value, tab);
          expect(app.screenRequest.value, screen);
        }
        app.initialized = true;
        app.paired = PairedDevice('synthetic-device', null);
        app.user = {};
        expect(app.profileComplete, false);
        expect(app.route, AppRoute.profile);
        app.user = {'age': 30, 'weight_kg': 70, 'height_cm': 170, 'sex': 'f'};
        expect(app.profileComplete, true);
        expect(app.route, AppRoute.shell);
        await app.refreshBatteryThreshold(const NotificationPrefs());
        await app.runCadenceChecks();
        await app.refreshReminders();
        final profile = await app.repo?.getProfile();
        expect(
          profile == null ||
              jsonEncode(profile).contains('synthetic-device') == false,
          true,
        );
      } finally {
        app.dispose();
        await app.engine.disconnect();
      }
    },
  );
}
