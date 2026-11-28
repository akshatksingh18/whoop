part of 'db.dart';

/// The per-day sleep derive intermediates (`sleep_session_candidates` and
/// `wake_day_features`), split out of [LocalDb] by concern. Pruning and bulk
/// deletes stay with the shared housekeeping in [LocalDb].
abstract final class SleepIntermediateStore {
  static Future<Map<String, dynamic>?> candidate(
    String dayId,
    int algoVersion,
  ) async {
    final db = await LocalDb.instance;
    final rows = await db.query(
      'sleep_session_candidates',
      where: 'day_id = ? AND algo_version = ?',
      whereArgs: [dayId, algoVersion],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  static Future<bool> putCandidate({
    required String dayId,
    required int algoVersion,
    required String payloadJson,
    int? sleepIntentGeneration,
  }) async {
    final db = await LocalDb.instance;
    return db.transaction((txn) async {
      final intent = await SleepOverrideStore._correctionVia(txn, dayId);
      if ((intent?['generation'] as num?)?.toInt() != sleepIntentGeneration) {
        return false;
      }
      await txn.insert('sleep_session_candidates', {
        'day_id': dayId,
        'algo_version': algoVersion,
        'payload_json': payloadJson,
        'computed_at': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return true;
    });
  }

  static Future<Map<String, dynamic>?> wakeFeatures(
    String dayId, [
    int? algoVersion,
  ]) async {
    final db = await LocalDb.instance;
    final rows = await db.query(
      'wake_day_features',
      where: algoVersion == null
          ? 'day_id = ?'
          : 'day_id = ? AND algo_version = ?',
      whereArgs: algoVersion == null ? [dayId] : [dayId, algoVersion],
      orderBy: algoVersion == null ? 'algo_version DESC' : null,
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  static Future<void> putWakeFeatures({
    required String dayId,
    required int algoVersion,
    required String payloadJson,
  }) async {
    final db = await LocalDb.instance;
    await db.insert('wake_day_features', {
      'day_id': dayId,
      'algo_version': algoVersion,
      'payload_json': payloadJson,
      'computed_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
