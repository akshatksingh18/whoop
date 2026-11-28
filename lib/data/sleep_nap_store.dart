part of 'db.dart';

/// The `sleep_nap` table and its dirty/corrected markers, split out of
/// [LocalDb] by concern.
abstract final class SleepNapStore {
  /// sleep_nap — the user's edits to a day's naps.
  ///
  /// Separate from `sleep_override` on purpose: that table means "the main
  /// sleep window for this day", which is one thing, while naps are a list.
  /// Widening its primary key would have made "the main sleep" and "a nap"
  /// indistinguishable in storage.
  ///
  /// Edits are stored SEPARATELY from the detector's output and replayed over
  /// it on every derivation. The detector improves; a day re-derived under a
  /// better stager should still respect "there was no nap here", and baking
  /// the edit into the result would freeze the old detection alongside it.
  ///
  /// `source` is 'manual' (a nap the user logged) or 'rejected' (a detected
  /// one they removed — the window is stored so it keeps suppressing that nap
  /// even after the detector's bounds shift by a minute).
  static Future<void> _create(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sleep_nap (
        day_id TEXT NOT NULL,
        start_ts INTEGER NOT NULL,
        end_ts INTEGER NOT NULL,
        source TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        PRIMARY KEY (day_id, start_ts)
      )
    ''');
  }

  /// Log a nap the detector missed, or suppress one it invented.
  static Future<void> putEdit({
    required String dayId,
    required int startTs,
    required int endTs,
    required String source,
  }) async {
    final db = await LocalDb.instance;
    await db.insert('sleep_nap', {
      'day_id': dayId,
      'start_ts': startTs,
      'end_ts': endTs,
      'source': source,
      'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await MetricSeriesStore.putBaseline(
      'nap_dirty:$dayId',
      '${DateTime.now().microsecondsSinceEpoch}',
    );
    await MetricSeriesStore.putBaseline('nap_corrected:$dayId', '{}');
  }

  static Future<void> deleteEdit(String dayId, int startTs) async {
    final db = await LocalDb.instance;
    await db.delete(
      'sleep_nap',
      where: 'day_id = ? AND start_ts = ?',
      whereArgs: [dayId, startTs],
    );
    await MetricSeriesStore.putBaseline(
      'nap_dirty:$dayId',
      '${DateTime.now().microsecondsSinceEpoch}',
    );
    await MetricSeriesStore.putBaseline('nap_corrected:$dayId', '{}');
  }

  static Future<List<Map<String, dynamic>>> edits(String dayId) async {
    final db = await LocalDb.instance;
    return db.query(
      'sleep_nap',
      where: 'day_id = ?',
      whereArgs: [dayId],
      orderBy: 'start_ts ASC',
    );
  }

  /// Every day carrying a nap edit. Force-derived alongside the sleep-override
  /// days for the same reason: an edit to a finalized day has to take effect.
  static Future<Set<String>> editDays() async {
    final db = await LocalDb.instance;
    final rows = await db.query('sleep_nap', columns: ['day_id']);
    return {
      for (final r in rows) r['day_id'] as String,
      ...await pendingDays(),
    };
  }

  static Future<Set<String>> correctionDays() async {
    final db = await LocalDb.instance;
    final markers = await db.query(
      'baselines',
      columns: ['key'],
      where: 'key LIKE ?',
      whereArgs: ['nap_corrected:%'],
    );
    return {
      ...await editDays(),
      for (final r in markers)
        (r['key'] as String).substring('nap_corrected:'.length),
    };
  }

  static Future<Set<String>> pendingDays() async {
    final db = await LocalDb.instance;
    final rows = await db.query(
      'baselines',
      columns: ['key'],
      where: 'key LIKE ?',
      whereArgs: ['nap_dirty:%'],
    );
    return {
      for (final r in rows) (r['key'] as String).substring('nap_dirty:'.length),
    };
  }
}
