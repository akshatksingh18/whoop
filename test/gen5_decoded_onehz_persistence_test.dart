// Gen5 v18 samples must land in `decoded_onehz` via the preferred-sample
// fallback in LocalDb._decodeOneHzSample — they lack gen4 optics so R24
// decode fails, but they are honest 1 Hz substrate rows. R10-lite hr-only
// records must stay excluded.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ble/ble_engine.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/models.dart';
import 'package:openstrap_protocol/openstrap_protocol.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

String _bytesToHex(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List _buildR10LiteInner({required int ts, required int counter, required int hr}) {
  final inner = Uint8List(18);
  inner[0] = PacketType.historicalData;
  inner[1] = Record.r10;
  inner.buffer.asByteData().setUint32(3, counter, Endian.little);
  inner.buffer.asByteData().setUint32(7, ts, Endian.little);
  inner[17] = hr;
  return inner;
}

/// Synthetic gen5 v18 lenient inner: valid unix@7 + HR, gravity fails gate.
Uint8List _buildGen5V18LenientInner({
  required int unix,
  required int counter,
  required int hr,
  List<int> rrMs = const [],
}) {
  final inner = Uint8List(112);
  inner[0] = PacketType.historicalData;
  inner[1] = 18;
  inner[2] = 0x80;
  inner[3] = counter & 0xff;
  inner[4] = (counter >> 8) & 0xff;
  inner[5] = (counter >> 16) & 0xff;
  inner[6] = (counter >> 24) & 0xff;
  inner.buffer.asByteData().setUint32(7, unix, Endian.little);
  inner[14] = hr;
  inner[15] = rrMs.length.clamp(0, 4).toInt();
  final view = inner.buffer.asByteData();
  for (var i = 0; i < rrMs.length && i < 4; i++) {
    view.setInt16(16 + 2 * i, rrMs[i], Endian.little);
  }
  view.setFloat32(33, 0.5, Endian.little);
  view.setFloat32(37, 0.05, Endian.little);
  view.setFloat32(41, 0.05, Endian.little);
  view.setFloat32(45, 0.05, Endian.little);
  return inner;
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.dbName = 'openstrap_gen5_onehz_test.db';
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  tearDownAll(() async {
    await LocalDb.close();
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  group('gen5 → decoded_onehz persistence', () {
  test('gen5 v18-shaped sample persists via preferred fallback (+ RR)', () async {
    // Real fixture inner — same bytes as gen5_sample_mapping_test.dart.
    final frameHex =
        'aa01740001003fb12f1280733d8401b69f266a66460066025a0265020000000'
        '000007b0a8d656463ff0012163cf6a439bf2924fd3ed763fe3e3200aa000000'
        '000000000000f7000901f10b0007010c020c000000000000000000000000000'
        '00000000000000000000100656f1e1e0000009d61a7c00000003e862817';
    final frame = Uint8List.fromList(
      List.generate(frameHex.length ~/ 2, (i) {
        return int.parse(frameHex.substring(i * 2, i * 2 + 2), radix: 16);
      }),
    );
    final parsed = parseFrame(frame, profile: BandProfile.gen5)!;
    final inner = parsed.inner;
    final sample = sampleFromGen5Historical(parseGen5Historical(inner));
    expect(sample, isNotNull);

    const recTs = 1780916150;
    final raw = RawRecord(
      counter: sample!.counter,
      packetType: PacketType.historicalData,
      hex: _bytesToHex(inner),
      capturedAt: recTs * 1000,
      recTs: recTs,
    );

    await LocalDb.commitSyncBatch([raw], [sample]);

    final db = await LocalDb.instance;
    final rows = await db.query(
      'decoded_onehz',
      where: 'rec_ts = ?',
      whereArgs: [recTs],
    );
    expect(rows.length, 1);
    expect(rows.first['hr'], 102);
    expect(rows.first['counter'], sample.counter);

    final rr = await db.query(
      'decoded_rr',
      where: 'rec_ts = ?',
      whereArgs: [recTs],
    );
    expect(rr.length, 2);
    expect([for (final r in rr) r['rr_ms']], containsAll([602, 613]));
  });

  // NOTE what this pins, and what it does NOT. `decoded_onehz.ax/ay/az` are
  // REAL NOT NULL, so absent gravity has to be STORED as 0 — that is a schema
  // constraint, not a claim about the wrist. Exact (0,0,0) is therefore the
  // ABSENT marker (no real gravity vector has zero magnitude, and every decoder
  // that emits one gates on magSq >= 0.25); `Substrate.accelPresentAt` is what
  // stops it being read back as a measurement. See
  // substrate_accel_absence_test.dart — without that, a night of these scores
  // as perfect immobility and fabricates a fully-staged sleep window.
  test('v18 sample with null accel still persists (stored as 0)', () async {
    const unix = 1785801600;
    const counter = 42;
    final inner = _buildGen5V18LenientInner(unix: unix, counter: counter, hr: 72);
    // Built directly rather than decoded: what this test pins is the
    // PERSISTENCE of a null-accel sample, independent of which decoder produced
    // it. Protocol emits exactly this shape for a v18 whose gravity vector
    // fails the magnitude gate — the rest of the second is kept.
    final sample = Sample(tsEpoch: unix, counter: counter, hr: 72);
    expect(sample.ax, isNull);

    final raw = RawRecord(
      counter: counter,
      packetType: PacketType.historicalData,
      hex: _bytesToHex(inner),
      capturedAt: unix * 1000,
      recTs: unix,
    );
    await LocalDb.commitSyncBatch([raw], [sample]);

    final db = await LocalDb.instance;
    final rows = await db.query(
      'decoded_onehz',
      where: 'rec_ts = ?',
      whereArgs: [unix],
    );
    expect(rows.length, 1);
    expect(rows.first['hr'], 72);
    expect(rows.first['ax'], 0);
    expect(rows.first['ay'], 0);
    expect(rows.first['az'], 0);
  });

  test('R10-lite + complete preferred → no decoded_onehz row', () async {
    const ts = 1780000100;
    const counter = 99;
    final inner = _buildR10LiteInner(ts: ts, counter: counter, hr: 65);
    final preferred = Sample(
      tsEpoch: ts,
      counter: counter,
      hr: 65,
      ax: 0.1,
      ay: -0.2,
      az: 0.95,
      spo2RedRaw: 100,
      spo2IrRaw: 200,
      skinTempRaw: 300,
    );
    expect(preferred.hasDecodedOneHz, isTrue);
    final raw = RawRecord(
      counter: counter,
      packetType: PacketType.historicalData,
      hex: _bytesToHex(inner),
      capturedAt: ts * 1000,
      recTs: ts,
    );

    await LocalDb.commitSyncBatch([raw], [preferred]);

    final db = await LocalDb.instance;
    final rows = await db.query(
      'decoded_onehz',
      where: 'rec_ts = ?',
      whereArgs: [ts],
    );
    expect(rows, isEmpty);
  });

  test('full gen4 R24 sample still persists', () async {
    const ts = 1780000200;
    const counter = 5001;
    final sample = Sample(
      tsEpoch: ts,
      counter: counter,
      hr: 70,
      rrIntervalsMs: [800],
      ax: 0.1,
      ay: -0.2,
      az: 0.95,
      spo2RedRaw: 100,
      spo2IrRaw: 200,
      skinTempRaw: 300,
    );
    // Minimal non-R10 historical hex — R24 decode won't match, but preferred
    // has full gen4 optics so _decodeOneHzSample returns it immediately.
    final raw = RawRecord(
      counter: counter,
      packetType: PacketType.historicalData,
      hex: '2f18' '00' * 20,
      capturedAt: ts * 1000,
      recTs: ts,
    );

    await LocalDb.commitSyncBatch([raw], [sample]);

    final db = await LocalDb.instance;
    final rows = await db.query(
      'decoded_onehz',
      where: 'rec_ts = ?',
      whereArgs: [ts],
    );
    expect(rows.length, 1);
    expect(rows.first['hr'], 70);
    expect(rows.first['spo2_red_raw'], 100);
  });
  });

  // CodeRabbit: the R10-lite case asserted only ABSENCE from `decoded_onehz`,
  // which would also pass if the record were dropped entirely. Retention in
  // `samples` is the other half of that contract.
  test('an R10-lite record is excluded from decoded_onehz but RETAINED in samples',
      () async {
    const ts = 1780000300;
    const counter = 4242;
    final inner = _buildR10LiteInner(ts: ts, counter: counter, hr: 71);
    final sample = Sample(tsEpoch: ts, counter: counter, hr: 71);
    final raw = RawRecord(
      counter: counter,
      packetType: PacketType.historicalData,
      hex: _bytesToHex(inner),
      capturedAt: ts * 1000,
      recTs: ts,
    );
    await LocalDb.commitSyncBatch([raw], [sample]);

    final db = await LocalDb.instance;
    expect(
      await db.query('decoded_onehz', where: 'rec_ts = ?', whereArgs: [ts]),
      isEmpty,
      reason: 'hr-only R10-lite is not 1 Hz substrate',
    );
    expect(
      await db.query('samples', where: 'counter = ?', whereArgs: [counter]),
      hasLength(1),
      reason: 'excluded from the substrate is NOT the same as discarded',
    );
  });

  // Protects the hex-conversion fallback in `LocalDb._decodeOneHzSample`: when
  // the raw hex cannot be parsed, a timestamp-valid preferred Sample must still
  // reach `decoded_onehz` rather than the record being lost.
  test('unparseable raw hex still persists a timestamp-valid preferred Sample',
      () async {
    const ts = 1780000400;
    const counter = 5150;
    final raw = RawRecord(
      counter: counter,
      packetType: PacketType.historicalData,
      hex: 'zzzz-not-hex',
      capturedAt: ts * 1000,
      recTs: ts,
    );
    final sample = Sample(
      tsEpoch: ts,
      counter: counter,
      hr: 66,
      rrIntervalsMs: const [910],
    );
    await LocalDb.commitSyncBatch([raw], [sample]);

    final db = await LocalDb.instance;
    final rows =
        await db.query('decoded_onehz', where: 'rec_ts = ?', whereArgs: [ts]);
    expect(rows, hasLength(1));
    expect(rows.first['hr'], 66);
  });
}
