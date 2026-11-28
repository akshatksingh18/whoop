part of 'db.dart';

/// Read-only store summaries for the Diagnostics screen (raw-record stats and
/// schema health), split out of [LocalDb] by concern. It names the
/// `observation` table only to check that it exists; nothing computed reads it.
abstract final class DiagnosticsStore {
  /// Raw store summary: total rows, rec_ts span (real record time, sec, >0 only),
  /// per-packet_type counts, and the captured_at span (ms) for comparison.
  static Future<Map<String, dynamic>> rawStats() async {
    final db = await LocalDb.instance;
    final count =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM decoded_onehz'),
        ) ??
        0;
    final tsRow = (await db.rawQuery(
      'SELECT MIN(rec_ts) AS lo, MAX(rec_ts) AS hi FROM decoded_onehz WHERE rec_ts > 0',
    )).first;
    final decodedOneHz =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM decoded_onehz'),
        ) ??
        0;
    final decodedRr =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM decoded_rr'),
        ) ??
        0;
    final legacySamples =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM samples'),
        ) ??
        0;
    return {
      'count': count,
      'min_rec_ts': (tsRow['lo'] as num?)?.toInt(),
      'max_rec_ts': (tsRow['hi'] as num?)?.toInt(),
      'by_type': const <String, int>{},
      'min_captured_ms': null,
      'max_captured_ms': null,
      'decoded_onehz': decodedOneHz,
      'decoded_rr': decodedRr,
      'legacy_samples': legacySamples,
    };
  }

  static Future<Map<String, dynamic>> schemaHealth() async {
    final db = await LocalDb.instance;
    Future<bool> hasTable(String name) async {
      final rows = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
        [name],
      );
      return rows.isNotEmpty;
    }

    Future<Set<String>> cols(String table) async {
      final info = await db.rawQuery('PRAGMA table_info($table)');
      return {
        for (final c in info)
          if (c['name'] is String) c['name'] as String,
      };
    }

    final requiredTables = <String>[
      'samples',
      'decoded_onehz',
      'decoded_rr',
      'events',
      'band_events',
      'band_battery',
      'day_result',
      'metric_series',
      'baselines',
      'sessions',
      'journal',
      'journal_metric',
      'journal_field_def',
      'lab_result',
      'lab_marker_def',
      'breathing_session',
      'food_entry',
      'food_def',
      'meal_template',
      'body_weight',
      'body_weight_reading',
      'food_day_count',
      'day_zone',
      'zone_change',
      'live_coverage',
      'med_def',
      'med_dose',
      'cycle_log',
      'notifications',
      'sync_cursor',
      'sync_ledger',
      'sync_quarantine',
      'compute_freshness',
      'compute_jobs',
      'sleep_session_candidates',
      'wake_day_features',
      'live_coverage',
      'workout_route',
      'workout_split',
      'session_detail',
      'notif_fired',
      'metric_series_version',
      'band_backlog',
      'external_hr',
      'imported_measurement',
      'imported_workout',
      'observation',
      'device',
    ];

    final missingTables = <String>[];
    for (final table in requiredTables) {
      if (!await hasTable(table)) missingTables.add(table);
    }

    final sessionCols = await hasTable('sessions')
        ? await cols('sessions')
        : <String>{};
    final syncLedgerCols = await hasTable('sync_ledger')
        ? await cols('sync_ledger')
        : <String>{};

    final missingColumns = <String, List<String>>{};
    void expect(String table, Set<String> present, List<String> required) {
      final miss = [
        for (final c in required)
          if (!present.contains(c)) c,
      ];
      if (miss.isNotEmpty) missingColumns[table] = miss;
    }

    expect('sessions', sessionCols, [
      'id',
      'start_ts',
      'status',
      'steps',
      // The frozen trace: a build that lost these columns silently blanks the
      // chart half of every session older than the substrate window.
      'trace_json',
      'trace_samples',
    ]);
    expect('sync_ledger', syncLedgerCols, [
      'chunk_id',
      'kind',
      'status',
      'updated_at',
      'meta_json',
    ]);

    final integrity = await db.rawQuery('PRAGMA integrity_check');
    final integrityOk =
        integrity.isNotEmpty && integrity.first.values.first == 'ok';

    return {
      'ok': missingTables.isEmpty && missingColumns.isEmpty && integrityOk,
      'missing_tables': missingTables,
      'missing_columns': missingColumns,
      'integrity_ok': integrityOk,
    };
  }
}
