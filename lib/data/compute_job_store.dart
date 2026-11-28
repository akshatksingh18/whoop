part of 'db.dart';

/// The durable `compute_jobs` queue (enqueue, claim, requeue, complete, fail and
/// crash recovery), split out of [LocalDb] by concern.
abstract final class ComputeJobStore {
  static Future<List<Map<String, dynamic>>> jobs({
    String? state,
    int limit = 50,
  }) async {
    final db = await LocalDb.instance;
    return db.query(
      'compute_jobs',
      where: state == null ? null : 'state = ?',
      whereArgs: state == null ? null : [state],
      orderBy: 'priority DESC, updated_at ASC',
      limit: limit,
    );
  }

  static Future<void> recover() async {
    final db = await LocalDb.instance;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.update(
      'compute_jobs',
      {'state': 'queued', 'updated_at': now},
      where: 'state = ?',
      whereArgs: ['running'],
    );
  }

  static Future<void> enqueueDerive({
    required String type,
    required String reason,
  }) async {
    final db = await LocalDb.instance;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      final active = await txn.query(
        'compute_jobs',
        columns: ['id', 'type', 'state'],
        where: 'scope = ? AND state IN (?, ?)',
        whereArgs: ['derive', 'queued', 'running'],
      );
      bool hasType(String t) =>
          active.any((row) => row['type']?.toString() == t);
      if (type == 'derive_light') {
        if (hasType('derive_light') || hasType('derive_heavy')) return;
      } else if (type == 'derive_heavy') {
        if (hasType('derive_heavy')) return;
        await txn.delete(
          'compute_jobs',
          where: 'scope = ? AND state = ? AND type = ?',
          whereArgs: ['derive', 'queued', 'derive_light'],
        );
      }
      await txn.insert('compute_jobs', {
        'id': 'derive_${type}_$now',
        'type': type,
        'scope': 'derive',
        'priority': type == 'derive_heavy' ? 200 : 100,
        'state': 'queued',
        'reason': reason,
        'depends_on': null,
        'input_from_ts': null,
        'input_to_ts': null,
        'algo_version': null,
        'attempts': 0,
        'next_run_at': null,
        'created_at': now,
        'updated_at': now,
      });
    });
  }

  static Future<Map<String, dynamic>?> takeNext() async {
    final db = await LocalDb.instance;
    return db.transaction((txn) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final rows = await txn.rawQuery(
        'SELECT * FROM compute_jobs '
        'WHERE state = ? AND (next_run_at IS NULL OR next_run_at <= ?) '
        'ORDER BY priority DESC, updated_at ASC, created_at ASC '
        'LIMIT 1',
        ['queued', now],
      );
      if (rows.isEmpty) return null;
      final row = rows.first;
      await txn.update(
        'compute_jobs',
        {
          'state': 'running',
          'attempts': ((row['attempts'] as num?)?.toInt() ?? 0) + 1,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [row['id']],
      );
      return {...row, 'state': 'running', 'updated_at': now};
    });
  }

  /// Put a claimed job back on the queue without counting it as an attempt.
  ///
  /// Used when a gate closes DURING acquisition: `_drain()` clears the gate,
  /// awaits [takeNext], and by the time that returns a workout may
  /// have started. The job is already marked `running`, so it has to be handed
  /// back explicitly or it sits claimed until the next [recover].
  /// The attempt increment is undone too — being deferred is not a failure.
  static Future<void> requeue(String id) async {
    final db = await LocalDb.instance;
    await db.rawUpdate(
      'UPDATE compute_jobs SET state = ?, '
      'attempts = MAX(attempts - 1, 0), updated_at = ? WHERE id = ?',
      ['queued', DateTime.now().millisecondsSinceEpoch, id],
    );
  }

  static Future<void> complete(String id) async {
    final db = await LocalDb.instance;
    await db.delete('compute_jobs', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> fail(String id, String error) async {
    final db = await LocalDb.instance;
    await db.update(
      'compute_jobs',
      {
        'state': 'failed',
        'reason': error,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
