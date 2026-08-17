// device_family (schema v41) — the ingest-stamped device seam.
//
// The migration rung and the write path, run against the REAL LocalDb over
// sqflite_ffi. The point of the column is that a gen4 skin-temp ADC count and a
// gen5 centi-°C reading do not share a column with nothing to tell them apart,
// so what is asserted here is: the column exists on all three tables, existing
// rows read NULL (unknown provenance, never a backfilled guess), a stamped
// commit lands the stamp, and an unstamped one lands NULL.
//
// The REAL-DB half (`OPENSTRAP_TEST_DBS=/path/one.db,/path/two.db`) runs the
// whole ladder over old-schema exports. Skipped when the env var is unset —
// those files are not in the repo.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/models.dart';

Sample _sample(int ts, int counter) => Sample(
  tsEpoch: ts,
  counter: counter,
  hr: 70,
  rrIntervalsMs: const [800, 810],
  ax: 0.1,
  ay: 0.2,
  az: 0.9,
  spo2RedRaw: 1,
  spo2IrRaw: 2,
  skinTempRaw: 3,
);

RawRecord _raw(int ts, int counter) => RawRecord(
  counter: counter,
  packetType: 47,
  hex: 'feed$counter',
  capturedAt: ts * 1000,
  recTs: ts,
);

Future<List<String>> _columns(String table) async {
  final db = await LocalDb.instance;
  return [
    for (final c in await db.rawQuery('PRAGMA table_info($table)'))
      c['name'] as String,
  ];
}

