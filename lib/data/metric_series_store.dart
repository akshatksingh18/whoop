part of 'db.dart';

/// The canonical `metric_series` (date, key) scalars and the persisted `baselines`
/// (rolling, cross-day and the frozen movement floor), split out of [LocalDb] by
/// concern.
abstract final class MetricSeriesStore {
  /// Single metric_series value for one (date, key), or null.
  static Future<double?> valueOn(String date, String key) async {
    final db = await LocalDb.instance;
    final rows = await db.query(
      'metric_series',
      where: 'date = ? AND key = ?',
      whereArgs: [date, key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return (rows.first['value'] as num?)?.toDouble();
  }

  /// The FROZEN personal movement floor (g, dynAmp units) + when it was frozen.
  ///
  /// Persisted rather than recomputed because a floor that keeps tracking the
  /// user cancels the trend it exists to report — see the derivation-engine
  /// comment for the measured before/after. Returns null until enrollment
  /// completes, which is the estimator's signal to abstain.
  static Future<({double floorG, String frozenOn, int days})?>
  movementFloor() async {
    final row = await baseline('movement_floor');
    final raw = row?['payload_json'];
    if (raw is! String || raw.isEmpty) return null;
    try {
      final d = jsonDecode(raw);
      if (d is! Map) return null;
      final f = (d['floor_g'] as num?)?.toDouble();
      final on = d['frozen_on'] as String?;
      if (f == null || !f.isFinite || f <= 0 || on == null) return null;
      return (floorG: f, frozenOn: on, days: (d['days'] as num?)?.toInt() ?? 0);
    } catch (_) {
      return null;
    }
  }

  static Future<void> putMovementFloor({
    required double floorG,
    required String frozenOn,
    required int days,
  }) => putBaseline(
    'movement_floor',
    jsonEncode({'floor_g': floorG, 'frozen_on': frozenOn, 'days': days}),
  );

  /// Write ONE (date, key) scalar into the canonical series store.
  ///
  /// The bulk path is [putDayResult]'s `series` map, which writes a whole day's
  /// scalars alongside its bundle. This is for the case where a series row has
  /// to be corrected on its own — a day whose bundle is gone but whose trend
  /// point is still on screen (see `strain_backfill.dart`).
  static Future<void> putValue(String date, String key, double? value) async {
    final db = await LocalDb.instance;
    await db.insert('metric_series', {
      'date': date,
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// A long-format metric series (oldest first) for trends/sparklines.
  ///
  /// [measuredOnly] drops days another vendor's export wrote (see
  /// [DayProvenanceStore.importedDates]). OFF by default: a trend line is a
  /// picture of the user's history and imported days belong in it. Turn it ON
  /// for anything that COMPUTES against the series — a baseline, a personal
  /// percentile, a seed-versus-band comparison — where a foreign algorithm's
  /// output is not the same measurement.
  static Future<List<Map<String, dynamic>>> series(
    String key, {
    int? limit,
    bool measuredOnly = false,
  }) async {
    final db = await LocalDb.instance;
    return db.query(
      'metric_series',
      where:
          'key = ? AND value IS NOT NULL'
          '${measuredOnly ? ' AND date NOT IN (${DayProvenanceStore._importedDatesSql})' : ''}',
      whereArgs: [key],
      orderBy: 'date ASC',
      limit: limit,
    );
  }

  /// The TRAILING [n] non-null values for [key] — the newest n days, returned
  /// oldest→newest. Unlike [series] (which is `date ASC LIMIT n`, i.e. the
  /// OLDEST n days), this is the right window for a rolling baseline. Because
  /// metric_series is keyed `(date, key)` with REPLACE, there is exactly one row
  /// per day, so the result is inherently de-duplicated.
  ///
  /// [measuredOnly] defaults ON here, unlike [series]: this helper exists to
  /// build a rolling baseline, and a baseline blended with another vendor's
  /// derived numbers is not a baseline of this person (see
  /// [DayProvenanceStore.importedDates]).
  static Future<List<double>> trailingValues(
    String key,
    int n, {
    bool measuredOnly = true,
  }) async {
    final db = await LocalDb.instance;
    final rows = await db.rawQuery(
      'SELECT value FROM metric_series '
      'WHERE key = ? AND value IS NOT NULL '
      '${measuredOnly ? 'AND date NOT IN (${DayProvenanceStore._importedDatesSql}) ' : ''}'
      'ORDER BY date DESC LIMIT ?',
      [key, n],
    );
    return [for (final r in rows.reversed) (r['value'] as num).toDouble()];
  }

  static Future<Map<String, dynamic>?> baseline(String key) async {
    final db = await LocalDb.instance;
    final rows = await db.query(
      'baselines',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  static Future<bool> putBaseline(
    String key,
    String payloadJson, {
    int? sleepRevision,
  }) async {
    final db = await LocalDb.instance;
    return db.transaction((txn) async {
      if (SleepOverrideStore._correctionArtifacts.contains(key) &&
          (await CursorStore._readIntVia(txn, 'sleep_correction_revision') ??
                  0) !=
              (sleepRevision ?? 0)) {
        return false;
      }
      await txn.insert('baselines', {
        'key': key,
        'payload_json': payloadJson,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return true;
    });
  }

  /// Atomically read-modify-write one `baselines` row.
  ///
  /// [transform] receives the current `payload_json` (null when the row does
  /// not exist) and returns the replacement, or null to leave the row alone.
  ///
  /// Needed because a Dart-level lock CANNOT serialize this. Derivation runs in
  /// more than one isolate — a background worker constructs its own
  /// `DerivationEngine` — and a `static`
  /// mutex has one copy per isolate. Two isolates would each read the same
  /// payload, merge into it, and write back, dropping the other's changes.
  /// That matters most for accumulator payloads like `sleep_user_profile`,
  /// where a lost write also loses the record of
  /// which days were already folded.
  ///
  /// `exclusive: true` issues BEGIN IMMEDIATE, taking SQLite's write lock up
  /// front rather than on first write. Without it a deferred transaction that
  /// reads and then writes can fail to upgrade under WAL when another
  /// connection holds the write lock. The lock is cross-connection and
  /// therefore cross-isolate, which is exactly the guarantee a Dart static
  /// cannot give.
  static Future<void> updateBaseline(
    String key,
    String? Function(String? current) transform, {
    String? sleepDayId,
    int? sleepIntentGeneration,
  }) async {
    final db = await LocalDb.instance;
    await db.transaction((txn) async {
      if (sleepDayId != null) {
        final intent = await SleepOverrideStore._correctionVia(txn, sleepDayId);
        if ((intent?['generation'] as num?)?.toInt() != sleepIntentGeneration) {
          return;
        }
      }
      final rows = await txn.query(
        'baselines',
        columns: ['payload_json'],
        where: 'key = ?',
        whereArgs: [key],
        limit: 1,
      );
      final current = rows.isEmpty
          ? null
          : rows.first['payload_json'] as String?;
      final next = transform(current);
      if (next == null) return;
      await txn.insert('baselines', {
        'key': key,
        'payload_json': next,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }, exclusive: true);
  }
}
