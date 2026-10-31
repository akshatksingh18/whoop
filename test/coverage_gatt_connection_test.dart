// Real FBP/engine connect and subscription paths; only the OS peripheral is scripted.
// This checks host behavior, not radio or iOS acceptance.
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart'
    as os;
import 'package:whoop_protocol/whoop_protocol.dart' as p;
import 'package:whoop_companion/ble/ble_engine.dart';

final class Peripheral extends os.FlutterBluePlusPlatform {
  final links = StreamController<os.BmConnectionStateResponse>.broadcast();
  final discovery = StreamController<os.BmDiscoverServicesResult>.broadcast();
  final incoming = StreamController<os.BmCharacteristicData>.broadcast();
  final written = StreamController<os.BmCharacteristicData>.broadcast();
  final adapters = StreamController<os.BmBluetoothAdapterState>.broadcast();
  final descriptors = StreamController<os.BmDescriptorData>.broadcast();
  @override
  Stream<os.BmDescriptorData> get onDescriptorWritten => descriptors.stream;
  final scans = StreamController<os.BmScanResponse>.broadcast();
  @override
  Stream<os.BmScanResponse> get onScanResponse => scans.stream;
  @override
  Future<bool> startScan(os.BmScanSettings r) async {
    trace.add('scan');
    if (scanError case final error?) throw error;
    if (mode == 'scan-refused') throw StateError('synthetic scan refusal');
    if (mode != 'empty-scan')
      Future<void>.delayed(
        const Duration(milliseconds: 20),
        () => scans.add(
          os.BmScanResponse(
            advertisements: [
              os.BmScanAdvertisement(
                remoteId: id,
                platformName: mode == 'name-scan'
                    ? 'WHOOP synthetic'
                    : 'Synthetic peripheral',
                advName: null,
                connectable: true,
                txPowerLevel: null,
                appearance: null,
                manufacturerData: {},
                serviceData: {},
                serviceUuids: mode == 'name-scan'
                    ? []
                    : [os.Guid(band.gatt.service)],
                rssi: -60,
              ),
            ],
            success: true,
            errorCode: 0,
            errorString: '',
          ),
        ),
      );
    return true;
  }

  @override
  Future<bool> stopScan(os.BmStopScanRequest r) async {
    trace.add('stop-scan');
    if (stopError case final error?) {
      throw error;
    }
    return true;
  }

  final trace = <String>[];
  Object? stopError;
  p.BandProfile band = p.BandProfile.gen4;
  final missing = <String>{};
  final refusedNotifications = <String>{};
  String mode = 'ready';
  Object? scanError;
  os.BmAdapterStateEnum radioState = os.BmAdapterStateEnum.on;
  late BleEngine engine;
  Future<void> Function(
    os.BmWriteCharacteristicRequest request,
    List<int> inner,
  )?
  beforeWrite;
  void Function(os.BmWriteCharacteristicRequest request, List<int> inner)?
  replyToCommand;
  static const id = os.DeviceIdentifier('AA:BB:CC:DD:EE:01');
  @override
  Stream<os.BmConnectionStateResponse> get onConnectionStateChanged =>
      links.stream;
  @override
  Stream<os.BmDiscoverServicesResult> get onDiscoveredServices =>
      discovery.stream;
  @override
  Stream<os.BmCharacteristicData> get onCharacteristicReceived =>
      incoming.stream;
  @override
  Stream<os.BmCharacteristicData> get onCharacteristicWritten => written.stream;
  @override
  Stream<os.BmBluetoothAdapterState> get onAdapterStateChanged =>
      adapters.stream;
  @override
  Future<os.BmBluetoothAdapterState> getAdapterState(
    os.BmBluetoothAdapterStateRequest r,
  ) async => os.BmBluetoothAdapterState(adapterState: radioState);
  @override
  Future<bool> isSupported(os.BmIsSupportedRequest r) async => true;
  void link(bool on, {os.DeviceIdentifier remoteId = id}) => links.add(
    os.BmConnectionStateResponse(
      remoteId: remoteId,
      connectionState: on
          ? os.BmConnectionStateEnum.connected
          : os.BmConnectionStateEnum.disconnected,
      disconnectReasonCode: on ? null : 19,
      disconnectReasonString: on ? null : 'synthetic link ended',
    ),
  );
  @override
  Future<bool> connect(os.BmConnectRequest r) async {
    trace.add('connect');
    if (mode == 'connect-refused')
      throw StateError('synthetic connect refusal');
    link(true);
    return true;
  }

