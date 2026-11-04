// Real connect/bootstrap cleanup and retry. Only OS replies and store callbacks
// are scripted; no radio, personal records or native acceptance claim.
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart'
    as os;
import 'package:whoop_companion/ble/ble_engine.dart';
import 'package:whoop_companion/ble/ble_state.dart';
import 'package:whoop_protocol/whoop_protocol.dart' as p;
import 'coverage_gatt_connection_test.dart' show Peripheral;
import 'gen5_bootstrap_official_test.dart' show helloBody;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final peripheral = Peripheral();
  final logs = <String>[];
  os.FlutterBluePlusPlatform? original;
  BleEngine? engine;
  setUpAll(() {
    try {
      original = os.FlutterBluePlusPlatform.instance;
    } on UnsupportedError {
      // No native implementation is installed in this host test isolate.
    }
    os.FlutterBluePlusPlatform.instance = peripheral;
  });
  setUp(() {
    BleEngine.resetBandClaimForTest();
    logs.clear();
    peripheral.trace.clear();
    peripheral.mode = 'ready';
    peripheral.connectError = null;
    peripheral.replyToCommand = (_, request) {
      final payload = request[2] == p.Cmd.getHello
          ? helloBody(tsSeconds: DateTime.now().millisecondsSinceEpoch ~/ 1000)
          : const <int>[];
      peripheral.incoming.add(
        os.BmCharacteristicData(
          remoteId: Peripheral.id,
          primaryServiceUuid: null,
          serviceUuid: os.Guid(peripheral.band.gatt.service),
          characteristicUuid: os.Guid(peripheral.band.gatt.cmdFrom),
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
    await engine?.disconnect();
    expect(engine?.holdsBandLink, false);
    expect(engine?.pendingCommandCount, 0);
    expect(BleEngine.bandClaimed, false);
    engine = null;
  });
  tearDownAll(() {
    if (original != null) os.FlutterBluePlusPlatform.instance = original!;
  });

  Future<bool> connect() => engine!.connectToRemoteId(
    Peripheral.id.str,
    generationHint: peripheral.band.isGen5 ? 'gen5' : 'gen4',
  );

  for (final band in [p.BandProfile.gen4, p.BandProfile.gen5]) {
    test(
      '${band.type.name} an unexpected setup observer failure releases ownership and the operation queue',
      () async {
        peripheral.band = band;
        var refuseOnce = true;
        engine = BleEngine(
          onRecord: (_, _) async {},
          onState: (s) {
            if (refuseOnce && s.connection == 'connecting') {
              refuseOnce = false;
              throw StateError('authored setup observer refusal');
            }
          },
          log: logs.add,
        );
        peripheral.engine = engine!;
        expect(await connect(), false);
        expect(refuseOnce, false);
        expect(logs.join('\n'), contains('connect failed (unhandled):'));
        expect(logs.join('\n'), contains('authored setup observer refusal'));
        expect(engine!.holdsBandLink, false);
        expect(BleEngine.bandClaimed, false);
        expect(engine!.pendingCommandCount, 0);
        expect(peripheral.trace, isNot(contains('connect')));
        expect(await connect(), true, reason: logs.join('\n'));
        expect(engine!.holdsBandLink, true);
      },
    );

    for (final (reason, blocker) in [
      ('Bluetooth permission denied', BleBlocker.permissionDenied),
      ('Bluetooth must be turned on', BleBlocker.adapterOff),
      ('Bluetooth not supported', BleBlocker.unsupported),
    ]) {
      test(
        '${band.type.name} late connect refusal preserves $blocker and permits radio retry',
        () async {
          peripheral.band = band;
          engine = BleEngine(
            onRecord: (_, _) async {},
            onState: (_) {},
            log: logs.add,
          );
          peripheral.engine = engine!;
          peripheral.connectError = PlatformException(
            code: 'authored_connect',
            message: reason,
          );
          for (var attempt = 0; attempt < 2; attempt++) {
            expect(await connect(), false);
            expect(engine!.bandStatus.isFault, true);
            expect(engine!.holdsBandLink, false);
            expect(BleEngine.bandClaimed, false);
            expect(engine!.pendingCommandCount, 0);
          }
          expect(logs.join('\n'), contains(blocker.name));
          expect(peripheral.trace, isNot(contains('discover')));
          peripheral.connectError = null;
          expect(await connect(), true, reason: logs.join('\n'));
          expect(engine!.bandStatus.isFault, false);
          expect(engine!.holdsBandLink, true);
          expect(logs.where((l) => l.contains('block cleared')), hasLength(1));
        },
      );
    }

    for (final refusedKey in ['rec_ts_hw', 'counter_hw']) {
      test(
        '${band.type.name} refused $refusedKey restore cannot claim READY or start history, then retries',
        () async {
          peripheral.band = band;
          var refusing = true;
          final reads = <String>[];
          final states = <String>[];
          engine = BleEngine(
            onRecord: (_, _) async {},
            onState: (s) => states.add(s.connection),
            log: logs.add,
            cursorReader: (key) async {
              reads.add(key);
              if (refusing && key == refusedKey) {
                throw StateError('authored $key restore refusal');
              }
              return null;
            },
          );
          peripheral.engine = engine!;
          expect(await connect(), false);
          expect(reads, contains(refusedKey));
          expect(states, isNot(contains('connected')));
          expect(logs.join('\n'), contains('connect setup failed:'));
          expect(
            logs.join('\n'),
            contains('authored $refusedKey restore refusal'),
          );
          expect(engine!.holdsBandLink, false);
          expect(BleEngine.bandClaimed, false);
          expect(engine!.pendingCommandCount, 0);
          expect(
            peripheral.trace,
            isNot(contains('write:${p.Cmd.sendHistoricalData}')),
          );
          refusing = false;
          expect(await connect(), true, reason: logs.join('\n'));
          expect(engine!.holdsBandLink, true);
          expect(states, contains('connected'));
          expect(states.last, 'connected');
          expect(
            peripheral.trace.where(
              (s) => s == 'write:${p.Cmd.sendHistoricalData}',
            ),
            hasLength(1),
          );
        },
      );
    }
  }
}
