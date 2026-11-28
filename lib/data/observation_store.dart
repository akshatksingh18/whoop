part of 'db.dart';

/// The write side of the `observation` table (vendor-computed, typed-in and
/// imported scalars), split out of [LocalDb] by concern. The DDL stays with the
/// schema ladder in [LocalDb].
abstract final class ObservationStore {
  /// Upsert observations. Idempotent on `(device_id, ts_ms, source_kind, name)`
  /// so re-running an import re-states rather than duplicates.
  ///
  /// `date` comes from [dayLabelOf] and nowhere else — the day model is LOCAL
  /// calendar days, and a label computed any other way is wrong for 23 h/25 h
  /// DST days and for every user whose local date differs from UTC's.
  ///
  /// There is deliberately NO reader here yet. Nothing writes observations
  /// either: the adapter seam that will is phase 4, and wiring an existing
  /// importer into this table today would move numbers users already see.
  static Future<int> putAll(
    List<Observation> rows, {
    String deviceId = LocalDb.kPrimaryDeviceId,
  }) async {
    if (rows.isEmpty) return 0;
    final db = await LocalDb.instance;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final o in rows) {
        batch.insert('observation', {
          'device_id': deviceId,
          'ts_ms': o.at.millisecondsSinceEpoch,
          'date': o.date,
          'source_kind': o.sourceKind.name,
          'vendor_key': o.vendorKey,
          'key': o.key,
          'value': o.value.toDouble(),
          'unit': o.unit,
          'attribution': o.attribution,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
    return rows.length;
  }

  /// One observation. [putAll] is the batch this delegates to.
  static Future<int> put(
    Observation o, {
    String deviceId = LocalDb.kPrimaryDeviceId,
  }) => putAll([o], deviceId: deviceId);
}
