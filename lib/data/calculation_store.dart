// Calculation anchors belong to the lossless database backup. Preferences are
// a synchronous cache for live timing; settings and secrets are not copied.
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'db.dart';

class CalculationStore {
  static const prefix = 'calculation:';

  /// Commit configuration with the history it belongs to; refresh preference
  /// mirrors only after the encompassing transaction has committed.
  static Future<void> writeIn(
    DatabaseExecutor db,
    String key,
    String value,
  ) async {
    await db.insert('baselines', {
      'key': '$prefix$key',
      'payload_json': value,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<String?> read(String key) async {
    final row = await LocalDb.baseline('$prefix$key');
    String? cached;
    SharedPreferences? p;
    try {
      p = await SharedPreferences.getInstance();
      cached = p.getString(key);
    } catch (_) {}
    final value = row?['payload_json'] as String? ?? cached;
    if (row == null && value != null)
      await LocalDb.putBaseline('$prefix$key', value);
    if (value != null && p != null && cached != value) {
      try {
        await p.setString(key, value);
      } catch (_) {}
    }
    return value;
  }

  static Future<void> write(String key, String value) async {
    await LocalDb.putBaseline('$prefix$key', value);
    // The committed database is authoritative. A failed cache mirror must not
    // report a rolled-back history/configuration write or invite duplicates.
    try {
      await (await SharedPreferences.getInstance()).setString(key, value);
    } catch (_) {}
  }

  static Future<void> remove(String key) async {
    await (await LocalDb.instance).delete(
      'baselines',
      where: 'key = ?',
      whereArgs: ['$prefix$key'],
    );
    await (await SharedPreferences.getInstance()).remove(key);
  }

  static Future<void> clearCache() async {
    final p = await SharedPreferences.getInstance();
    for (final key
        in p
            .getKeys()
            .where(
              (k) =>
                  k == 'steps.goal_history' ||
                  k == 'profile.calculation_history' ||
                  k == 'streak.protection' ||
                  k.startsWith('lift.') ||
                  k.startsWith('workout.clock.') ||
                  k.startsWith('motion.') ||
                  k.startsWith('training.review.') ||
                  k.startsWith('notification.report.'),
            )
            .toList()) {
      await p.remove(key);
    }
  }

  static Future<void> hydrate() async {
    final rows = await (await LocalDb.instance).query(
      'baselines',
      columns: ['key', 'payload_json'],
      where: 'key LIKE ?',
      whereArgs: ['$prefix%'],
    );
    if (rows.isEmpty) {
      return; // Legacy database-only restores have no preference cache to populate.
    }
    try {
      final p = await SharedPreferences.getInstance();
      for (final row in rows) {
        await p.setString(
          (row['key'] as String).substring(prefix.length),
          row['payload_json'] as String,
        );
      }
    } catch (_) {
      /* Rebuilt from the database on the next open/read. */
    }
  }
}
