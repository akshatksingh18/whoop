// Authored event-envelope/body contracts and persistence/backfill checks.
// Original captured events and physical charge correlations remain local-only.
// Synthetic ratios test byte placement, not battery calibration or units.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_protocol/whoop_protocol.dart' as proto;

proto.EventInfo _event(String hex) => proto.parseEvent(proto.hexToBytes(hex))!;

Uint8List _body(String hex) => Uint8List.fromList(proto.hexToBytes(hex));

final _batteryEpoch = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 60;

String _envelope(int id, Uint8List body, int ts) {
  final inner = Uint8List(12 + body.length);
  final v = ByteData.sublistView(inner);
  inner[0] = 0x30;
  v.setUint16(2, id, Endian.little);
  v.setUint32(4, ts, Endian.little);
  v.setUint16(10, body.length, Endian.little);
  inner.setRange(12, inner.length, body);
  return inner.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
}

Uint8List _extended(int revision, int units) {
  final body = Uint8List(revision == 1 ? 28 : 12);
  body[0] = revision;
  final v = ByteData.sublistView(body);
  if (revision == 1) v.setUint16(9, 77, Endian.little); // wrong-offset trap
  v.setUint16(revision == 1 ? 11 : 9, units, Endian.little);
  return body;
}

Uint8List _level(int tenths, int millivolts, bool charging) {
  final body = Uint8List(20);
  body[0] = 2;
  final v = ByteData.sublistView(body);
  v.setUint32(1, tenths, Endian.little);
  v.setUint32(5, millivolts, Endian.little);
  body[9] = charging ? 1 : 0;
  return body;
}

final _mgExt = _envelope(63, _extended(3, 1920), _batteryEpoch);
final _mgLevel = _envelope(3, _level(1000, 4200, false), _batteryEpoch);
final _mgLevelCharging = _envelope(
  3,
  _level(750, 4100, true),
  _batteryEpoch + 20,
);
final _mgChargingOn = _envelope(7, Uint8List(0), _batteryEpoch + 10);
final _gen4Ext = _envelope(63, _extended(1, 800), _batteryEpoch);
final _gen4Level = _envelope(3, _level(500, 3800, false), _batteryEpoch);

