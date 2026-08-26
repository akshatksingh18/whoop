// The standard Bluetooth heart-rate sensor path: 0x2A37 in, `decoded_onehz` /
// `decoded_rr` out.
//
// THE DECODE ITSELF (`parseHeartRateMeasurement`) IS NOT PINNED HERE — it is
// pure protocol and its own tests live with it in the protocol package. This
// file is the WRITE half: given already-decoded bytes, do they land in the
// substrate correctly attributed. Still EXPERIMENTAL (ASSUMPTIONS R6) —
// nobody on this project owns a strap and `flutter_blue_plus` has no
// simulator path, so this proves the write is correct, not that any real
// strap sends these exact bytes.

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:openstrap_edge/ble/adapters/_registry.dart';
import 'package:openstrap_edge/ble/hrs_link.dart';
import 'package:openstrap_edge/data/db.dart';

/// Frames as the three common flag shapes put them on the wire.
///
/// The RR-Interval flag (bit 4) is OPTIONAL in the spec, and [bpmOnly] is the
/// case that matters most: plenty of optical armbands never set it, and the
/// parser has to degrade to "HR, no beats" rather than assume beats are there.
const List<int> kBpmOnly = <int>[0x00, 61]; // flags 0x00 — RR bit CLEAR
const List<int> kBpmOnlyWithContact = <int>[0x06, 61]; // contact reported
const List<int> kHrWithTwoRr = <int>[
  0x16, // uint8 HR + contact supported/detected + RR present
  120,
  0xF4, 0x01, // 500 ticks = 488 ms
  0x00, 0x02, // 512 ticks = 500 ms
];

void main() {
  group('substrate write', () {
    const deviceId = 'hrs-0a1b2c3d';

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      await LocalDb.close();
      LocalDb.dbName = 'hrs_link_test.db';
      final dir = await databaseFactory.getDatabasesPath();
      await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
    });

    tearDown(() async => LocalDb.close());

    test('HR and beats land in the real substrate, attributed', () async {
      await HrsLink.instance.ingestForTest(deviceId, const [
        (1_800_000_000, kHrWithTwoRr),
        (1_800_000_001, kBpmOnly),
      ]);

      final db = await LocalDb.instance;
      final onehz = await db.query('decoded_onehz', orderBy: 'ts_ms');
      expect(onehz, hasLength(2));
      expect(onehz.first['device_id'], deviceId);
      expect(onehz.first['device_id'], isNot(LocalDb.kPrimaryDeviceId));
      expect(onehz.first['ts_ms'], 1_800_000_000 * 1000);
      expect(onehz.first['rec_ts'], 1_800_000_000);
      expect(onehz.first['hr'], 120);
      expect(onehz.first['source'], 'ble_hrs');
      expect(onehz.first['device_family'], 'ble_hrs');
      // A strap has no accelerometer, no optical block and no thermistor.
      // Absent is NULL — never a measurement of zero.
      for (final c in ['ax', 'ay', 'az', 'spo2_red_raw', 'skin_temp_raw']) {
        expect(onehz.first[c], isNull, reason: c);
      }
      // The RR-bit-clear second is still a heart rate.
      expect(onehz.last['hr'], 61);

      final rr = await db.query('decoded_rr', orderBy: 'ts_ms, beat_index');
      expect(rr, hasLength(2), reason: 'only the first second carried beats');
      expect(rr.map((r) => r['rr_ms']), [488, 500]);
      expect(rr.map((r) => r['beat_index']), [0, 1]);
      expect(rr.first['device_id'], deviceId);
      expect(rr.first['source'], 'ble_hrs');
      // THE LOAD-BEARING ONE. `beat_ts_ms` means "where the beat actually
      // was"; this source has no clock, so we do not know. An arrival anchor
      // written there would be a measured claim we cannot make.
      expect(rr.first['beat_ts_ms'], isNull);
      expect(rr.first['rr_ts_ms'], 1_800_000_000 * 1000,
          reason: 'the arrival second, which is all the anchor there is');
    });

    test('two notifications in one second do not evict each other', () async {
      // The failure this prevents: writing the second twice restarts
      // `beat_index` at 0 and REPLACE deletes the beats already stored.
      await HrsLink.instance.ingestForTest(deviceId, const [
        (1_800_000_000, kHrWithTwoRr),
        (1_800_000_000, kHrWithTwoRr),
      ]);
      final db = await LocalDb.instance;
      expect(await db.query('decoded_onehz'), hasLength(1));
      final rr = await db.query('decoded_rr', orderBy: 'beat_index');
      expect(rr.map((r) => r['beat_index']), [0, 1, 2, 3]);
    });

    test('an off-chest reading is refused, not stored as a low HR', () async {
      await HrsLink.instance.ingestForTest(deviceId, const [
        (1_800_000_000, <int>[0x04, 45]), // contact bits 0b10 = no contact
      ]);
      final db = await LocalDb.instance;
      expect(await db.query('decoded_onehz'), isEmpty);
    });

    test('the band-only readers cannot see a strap row', () async {
      await HrsLink.instance.ingestForTest(deviceId, const [
        (1_800_000_000, kHrWithTwoRr),
      ]);
      final db = await LocalDb.instance;
      final banded = await db.rawQuery(
        'SELECT COUNT(*) c FROM decoded_onehz WHERE source IS NULL',
      );
      expect(banded.first['c'], 0,
          reason: 'every derive/export read filters `source IS NULL`');
    });

    test('the primary device id is refused outright', () async {
      // `''` is the primary band, permanently (ASSUMPTIONS A1). A sensor
      // writing under it would interleave with the band's own seconds in a
      // REPLACE-keyed table, unrecoverably.
      await LocalDb.upsertDevice(
        adapterId: kBleHrs.id,
        remoteId: 'AA:BB:CC:DD:EE:FF',
      );
      expect(await HrsLink.instance.arm(), isFalse);
    });

    test('nothing paired means nothing armed', () async {
      expect(await HrsLink.instance.arm(), isFalse);
      expect(await HrsLink.pairedSensorRow(), isNull);
    });

    test('two arms in flight are ONE arm', () async {
      // Every caller fires this `unawaited`, and the body awaits a database
      // read, a 12 s connect and discovery before it publishes anything. A
      // second call used to walk straight past the `_armed` check and overwrite
      // the first one's `_device`, `_link`, `_runSub` and `_flushTimer` — the
      // originals then ran on with nothing holding them. Same future, one
      // attempt.
      final a = HrsLink.instance.arm();
      final b = HrsLink.instance.arm();
      expect(identical(a, b), isTrue);
      expect(await a, isFalse);
      expect(await b, isFalse);
      // And the memo clears, so a later arm is a real attempt again.
      expect(identical(HrsLink.instance.arm(), a), isFalse);
    });
  });
}
