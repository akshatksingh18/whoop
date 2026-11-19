// The subscribed legacy link retains undecodable bytes while its cursor opens.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart'
    as os;
import 'package:whoop_companion/ble/ble_engine.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_protocol/whoop_protocol.dart' as protocol;

import 'coverage_gatt_connection_test.dart' show Peripheral;
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final peripheral = Peripheral();
  setUpAll(() async {
    os.FlutterBluePlusPlatform.instance = peripheral;
    await coverageStore('legacy-early-archive-owner');
  });
  setUp(() async {
    await resetCoverageStore();
    BleEngine.resetBandClaimForTest();
    peripheral.trace.clear();
  });
  tearDown(BleEngine.resetBandClaimForTest);
  tearDownAll(LocalDb.close);

  for (final revision in [24, 199]) {
    test(
      'legacy historical revision $revision is recoverable before INIT',
      () async {
        final reading = Completer<void>();
        final release = Completer<int?>();
        final archived = Completer<void>();
        const frontier = 1617710200;
        await LocalDb.setCursor('rec_ts_hw', '$frontier');
        final db = await LocalDb.instance;
        final cursors = await db.query('sync_cursor');
        final engine = BleEngine(
          cursorReader: (name) async {
            if (name == 'rec_ts_hw') {
              reading.complete();
              return release.future;
            }
            return LocalDb.getCursorInt(name);
          },
          onRecord: (_, _) async => fail('Undecodable history must stay raw'),
          onState: (_) {},
          onArchiveRecord: (record) async {
            await LocalDb.archiveRawRecord(record);
            archived.complete();
          },
        );
        peripheral.engine = engine;
        final connected = engine.connectToRemoteId(
          Peripheral.id.str,
          generationHint: 'gen4',
        );
        try {
          await reading.future.timeout(const Duration(seconds: 3));
          final before = List<String>.of(peripheral.trace);
          final inner = Uint8List.fromList([
            protocol.PacketType.historicalData,
            revision,
            0,
            1,
            0,
            0,
            0,
          ]);
          const g = protocol.GattProfile.gen4;
          peripheral.incoming.add(
            os.BmCharacteristicData(
              remoteId: Peripheral.id,
              primaryServiceUuid: null,
              serviceUuid: os.Guid(g.service),
              characteristicUuid: os.Guid(g.events),
              instanceId: 0,
              value: protocol.buildFrame(inner),
              success: true,
              errorCode: 0,
              errorString: '',
            ),
          );
          await archived.future.timeout(const Duration(seconds: 3));
          final row = (await db.query('raw_archive')).single;
          expect(
            row['hex'],
            // The on-air body includes CRC-protected alignment padding.
            [
              ...inner,
              0,
            ].map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
          );
          expect(row['reason'], 'undecodable_rec_v$revision');
          expect(await db.query('decoded_onehz'), isEmpty);
          expect(await db.query('sync_cursor'), cursors);
          expect(peripheral.trace, before);
          release.complete(frontier);
          expect(await connected, isTrue);
          expect(await db.query('raw_archive'), [row]);
          expect(await db.query('sync_cursor'), cursors);
        } finally {
          if (!release.isCompleted) release.complete(frontier);
          await connected;
          await engine.disconnect();
        }
      },
    );
  }
}