void main() {
  group('extendedChargeUnits', () {
    test('rev 3 (gen5/MG) reads the counter at [9]', () {
      // 0x077b = 1920, against the 100.0% the strap reported in the same second.
      expect(LocalDb.extendedChargeUnits(_event(_mgExt).body), 1920);
    });

    test('authored counters are read independently across the field range', () {
      for (final (units, pct) in [
        (1920, 100.0),
        (960, 50.0),
        (480, 25.0),
        (240, 12.5),
      ]) {
        expect(LocalDb.extendedChargeUnits(_extended(3, units)), units);
        expect(LocalDb.extendedChargeUnits(_extended(3, units))! / pct, 19.2);
      }
    });

    test('rev 1 (gen4) reads the counter at [11], not at [9]', () {
      // [9] holds 48 on this body. Reading the gen5 offset on a gen4 body is
      // exactly why the offset is chosen by revision byte and never by length.
      expect(LocalDb.extendedChargeUnits(_event(_gen4Ext).body), 800);
    });

    test('an unknown revision decodes to nothing rather than to a guess', () {
      expect(LocalDb.extendedChargeUnits(_extended(9, 100)), isNull);
    });

    test('a truncated body decodes to nothing', () {
      expect(
        LocalDb.extendedChargeUnits(Uint8List.fromList([3, 0, 0])),
        isNull,
      );
      expect(LocalDb.extendedChargeUnits(Uint8List(0)), isNull);
    });

    test('zero is absence, never a flat pack', () {
      expect(
        LocalDb.extendedChargeUnits(_body('030000000000000000000000')),
        isNull,
      );
    });
  });

  group('batteryRowFromEvent', () {
    test('BATTERY_LEVEL carries the voltage that had no writer', () {
      final row = LocalDb.batteryRowFromEvent(_event(_mgLevel))!;
      expect(row['source'], 'band_event');
      expect(row['millivolts'], 4200);
      expect(row['battery_pct'], 100.0);
      expect(row['charging'], 0);
      expect(row['charge_units'], isNull);
    });

    test('gen4 BATTERY_LEVEL decodes the same three fields', () {
      final row = LocalDb.batteryRowFromEvent(_event(_gen4Level))!;
      expect(row['millivolts'], 3800);
      expect(row['battery_pct'], 50.0);
      expect(row['charging'], 0);
    });

    test('the extended event lands under its own source, not the same row', () {
      // Both events arrive on the SAME strap second. band_battery is keyed
      // (ts, source), so one shared source would make each overwrite the
      // other's columns — which is why they are split.
      final level = LocalDb.batteryRowFromEvent(_event(_mgLevel))!;
      final ext = LocalDb.batteryRowFromEvent(_event(_mgExt))!;
      expect(level['ts'], ext['ts']);
      expect(level['source'], isNot(ext['source']));
      expect(ext['charge_units'], 1920);
      expect(ext['battery_pct'], isNull);
      expect(ext['millivolts'], isNull);
    });

    test('an event that carries no battery makes no row', () {
      // Authored WRIST_ON: unrelated event must not create a battery row.
      final e = _event(_envelope(9, Uint8List(0), _batteryEpoch));
      expect(LocalDb.batteryRowFromEvent(e), isNull);
    });
  });

  // The bug was never the decode — it was that nothing carried the number the
  // last four inches into the table the widget reads. These two run the real
  // LocalDb.
  group('the series actually gets written', () {
    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    tearDown(() async {
      await LocalDb.close();
    });

    test('insertEvent fills the voltage that batteryHealth reports', () async {
      LocalDb.dbName = 'band_battery_live_test.db';
      await LocalDb.close();
      final db = await LocalDb.instance;
      await db.delete('band_battery');
      await db.delete('band_events');

      // 100.0% / 4200 mV, OFF the charger.
      await LocalDb.insertEvent(3, _batteryEpoch, _mgLevel);
      await LocalDb.insertEvent(63, _batteryEpoch, _mgExt);
      await LocalDb.insertEvent(7, _batteryEpoch + 10, _mgChargingOn);
      // 75.0% / 4100 mV, ON the charger — an authored event.
      await LocalDb.insertEvent(3, _batteryEpoch + 20, _mgLevelCharging);

      final rows = await LocalDb.recentBandBatterySamples();
      expect(rows.where((r) => r['millivolts'] != null), isNotEmpty);
      expect(rows.where((r) => r['charge_units'] == 1920), hasLength(1));

      final h = await LocalDb.batteryHealth();
      // 4100, NOT the higher 4200: a full-charge voltage is the highest
      // reading seen WHILE CHARGING, and an off-charger reading is not one.
      expect(h['full_charge_mv'], 4100);
      expect(h['latest_mv'], 4100);
      expect(h['latest_pct'], 75.0);
      // One CHARGING_ON event went in, so one charge is logged — counted off
      // the event, not off edges in a sampled series.
      expect(h['charge_cycles'], 1);
    });

    test('the upgrade replays history that was already on disk', () async {
      LocalDb.dbName = 'band_battery_backfill_test.db';
      await LocalDb.close();
      var db = await LocalDb.instance;
      await db.delete('band_battery');
      await db.delete('band_events');
      // Exactly the state every existing install is in: the frames are banked,
      // the battery series is empty.
      for (final f in [
        (3, _batteryEpoch, _mgLevel),
        (63, _batteryEpoch, _mgExt),
      ]) {
        await db.insert('band_events', {
          'hex': f.$3,
          'event_id': f.$1,
          'name': 'x',
          'ts': f.$2,
          'payload_json': '{}',
          'captured_at': 0,
        });
      }
      expect(await LocalDb.recentBandBatterySamples(), isEmpty);

      // Force the ladder to re-run this rung.
      await db.execute('PRAGMA user_version = 44');
      await LocalDb.close();
      db = await LocalDb.instance;
      expect(LocalDb.lastRebuild, isNull);

      final rows = await LocalDb.recentBandBatterySamples();
      expect(rows.map((r) => r['millivolts']).whereType<int>(), [4200]);
      expect(rows.map((r) => r['charge_units']).whereType<int>(), [1920]);
    });
  });
}
