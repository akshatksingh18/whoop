// The per-second fields a gen5 band computes ITSELF — its pedometer's
// cumulative step count and cadence, its activity class, a calibrated skin
// temperature in °C, its on-wrist determination, and the HR-validity flag plus
// the corroborating second HR byte — are decoded off every record and now
// PERSISTED (schema v34) instead of being dropped on the floor.
//
// The invariant these tests exist to protect is ABSENCE, not presence: a gen4
// band sends none of this, so a gen4 second must store NULL. Zeroing them would
// mint a 0-step second and a 0 °C skin temperature for every gen4 record in the
// ledger — indistinguishable from a real reading downstream, and exactly the
// class of fabrication this codebase keeps having to undo.
//
// Runs the REAL LocalDb over sqflite_ffi, so the DDL, the migration ladder and
// the read paths are the shipping ones.

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/models.dart';

/// The v33 `decoded_onehz` / `decoded_rr` shape — rec_ts-keyed, WITHOUT any of
/// the band-computed columns. This is what an existing install's (million-row)
/// table looks like before the upgrade.
const _v33DecodedDdl = [
  '''
  CREATE TABLE decoded_onehz (
    rec_ts INTEGER PRIMARY KEY,
    counter INTEGER NOT NULL,
    hr INTEGER NOT NULL,
    ax REAL NOT NULL, ay REAL NOT NULL, az REAL NOT NULL,
    spo2_red_raw INTEGER NOT NULL,
    spo2_ir_raw INTEGER NOT NULL,
    skin_temp_raw INTEGER NOT NULL)
''',
  'CREATE INDEX idx_decoded_onehz_counter ON decoded_onehz(counter)',
  '''
  CREATE TABLE decoded_rr (
    rec_ts INTEGER NOT NULL, beat_index INTEGER NOT NULL,
    rr_ts_ms INTEGER NOT NULL, rr_ms INTEGER NOT NULL,
    PRIMARY KEY (rec_ts, beat_index))
''',
];

Future<String> _dbPath(String name) async =>
    p.join(await databaseFactory.getDatabasesPath(), name);

/// Point LocalDb at a fresh, empty database file.
Future<void> _useFreshDb(String name) async {
  await LocalDb.close();
  LocalDb.dbName = name;
  await databaseFactory.deleteDatabase(await _dbPath(name));
}

RawRecord _raw(int recTs, int counter) => RawRecord(
  counter: counter,
  packetType: 47,
  // Not hex: forces the decode helper onto the supplied (already decoded)
  // Sample, which is how the BLE engine hands records over anyway.
  hex: 'decoded-by-the-supplied-sample',
  capturedAt: recTs * 1000,
  recTs: recTs,
);

/// A row straight out of `decoded_onehz`, so NULL can be told from 0.
Future<Map<String, Object?>> _rowAt(int recTs) async {
  final db = await LocalDb.instance;
  final rows = await db.query(
    'decoded_onehz',
    where: 'rec_ts = ?',
    whereArgs: [recTs],
  );
  return rows.single;
}

