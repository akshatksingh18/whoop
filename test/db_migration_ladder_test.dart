// END-TO-END migration-ladder regressions, run against the REAL LocalDb over
// sqflite_ffi. Each test hand-builds a database at an OLD schema version, then
// opens it through LocalDb so sqflite runs the whole onUpgrade ladder.
//
// Why this file exists: `onUpgrade` runs inside ONE exclusive transaction, so a
// single throwing step rolls the whole ladder back and `openDatabase` rethrows.
// The app then has NO recoverable state — it is stuck on the loading screen on
// every launch, permanently. Two steps used a bare `ALTER TABLE … ADD COLUMN`
// against a table that a LATER-numbered `_create*` helper had already created
// with the CURRENT (column-bearing) DDL:
//
//   oldV <= 2 : step 3 re-creates raw_records WITH rec_ts, step 6 re-adds it.
//   oldV <= 6 : step 7 creates sessions WITH steps,        step 11 re-adds it.
//
// Plus the legacy-table migrations (sync_cursor / sync_ledger / sync_quarantine)
// which renamed → created → copied → dropped OUTSIDE any transaction, so a crash
// mid-copy orphaned `<table>_legacy` forever and silently lost the resumable-sync
// cursor (strap_trim / counter_hw / rec_ts_hw).

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/journal_fields.dart';
import 'package:openstrap_edge/data/models.dart';

/// The pre-v3 raw_records shape: keyed by frame hex, NO rec_ts column.
const _legacyRawDdl = '''
  CREATE TABLE raw_records (
    hex TEXT PRIMARY KEY,
    counter INTEGER,
    packet_type INTEGER,
    captured_at INTEGER NOT NULL,
    uploaded INTEGER NOT NULL DEFAULT 0
  )
''';

/// The v6-era raw_records shape: hex PK, rec_ts already present.
const _v6RawDdl = '''
  CREATE TABLE raw_records (
    hex TEXT PRIMARY KEY,
    counter INTEGER,
    packet_type INTEGER,
    captured_at INTEGER NOT NULL,
    rec_ts INTEGER NOT NULL DEFAULT 0,
    uploaded INTEGER NOT NULL DEFAULT 0
  )
''';

/// The origin/main (pre-v33) COUNTER-keyed decoded store, exactly as a user who
/// installed at v19..31 has it — and by then raw_records is already DROPPED, so
/// the v33 rekey is the ONLY copy of their 1 Hz data (no raw-backfill safety
/// net). This is the highest-risk path the re-key touches.
const _counterKeyedDecodedDdl = [
  '''
  CREATE TABLE decoded_onehz (
    counter INTEGER PRIMARY KEY, rec_ts INTEGER NOT NULL,
    hr INTEGER NOT NULL, ax REAL NOT NULL, ay REAL NOT NULL, az REAL NOT NULL,
    spo2_red_raw INTEGER NOT NULL, spo2_ir_raw INTEGER NOT NULL,
    skin_temp_raw INTEGER NOT NULL)
''',
  'CREATE UNIQUE INDEX idx_decoded_onehz_rec_ts_unique ON decoded_onehz(rec_ts)',
  '''
  CREATE TABLE decoded_rr (
    counter INTEGER NOT NULL, beat_index INTEGER NOT NULL,
    rr_ts_ms INTEGER NOT NULL, rr_ms INTEGER NOT NULL,
    PRIMARY KEY (counter, beat_index))
''',
  'CREATE UNIQUE INDEX idx_decoded_rr_ts_beat_unique '
      'ON decoded_rr(rr_ts_ms, beat_index)',
];

/// The v5-era derived tables, so step 9's derived_day → day_result copy is real.
const _v5DerivedDdl = [
  '''
  CREATE TABLE derived_day (
    date TEXT PRIMARY KEY,
    payload_json TEXT NOT NULL,
    version INTEGER NOT NULL,
    last_raw_ts INTEGER NOT NULL,
    computed_at INTEGER NOT NULL,
    rhr REAL, rmssd REAL, readiness REAL
  )
''',
  '''
  CREATE TABLE baselines (
    key TEXT PRIMARY KEY,
    payload_json TEXT NOT NULL,
    updated_at INTEGER NOT NULL
  )
''',
  '''
  CREATE TABLE metric_series (
    date TEXT NOT NULL, key TEXT NOT NULL, value REAL,
    PRIMARY KEY (date, key)
  )
''',
];

