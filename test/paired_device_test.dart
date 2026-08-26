// PairedDevice — the persisted pairing record, including the generation the
// connect route is chosen by.
//
// What this stands in for: the generation is a DEVICE property that steers
// the bond position of every reconnect. Persist it wrong and a gen5 band runs
// its bond in the wrong place (or a new band inherits the forgotten band's
// identity), so the save/load/clear semantics get pinned directly:
// same-device saves without a generation must preserve the stored one,
// a DIFFERENT remoteId must never inherit it, and a corrupted stored value
// must sanitize to null rather than steer the route.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/sync/paired_device.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // `PairedDevice` is table-first now (the `device` row, schema 49) with the
  // prefs pair as the mirror that heals a rebuilt database, so both halves
  // have to be real here — mocking prefs alone would exercise neither the
  // authoritative read nor the COALESCE that preserves a known generation.
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.dbName = 'openstrap_paired_device_test.db';
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  tearDownAll(() async {
    await LocalDb.close();
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // Both copies, or one test's pairing steers the next one's.
    await LocalDb.deleteDevice();
  });

  test('save/load round-trips remoteId, serial and generation', () async {
    await PairedDevice.save(
      'AA:BB:CC:DD:EE:FF',
      '5AG0000001',
      generation: 'gen5',
    );
    final p = await PairedDevice.load();
    expect(p!.remoteId, 'AA:BB:CC:DD:EE:FF');
    expect(p.serial, '5AG0000001');
    expect(p.generation, 'gen5');
  });

  test(
    'a same-device save without a generation preserves the stored one',
    () async {
      await PairedDevice.save(
        'AA:BB:CC:DD:EE:FF',
        '5AG0000001',
        generation: 'gen5',
      );
      // The serial-heal save site only carries the serial.
      await PairedDevice.save('AA:BB:CC:DD:EE:FF', '5AG0000002');
      final p = await PairedDevice.load();
      expect(p!.serial, '5AG0000002');
      expect(
        p.generation,
        'gen5',
        reason: 'not knowing the generation is not evidence it changed',
      );
    },
  );

  test(
    'pairing a DIFFERENT remoteId without a generation drops the old one',
    () async {
      await PairedDevice.save(
        'AA:BB:CC:DD:EE:FF',
        '5AG0000001',
        generation: 'gen4',
      );
      await PairedDevice.save('11:22:33:44:55:66', '5AG0000009');
      final p = await PairedDevice.load();
      expect(p!.remoteId, '11:22:33:44:55:66');
      expect(
        p.generation,
        isNull,
        reason:
            'a new band must never inherit the forgotten band\'s '
            'generation — its first connect probes gen5-first instead',
      );
    },
  );

  test(
    'a garbled generation is refused on save and sanitized on load',
    () async {
      await PairedDevice.save('AA:BB:CC:DD:EE:FF', null, generation: 'gen6');
      expect((await PairedDevice.load())!.generation, isNull);

      // A corrupted value written by some other path never steers the route.
      SharedPreferences.setMockInitialValues({
        'paired_remote_id': 'AA:BB:CC:DD:EE:FF',
        'paired_generation': 'banana',
      });
      expect((await PairedDevice.load())!.generation, isNull);
    },
  );

  test('clear removes the whole record, generation included', () async {
    await PairedDevice.save(
      'AA:BB:CC:DD:EE:FF',
      '5AG0000001',
      generation: 'gen5',
    );
    await PairedDevice.clear();
    expect(await PairedDevice.load(), isNull);
    // Re-pairing after a clear starts with no generation at all.
    await PairedDevice.save('AA:BB:CC:DD:EE:FF', null);
    expect((await PairedDevice.load())!.generation, isNull);
  });

  test('junk serials still sanitize to null on load', () async {
    SharedPreferences.setMockInitialValues({
      'paired_remote_id': 'AA:BB:CC:DD:EE:FF',
      'paired_serial': '?*',
    });
    expect((await PairedDevice.load())!.serial, isNull);
  });
}
