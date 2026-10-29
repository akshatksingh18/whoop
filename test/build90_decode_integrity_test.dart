import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/derive_prepare.dart';
import 'package:whoop_companion/compute/substrate.dart';
import 'package:whoop_companion/data/csv_export.dart';
import 'package:whoop_protocol/whoop_protocol.dart' as proto;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Uint8List record(int version, int count) {
  final b = Uint8List(89)..[0] = proto.PacketType.historicalData;
  b[1] = version;
  final v = ByteData.sublistView(b);
  v.setUint32(3, 1, Endian.little);
  v.setUint32(7, 1700000000, Endian.little);
  b[version == 18 ? 14 : 17] = 60;
  b[18] = count;
  for (var i = 0; i < count; i++) {
    v.setInt16(19 + i * 2, 800 + i, Endian.little);
  }
  v.setFloat32(44, 1, Endian.little);
  v.setUint16(29, 1111, Endian.little);
  v.setUint16(64, 2222, Endian.little);
  v.setUint16(66, 3333, Endian.little);
  v.setUint16(68, 4444, Endian.little);
  v.setUint16(70, 5555, Endian.little);
  return b;
}

String hex(Uint8List b) =>
    b.map((v) => v.toRadixString(16).padLeft(2, '0')).join();

void main() {
  test('historical counts above four never read later sensor bytes as RR', () {
    for (final version in [12, 24]) {
      expect(proto.parseR24(record(version, 4))!.rrIntervalsMs, hasLength(4));
      for (final count in [5, 8]) {
        expect(proto.parseR24(record(version, count))!.rrIntervalsMs, isEmpty);
      }
    }
  });
  test('R10 retains its independent eight-interval layout', () {
    final b = record(10, 8);
    expect(proto.realtimeRr(hex(b))!.rrMs, hasLength(8));
  });
  test(
    'unknown optical values are NULL; confirmed fields retain raw values',
    () {
      final unknown = proto.parseR24(record(18, 4))!;
      expect([
        unknown.ppgGreen,
        unknown.ppgRedIr,
        unknown.skinContact,
        unknown.spo2RedRaw,
        unknown.spo2IrRaw,
        unknown.skinTempRaw,
        unknown.ambientRaw,
      ], everyElement(isNull));
      final known = proto.parseR24(record(24, 4))!;
      expect(known.ppgGreen, 1111);
      expect(known.spo2RedRaw, 2222);
      expect(known.ambientRaw, 5555);
      final sub = decodeSubstrate([hex(record(18, 4))]);
      expect(sub.skinTemp, [null]);
      expect(Substrate.fromJson(sub.toJson()).skinTemp, [null]);
      expect(sub.hr, [60]);
    },
  );
  test('legacy decoded sentinel zeros and missing channels stay absent', () {
    final sub = substrateFromDecodedPage([
      {
        'rec_ts': 1700000000,
        'hr': 60,
        'ax': 0.0,
        'ay': 0.0,
        'az': 1.0,
        'spo2_red_raw': 0,
        'spo2_ir_raw': 0,
        'skin_temp_raw': 0,
      },
    ], []);
    expect(sub.spo2Red, [null]);
    expect(sub.spo2Ir, [null]);
    expect(sub.skinTemp, [null]);
    expect(sub.skinContact, [null]);
  });
  test(
    'CSV metric history excludes legacy oxygen but preserves other rows',
    () async {
      sqfliteFfiInit();
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      try {
        await db.execute(
          'CREATE TABLE v_metric (date TEXT, key TEXT, value REAL)',
        );
        for (final key in ['spo2', 'odi_per_hour', 'rmssd', 'strain']) {
          await db.insert('v_metric', {
            'date': '2025-01-01',
            'key': key,
            'value': 1.0,
          });
        }
        final sql = kCsvExportSets.singleWhere((s) => s.name == 'metrics').sql;
        expect((await db.rawQuery(sql)).map((r) => r['key']), [
          'rmssd',
          'strain',
        ]);
      } finally {
        await db.close();
      }
    },
  );
}
