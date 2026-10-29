// Actual AppState constructor -> FBP -> atomic store -> verbatim ACK.
// Raw/derive journeys run in cloud CI; only the empty startup probe is local.
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart'
    as os;
import 'package:whoop_companion/ble/ble_engine.dart';
import 'package:whoop_companion/ble/ios_ble_restore.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/notify/notification_service.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/sync/band_ownership.dart';
import 'package:whoop_companion/sync/file_log.dart';
import 'package:whoop_companion/sync/ios_bg_task.dart';
import 'package:whoop_companion/sync/paired_device.dart';
import 'package:whoop_protocol/whoop_protocol.dart' as p;
import 'coverage_gatt_connection_test.dart' show Peripheral;
import 'gen5_bootstrap_official_test.dart' show helloBody;
import 'coverage_ble_durable_boundary_test.dart'
    show historyStart, historyEnd, record, until;
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final peripheral = Peripheral();
  final notifications = NotificationService.instance;
  late AppState app;
  final reports = <Future<SyncReport>>[];
  setUpAll(() async {
    await coverageStore('app-gatt-storage');
    os.FlutterBluePlusPlatform.instance = peripheral;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_timezone'),
          (_) async => 'UTC',
        );
  });
  void receive(Uint8List inner, {String? characteristic}) {
    final g = peripheral.band.gatt;
    peripheral.incoming.add(
      os.BmCharacteristicData(
        remoteId: Peripheral.id,
        primaryServiceUuid: null,
        serviceUuid: os.Guid(g.service),
        characteristicUuid: os.Guid(characteristic ?? g.data),
        instanceId: 0,
        value: p.buildFrame(inner, profile: peripheral.band),
        success: true,
        errorCode: 0,
        errorString: '',
      ),
    );
  }

  setUp(() async {
    await resetCoverageStore();
    reports.clear();
    BandOwnership.resetForTest();
    BleEngine.resetBandClaimForTest();
    peripheral.band = p.BandProfile.gen4;
    peripheral.mode = 'ready';
    peripheral.trace.clear();
    peripheral.beforeWrite = null;
    peripheral.missing.clear();
    peripheral.refusedNotifications.clear();
    notifications.debugProbePermission = () async => false;
    notifications.debugRequestPermission = () async => false;
    notifications.debugCancel = (_) async {};
    notifications.invalidatePermissionCache();
    app = AppState();
    peripheral.engine = app.engine;
    peripheral.replyToCommand = (_, request) {
      final op = request[2];
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final payload = op == p.Cmd.getHello
          ? helloBody(tsSeconds: now)
          : op == p.Cmd.getClock
          ? (Uint8List(4)..buffer.asByteData().setUint32(0, now, Endian.little))
          : const <int>[];
      receive(
        Uint8List.fromList([
          p.PacketType.commandResponse,
          17,
          op,
          request[1],
          1,
          ...payload,
        ]),
        characteristic: peripheral.band.gatt.cmdFrom,
      );
    };
    await until(() => app.initialized || app.initError != null, attempts: 2000);
    expect(app.initError, isNull);
    expect(app.initialized, true);
    app.user = {'age': 30, 'sex': 'f', 'weight_kg': 70, 'height_cm': 170};
  });
  tearDown(() async {
    await (await LocalDb.instance).execute(
      'DROP TRIGGER IF EXISTS authored_app_commit_refusal',
    );
    await app.pauseForBackground();
    await app.endSession();
    app.dispose();
    await app.engine.disconnect();
    await Future.wait(reports);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    IosBgTask.foregroundPull = null;
    IosBleRestore.onWake = null;
    IosBleRestore.foregroundActive = false;
    notifications.debugProbePermission = null;
    notifications.debugRequestPermission = null;
    notifications.debugCancel = null;
    notifications.invalidatePermissionCache();
    peripheral.beforeWrite = null;
    BandOwnership.resetForTest();
    BleEngine.resetBandClaimForTest();
    await FileLog.write('Authored full-app storage barrier');
  });
  tearDownAll(LocalDb.close);

  test(
    'empty real startup binds foreground ownership without starting a radio session',
    () async {
      await app.openSession();
      expect(app.engine.isForegroundActive(), true);
      expect(peripheral.trace, isNot(contains('connect')));
      expect(app.engine.onCommitBatch, isNotNull);
      expect(app.engine.onArchiveRecord, isNotNull);
      await app.pauseForBackground();
      expect(app.engine.isForegroundActive(), false);
      expect(await (await LocalDb.instance).query('decoded_onehz'), isEmpty);
    },
  );

  for (final band in [p.BandProfile.gen4, p.BandProfile.gen5]) {
    for (final refusal in [false, true]) {
      test(
        'cloud full-app ${band.type.name} commit refusal=$refusal preserves row/cursor before its ACK',
        () async {
          peripheral.band = band;
          app.paired = PairedDevice(
            Peripheral.id.str,
            null,
            generation: band.isGen5 ? 'gen5' : 'gen4',
          );
          final db = await LocalDb.instance;
          final acks = <List<int>>[];
          peripheral.beforeWrite = (_, inner) async {
            if (inner[2] == p.Cmd.historicalDataResult && inner[3] == 1) {
              expect(await db.query('decoded_onehz'), hasLength(1));
              expect(await LocalDb.getCursor('strap_trim'), '8172635445362718');
              acks.add(List.of(inner));
            }
          };
          Future<void> connect() async {
            await app.openSession();
            expect(
              app.engine.isConnected,
              true,
              reason: app.logLines.join('\n'),
            );
            await app.pauseForBackground();
            // This is a passive observer of the same real drain, not a request
            // for another transfer. Await it at teardown before resetting SQLite.
            reports.add(
              app.engine.runSync(timeout: const Duration(seconds: 10)),
            );
          }

          Future<void> burst() async {
            receive(historyStart());
            final sample = record(band);
            ByteData.sublistView(sample).setUint32(
              7,
              DateTime.now().millisecondsSinceEpoch ~/ 1000 - 60,
              Endian.little,
            );
            receive(sample);
            await until(
              () => app.engine.offloadSnapshot['buffered_records'] == 1,
            );
            receive(historyEnd());
          }

          await connect();
          if (refusal) {
            await db.execute(
              "CREATE TRIGGER authored_app_commit_refusal BEFORE INSERT ON decoded_onehz BEGIN SELECT RAISE(ABORT,'authored app commit refusal'); END",
            );
          }
          await burst();
          if (refusal) {
            await until(
              () =>
                  app.logLines.any((s) => s.contains('offload commit FAILED')),
            );
            expect(acks, isEmpty);
            expect(await db.query('decoded_onehz'), isEmpty);
            expect(await LocalDb.getCursor('strap_trim'), isNull);
            await app.endSession();
            await db.execute('DROP TRIGGER authored_app_commit_refusal');
            await connect();
            await burst();
          }
          await until(() => acks.isNotEmpty, attempts: 2000);
          expect(acks, hasLength(1));
          expect(acks.single.sublist(3, 12), [
            1,
            0x81,
            0x72,
            0x63,
            0x54,
            0x45,
            0x36,
            0x27,
            0x18,
          ]);
          final saved = await db.query('decoded_onehz');
          expect(saved, hasLength(1));
          expect(saved.single['device_family'], app.engine.state.generation);
          expect(await LocalDb.getCursorInt('counter_hw'), 41);
          // Stop the owning session before a held drain can schedule night workers.
          await app.endSession();
        },
        timeout: const Timeout(Duration(seconds: 95)),
      );
    }
  }
}