  @override
  Future<bool> disconnect(os.BmDisconnectRequest r) async {
    trace.add('disconnect');
    link(false, remoteId: r.remoteId);
    return true;
  }

  os.BmBluetoothCharacteristic characteristic(String uuid) =>
      os.BmBluetoothCharacteristic(
        remoteId: id,
        primaryServiceUuid: null,
        serviceUuid: os.Guid(band.gatt.service),
        characteristicUuid: os.Guid(uuid),
        instanceId: 0,
        descriptors: [],
        properties: os.BmCharacteristicProperties(
          broadcast: false,
          read: true,
          write: true,
          writeWithoutResponse: false,
          notify: true,
          indicate: false,
          authenticatedSignedWrites: false,
          extendedProperties: false,
          notifyEncryptionRequired: false,
          indicateEncryptionRequired: false,
        ),
      );
  @override
  Future<bool> discoverServices(os.BmDiscoverServicesRequest r) async {
    trace.add('discover');
    if (mode == 'discovery-refused')
      throw StateError('synthetic discovery refusal');
    final g = band.gatt;
    discovery.add(
      os.BmDiscoverServicesResult(
        remoteId: id,
        services: mode == 'no-service'
            ? []
            : [
                os.BmBluetoothService(
                  remoteId: id,
                  primaryServiceUuid: null,
                  serviceUuid: os.Guid(g.service),
                  characteristics: [
                    for (final u in [
                      g.cmdTo,
                      g.cmdFrom,
                      g.events,
                      g.data,
                      g.memfault,
                    ])
                      if (!missing.contains(u) &&
                          (mode != 'missing-data' || u != g.data))
                        characteristic(u),
                  ],
                ),
              ],
        success: true,
        errorCode: 0,
        errorString: '',
      ),
    );
    return true;
  }

  @override
  Future<bool> setNotifyValue(os.BmSetNotifyValueRequest r) async {
    trace.add('subscribe:${r.characteristicUuid.str}');
    descriptors.add(
      os.BmDescriptorData(
        remoteId: r.remoteId,
        primaryServiceUuid: r.primaryServiceUuid,
        serviceUuid: r.serviceUuid,
        characteristicUuid: r.characteristicUuid,
        instanceId: r.instanceId,
        descriptorUuid: os.Guid('2902'),
        value: [1, 0],
        success: true,
        errorCode: 0,
        errorString: '',
      ),
    );
    if (mode == 'subscribe-refused' ||
        refusedNotifications.contains(r.characteristicUuid.str128))
      throw StateError('synthetic subscription refusal');
    return true;
  }

