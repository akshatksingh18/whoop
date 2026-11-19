// SQLite may be temporarily unavailable when the native wake arrives.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart'
    as os;
import 'package:whoop_companion/ble/ios_ble_restore.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/sync/background_sync.dart';
import 'package:whoop_companion/sync/band_ownership.dart';
import 'package:whoop_companion/sync/file_log.dart';
import 'package:whoop_companion/sync/headless_gate.dart';
import 'package:whoop_companion/sync/paired_device.dart';

import 'coverage_gatt_connection_test.dart' show Peripheral;
import 'support/coverage_store.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final peripheral = Peripheral()..mode = 'connect-refused';
  const channel = MethodChannel('whoop/ble_restore');
  final replies = <String>[];
  setUpAll(() async {
    os.FlutterBluePlusPlatform.instance = peripheral;
    await coverageStore('headless-pairing-read-refusal');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      replies.add(call.method);
      return null;
    });
  });
  setUp(() async {
    await resetCoverageStore();
    BandOwnership.resetForTest();
    IosBleRestore.foregroundActive = false;
    IosBleRestore.onWake = null;
    replies.clear();
    peripheral.trace.clear();
  });
  tearDownAll(() async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    await LocalDb.close();
  });

  for (final restore in [false, true]) {
    test(
      'a refused pairing read releases the headless lease: restore=$restore',
      () async {
        const frontier = 1617711234;
        await LocalDb.setCursor('rec_ts_hw', '$frontier');
        await PairedDevice.save(
          Peripheral.id.str,
          'Authored band',
          generation: 'gen4',
        );
        final db = await LocalDb.instance;
        final identity = await db.query('device');
        final cursors = await db.query('sync_cursor');
        Future<void> wake() async {
          if (restore) {
            await IosBleRestore.handleCall(const MethodCall('wake'));
          } else {
            expect(await runHeadlessSync(wake: 'authored_refresh'), isTrue);
          }
          expect(BandOwnership.owner, isNull);
          expect(HeadlessSyncGate.busy, isFalse);
        }

        final marker = 'Authored pairing read start restore=$restore';
        await FileLog.write(marker);
        await db.execute('ALTER TABLE device RENAME TO authored_held_device');
        try {
          await wake();
          expect(peripheral.trace, isEmpty);
          expect(await db.query('authored_held_device'), identity);
          expect(await db.query('sync_cursor'), cursors);
          expect(replies, restore ? ['syncDone'] : isEmpty);
          await FileLog.write('Authored pairing read end');
          final log = await File((await FileLog.path())!).readAsString();
          final wakeLog = log.split(marker).last;
          expect(wakeLog, contains('[bgsync] error (ignored):'));
          expect(wakeLog, contains('no such table: device'));
        } finally {
          await db.execute('ALTER TABLE authored_held_device RENAME TO device');
        }

        expect((await PairedDevice.load())?.remoteId, Peripheral.id.str);
        await wake();
        expect(
          peripheral.trace.where((event) => event == 'connect'),
          hasLength(1),
        );
        expect(await db.query('device'), identity);
        expect(await db.query('sync_cursor'), cursors);
        expect(await LocalDb.getCursorInt('rec_ts_hw'), frontier);
        expect(await db.query('decoded_onehz'), isEmpty);
        expect(await LocalDb.computeJobs(), isEmpty);
        expect(replies, restore ? ['syncDone', 'syncDone'] : isEmpty);
      },
    );
  }
}