Future<void> _useFreshDb(String name) async {
  await LocalDb.close();
  LocalDb.dbName = name;
  final dir = await databaseFactory.getDatabasesPath();
  await databaseFactory.deleteDatabase(p.join(dir, name));
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() async {
    await LocalDb.close();
  });

  test('device_family exists on all three tables of a fresh DB', () async {
    await _useFreshDb('device_family_fresh_test.db');
    for (final t in ['decoded_onehz', 'decoded_rr', 'sessions']) {
      expect(await _columns(t), contains('device_family'), reason: t);
    }
    // v43: the sensor-provenance guard rides beside it on the two substrate
    // tables — a chest strap's resting HR and the wrist's differ
    // systematically, so every baseline read filters on this.
    for (final t in ['decoded_onehz', 'decoded_rr']) {
      expect(await _columns(t), contains('source'), reason: t);
    }
  });

  test('a baseline read never sees a non-band row', () async {
    await _useFreshDb('source_filter_test.db');
    await LocalDb.commitSyncBatch([_raw(1000, 1)], [_sample(1000, 1)]);
    final db = await LocalDb.instance;
    // Stand in for a peripheral sensor writing into the substrate: one second
    // that is NOT the band's. Nothing routes here today, which is exactly why
    // the filter has to be proven now rather than when it does.
    await db.insert('decoded_onehz', {
      'rec_ts': 2000,
      'counter': 2,
      'hr': 55,
      'source': 'hrs:Chest strap',
    });
    await db.insert('decoded_rr', {
      'rec_ts': 2000,
      'beat_index': 0,
      'rr_ts_ms': 2000 * 1000,
      'rr_ms': 900,
      'source': 'hrs:Chest strap',
    });

    final page = await LocalDb.decodedOneHzBatchByRecTsRange(
      limit: 100,
      fromRecTs: 0,
      toRecTs: 9999,
    );
    expect(page.map((r) => r['rec_ts']), [1000]);
    final rr = await LocalDb.decodedRrByRecTsRange(fromRecTs: 0, toRecTs: 9999);
    expect(rr.every((r) => r['rec_ts'] == 1000), isTrue);
    // The data edge is the BAND's edge — a sensor second must not look like
    // sync progress.
    expect(await LocalDb.lastDecodedRecTs(), 1000);
    expect(await LocalDb.firstAndLastRecordTs(), (1000, 1000));
  });

  test('the stamp comes from the commit, and absence stays NULL', () async {
    await _useFreshDb('device_family_write_test.db');
    // Stamped by a gen5 link.
    await LocalDb.commitSyncBatch(
      [_raw(1000, 1)],
      [_sample(1000, 1)],
      deviceFamily: 'gen5',
    );
    // No link named itself — unknown provenance.
    await LocalDb.commitSyncBatch([_raw(2000, 2)], [_sample(2000, 2)]);

    final db = await LocalDb.instance;
    Future<Object?> familyAt(String table, int recTs) async {
      final rows = await db.rawQuery(
        'SELECT device_family AS f FROM $table WHERE rec_ts = ? LIMIT 1',
        [recTs],
      );
      return rows.isEmpty ? #missing : rows.first['f'];
    }

    expect(await familyAt('decoded_onehz', 1000), 'gen5');
    expect(await familyAt('decoded_rr', 1000), 'gen5');
    // NULL, not 'gen4' — an unknown family is its own case.
    expect(await familyAt('decoded_onehz', 2000), isNull);
    expect(await familyAt('decoded_rr', 2000), isNull);
  });

  test('the migration rung is idempotent', () async {
    await _useFreshDb('device_family_idempotent_test.db');
    // Wind user_version back and reopen so the v41 rung runs again on a DB that
    // ALREADY has the column — a throw there rolls the whole ladder back and
    // quarantines the user's database, so it has to be a no-op.
    for (var i = 0; i < 3; i++) {
      await (await LocalDb.instance).execute('PRAGMA user_version = 40');
      await LocalDb.close();
      await LocalDb.instance;
    }
    expect(await _columns('decoded_onehz'), contains('device_family'));
    expect(
      (await _columns(
        'decoded_onehz',
      )).where((c) => c == 'device_family').length,
      1,
    );
  });

  // Old-schema exports: the whole ladder, end to end.
  final real = (Platform.environment['OPENSTRAP_TEST_DBS'] ?? '')
      .split(',')
      .where((s) => s.trim().isNotEmpty)
      .toList();
  for (final src in real) {
    test(
      'migrates ${p.basename(src)} and ends with device_family NULL',
      () async {
        final name = 'devfam_${p.basenameWithoutExtension(src)}.db';
        await _useFreshDb(name);
        final dir = await databaseFactory.getDatabasesPath();
        await File(src).copy(p.join(dir, name));

        final db = await LocalDb.instance;
        for (final t in ['decoded_onehz', 'decoded_rr', 'sessions']) {
          expect(
            await _columns(t),
            contains('device_family'),
            reason: '$src $t',
          );
          final nonNull = (await db.rawQuery(
            'SELECT COUNT(*) AS n FROM $t WHERE device_family IS NOT NULL',
          )).first['n'];
          // NEVER backfilled: pre-v41 rows have no provenance to claim.
          expect(nonNull, 0, reason: '$src $t must not be guessed at');
          final rows = (await db.rawQuery(
            'SELECT COUNT(*) AS n FROM $t',
          )).first['n'];
          // ignore: avoid_print
          print('[devfam] ${p.basename(src)} $t rows=$rows');
        }
        // v43 `source` — the peripheral-sensor guard. Same rule as
        // device_family: it exists after the ladder and every migrated row
        // reads NULL, i.e. "the band measured this", which is the truth for
        // every row that predates a second sensor being possible at all.
        for (final t in ['decoded_onehz', 'decoded_rr']) {
          expect(await _columns(t), contains('source'), reason: '$src $t');
          final nonNull = (await db.rawQuery(
            'SELECT COUNT(*) AS n FROM $t WHERE source IS NOT NULL',
          )).first['n'];
          expect(nonNull, 0, reason: '$src $t source must migrate as NULL');
        }
        final health = await LocalDb.schemaHealth();
        expect(health['ok'], isTrue, reason: '$src $health');
      },
      timeout: const Timeout(Duration(minutes: 10)),
    );
  }
}
