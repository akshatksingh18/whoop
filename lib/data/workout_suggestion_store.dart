part of 'db.dart';

/// Opt-in `workout_suggestions` (auto-detected "did you work out?" rows), split
/// out of [LocalDb] by concern.
abstract final class WorkoutSuggestionStore {
  static Future<void> _create(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS workout_suggestions (
        id TEXT PRIMARY KEY,
        date TEXT NOT NULL,
        start_ts INTEGER NOT NULL,
        end_ts INTEGER NOT NULL,
        avg_bpm INTEGER,
        peak_bpm INTEGER,
        duration_min INTEGER,
        sport TEXT,
        dismissed INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      )
    ''');
  }

  /// Upsert an auto-detected workout suggestion (id = "$date:$startSec").
  static Future<void> put(Map<String, dynamic> row) async {
    final db = await LocalDb.instance;
    await db.insert(
      'workout_suggestions',
      row,
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// Active (not-yet-dismissed, not-yet-confirmed) suggestions, newest first.
  ///
  /// Build 90: a suggestion whose window overlaps any logged session — done
  /// or still live — is not active. The detector skips saved windows, but a
  /// derive that ran DURING a live workout (no end yet) could still file the
  /// workout's own effort as "spotted but not logged", and stopping the
  /// workout never retired it. Filtering here clears those, including rows
  /// already stored, for the list, the review screen and the notification.
  static Future<List<Map<String, dynamic>>> active() async {
    final db = await LocalDb.instance;
    return db.rawQuery(
      'SELECT w.* FROM workout_suggestions w '
      'WHERE w.dismissed = 0 AND NOT EXISTS ('
      '  SELECT 1 FROM sessions s '
      '  WHERE s.start_ts < w.end_ts '
      '    AND (s.end_ts IS NULL OR s.end_ts > w.start_ts)'
      ') '
      'ORDER BY w.start_ts DESC',
    );
  }

  static Future<void> dismiss(String id) async {
    final db = await LocalDb.instance;
    await db.update(
      'workout_suggestions',
      {'dismissed': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
