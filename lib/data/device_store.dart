part of 'db.dart';

/// The `device` table (the things that measure, one row each), split out of
/// [LocalDb] by concern. The DDL stays with the schema ladder in [LocalDb].
abstract final class DeviceStore {
  /// Record that [id] exists and was seen now. Every field except [id] is
  /// COALESCED, so a caller that only knows the remote id cannot blank out a
  /// label or an adapter another caller already established.
  ///
  /// [clearAdapterId] is the one deliberate exception, and it exists because
  /// COALESCE is wrong in exactly one case: this row is the PRIMARY band
  /// permanently (`id` is `''`), so pairing a DIFFERENT band reuses it, and a
  /// null [adapterId] would then leave the FORGOTTEN band's family on the new
  /// one. `PairedDevice.save` passes it when the remote id changed and the
  /// caller does not know the new band's family. It is ignored when
  /// [adapterId] is non-null — a caller that knows wins over one that clears.
  static Future<void> upsert({
    String id = LocalDb.kPrimaryDeviceId,
    String? adapterId,
    String? remoteId,
    String? label,
    String? tier,
    bool clearAdapterId = false,
  }) async {
    final db = await LocalDb.instance;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await db.insert('device', {
      'id': id,
      'adapter_id': adapterId,
      'remote_id': remoteId,
      'label': label,
      'tier': tier,
      'first_seen': now,
      'last_seen': now,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    // ONE flag decides both the placeholder and its argument. It is a local
    // and not the expression twice because the two must never disagree: a
    // statement whose `?` count differs from the argument list binds every
    // value one column to the left, which SQLite accepts silently.
    final blankAdapter = adapterId == null && clearAdapterId;
    await db.rawUpdate(
      'UPDATE device SET '
      '${blankAdapter ? 'adapter_id = NULL, ' : 'adapter_id = COALESCE(?, adapter_id), '}'
      'remote_id = COALESCE(?, remote_id), label = COALESCE(?, label), '
      'tier = COALESCE(?, tier), last_seen = ? WHERE id = ?',
      [if (!blankAdapter) adapterId, remoteId, label, tier, now, id],
    );
  }

  /// One device row, or null when this phone has never seen it.
  static Future<Map<String, Object?>?> row([
    String id = LocalDb.kPrimaryDeviceId,
  ]) async {
    final db = await LocalDb.instance;
    final r = await db.query('device', where: 'id = ?', whereArgs: [id]);
    return r.isEmpty ? null : r.first;
  }

  /// Forget one device. The MEASUREMENTS it wrote are untouched — "this
  /// removes the source, not the data", which is what the forget dialog
  /// promises and what `decoded_*` keeping its `device_id` makes possible.
  static Future<void> delete([String id = LocalDb.kPrimaryDeviceId]) async {
    final db = await LocalDb.instance;
    await db.delete('device', where: 'id = ?', whereArgs: [id]);
  }
}