void main() {
  final created = <String>[];

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDownAll(() async {
    await LocalDb.close();
    for (final n in created) {
      await databaseFactory.deleteDatabase(await _dbPath(n));
    }
  });

  test('a gen5 second round-trips every band-computed field', () async {
    const name = 'openstrap_gen5_fields_test.db';
    created.add(name);
    await _useFreshDb(name);

    const recTs = 1785000000;
    await LocalDb.insertRecord(
      _raw(recTs, 9001),
      Sample(
        tsEpoch: recTs,
        counter: 9001,
        hr: 58,
        rrIntervalsMs: const [1010],
        ax: 0.02,
        ay: -0.05,
        az: 0.99,
        spo2RedRaw: 1111,
        spo2IrRaw: 2222,
        skinTempRaw: 3333,
        stepCount: 12345,
        stepCadence: 94,
        activityClass: 2,
        skinTempC: 30.62,
        onWrist: 1,
        hrValid: true,
        hrAlt: 59,
      ),
    );

    // The derive read path must actually SELECT the new columns — a column that
    // is written but never read back is the same as not storing it.
    final frames = await LocalDb.decodedOneHzBatchByRecTsRange(
      limit: 10,
      fromRecTs: recTs - 1,
      toRecTs: recTs + 1,
    );
    expect(frames, hasLength(1));
    final f = frames.single;
    expect(f['step_count'], 12345);
    expect(f['step_cadence'], 94);
    expect(f['activity_class'], 2);
    expect((f['skin_temp_c'] as num).toDouble(), closeTo(30.62, 1e-9));
    expect(f['on_wrist'], 1);
    expect(f['hr_valid'], 1);
    expect(f['hr_alt'], 59);
    // The pre-existing columns are untouched by the widening.
    expect(f['hr'], 58);
    expect(f['skin_temp_raw'], 3333);

    // …and the Sample-returning paths carry them back as typed fields.
    final ranged = await LocalDb.samplesInRange(recTs - 1, recTs + 1);
    expect(ranged, hasLength(1));
    expect(ranged.single.stepCount, 12345);
    expect(ranged.single.stepCadence, 94);
    expect(ranged.single.activityClass, 2);
    expect(ranged.single.skinTempC, closeTo(30.62, 1e-9));
    expect(ranged.single.onWrist, 1);
    expect(ranged.single.hrValid, isTrue);
    expect(ranged.single.hrAlt, 59);

    final latest = await LocalDb.latestSample();
    expect(latest!.stepCount, 12345);
    expect(latest.hrValid, isTrue);

    // hrValid FALSE must survive as false, not collapse to null/absent.
    await LocalDb.insertRecord(
      _raw(recTs + 1, 9002),
      Sample(
        tsEpoch: recTs + 1,
        counter: 9002,
        hr: 0,
        ax: 0,
        ay: 0,
        az: 1,
        spo2RedRaw: 0,
        spo2IrRaw: 0,
        skinTempRaw: 0,
        stepCount: 12345,
        hrValid: false,
      ),
    );
    expect((await _rowAt(recTs + 1))['hr_valid'], 0);
    expect((await LocalDb.latestSample())!.hrValid, isFalse);
  });

  test('a gen4 second stores NULL — never a fabricated 0 — for all of them',
      () async {
    const name = 'openstrap_gen4_null_fields_test.db';
    created.add(name);
    await _useFreshDb(name);

    const recTs = 1785100000;
    await LocalDb.insertRecord(
      _raw(recTs, 4001),
      // Exactly what a gen4 record decodes to: no step count, no cadence, no
      // class, no calibrated temperature, no wear bits, no HR-quality flag.
      Sample(
        tsEpoch: recTs,
        counter: 4001,
        hr: 62,
        rrIntervalsMs: const [960],
        ax: 0.1,
        ay: -0.2,
        az: 0.97,
        spo2RedRaw: 1234,
        spo2IrRaw: 2345,
        skinTempRaw: 3456,
      ),
    );

    final row = await _rowAt(recTs);
    for (final c in const [
      'step_count',
      'step_cadence',
      'activity_class',
      'skin_temp_c',
      'on_wrist',
      'hr_valid',
      'hr_alt',
    ]) {
      expect(row[c], isNull, reason: '$c must be NULL on a gen4 record, not 0');
    }
    // The gen4 fields it DOES carry are stored as before.
    expect(row['hr'], 62);
    expect(row['skin_temp_raw'], 3456);

    final s = await LocalDb.latestSample();
    expect(s!.stepCount, isNull);
    expect(s.skinTempC, isNull);
    expect(s.hrValid, isNull);
    expect(s.activityClass, isNull);
  });

  test('upgrading a populated v33 database keeps its rows readable', () async {
    const name = 'openstrap_v33_upgrade_fields_test.db';
    created.add(name);
    final path = await _dbPath(name);
    await LocalDb.close();
    await databaseFactory.deleteDatabase(path);

    const recTs = 1780000000;
    final old = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 33,
        onCreate: (db, _) async {
          for (final s in _v33DecodedDdl) {
            await db.execute(s);
          }
        },
      ),
    );
    await old.insert('decoded_onehz', {
      'rec_ts': recTs,
      'counter': 777,
      'hr': 55,
      'ax': 0.01,
      'ay': 0.02,
      'az': 0.99,
      'spo2_red_raw': 10,
      'spo2_ir_raw': 20,
      'skin_temp_raw': 30,
    });
    await old.insert('decoded_rr', {
      'rec_ts': recTs,
      'beat_index': 0,
      'rr_ts_ms': recTs * 1000,
      'rr_ms': 1090,
    });
    await old.close();

    LocalDb.dbName = name;
    final db = await LocalDb.instance;
    expect(
      ((await db.rawQuery('PRAGMA user_version')).first.values.first as num)
          .toInt(),
      LocalDb.schemaVersion,
    );

    // The pre-migration row survived intact, and reads back through the same
    // widened query the derive path uses.
    final frames = await LocalDb.decodedOneHzBatchByRecTsRange(
      limit: 10,
      fromRecTs: recTs - 1,
      toRecTs: recTs + 1,
    );
    expect(frames, hasLength(1));
    expect(frames.single['hr'], 55);
    expect(frames.single['skin_temp_raw'], 30);
    // It predates the columns, so it reports nothing for them — not zero.
    expect(frames.single['step_count'], isNull);
    expect(frames.single['skin_temp_c'], isNull);
    expect((await LocalDb.latestSample())!.stepCount, isNull);

    final rr = await LocalDb.decodedRrByRecTsRange(
      fromRecTs: recTs,
      toRecTs: recTs,
    );
    expect(rr.single['rr_ms'], 1090);

    // A NEW gen5 second lands beside the migrated one in the upgraded table.
    await LocalDb.insertRecord(
      _raw(recTs + 60, 778),
      Sample(
        tsEpoch: recTs + 60,
        counter: 778,
        hr: 57,
        ax: 0,
        ay: 0,
        az: 1,
        spo2RedRaw: 0,
        spo2IrRaw: 0,
        skinTempRaw: 0,
        stepCount: 4242,
        skinTempC: 22.5,
        onWrist: 0,
      ),
    );
    final fresh = await _rowAt(recTs + 60);
    expect(fresh['step_count'], 4242);
    expect((fresh['skin_temp_c'] as num).toDouble(), closeTo(22.5, 1e-9));
    expect(fresh['on_wrist'], 0);
    expect(fresh['hr_alt'], isNull);

    expect((await LocalDb.schemaHealth())['ok'], isTrue);
  });
}
