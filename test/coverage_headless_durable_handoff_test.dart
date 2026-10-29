// Real background orchestration, protocol subscription and one-row SQLite ACK
// boundary. The OS peripheral is scripted; no radio/OS wake is certified here.
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart'
    as os;
import 'package:whoop_protocol/whoop_protocol.dart' as p;
import 'package:whoop_companion/ble/ble_engine.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/sync/background_sync.dart';
import 'package:whoop_companion/sync/band_ownership.dart';
import 'package:whoop_companion/sync/file_log.dart';
import 'package:whoop_companion/sync/paired_device.dart';
import 'coverage_gatt_connection_test.dart' show Peripheral;
import 'coverage_ble_durable_boundary_test.dart'
    show historyStart, historyEnd, historyComplete, record;
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final peripheral = Peripheral();
  setUpAll(() async {
    await coverageStore('headless-durable-handoff');
    os.FlutterBluePlusPlatform.instance = peripheral;
  });
  setUp(() async {
    await resetCoverageStore();
    BandOwnership.resetForTest();
    BleEngine.resetBandClaimForTest();
    peripheral.trace.clear();
    peripheral.mode = 'ready';
    peripheral.replyToCommand = null;
  });
  tearDown(() async {
    await FileLog.write('Authored headless handoff cleanup');
    expect(BleEngine.bandClaimed, false);
    expect(BandOwnership.owner, isNull);
  });
  tearDownAll(LocalDb.close);

  for (final mode in [
    'not-paired',
    'connect-refused',
    'no-service',
    'subscribe-refused',
  ]) {
    test(
      'headless $mode preserves pairing and leaves no band owner or derive job',
      () async {
        if (mode != 'not-paired') {
          await PairedDevice.save(Peripheral.id.str, null, generation: 'gen4');
        }
        peripheral.mode = mode;
        expect(await runHeadlessSync(wake: 'authored-$mode'), true);
        expect(
          (await PairedDevice.load())?.remoteId,
          mode == 'not-paired' ? isNull : Peripheral.id.str,
        );
        expect(await LocalDb.getCursorInt('rec_ts_hw'), isNull);
        expect(await LocalDb.computeJobs(state: 'queued'), isEmpty);
        expect(peripheral.trace.where((s) => s.startsWith('write:')), isEmpty);
      },
    );
  }
  test(
    'foreground ownership skips a headless connect without releasing its peer lease',
    () async {
      final foreground = await BandOwnership.acquireForeground();
      try {
        expect(await runHeadlessSync(wake: 'authored-busy'), true);
        expect(BandOwnership.owner, BandOwnerKind.foreground);
        expect(peripheral.trace, isEmpty);
      } finally {
        BandOwnership.release(foreground);
      }
    },
  );
  for (final outcome in ['queued', 'queue-refused', 'expired-after-ack']) {
    final refuseQueue = outcome == 'queue-refused';
    final expireAfterAck = outcome == 'expired-after-ack';
    test(
      'headless durable ACK precedes calculation queue and teardown $outcome',
      () async {
        await PairedDevice.save(Peripheral.id.str, null);
        final db = await LocalDb.instance;
        if (refuseQueue) {
          await db.execute(
            "CREATE TRIGGER synthetic_queue_refusal BEFORE INSERT ON compute_jobs BEGIN SELECT RAISE(ABORT,'synthetic queue refusal'); END",
          );
        }
        final timers = <Timer>[];
        final at = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final sample = record(p.BandProfile.gen4);
        ByteData.sublistView(sample).setUint32(7, at - 60, Endian.little);
        final ackRows = <int>[], ackCursors = <String?>[];
        final ackTokens = <List<int>>[];
        void receive(List<int> inner, String role) {
          peripheral.incoming.add(
            os.BmCharacteristicData(
              remoteId: Peripheral.id,
              primaryServiceUuid: null,
              serviceUuid: os.Guid(p.GattProfile.gen4.service),
              characteristicUuid: os.Guid(role),
              instanceId: 0,
              value: p.buildFrame(Uint8List.fromList(inner)),
              success: true,
              errorCode: 0,
              errorString: '',
            ),
          );
        }

        peripheral.replyToCommand = (_, inner) {
          final op = inner[2];
          final response = Uint8List(op == p.Cmd.getClock ? 9 : 5)
            ..[0] = p.PacketType.commandResponse
            ..[2] = op
            ..[3] = inner[1]
            ..[4] = 1;
          if (op == p.Cmd.getClock) {
            ByteData.sublistView(response).setUint32(5, at, Endian.little);
          }
          receive(response, p.GattProfile.gen4.cmdFrom);
          if (op == p.Cmd.sendHistoricalData) {
            timers.add(
              Timer(const Duration(milliseconds: 100), () {
                for (final part in [historyStart(), sample, historyEnd()]) {
                  receive(part, p.GattProfile.gen4.data);
                }
              }),
            );
          }
          if (op == p.Cmd.historicalDataResult) {
            ackTokens.add(inner.sublist(4, 12));
            // The callback runs only after the production durable transaction.
            unawaited(() async {
              ackRows.add((await db.query('decoded_onehz')).length);
              ackCursors.add(await LocalDb.getCursor('strap_trim'));
              if (expireAfterAck) {
                // The real registered headless stop disconnects this transport.
                // No HISTORY_COMPLETE is supplied after the durable ACK.
                BandOwnership.requestHeadlessStop('authored_wake_expired');
              } else {
                receive(historyComplete(), p.GattProfile.gen4.data);
              }
            }());
          }
        };
        try {
          expect(
            await runHeadlessSync(wake: 'authored-durable').timeout(
              const Duration(seconds: 12),
              onTimeout: () {
                BandOwnership.requestHeadlessStop('authored_test_deadline');
                throw TimeoutException(
                  'Authored headless handoff did not settle',
                );
              },
            ),
            true,
          );
          expect(ackRows, [1]);
          expect(ackCursors, ['8172635445362718']);
          expect(ackTokens, [
            [0x81, 0x72, 0x63, 0x54, 0x45, 0x36, 0x27, 0x18],
          ]);
          expect(await LocalDb.getCursorInt('rec_ts_hw'), at - 60);
          expect((await PairedDevice.load())!.generation, 'gen4');
          final jobs = await LocalDb.computeJobs(state: 'queued');
          expect(jobs, refuseQueue ? isEmpty : hasLength(1));
          if (!refuseQueue) expect(jobs.single['reason'], 'headless_sync');
          expect(peripheral.trace.last, 'disconnect');
        } finally {
          BandOwnership.requestHeadlessStop('authored_test_cleanup');
          for (final timer in timers) {
            timer.cancel();
          }
          await db.execute('DROP TRIGGER IF EXISTS synthetic_queue_refusal');
        }
      },
    );
  }
}
