// Scripted OS disconnects through the real FBP bootstrap and command awaiter.
// Only authored replies; no native delivery or physical calibration claim.
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart'
    as os;
import 'package:whoop_companion/ble/ble_engine.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_protocol/whoop_protocol.dart' as p;
import 'coverage_gatt_connection_test.dart' show Peripheral;
import 'coverage_ble_durable_boundary_test.dart' show until;
import 'gen5_bootstrap_official_test.dart' show helloBody;
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final peripheral = Peripheral();
  final logs = <String>[], states = <String>[];
  late BleEngine engine;
  var oldClock = false;
  int? discriminator, helloRevision;
  setUpAll(() async {
    await coverageStore('gatt-bootstrap-disconnect');
    os.FlutterBluePlusPlatform.instance = peripheral;
  });
  setUp(() async {
    await resetCoverageStore();
    BleEngine.resetBandClaimForTest();
    logs.clear();
    states.clear();
    oldClock = false;
    discriminator = helloRevision = null;
    peripheral.band = p.BandProfile.gen4;
    peripheral.mode = 'ready';
    peripheral.trace.clear();
    peripheral.missing.clear();
    peripheral.refusedNotifications.clear();
    peripheral.beforeWrite = null;
    engine = BleEngine(
      onRecord: (_, _) async {},
      onState: (s) => states.add(s.connection),
      log: logs.add,
    );
    peripheral.engine = engine;
    peripheral.replyToCommand = (_, request) {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final payload = request[2] == p.Cmd.getHello
          ? helloBody(tsSeconds: oldClock ? now - 120 : now)
          : request[2] == p.Cmd.getClock
          ? (Uint8List(4)..buffer.asByteData().setUint32(0, now, Endian.little))
          : Uint8List(0);
      if (request[2] == p.Cmd.getHello) {
        if (discriminator case final value?) {
          ByteData.sublistView(payload).setUint32(87, value, Endian.little);
        }
        if (helloRevision case final value?) {
          payload[0] = value;
        }
      }
      final gatt = peripheral.band.gatt;
      peripheral.incoming.add(
        os.BmCharacteristicData(
          remoteId: Peripheral.id,
          primaryServiceUuid: null,
          serviceUuid: os.Guid(gatt.service),
          characteristicUuid: os.Guid(gatt.cmdFrom),
          instanceId: 0,
          value: p.buildFrame(
            Uint8List.fromList([
              p.PacketType.commandResponse,
              17,
              request[2],
              request[1],
              1,
              ...payload,
            ]),
            profile: peripheral.band,
          ),
          success: true,
          errorCode: 0,
          errorString: '',
        ),
      );
    };
  });
  tearDown(() async {
    await engine.disconnect();
    peripheral.beforeWrite = null;
    peripheral.replyToCommand = null;
    expect(engine.pendingCommandCount, 0);
    expect(engine.holdsBandLink, false);
    expect(BleEngine.bandClaimed, false);
  });
  tearDownAll(LocalDb.close);

  for (final stage in [
    (p.BandProfile.gen4, p.Cmd.getClock, 'clock read'),
    (p.BandProfile.gen4, p.Cmd.setClock, 'SET_CLOCK'),
    (p.BandProfile.gen5, p.Cmd.setClock, 'SET_CLOCK'),
    (
      p.BandProfile.gen5,
      p.Cmd.getCustomAdvertisingName,
      'advertising-name read',
    ),
  ]) {
    test(
      'COV-48 ${stage.$1.type.name} bootstrap disconnect during ${stage.$3} releases readiness and retries',
      () async {
        peripheral.band = stage.$1;
        oldClock = stage.$1.isGen5 && stage.$2 == p.Cmd.setClock;
        var dropped = false;
        peripheral.beforeWrite = (_, inner) async {
          if (!dropped && inner[2] == stage.$2) {
            dropped = true;
            peripheral.link(false);
            await Future<void>.delayed(const Duration(milliseconds: 40));
          }
        };
        expect(
          await engine.connectToRemoteId(
            Peripheral.id.str,
            generationHint: stage.$1.isGen5 ? 'gen5' : 'gen4',
          ),
          false,
          reason: logs.join('\n'),
        );
        expect(dropped, true);
        expect(states, isNot(contains('connected')));
        expect(engine.pendingCommandCount, 0);
        await until(() => !engine.holdsBandLink && !BleEngine.bandClaimed);
        expect(
          logs.any(
            (l) => l.contains('link dropped during') && l.contains(stage.$3),
          ),
          true,
          reason: logs.join('\n'),
        );
        final writesBeforeRetry = peripheral.trace
            .where((s) => s == 'write:${p.Cmd.sendHistoricalData}')
            .length;
        expect(writesBeforeRetry, 0);
        peripheral.beforeWrite = null;
        expect(
          await engine.connectToRemoteId(
            Peripheral.id.str,
            generationHint: stage.$1.isGen5 ? 'gen5' : 'gen4',
          ),
          true,
          reason: logs.join('\n'),
        );
        expect(engine.isConnected, true);
        expect(engine.pendingCommandCount, 0);
        expect(
          peripheral.trace.where(
            (s) => s == 'write:${p.Cmd.sendHistoricalData}',
          ),
          hasLength(1),
        );
        expect(await LocalDb.getCursor('strap_trim'), isNull);
        expect(await (await LocalDb.instance).query('decoded_onehz'), isEmpty);
      },
    );
  }
  for (final throwWrite in [false, true]) {
    test(
      'COV-48 gen5 optional advertising-name write refusal=$throwWrite does not fail readiness',
      () async {
        peripheral.band = p.BandProfile.gen5;
        var refused = false;
        peripheral.beforeWrite = (_, inner) async {
          if (inner[2] == p.Cmd.getCustomAdvertisingName) {
            refused = true;
            if (throwWrite) {
              throw StateError('authored optional-name write refusal');
            }
          }
        };
        expect(
          await engine.connectToRemoteId(
            Peripheral.id.str,
            generationHint: 'gen5',
          ),
          true,
          reason: logs.join('\n'),
        );
        expect(refused, true);
        expect(engine.isConnected, true);
        expect(engine.state.generation, 'gen5');
        expect(
          logs.any((l) => l.contains('GET_ADVERTISING_NAME was never written')),
          throwWrite,
        );
        expect(
          peripheral.trace.where(
            (s) => s == 'write:${p.Cmd.sendHistoricalData}',
          ),
          hasLength(1),
        );
      },
    );
  }
  for (final unknown in ['family', 'revision']) {
    test(
      'COV-48 gen5 unknown hello $unknown preserves identity and its clock contract',
      () async {
        peripheral.band = p.BandProfile.gen5;
        if (unknown == 'family') {
          discriminator = 204;
        }
        if (unknown == 'revision') {
          helloRevision = 2;
        }
        expect(
          await engine.connectToRemoteId(
            Peripheral.id.str,
            generationHint: 'gen5',
          ),
          true,
          reason: logs.join('\n'),
        );
        expect(engine.state.generation, 'gen5');
        expect(
          engine.state.serial,
          unknown == 'revision' ? isNull : 'W5AB12CD34',
        );
        expect(
          peripheral.trace.where((s) => s == 'write:${p.Cmd.getClock}'),
          isEmpty,
        );
        expect(
          peripheral.trace.where((s) => s == 'write:${p.Cmd.setClock}'),
          unknown == 'revision' ? hasLength(1) : isEmpty,
        );
        expect(
          logs.any(
            (l) => l.contains(
              unknown == 'family'
                  ? 'maps to no known family'
                  : 'correcting unconditionally',
            ),
          ),
          true,
        );
        expect(engine.pendingCommandCount, 0);
      },
    );
  }
}
