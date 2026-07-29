// Storage hygiene:
//  1. decoded_rr's rr_ts_ms lookups are still index-served after dropping
//     idx_decoded_rr_ts, which was a strict prefix of the (rr_ts_ms,
//     beat_index) unique index and only added write cost.
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

  test('the redundant single-column rr index is gone', () async {
    final db = await LocalDb.instance;
    final idx = (await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='decoded_rr'",
    )).map((r) => r['name'] as String?).whereType<String>().toList();
    expect(idx, isNot(contains('idx_decoded_rr_ts')));
    expect(idx, contains('idx_decoded_rr_ts_beat_unique'));
  });

  test('rr_ts_ms range scans are still served by an index', () async {
    final db = await LocalDb.instance;
    final plan = await db.rawQuery(
      'EXPLAIN QUERY PLAN SELECT * FROM decoded_rr WHERE rr_ts_ms < 1000 '
      'ORDER BY rr_ts_ms ASC, beat_index ASC',
    );
    final detail = plan.map((r) => r['detail'].toString()).join(' | ');
    expect(detail, contains('idx_decoded_rr_ts_beat_unique'),
        reason: 'planner fell back to a scan: $detail');
    expect(detail.toUpperCase(), isNot(contains('USE TEMP B-TREE')),
        reason: 'ordering should come from the index: $detail');
  });

  test('superseded intermediate generations are pruned, recent ones kept',
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
  });

  test('pruning is a no-op when there is nothing superseded', () async {
    expect(await LocalDb.pruneSupersededIntermediates(), 0);
  });
}
