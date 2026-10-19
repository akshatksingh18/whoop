// Derived-only SQL views (the CSV export reads them) — verify they CREATE
// and that json1 unnesting works.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:openstrap_edge/data/db.dart';

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.dbName = 'openstrap_coach_views_test.db';
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  tearDownAll(() async {
    await LocalDb.close();
  });

  test('views create + json1 unnest works', () async {
    final db = await LocalDb.instance; // onCreate builds tables + views

    // Seed derived data.
    await db.insert('metric_series', {'date': '2026-06-29', 'key': 'rhr', 'value': 55.0});
    await db.insert('metric_series', {'date': '2026-06-29', 'key': 'hrr_bpm', 'value': 31.0});
    await db.insert('day_result', {
      'day_id': '2026-06-29',
      'algo_version': 25,
      'payload_json': jsonEncode({
        'series': {
          'hr_curve': [
            {'t': 0, 'v': 60},
            {'t': 60, 'v': 62},
          ],
        },
      }),
      'window_json': '{}',
      'computed_at': 0,
      'finalized': 0,
      'rhr': 55.0,
    });

    // Views via the RW handle (json1 sanity).
    final daily = await db.rawQuery('SELECT resting_hr, hrr_bpm FROM v_daily');
    expect((daily.first['resting_hr'] as num).toInt(), 55);
    expect((daily.first['hrr_bpm'] as num).toInt(), 31);
    final series = await db.rawQuery(
        "SELECT t, v FROM v_series WHERE date='2026-06-29' AND series='hr_curve' ORDER BY t");
    expect(series.length, 2);
    expect((series.last['v'] as num).toInt(), 62);

  });
}