  @override
  Future<bool> writeCharacteristic(os.BmWriteCharacteristicRequest r) async {
    final inner = p
        .parseFrame(Uint8List.fromList(r.value), profile: band)!
        .inner;
    final op = inner[2];
    trace.add('write:$op');
    if (mode == 'write-refused') throw StateError('synthetic write refusal');
    final observer = beforeWrite;
    if (observer != null) {
      await observer(r, inner);
    }
    written.add(
      os.BmCharacteristicData(
        remoteId: id,
        primaryServiceUuid: r.primaryServiceUuid,
        serviceUuid: r.serviceUuid,
        characteristicUuid: r.characteristicUuid,
        instanceId: r.instanceId,
        value: r.value,
        success: true,
        errorCode: 0,
        errorString: '',
      ),
    );
    if (replyToCommand case final reply?) {
      reply(r, inner);
      return true;
    }
    engine.debugAbsorbDecoded(
      p.Decoded('cmd_response', {
        'opcode': op,
        'req_seq': inner[1],
        'cmd_status': 1,
        if (op == p.Cmd.getClock)
          'clock_epoch': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      }),
    );
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final peripheral = Peripheral();
  setUpAll(() => os.FlutterBluePlusPlatform.instance = peripheral);
  setUp(() {
    peripheral.trace.clear();
    BleEngine.resetBandClaimForTest();
  });
  for (final mode in [
    'ready',
    'connect-refused',
    'discovery-refused',
    'no-service',
    'missing-data',
    'subscribe-refused',
  ]) {
    test(
      'COV-44 real GATT connect $mode retains single-owner and teardown boundaries',
      () async {
        final logs = <String>[];
        final states = <String>[];
        peripheral.mode = mode;
        final engine = BleEngine(
          onRecord: (_, _) async {},
          onState: (s) => states.add(s.connection),
          log: logs.add,
        );
        peripheral.engine = engine;
        try {
          final connected = await engine.connectToRemoteId(Peripheral.id.str);
          expect(connected, mode == 'ready');
          if (mode == 'ready') {
            expect(engine.isConnected, true);
            expect(states, containsAllInOrder(['connecting', 'connected']));
            expect(
              peripheral.trace.where((s) => s.startsWith('subscribe:')).length,
              3,
            );
            final before = peripheral.trace.where((s) => s == 'connect').length;
            expect(await engine.connectToRemoteId(Peripheral.id.str), true);
            expect(
              peripheral.trace.where((s) => s == 'connect').length,
              before,
            );
            await engine.setStrapName('Synthetic name');
            await engine.getStrapName();
            await engine.getHello();
            await engine.runAlarm();
            await engine.disableAlarm();
          } else {
            expect(engine.isConnected, false);
            expect(engine.holdsBandLink, false);
            expect(BleEngine.bandClaimed, false);
            expect(states.last, 'disconnected');
          }
        } finally {
          await engine.disconnect();
        }
        expect(BleEngine.bandClaimed, false);
        expect(engine.holdsBandLink, false);
      },
    );
  }
  for (final mode in [
    'name-scan',
    'service-scan',
    'empty-scan',
    'scan-refused',
  ]) {
    test(
      'COV-44 real scan $mode closes discovery and does not connect',
      () async {
        peripheral.mode = mode;
        final logs = <String>[];
        final engine = BleEngine(
          onRecord: (_, _) async {},
          onState: (_) {},
          log: logs.add,
        );
        peripheral.engine = engine;
        try {
          final found = await engine.scan(
            timeout: const Duration(milliseconds: 150),
          );
          expect(
            found?.remoteId.str,
            mode.endsWith('-scan') && mode != 'empty-scan'
                ? Peripheral.id.str
                : isNull,
          );
          expect(peripheral.trace, contains('scan'));
          expect(peripheral.trace, isNot(contains('connect')));
          expect(BleEngine.bandClaimed, false);
        } finally {
          await engine.disconnect();
        }
      },
    );
  }
  test(
    'COV-44 native notification chunks preserve valid HR and count CRC corruption',
    () async {
      peripheral.mode = 'ready';
      final logs = <String>[];
      final engine = BleEngine(
        onRecord: (_, _) async {},
        onState: (_) {},
        log: logs.add,
      );
      peripheral.engine = engine;
      void notify(List<int> bytes) {
        peripheral.incoming.add(
          os.BmCharacteristicData(
            remoteId: Peripheral.id,
            primaryServiceUuid: null,
            serviceUuid: os.Guid(p.GattProfile.gen4.service),
            characteristicUuid: os.Guid(p.GattProfile.gen4.data),
            instanceId: 0,
            value: bytes,
            success: true,
            errorCode: 0,
            errorString: '',
          ),
        );
      }

      try {
        expect(await engine.connectToRemoteId(Peripheral.id.str), true);
        final inner = Uint8List(20);
        inner[0] = 0x28;
        inner[8] = 88;
        inner[18] = 1;
        ByteData.sublistView(inner).setUint32(
          2,
          DateTime.now().millisecondsSinceEpoch ~/ 1000,
          Endian.little,
        );
        final frame = p.buildFrame(inner);
        notify(frame.sublist(0, 3));
        notify(frame.sublist(3));
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(engine.state.liveHr, 88);
        final bad = p.buildFrame(inner)
          ..[p.buildFrame(inner).length - 1] ^= 0xff;
        for (var i = 0; i < 25; i++) notify(bad);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(engine.offloadSnapshot['crc_failures_this_session'], 25);
        expect(engine.state.standardHrFallback, true);
        expect(
          logs.where((s) => s.contains('frame-corruption tripped')),
          hasLength(1),
        );
        await engine.disconnect();
        notify(frame);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(engine.isConnected, false);
        expect(BleEngine.bandClaimed, false);
      } finally {
        await engine.disconnect();
      }
    },
  );
}
