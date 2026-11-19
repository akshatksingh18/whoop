// An unsolicited legacy record stays recoverable through its regular receive route.
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
    await coverageStore('unsolicited-archive');
  });
  setUp(() async {
    await resetCoverageStore();
    BleEngine.resetBandClaimForTest();
    peripheral.trace.clear();
  });
  tearDownAll(LocalDb.close);

  for (final revision in [24, 199]) {
    test(
      'an unsolicited legacy record revision $revision archives without advancing history',
      () async {
        final written = Completer<void>();
        final engine = BleEngine(
          onRecord: (_, _) async =>
              fail('An undecodable record must not become a sample'),
          onState: (_) {},
          log: (_) {},
          onArchiveRecord: (record) async {
            await LocalDb.archiveRawRecord(record);
            written.complete();
          },
        );
        peripheral.engine = engine;
        try {
          expect(await engine.connectToRemoteId(Peripheral.id.str), isTrue);
          final db = await LocalDb.instance;
          final cursors = await db.query('sync_cursor');
          final before = peripheral.trace
              .where((line) => line.startsWith('write:'))
              .toList();
          final inner = Uint8List.fromList([
            protocol.PacketType.historicalData,
            revision,
            0,
            1,
            0,
            0,
            0,
          ]);
          engine.debugReceiveFrame(
            protocol.Frame(inner, true, true),
            role: 'events',
          );
          await written.future.timeout(const Duration(seconds: 2));

          final archive = (await db.query('raw_archive')).single;
          expect(
            archive['hex'],
            inner.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(),
          );
          expect(archive['reason'], 'undecodable_rec_v$revision');
          expect(archive['packet_type'], protocol.PacketType.historicalData);
          expect(await db.query('sync_cursor'), cursors);
          expect(await db.query('decoded_onehz'), isEmpty);
          expect(
            peripheral.trace.where((line) => line.startsWith('write:')),
            before,
          );
        } finally {
          await engine.disconnect();
        }
      },
    );
  }
}
