// The standard Bluetooth heart-rate sensor path: 0x2A37 in, `decoded_onehz` /
// `decoded_rr` out.
//
// NOTHING HERE HAS MET HARDWARE. Nobody on this project owns a strap and
// `flutter_blue_plus` has no simulator path, so the fixtures below are built
// from the Bluetooth SIG's Heart Rate Service 1.0 characteristic layout, not
// captured off a device. They pin the decode and the write; they do not prove
// any real strap behaves this way. This path ships EXPERIMENTAL (ASSUMPTIONS
// R6) until he owns one.

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
  // ── the parser ────────────────────────────────────────────────────────────
  test('uint8 HR, no RR', () {
    final s = parseHeartRateMeasurement([0x00, 72])!;
    expect(s.hr, 72);
    expect(s.rrMs, isEmpty);
    expect(s.contact, isNull); // contact not supported → absent, not "false"
  });

  test('the RR bit CLEAR is a strap with no beats, not a strap with zero', () {
    final s = parseHeartRateMeasurement(kBpmOnly)!;
    expect(s.hr, 61);
    expect(s.rrMs, isEmpty);
    expect(parseHeartRateMeasurement(kBpmOnlyWithContact)!.contact, isTrue);
  });

  test('uint16 HR reads little-endian', () {
    final s = parseHeartRateMeasurement([0x01, 0x2C, 0x01])!; // 300
    expect(s.hr, 300);
  });

  test('RR intervals convert from 1/1024 s to ms', () {
    // 1024 ticks = 1000 ms; 512 = 500 ms.
    final s = parseHeartRateMeasurement([0x10, 60, 0x00, 0x04, 0x00, 0x02])!;
    expect(s.rrMs, [1000, 500]);
  });

  test('energy-expended field is skipped, not read as an RR interval', () {
    // flags 0x18 = RR present + energy expended present. The 2-byte energy
    // field sits BETWEEN hr and the RR list; reading it as RR is the classic
    // bug and would yield a bogus first interval.
    final s = parseHeartRateMeasurement([
      0x18, 60, //
      0xE8, 0x03, // energy expended = 1000 kJ
      0x00, 0x04, // RR = 1024 ticks = 1000 ms
    ])!;
    expect(s.rrMs, [1000]);
  });

  test('contact bits: reported false is distinguishable from unsupported', () {
    expect(parseHeartRateMeasurement([0x04, 60])!.contact, isFalse); // 0b10
    expect(parseHeartRateMeasurement([0x06, 60])!.contact, isTrue); // 0b11
    expect(parseHeartRateMeasurement([0x02, 60])!.contact, isNull); // 0b01
  });

  test('implausible beat intervals are dropped, not clamped', () {
    // 8 ticks ≈ 8 ms and 4096 ticks = 4 s: neither is a beat. A clamped value
    // would be a fabricated one.
    final s = parseHeartRateMeasurement([
      0x10, 60, //
      0x08, 0x00, // 8 ms
      0x00, 0x10, // 4000 ms
      0x00, 0x04, // 1000 ms — the only real one
    ])!;
    expect(s.rrMs, [1000]);
  });

  test('a searching sensor reporting 0 bpm is not a measurement', () {
    expect(parseHeartRateMeasurement([0x00, 0]), isNull);
  });

  test('truncated values are dropped rather than patched up', () {
    expect(parseHeartRateMeasurement([0x00]), isNull);
    expect(parseHeartRateMeasurement([]), isNull);
    expect(parseHeartRateMeasurement([0x01, 0x48]), isNull); // uint16, 1 byte
  });

  test('a trailing odd byte does not read past the buffer', () {
    final s = parseHeartRateMeasurement([0x10, 60, 0x00, 0x04, 0x7F])!;
    expect(s.rrMs, [1000]);
  });

  // ── the write ─────────────────────────────────────────────────────────────
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
  });
}