Future<String> _dbPath(String name) async =>
    p.join(await databaseFactory.getDatabasesPath(), name);

/// Build a database file at [version] with [ddl] applied, then close it.
Future<void> _seedOldDb(
  String name,
  int version,
  List<String> ddl, {
  Future<void> Function(Database db)? seedRows,
}) async {
  final path = await _dbPath(name);
  await databaseFactory.deleteDatabase(path);
  final db = await databaseFactory.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: version,
      onCreate: (db, _) async {
        for (final s in ddl) {
          await db.execute(s);
        }
      },
    ),
  );
  if (seedRows != null) await seedRows(db);
  await db.close();
}

/// Open [name] through LocalDb (running the real ladder) and hand back the
/// resulting user_version.
Future<int> _openThroughLocalDb(String name) async {
  await LocalDb.close();
  LocalDb.dbName = name;
  final db = await LocalDb.instance;
  final rows = await db.rawQuery('PRAGMA user_version');
  return (rows.first.values.first as num?)?.toInt() ?? -1;
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

  test(
    'upgrade from v2 completes — step 3 recreates raw_records WITH rec_ts, '
    'so step 6 must not re-add it (duplicate column bricked every launch)',
    () async {
      const name = 'migrate_from_v2_test.db';
      created.add(name);
      await _seedOldDb(name, 2, [
        _legacyRawDdl,
        'CREATE TABLE samples (counter INTEGER PRIMARY KEY, ts INTEGER NOT NULL, hr INTEGER)',
        '''CREATE TABLE events (
             hex TEXT PRIMARY KEY, event_id INTEGER, ts INTEGER,
             captured_at INTEGER NOT NULL)''',
      ]);

      // Before the guard this threw
      // DatabaseException(duplicate column name: rec_ts) out of openDatabase,
      // rolling the whole ladder back — forever, on every launch.
      final version = await _openThroughLocalDb(name);
      expect(version, LocalDb.schemaVersion);

      final health = await LocalDb.schemaHealth();
      expect(health['ok'], isTrue, reason: '$health');
    },
  );

  test(
    'upgrade from v6 completes — step 7 creates sessions WITH steps, '
    'so step 11 must not re-add it',
    () async {
      const name = 'migrate_from_v6_test.db';
      created.add(name);
      await _seedOldDb(
        name,
        6,
        [
          _v6RawDdl,
          'CREATE TABLE samples (counter INTEGER PRIMARY KEY, ts INTEGER NOT NULL, hr INTEGER)',
          '''CREATE TABLE events (
               hex TEXT PRIMARY KEY, event_id INTEGER, ts INTEGER,
               captured_at INTEGER NOT NULL)''',
          ..._v5DerivedDdl,
        ],
        seedRows: (db) async {
          await db.insert('raw_records', {
            'hex': 'deadbeef',
            'counter': 42,
            'packet_type': 47,
            'captured_at': 1780000000 * 1000,
            'rec_ts': 0,
          });
          await db.insert('derived_day', {
            'date': '2026-05-05',
            'payload_json': '{"legacy": true}',
            'version': 1,
            'last_raw_ts': 1780000000,
            'computed_at': 1,
            'rhr': 55.0,
          });
        },
      );

      // Before the guard: DatabaseException(duplicate column name: steps).
      final version = await _openThroughLocalDb(name);
      expect(version, LocalDb.schemaVersion);

      final health = await LocalDb.schemaHealth();
      expect(health['ok'], isTrue, reason: '$health');

      // The ladder's real work still happened: derived_day carried across.
      final migrated = await LocalDb.dayResult('2026-05-05');
      expect(migrated, isNotNull);
      expect(migrated!['payload_json'], '{"legacy": true}');

      // …and `sessions` has exactly ONE `steps` column, not two.
      final db = await LocalDb.instance;
      final cols = await db.rawQuery('PRAGMA table_info(sessions)');
      expect(cols.where((c) => c['name'] == 'steps').length, 1);
      expect(cols.where((c) => c['name'] == 'hrr_bpm').length, 1);
    },
  );

  test(
    'an orphaned sync_cursor_legacy is RESUMED, not abandoned — a crash '
    'mid-copy must not silently lose the resumable-sync cursor',
    () async {
      const name = 'migrate_legacy_resume_test.db';
      created.add(name);
      // Exactly the state an interrupted legacy migration leaves behind: the
      // NEW-shaped sync_cursor already exists (so the old code's "already
      // current" early-return fired and never looked at the orphan), while
      // sync_cursor_legacy still holds the rows that were never copied.
      await _seedOldDb(
        name,
        LocalDb.schemaVersion,
        [
          '''CREATE TABLE sync_cursor (
               name TEXT PRIMARY KEY, value TEXT, updated_at INTEGER NOT NULL)''',
          '''CREATE TABLE sync_cursor_legacy (
               name TEXT PRIMARY KEY, value TEXT, note TEXT)''',
        ],
        seedRows: (db) async {
          // Say the copy died after one of three rows.
          await db.insert('sync_cursor', {
            'name': 'strap_trim',
            'value': 'aabbccdd',
            'updated_at': 1,
          });
          for (final r in const [
            ['strap_trim', 'aabbccdd'],
            ['counter_hw', '1200000'],
            ['rec_ts_hw', '1780000000'],
          ]) {
            await db.insert('sync_cursor_legacy', {
              'name': r[0],
              'value': r[1],
            });
          }
        },
      );

      await _openThroughLocalDb(name);

      // Every legacy row is now in the live table…
      expect(await LocalDb.getCursor('strap_trim'), 'aabbccdd');
      expect(await LocalDb.getCursorInt('counter_hw'), 1200000);
      expect(await LocalDb.getCursorInt('rec_ts_hw'), 1780000000);
      // …and the orphan is gone, so this can never run again.
      final db = await LocalDb.instance;
      final left = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' "
        "AND name='sync_cursor_legacy'",
      );
      expect(left, isEmpty);
    },
  );

  test(
    'a legacy migration interrupted BEFORE the CREATE (table missing, legacy '
    'present) also resumes cleanly',
    () async {
      const name = 'migrate_legacy_resume2_test.db';
      created.add(name);
      await _seedOldDb(
        name,
        LocalDb.schemaVersion,
        [
          '''CREATE TABLE sync_cursor_legacy (
               name TEXT PRIMARY KEY, value TEXT, note TEXT)''',
        ],
        seedRows: (db) async {
          await db.insert('sync_cursor_legacy', {
            'name': 'strap_trim',
            'value': 'feedface',
          });
        },
      );

      await _openThroughLocalDb(name);
      expect(await LocalDb.getCursor('strap_trim'), 'feedface');
      final db = await LocalDb.instance;
      expect(
        await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' "
          "AND name='sync_cursor_legacy'",
        ),
        isEmpty,
      );
    },
  );

  test(
    'upgrade from v27 adds the numeric journal tables without touching the '
    'tags and note already stored for a day',
    () async {
      const name = 'migrate_from_v27_test.db';
      created.add(name);
      await _seedOldDb(
        name,
        27,
        [
          ..._v5DerivedDdl,
          "CREATE TABLE journal (date TEXT PRIMARY KEY, "
              "tags_json TEXT NOT NULL DEFAULT '[]', "
              "note TEXT NOT NULL DEFAULT '', updated_at INTEGER NOT NULL)",
        ],
        seedRows: (db) async {
          await db.insert('journal', {
            'date': '2026-06-01',
            'tags_json': '["caffeine","late meal"]',
            'note': 'felt rough',
            'updated_at': 1,
          });
        },
      );

      final version = await _openThroughLocalDb(name);
      expect(version, LocalDb.schemaVersion);

      // The upgrade is purely additive: a day that only ever had tags keeps
      // them, and simply has no numeric rows.
      final rows = await LocalDb.journalRows();
      expect(rows.single['tags_json'], '["caffeine","late meal"]');
      expect(rows.single['note'], 'felt rough');
      expect(await LocalDb.journalMetricsForDay('2026-06-01'), isEmpty);

      // And the new tables are usable immediately, not on the next launch.
      await LocalDb.putJournalMetrics('2026-06-01', {
        'mood': const JournalMetricValue(4),
      });
      expect(
        (await LocalDb.journalMetricsForDay('2026-06-01'))['mood']!.value,
        4,
      );
      expect(await LocalDb.journalFieldDefs(), isEmpty);

      final health = await LocalDb.schemaHealth();
      expect(health['ok'], isTrue, reason: '$health');
    },
  );


  test(
    'upgrade from v27 creates the lab tables and they accept a write '
    'immediately, not on the next launch',
    () async {
      const name = 'migrate_from_v27_labs_test.db';
      created.add(name);
      await _seedOldDb(name, 27, _v5DerivedDdl);

      final version = await _openThroughLocalDb(name);
      expect(version, LocalDb.schemaVersion);

      await LocalDb.putLabResult(
        marker: 'ferritin',
        takenOn: '2026-03-04',
        value: 42,
        unit: 'ng/mL',
      );
      expect((await LocalDb.labResults()).single['value'], 42.0);
      expect(await LocalDb.labMarkerDefs(), isEmpty);

      final health = await LocalDb.schemaHealth();
      expect(health['ok'], isTrue, reason: '$health');
    },
  );

  test(
    'upgrade from v27 runs the whole ladder to 31 and every new table works',
    () async {
      const name = 'migrate_from_v27_to_31_test.db';
      created.add(name);
      await _seedOldDb(name, 27, _v5DerivedDdl);

      expect(await _openThroughLocalDb(name), LocalDb.schemaVersion);

      // Each rung's table, exercised rather than merely present — a CREATE
      // that ran with a typo still leaves a table that nothing can write to.
      await LocalDb.putJournalMetrics('2026-06-01', {
        'mood': const JournalMetricValue(4),
      });
      await LocalDb.putLabResult(
        marker: 'ferritin',
        takenOn: '2026-03-04',
        value: 42,
        unit: 'ng/mL',
      );
      await LocalDb.putBreathingSession(
        startedAt: 1000,
        endedAt: 2000,
        pattern: 'resonance',
        seconds: 120,
      );
      await LocalDb.putNapEdit(
        dayId: '2026-06-01',
        startTs: 1000,
        endTs: 4600,
        source: 'manual',
      );

      expect(
        (await LocalDb.journalMetricsForDay('2026-06-01'))['mood']!.value,
        4,
      );
      expect((await LocalDb.labResults()).single['value'], 42.0);
      expect((await LocalDb.breathingSessions()).single['seconds'], 120);
      expect((await LocalDb.napEdits('2026-06-01')).single['source'], 'manual');
      expect(await LocalDb.napEditDays(), {'2026-06-01'});

      final health = await LocalDb.schemaHealth();
      expect(health['ok'], isTrue, reason: '$health');
    },
  );

  test(
    'v33 re-key converts a v31 COUNTER-keyed decoded store to rec_ts LOSSLESSLY '
    '— raw_records is already dropped, so the rekey is the only copy',
    () async {
      const name = 'migrate_from_v31_counterkeyed_test.db';
      created.add(name);
      await _seedOldDb(
        name,
        31,
        [..._counterKeyedDecodedDdl, ..._v5DerivedDdl],
        seedRows: (db) async {
          // Three distinct seconds, distinct counters (valid old-schema data).
          for (final r in const [
            [100, 1785000000, 60],
            [101, 1785000001, 61],
            [102, 1785000002, 62],
          ]) {
            await db.insert('decoded_onehz', {
              'counter': r[0], 'rec_ts': r[1], 'hr': r[2],
              'ax': 0.0, 'ay': 0.0, 'az': 0.0,
              'spo2_red_raw': 0, 'spo2_ir_raw': 0, 'skin_temp_raw': 0,
            });
          }
          // Beats under counter 100 (two) and 102 (one).
          await db.insert('decoded_rr', {
            'counter': 100, 'beat_index': 0,
            'rr_ts_ms': 1785000000 * 1000, 'rr_ms': 800,
          });
          await db.insert('decoded_rr', {
            'counter': 100, 'beat_index': 1,
            'rr_ts_ms': 1785000000 * 1000, 'rr_ms': 810,
          });
          await db.insert('decoded_rr', {
            'counter': 102, 'beat_index': 0,
            'rr_ts_ms': 1785000002 * 1000, 'rr_ms': 900,
          });
        },
      );

      expect(await _openThroughLocalDb(name), LocalDb.schemaVersion);
      final db = await LocalDb.instance;

      // Every second survives; counter is preserved as the forensic column.
      final oh = await db.query('decoded_onehz', orderBy: 'rec_ts ASC');
      expect([for (final r in oh) r['rec_ts']],
          [1785000000, 1785000001, 1785000002]);
      expect([for (final r in oh) r['counter']], [100, 101, 102]);
      // PK is now rec_ts, not counter.
      final ohInfo = await db.rawQuery('PRAGMA table_info(decoded_onehz)');
      expect(ohInfo.firstWhere((c) => c['name'] == 'rec_ts')['pk'], 1);
      expect(ohInfo.firstWhere((c) => c['name'] == 'counter')['pk'], 0);

      // Beats re-home onto their real second; decoded_rr loses its counter col.
      final rr =
          await db.query('decoded_rr', orderBy: 'rec_ts ASC, beat_index ASC');
      expect([for (final r in rr) r['rec_ts']],
          [1785000000, 1785000000, 1785000002]);
      expect([for (final r in rr) r['rr_ms']], [800, 810, 900]);
      final rrInfo = await db.rawQuery('PRAGMA table_info(decoded_rr)');
      expect(rrInfo.any((c) => c['name'] == 'counter'), isFalse);

      // No stranded beats, no cross-stamped timestamps, no leaked temp tables.
      expect(
        (await db.rawQuery(
          'SELECT COUNT(*) c FROM decoded_rr WHERE rr_ts_ms != rec_ts * 1000',
        )).first['c'],
        0,
      );
      expect(
        await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE name LIKE '%\\_v33' ESCAPE '\\' "
          "OR name LIKE '%\\_new' ESCAPE '\\'",
        ),
        isEmpty,
      );

      final health = await LocalDb.schemaHealth();
      expect(health['ok'], isTrue, reason: '$health');
    },
  );

  test(
    'v31→v32 re-keys raw_archive off the volatile counter onto frame hex '
    'without losing a distinct frame, collapsing only exact-duplicate hex',
    () async {
      const name = 'migrate_from_v31_rawarchive_test.db';
      created.add(name);
      // The pre-v32 raw_archive shape: keyed by the strap counter, which resets
      // to ~0 on reboot — so a post-reboot frame reusing a live counter was
      // silently IGNORE-dropped in the one table meant to never lose a frame.
      await _seedOldDb(
        name,
        31,
        const [
          '''
          CREATE TABLE raw_archive (
            counter INTEGER PRIMARY KEY,
            hex TEXT NOT NULL,
            packet_type INTEGER NOT NULL,
            rec_ts INTEGER,
            captured_at INTEGER NOT NULL,
            reason TEXT NOT NULL
          )
          ''',
          'CREATE INDEX idx_raw_archive_captured ON raw_archive(captured_at DESC)',
        ],
        seedRows: (db) async {
          Future<void> row(int counter, String hex) => db.insert('raw_archive', {
                'counter': counter,
                'hex': hex,
                'packet_type': 0x2F,
                'captured_at': 1750000000000 + counter,
                'reason': 'undecodable_rec_v99',
              });
          // Three distinct frames (distinct counter AND hex) — none may be lost.
          await row(1, 'aa01');
          await row(2, 'bb02');
          await row(3, 'cc03');
          // Two rows the OLD counter-PK allowed but that carry IDENTICAL bytes;
          // the content re-key must collapse them to one (the dedup we want).
          await row(10, 'ff06');
          await row(11, 'ff06');
        },
      );

      expect(await _openThroughLocalDb(name), LocalDb.schemaVersion);

      // 5 old rows → 4: the three distinct frames survive, the duplicate-hex
      // pair collapses to one. Nothing distinct was lost.
      final stats = await LocalDb.rawArchiveStats();
      expect(stats['count'], 4);

      // The migrated table is now hex-PK, proven end-to-end through the REAL
      // ladder (not just a fresh onCreate): two DISTINCT frames that reuse ONE
      // counter both survive — the exact loss the old counter-PK caused.
      await LocalDb.archiveRawRecord(ArchiveRecord(
        counter: 1, // reuses a counter already present from the seed
        hex: 'dd04',
        packetType: 0x2F,
        capturedAt: 1750000500000,
        reason: 'undecodable_post_reboot',
      ));
      await LocalDb.archiveRawRecord(ArchiveRecord(
        counter: 1, // SAME counter, DIFFERENT bytes
        hex: 'ee05',
        packetType: 0x2F,
        capturedAt: 1750000600000,
        reason: 'undecodable_post_reboot',
      ));
      expect((await LocalDb.rawArchiveStats())['count'], 6);

      // …and an identical re-flood still dedups on content.
      await LocalDb.archiveRawRecord(ArchiveRecord(
        counter: 999, // different counter, but bytes already archived
        hex: 'dd04',
        packetType: 0x2F,
        capturedAt: 1750000700000,
        reason: 'undecodable_post_reboot',
      ));
      expect((await LocalDb.rawArchiveStats())['count'], 6);

      final health = await LocalDb.schemaHealth();
      expect(health['ok'], isTrue, reason: '$health');
    },
  );
}
