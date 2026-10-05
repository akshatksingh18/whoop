// Calculation anchors belong to the lossless database backup. Preferences are
// a synchronous cache for live timing; settings and secrets are not copied.
import 'package:shared_preferences/shared_preferences.dart';
import 'db.dart';

class CalculationStore {
  static const prefix = 'calculation:';
  static Future<String?> read(String key) async {
    final row = await LocalDb.baseline('$prefix$key');
    final p = await SharedPreferences.getInstance();
    final value = row?['payload_json'] as String? ?? p.getString(key);
    if (row == null && value != null) {
      await LocalDb.putBaseline('$prefix$key', value);
    }
    if (value != null && p.getString(key) != value) {
      await p.setString(key, value);
    }
    return value;
  }

  static Future<void> write(String key, String value) async {
    await LocalDb.putBaseline('$prefix$key', value);
    final p = await SharedPreferences.getInstance();
    if (!await p.setString(key, value)) {
      throw StateError('Calculation cache did not save');
    }
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
    final p = await SharedPreferences.getInstance();
    for (final row in rows) {
      await p.setString(
        (row['key'] as String).substring(prefix.length),
        row['payload_json'] as String,
      );
    }
  }
}
