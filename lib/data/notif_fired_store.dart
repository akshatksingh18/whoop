part of 'db.dart';

/// The `notif_fired` table, split out of [LocalDb] by concern. A `part` of
/// `db.dart` because its writes go through [LocalDb]'s guarded-write retry.
abstract final class NotifFiredStore {
  /// The cross-isolate fire-once claim ledger for notification dedupeKeys.
  ///
  /// SharedPreferences CANNOT enforce fire-once across isolates, however fresh
  /// its reads: a check and a record are two independent operations, so the
  /// foreground derive isolate and the WorkManager background derive isolate
  /// can both read "not fired" before either writes, and both alert. SQLite
  /// can: `INSERT OR IGNORE` against a PRIMARY KEY is ONE atomic statement, and
  /// writers are serialised (a single native handle per process, and SQLite's
  /// own write lock across handles), so for a given key exactly one caller ever
  /// observes `changes() == 1`. That caller owns the fire; everyone else backs
  /// off. See [claim] and lib/notify/fired_keys.dart.
  static Future<void> _create(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS notif_fired (
        key TEXT PRIMARY KEY,
        fired_at INTEGER NOT NULL
      )
    ''');
  }

  /// Atomically claim [key] for a one-time OS notification fire.
  ///
  /// Returns true iff THIS caller won the claim (the row did not exist and we
  /// inserted it). A concurrent claimant — in this isolate or the other
  /// derivation isolate — gets false and MUST NOT present.
  ///
  /// Throws if the claim can't be decided, deliberately: the caller falls back
  /// to the best-effort store rather than treating an unusable DB as "already
  /// fired", which would silently swallow every notification on the device.
  static Future<bool> claim(String key, {int? firedAtMs}) async {
    final now = firedAtMs ?? DateTime.now().millisecondsSinceEpoch;
    final won = await LocalDb._guardedWrite<bool>((db) async {
      return db.transaction<bool>((txn) async {
        await txn.rawInsert(
          'INSERT OR IGNORE INTO notif_fired(key, fired_at) VALUES(?, ?)',
          [key, now],
        );
        // changes() reports rows touched by the statement just executed on this
        // connection; inside the transaction that is unambiguously our INSERT.
        final n = Sqflite.firstIntValue(await txn.rawQuery('SELECT changes()'));
        return n == 1;
      });
    });
    // Not best-effort, so the guarded write returns its answer or throws.
    return won!;
  }

  /// Give back a claim taken by [claim] — used when the present did
  /// NOT actually happen (permission denied, OS error), so a later attempt can
  /// still fire. Best-effort: never throws into the notification path.
  static Future<void> release(String key) async {
    await LocalDb._guardedWrite<int>(
      (db) => db.delete('notif_fired', where: 'key = ?', whereArgs: [key]),
      bestEffort: true,
    );
  }

  /// Whether [key] has already been claimed (read-only; does not claim).
  static Future<bool> exists(String key) async {
    final db = await LocalDb.instance;
    final rows = await db.query(
      'notif_fired',
      columns: ['key'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Seed claims for [keys] without taking ownership — used once to carry the
  /// legacy SharedPreferences fired-key list over, so keys that already fired
  /// under the old store don't re-fire on the upgrade.
  static Future<void> seed(Iterable<String> keys, {int? firedAtMs}) async {
    if (keys.isEmpty) return;
    final now = firedAtMs ?? DateTime.now().millisecondsSinceEpoch;
    await LocalDb._guardedWrite<void>((db) async {
      final batch = db.batch();
      for (final k in keys) {
        batch.rawInsert(
          'INSERT OR IGNORE INTO notif_fired(key, fired_at) VALUES(?, ?)',
          [k, now],
        );
      }
      await batch.commit(noResult: true);
    }, bestEffort: true);
  }

  /// Drop dated claims whose leading "YYYY-MM-DD" is before [cutoffDate].
  ///
  /// Undated keys (e.g. `alarm_fired:<epoch>`) are left alone: they have no day
  /// to expire against, and they're rare enough to be self-limiting. Matches
  /// the retention semantics of the SharedPreferences fallback exactly.
  static Future<void> prune(String cutoffDate) async {
    await LocalDb._guardedWrite<int>(
      (db) => db.rawDelete(
        "DELETE FROM notif_fired "
        "WHERE substr(key, 1, 10) GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]' "
        "AND substr(key, 1, 10) < ?",
        [cutoffDate],
      ),
      bestEffort: true,
    );
  }
}
