// Real FBP discovery, CCC registration and framed gen5 replies over an authored
// peripheral. This checks Dart ownership/retry, not native or physical delivery.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart'
    as os;
import 'package:whoop_companion/ble/adapters/_registry.dart';
import 'package:whoop_companion/ble/ble_engine.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/models.dart';
import 'package:whoop_protocol/whoop_protocol.dart' as p;

import 'coverage_gatt_connection_test.dart' show Peripheral;
import 'gen5_bootstrap_official_test.dart' show helloBody;
import 'coverage_ble_durable_boundary_test.dart' show historyComplete, until;
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final peripheral = Peripheral()..band = p.BandProfile.gen5;
  final gatt = p.GattProfile.gen5;
  final logs = <String>[], states = <String>[];
  final archives = <ArchiveRecord>[];
  late BleEngine engine;
  setUpAll(() async {
    os.FlutterBluePlusPlatform.instance = peripheral;
    await coverageStore('gen5-gatt-handoff');
  });
  tearDownAll(LocalDb.close);

  void receive(String characteristic, List<int> bytes) {
    peripheral.incoming.add(
      os.BmCharacteristicData(
        remoteId: Peripheral.id,
        primaryServiceUuid: null,
        serviceUuid: os.Guid(gatt.service),
        characteristicUuid: os.Guid(characteristic),
        instanceId: 0,
        value: bytes,
        success: true,
        errorCode: 0,
        errorString: '',
      ),
    );
  }

  setUp(() async {
    await resetCoverageStore();
    BleEngine.resetBandClaimForTest();
    peripheral.trace.clear();
    peripheral.missing.clear();
    peripheral.refusedNotifications.clear();
    peripheral.mode = 'ready';
    logs.clear();
    states.clear();
    archives.clear();
    engine = BleEngine(
      onRecord: (_, _) async {},
      onState: (s) => states.add(s.connection),
      log: logs.add,
      onArchiveRecord: (a) async {
        await LocalDb.archiveRawRecord(a);
        archives.add(a);
      },
    );
    peripheral.engine = engine;
    peripheral.replyToCommand = (_, request) {
      final payload = request[2] == p.Cmd.getHello
          ? helloBody(tsSeconds: DateTime.now().millisecondsSinceEpoch ~/ 1000)
          : const <int>[];
      receive(
        gatt.cmdFrom,
        p.buildFrame(
          Uint8List.fromList([
            p.PacketType.commandResponse,
            17,
            request[2],
            request[1],
            1,
            ...payload,
          ]),
          profile: p.BandProfile.gen5,
        ),
      );
    };
  });
  tearDown(() async {
    await engine.disconnect();
    expect(engine.holdsBandLink, false);
    expect(BleEngine.bandClaimed, false);
    expect(engine.pendingCommandCount, 0);
  });

  for (final mode in [
    'ready',
    'optional-missing',
    'optional-refused',
    'missing-write',
    'missing-command',
    'missing-data',
    'missing-events',
    'refused-command',
    'refused-data',
    'refused-events',
  ]) {
    test(
      'real gen5 GATT $mode keeps required readiness and recoverable ownership',
      () async {
        final required = {
          'write': gatt.cmdTo,
          'command': gatt.cmdFrom,
          'data': gatt.data,
          'events': gatt.events,
        };
        if (mode.startsWith('missing-')) {
          peripheral.missing.add(required[mode.substring(8)]!);
        }
        if (mode.startsWith('refused-')) {
          peripheral.refusedNotifications.add(required[mode.substring(8)]!);
        }
        if (mode == 'optional-missing') peripheral.missing.add(gatt.memfault);
        if (mode == 'optional-refused') {
          peripheral.refusedNotifications.add(gatt.memfault);
        }
        final succeeds = mode == 'ready' || mode.startsWith('optional-');
        expect(
          await engine.connectToRemoteId(
            Peripheral.id.str,
            generationHint: 'gen5',
          ),
          succeeds,
          reason: logs.join('\n'),
        );
        if (!succeeds) {
          expect(states, isNot(contains('connected')));
          expect(engine.holdsBandLink, false);
          expect(BleEngine.bandClaimed, false);
          expect(peripheral.trace, isNot(contains('write:${p.Cmd.getHello}')));
          expect(engine.pendingCommandCount, 0);
          peripheral.missing.clear();
          peripheral.refusedNotifications.clear();
          expect(
            await engine.connectToRemoteId(
              Peripheral.id.str,
              generationHint: 'gen5',
            ),
            true,
            reason: logs.join('\n'),
          );
        }
        expect(engine.isConnected, true);
        expect(engine.state.generation, kWhoopGen5.id);
        expect(
          peripheral.trace,
          containsAllInOrder([
            'subscribe:${gatt.cmdFrom}',
            if (mode != 'optional-missing') 'subscribe:${gatt.memfault}',
            'subscribe:${gatt.data}',
            'subscribe:${gatt.events}',
            'write:${p.Cmd.getHello}',
            'write:${p.Cmd.getCustomAdvertisingName}',
          ]),
        );
        expect(engine.pendingCommandCount, 0);
        expect(engine.state.needsRepairGuide, false);
        if (mode == 'ready') {
          receive(gatt.memfault, [1, 2, 3]);
          receive(gatt.memfault, [4, 5]);
          await Future<void>.delayed(const Duration(milliseconds: 20));
          expect(engine.offloadSnapshot['memfault_chunks'], 2);
          expect(engine.offloadSnapshot['memfault_bytes'], 5);
          expect(engine.isConnected, true);
          await engine.disconnect();
          final before = engine.offloadSnapshot['memfault_chunks'];
          receive(gatt.memfault, [6, 7]);
          await Future<void>.delayed(const Duration(milliseconds: 20));
          expect(engine.offloadSnapshot['memfault_chunks'], before);
        }
      },
    );
  }

  for (final channel in [gatt.cmdFrom, gatt.events, gatt.data]) {
    for (final syncing in [false, true]) {
      test(
        'gen5 $channel archives unknown envelope revisions only during offload=$syncing',
        () async {
          expect(
            await engine.connectToRemoteId(
              Peripheral.id.str,
              generationHint: 'gen5',
            ),
            true,
          );
          if (!syncing) {
            receive(
              gatt.data,
              p.buildFrame(historyComplete(), profile: p.BandProfile.gen5),
            );
            await until(() => !engine.offloadActive);
          }
          final inner = Uint8List(16)..[0] = p.PacketType.historicalData;
          ByteData.sublistView(inner).setUint32(3, 41, Endian.little);
          final frame = p.buildFrame(inner, profile: p.BandProfile.gen5)
            ..[1] = 2;
          final crc = p.crc16Modbus(frame.sublist(0, 6));
          frame[6] = crc & 255;
          frame[7] = crc >> 8;
          expect(p.parseFrame(frame, profile: p.BandProfile.gen5)!.valid, true);
          receive(channel, frame.sublist(0, 4));
          receive(channel, frame.sublist(4));
          await until(
            () => engine.offloadSnapshot['frame_rev_rejects_total'] == 1,
          );
          if (syncing) await until(() => archives.length == 1);
          expect(engine.offloadSnapshot['crc_failures_this_session'], 0);
          final rows = await (await LocalDb.instance).query('raw_archive');
          expect(rows, hasLength(syncing ? 1 : 0));
          if (syncing) {
            final hex = inner
                .map((b) => b.toRadixString(16).padLeft(2, '0'))
                .join();
            expect(rows.single['hex'], hex);
            expect(rows.single['reason'], 'undecodable_frame_rev');
            expect(archives.single.recTs, isNull);
          }
          expect(
            await (await LocalDb.instance).query('decoded_onehz'),
            isEmpty,
          );
          expect(
            peripheral.trace,
            isNot(contains('write:${p.Cmd.historicalDataResult}')),
          );
          expect(engine.isConnected, true);
        },
      );
    }
    test(
      'gen5 $channel CRC failure is counted without archiving or decoding the bytes',
      () async {
        expect(
          await engine.connectToRemoteId(
            Peripheral.id.str,
            generationHint: 'gen5',
          ),
          true,
        );
        final inner = Uint8List(16)..[0] = p.PacketType.historicalData;
        final frame = p.buildFrame(inner, profile: p.BandProfile.gen5);
        frame[frame.length - 1] ^= 1;
        receive(channel, frame);
        await until(
          () => engine.offloadSnapshot['crc_failures_this_session'] == 1,
        );
        expect(engine.offloadSnapshot['frame_rev_rejects_total'], 0);
        expect(archives, isEmpty);
        expect(await (await LocalDb.instance).query('raw_archive'), isEmpty);
        expect(await (await LocalDb.instance).query('decoded_onehz'), isEmpty);
        expect(engine.isConnected, true);
      },
    );
  }
}
