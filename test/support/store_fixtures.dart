import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/journal_fields.dart';

/// Sets one day's stored numeric journal fields to exactly [fields], in one
/// transaction: a fixture for a day's state, or for a write that lands from
/// elsewhere while an editor is open. The app writes through
/// `JournalStore.saveEdit`.
Future<void> seedJournalMetrics(
  String date,
  Map<String, JournalMetricValue> fields,
) async {
  final db = await LocalDb.instance;
  final now = DateTime.now().millisecondsSinceEpoch;
  await db.transaction((txn) async {
    await txn.delete('journal_metric', where: 'date = ?', whereArgs: [date]);
    for (final e in fields.entries) {
      await txn.insert('journal_metric', {
        'date': date,
        'field': e.key,
        'value': e.value.value,
        'at_min': e.value.atMinuteOfDay,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  });
}

/// A stored cycle-log marker, as the retired cycle tracker wrote it; the app
/// still reads the table.
Future<void> seedCycleLog(String date, String kind) async {
  final db = await LocalDb.instance;
  await db.insert('cycle_log', {
    'date': date,
    'kind': kind,
  }, conflictAlgorithm: ConflictAlgorithm.replace);
}

/// The archived undecodable records: their count and their count per reason.
Future<({int count, Map<String, int> byReason})> rawArchiveCounts() async {
  final db = await LocalDb.instance;
  final rows = await db.rawQuery(
    'SELECT reason, COUNT(*) AS n FROM raw_archive GROUP BY reason',
  );
  final byReason = {
    for (final r in rows) (r['reason'] as String? ?? 'unknown'): r['n'] as int,
  };
  return (count: byReason.values.fold(0, (a, b) => a + b), byReason: byReason);
}

/// Every sync-ledger row, oldest first.
Future<List<Map<String, Object?>>> syncLedgerRows() async =>
    (await LocalDb.instance).query('sync_ledger', orderBy: 'created_at ASC');

/// Every quarantined sync chunk, newest first.
Future<List<Map<String, Object?>>> quarantineRows() async =>
    (await LocalDb.instance).query(
      'sync_quarantine',
      orderBy: 'created_at DESC',
    );

/// One session's stored splits, in kilometre order.
Future<List<Map<String, Object?>>> splitRows(String sessionId) async =>
    (await LocalDb.instance).query(
      'workout_split',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'km ASC',
    );
