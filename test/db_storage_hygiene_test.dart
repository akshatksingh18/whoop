// Storage hygiene:
//  1. decoded_rr is keyed (rec_ts, beat_index) and carries no redundant
//     secondary index; rec_ts-range reads are served by the PK auto-index.
//  2. Superseded generations of the recomputable per-day intermediates are
//     pruned. They are keyed (day_id, algo_version), so every kAlgoVersion
//     bump wrote a whole new generation beside the old one and nothing
//     removed it.
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:openstrap_edge/data/db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.dbName = 'openstrap_storage_hygiene_test.db';
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  tearDownAll(() async {
    await LocalDb.close();
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  test('decoded_rr carries no redundant secondary index', () async {
    final db = await LocalDb.instance;
    final idx = await _rrIndexes(db);
    // The (rec_ts, beat_index) PRIMARY KEY auto-indexes; nothing else should be
    // maintained on this hot insert path.
    expect(
      idx.where((n) => !n.startsWith('sqlite_autoindex')),
      isEmpty,
      reason: 'unexpected secondary index on decoded_rr: $idx',
    );
  });

  test('rec_ts-range reads on decoded_rr are served by the PK auto-index', () async {
    // decoded_rr shares the rec_ts key with decoded_onehz, so the derive read
    // path (decodedRrByRecTsRange) is a PK range scan — never a full-table read.
    final db = await LocalDb.instance;
    final detail = (await db.rawQuery(
      'EXPLAIN QUERY PLAN SELECT * FROM decoded_rr WHERE rec_ts BETWEEN 1 AND 9 '
      'ORDER BY rec_ts ASC, beat_index ASC',
    )).map((r) => r['detail'].toString()).join(' | ');
    expect(
      detail.toUpperCase(),
      contains('USING'),
      reason: 'planner fell back to a full scan: $detail',
    );
    expect(
      detail,
      contains('sqlite_autoindex_decoded_rr_1'),
      reason: 'expected the primary key auto-index: $detail',
    );
    expect(
      detail.toUpperCase(),
      isNot(contains('USE TEMP B-TREE')),
      reason: 'ordering should come from the PK: $detail',
    );
  });

  test(
    'superseded intermediate generations are pruned, recent ones kept',
    () async {
      final db = await LocalDb.instance;
      for (final table in const [
        'sleep_session_candidates',
        'wake_day_features',
      ]) {
        for (final v in const [48, 49, 50]) {
          for (final day in const ['2026-07-01', '2026-07-02']) {
            await db.insert(table, {
              'day_id': day,
              'algo_version': v,
              'payload_json': '{}',
              'computed_at': 0,
            });
          }
        }
      }

      final deleted = await LocalDb.pruneSupersededIntermediates();
      expect(deleted, 4, reason: 'two days x v48, in both tables');

      for (final table in const [
        'sleep_session_candidates',
        'wake_day_features',
      ]) {
        final left = (await db.rawQuery(
          'SELECT DISTINCT algo_version FROM $table ORDER BY algo_version',
        )).map((r) => r['algo_version'] as int).toList();
        expect(left, [49, 50], reason: '$table keeps current + previous');
      }
    },
  );

  test('pruning is a no-op when there is nothing superseded', () async {
    expect(await LocalDb.pruneSupersededIntermediates(), 0);
  });

  test('a day stuck on an old version (raw aged out, never re-derived) is not '
      'orphaned just because OTHER days reached newer versions', () async {
    final db = await LocalDb.instance;
    // '2026-06-01' only ever got derived once, at v48 — its raw substrate is
    // long gone (raw retention is 3 days) so it can never write a v49/v50
    // row of its own. Two unrelated recent days churn through v49 then v50.
    await db.insert('sleep_session_candidates', {
      'day_id': '2026-06-01',
      'algo_version': 48,
      'payload_json': '{"stale":true}',
      'computed_at': 0,
    });
    for (final v in const [49, 50]) {
      for (final day in const ['2026-07-28', '2026-07-29']) {
        await db.insert('sleep_session_candidates', {
          'day_id': day,
          'algo_version': v,
          'payload_json': '{}',
          'computed_at': 0,
        });
      }
    }

    await LocalDb.pruneSupersededIntermediates();

    final stale = await LocalDb.sleepSessionCandidate('2026-06-01', 48);
    expect(
      stale,
      isNotNull,
      reason:
          'a table-wide "keep the 2 highest versions present anywhere" '
          'cutoff would delete this the moment two OTHER days reach v49/50 '
          '— it must be scoped per day_id instead',
    );
    expect(stale!['payload_json'], '{"stale":true}');

    // The recent days still get their own per-day retention (49/50 kept,
    // nothing older present to prune here).
    final recent = (await db.rawQuery(
      "SELECT DISTINCT algo_version FROM sleep_session_candidates "
      "WHERE day_id = '2026-07-28' ORDER BY algo_version",
    )).map((r) => r['algo_version'] as int).toList();
    expect(recent, [49, 50]);
  });
}

Future<List<String>> _rrIndexes(Database db) async => (await db.rawQuery(
  "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='decoded_rr'",
)).map((r) => r["name"] as String?).whereType<String>().toList();
