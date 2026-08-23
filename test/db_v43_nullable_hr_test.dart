// Schema v43, over the REAL LocalDb on sqflite_ffi.
//
// The load-bearing change is SLP-05: `decoded_onehz.hr` loses its NOT NULL so a
// record that carries a validated gravity vector and genuinely NO heart rate
// (gen4's v25 PPG burst) can be banked instead of archived. `hr == 0` is this
// app's off-skin sentinel, so the whole risk of the change is a reader that
// inherits it — this file is that audit, run rather than asserted in a comment.
//
// Also here: the per-km split freeze (CV-01), the RPE column (TS-09), and
// export-provenance's `source` on L13's side table.

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/models.dart';

/// A record with a real gravity vector and NO heart rate — the v25 shape.
Sample _accelOnly(int ts, int counter) => Sample(
  tsEpoch: ts,
  counter: counter,
  hr: 0,
  ax: 0.10,
  ay: 0.20,
  az: 0.95,
);

Sample _withHr(int ts, int counter, int hr) => Sample(
  tsEpoch: ts,
  counter: counter,
  hr: hr,
  rrIntervalsMs: const [800],
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

Future<void> _useFreshDb(String name) async {
  await LocalDb.close();
  LocalDb.dbName = name;
  final dir = await databaseFactory.getDatabasesPath();
  await databaseFactory.deleteDatabase(p.join(dir, name));
}

Future<List<String>> _columns(String table) async {
  final db = await LocalDb.instance;
  return [
    for (final c in await db.rawQuery('PRAGMA table_info($table)'))
      c['name'] as String,
  ];
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() async {
    await LocalDb.close();
  });

  test('decoded_onehz.hr is nullable and absence lands as NULL', () async {
    await _useFreshDb('v43_hr_null_test.db');
    final db = await LocalDb.instance;

    final hrCol = (await db.rawQuery(
      'PRAGMA table_info(decoded_onehz)',
    )).firstWhere((c) => c['name'] == 'hr');
    expect(hrCol['notnull'], 0, reason: 'a record with no HR must be storable');

    await LocalDb.commitSyncBatch(
      [_raw(1000, 1), _raw(1001, 2)],
      [_withHr(1000, 1, 62), _accelOnly(1001, 2)],
    );

    Future<Object?> hrAt(int ts) async => (await db.rawQuery(
      'SELECT hr FROM decoded_onehz WHERE rec_ts = ?',
      [ts],
    )).first['hr'];

    expect(await hrAt(1000), 62);
    // NOT 0 — 0 asserts "the band was off your wrist" for a second the band
    // was demonstrably ON it (the gravity vector below proves it).
    expect(await hrAt(1001), isNull);

    // The accel SURVIVES. That is the whole point of the column change: the
    // second is observed for the rest window even though it carries no beat.
    final row = (await db.query(
      'decoded_onehz',
      where: 'rec_ts = ?',
      whereArgs: [1001],
    )).first;
    expect(row['az'], closeTo(0.95, 1e-9));
  });

  test('no reader inherits the off-skin sentinel from a NULL hr', () async {
    await _useFreshDb('v43_hr_readers_test.db');
    await LocalDb.commitSyncBatch(
      [_raw(2000, 1), _raw(2001, 2), _raw(2002, 3)],
      [_withHr(2000, 1, 60), _accelOnly(2001, 2), _withHr(2002, 3, 80)],
    );

    // 1. The Sample mapper. NULL reads back as the same 0 the substrate has
    //    always used for "no heart rate this second" — never as a throw.
    final samples = await LocalDb.samplesInRange(2000, 2002);
    expect(samples.map((s) => s.hr), [60, 0, 80]);
    // `Sample.wristOn` (`hr > 0`) is GONE — BANDAGNOSTIC C11. It was the one
    // reader in the app that turned "no usable heart rate this second" into
    // "the band was off your wrist", and it had no callers. Wear truth is the
    // HELLO body, the wrist on/off events and record presence.

    // 2. Every SQL read is gated `hr > 0`, which NULL fails — so the
    //    heart-rate readers simply do not see the second, rather than
    //    averaging a zero into it.
    final hrRows = await LocalDb.hrSamplesInRange(2000, 2002);
    expect(hrRows.map((r) => r['hr']), [60, 80]);

    // 3. The derive page carries the row WITH its accel and a null hr, so the
    //    1 Hz arrays stay 1:1 with the seconds.
    final page = await LocalDb.decodedOneHzBatchByRecTsRange(
      limit: 10,
      fromRecTs: 2000,
      toRecTs: 2002,
    );
    expect(page.length, 3);
    expect(page[1]['hr'], isNull);
    expect(page[1]['az'], closeTo(0.95, 1e-9));
  });

  test('workout_split freezes what decoded_onehz cannot answer later',
      () async {
    await _useFreshDb('v43_splits_test.db');
    expect(await _columns('workout_split'), contains('net_elev_m'));

    await LocalDb.putWorkoutSplits('s1', [
      {'km': 1, 'meters': 1000.0, 'duration_sec': 300, 'avg_hr': 141.0,
        'net_elev_m': 12.5},
      // A split whose points carried no altitude: NULL, never 0 (which reads
      // as flat).
      {'km': 2, 'meters': 640.0, 'duration_sec': 200, 'avg_hr': null,
        'net_elev_m': null},
    ]);

    final rows = await LocalDb.workoutSplits('s1');
    expect(rows.length, 2);
    expect(rows.first['avg_hr'], 141.0);
    expect(rows[1]['avg_hr'], isNull);
    expect(rows[1]['net_elev_m'], isNull);

    // Re-writing replaces rather than duplicating, and deleting the session
    // takes its splits with it.
    await LocalDb.putWorkoutSplits('s1', [
      {'km': 1, 'meters': 1000.0, 'duration_sec': 291, 'avg_hr': 139.0,
        'net_elev_m': 12.5},
    ]);
    expect((await LocalDb.workoutSplits('s1')).length, 1);
    await LocalDb.deleteSession('s1');
    expect(await LocalDb.workoutSplits('s1'), isEmpty);
  });

  test('sessions.rpe is nullable with no default — unrated stays unrated',
      () async {
    await _useFreshDb('v43_rpe_test.db');
    final rpe = (await (await LocalDb.instance).rawQuery(
      'PRAGMA table_info(sessions)',
    )).firstWhere((c) => c['name'] == 'rpe');
    expect(rpe['notnull'], 0);
    // The set-level picker already defaults to 7. A session-level default is
    // the same garbage-data mechanism, so there must not be one.
    expect(rpe['dflt_value'], isNull);
  });

  test('export-provenance: source is stamped, never guessed', () async {
    await _useFreshDb('v43_provenance_test.db');
    Future<void> put(String day, {String? source}) => LocalDb.putDayResult(
      dayId: day,
      algoVersion: 70,
      payloadJson: '{}',
      windowJson: '{}',
      series: {'rhr': 51},
      source: source,
    );

    await put('2026-01-01', source: 'band');
    await put('2026-01-02'); // provenance genuinely unknown

    final rows = await LocalDb.metricSeriesVersions();
    expect(rows.length, 2);
    expect(rows.first['source'], 'band');
    // NOT retro-filled with 'band'. csvField renders NULL as an empty cell,
    // which is the honest reading of "we do not know".
    expect(rows[1]['source'], isNull);
    expect(rows[1]['algo_version'], 70);
  });
}
