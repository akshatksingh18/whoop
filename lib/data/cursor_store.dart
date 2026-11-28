part of 'db.dart';

/// The durable `sync_cursor` key/value store (resumable-sync positions and small
/// pinned values), split out of [LocalDb] by concern.
abstract final class CursorStore {
  /// Read a sync-cursor value (null if unset).
  static Future<String?> read(String name) async {
    final db = await LocalDb.instance;
    final rows = await db.query(
      'sync_cursor',
      columns: ['value'],
      where: 'name = ?',
      whereArgs: [name],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  static Future<int?> readInt(String name) async {
    final v = await read(name);
    return v == null ? null : int.tryParse(v);
  }

  /// Read a cursor int through a specific executor (used inside a transaction so
  /// the read shares the open txn instead of contending on the global handle).
  static Future<int?> _readIntVia(DatabaseExecutor ex, String name) async {
    final rows = await ex.query(
      'sync_cursor',
      columns: ['value'],
      where: 'name = ?',
      whereArgs: [name],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return int.tryParse(rows.first['value'] as String? ?? '');
  }

  /// Upsert a sync-cursor value. Caller may pass a [txn] so the cursor write
  /// shares the SAME transaction as the raw batch — keeping "persist raw then
  /// persist cursor" atomic before the band is ACKed.
  static Future<void> write(
    String name,
    String value, {
    DatabaseExecutor? txn,
  }) async {
    final ex = txn ?? await LocalDb.instance;
    await ex.insert('sync_cursor', {
      'name': name,
      'value': value,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
