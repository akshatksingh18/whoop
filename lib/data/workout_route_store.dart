part of 'db.dart';

/// The `workout_route` GPS points and frozen `workout_split` kilometres,
/// split out of [LocalDb] by concern.
abstract final class WorkoutRouteStore {
  static Future<void> _create(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS workout_route (
        session_id TEXT NOT NULL,
        seq INTEGER NOT NULL,
        ts_ms INTEGER NOT NULL,
        lat REAL NOT NULL,
        lng REAL NOT NULL,
        alt REAL,
        accuracy REAL,
        PRIMARY KEY (session_id, seq)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_workout_route_session '
      'ON workout_route(session_id, seq)',
    );
  }

  /// workout_split — per-KILOMETRE splits, frozen at finalize (CV-01 / TS-07).
  ///
  /// WHY A TABLE AND NOT A QUERY. A split's `avg_hr` is computed on demand by
  /// joining the route against `decoded_onehz`, which is gone at ~3 days. So
  /// there is NO retroactive index here and never can be: this write is the
  /// whole gate, it is FORWARD-ONLY, and it produces its first honest chart
  /// 8-12 weeks after it ships. Nothing reads this table yet.
  ///
  /// `net_elev_m` is the elevation change over the WHOLE kilometre, not a
  /// per-point sum. GPS altitude error is tens of metres pointwise and there is
  /// no barometer in this stack, so a 1 m-deadband ascent total would be mostly
  /// noise; the net over a km is the only elevation figure the fix supports.
  /// NULL when any point in the split carried no altitude — never 0, which
  /// would read as "flat".
  ///
  /// Kilometres only. The UI also renders miles, but that is a display unit for
  /// the same route; a second stored copy of the same run in different bins is
  /// not a second measurement.
  static Future<void> _createSplit(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS workout_split (
        session_id TEXT NOT NULL,
        km INTEGER NOT NULL,
        meters REAL NOT NULL,
        duration_sec INTEGER NOT NULL,
        avg_hr REAL,
        net_elev_m REAL,
        PRIMARY KEY (session_id, km)
      )
    ''');
  }

  /// Additive: add the `speed` column (smoothed instantaneous m/s) to an
  /// existing workout_route table. Guarded — fresh installs get it from
  /// _create directly once that's updated; ALTER … ADD COLUMN
  /// throws if it's already there.
  static Future<void> _ensureSpeed(Database db) =>
      LocalDb._addColumnIfMissing(db, 'workout_route', 'speed', 'REAL');

  /// Replace the stored splits for one session (empty list clears them).
  /// INSERT OR REPLACE on (session_id, km), so a later pass over a fuller
  /// window overwrites rather than duplicating.
  static Future<void> putSplits(
    String sessionId,
    List<Map<String, Object?>> rows,
  ) async {
    final db = await LocalDb.instance;
    await db.transaction((txn) => _replaceSplits(txn, sessionId, rows));
  }

  static Future<void> _replaceSplits(
    DatabaseExecutor db,
    String sessionId,
    List<Map<String, Object?>> rows,
  ) async {
    await db.delete(
      'workout_split',
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
    for (final r in rows) {
      await db.insert('workout_split', {
        'session_id': sessionId,
        ...r,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  /// Append a batch of route rows (INSERT OR REPLACE — idempotent on
  /// (session_id, seq)). Each row is a [RoutePoint.toRow] map.
  static Future<void> appendPoints(
    String sessionId,
    List<Map<String, Object?>> rows,
  ) async {
    if (rows.isEmpty) return;
    final db = await LocalDb.instance;
    final batch = db.batch();
    for (final r in rows) {
      batch.insert(
        'workout_route',
        r,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// The `seq` a new recorder for [sessionId] must start at: one past the
  /// highest stored, or 0 for a session with no route yet.
  static Future<int> nextSeq(String sessionId) async {
    final db = await LocalDb.instance;
    final rows = await db.rawQuery(
      'SELECT MAX(seq) AS m FROM workout_route WHERE session_id = ?',
      [sessionId],
    );
    final m = rows.isEmpty ? null : (rows.first['m'] as num?)?.toInt();
    return m == null ? 0 : m + 1;
  }

  /// All route rows for a session, ordered by seq.
  static Future<List<Map<String, dynamic>>> points(String sessionId) async {
    final db = await LocalDb.instance;
    return db.query(
      'workout_route',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'seq ASC',
    );
  }

  /// True when a session has any recorded route points (cheap existence check).
  static Future<bool> hasRoute(String sessionId) async {
    final db = await LocalDb.instance;
    final rows = await db.rawQuery(
      'SELECT 1 FROM workout_route WHERE session_id = ? LIMIT 1',
      [sessionId],
    );
    return rows.isNotEmpty;
  }
}
