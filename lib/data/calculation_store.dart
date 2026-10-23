// Calculation anchors belong to the lossless database backup. Preferences are
// a synchronous cache for live timing; settings and secrets are not copied.
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'db.dart';
import '../state/prefs.dart';

class CalculationStore {
  static const prefix = 'calculation:';

  // A read may repair its cache: order it with removal so an older mirror
  // cannot land after deletion and migrate the removed value back on restart.
  // ponytail: one queue per isolate; split by key only if profiling shows
  // contention beyond the database's existing serialized work.
  static Future<void>? _tail;
  static Future<T> _serial<T>(Future<T> Function() action) async {
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    try {
      if (previous != null) await previous;
      return await action();
    } finally {
      // Release before the caller resumes, without retaining an idle future
      // created in a different scheduler zone (notably Flutter test clocks).
      if (identical(_tail, done.future)) _tail = null;
      done.complete();
    }
  }

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

  static Future<String?> read(String key) => _serial(() => _read(key));
  static Future<String?> _read(String key) async {
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

  static Future<void> write(String key, String value) =>
      _serial(() => _write(key, value));
  static Future<void> _write(String key, String value) async {
    await LocalDb.putBaseline('$prefix$key', value);
    // The committed database is authoritative. A failed cache mirror must not
    // report a rolled-back history/configuration write or invite duplicates.
    try {
      await (await SharedPreferences.getInstance()).setString(key, value);
    } catch (_) {}
  }

  static Future<void> remove(String key) => _serial(() async {
    // A refused cache deletion leaves the authoritative value available for
    // retry. Dropping the row first would allow read() to resurrect the cache.
    await Prefs.saveValues({key: null});
    await (await LocalDb.instance).delete(
      'baselines',
      where: 'key = ?',
      whereArgs: ['$prefix$key'],
    );
  });

  /// Keep deletion and mirror cleanup in the same ordering as reads that can
  /// heal a missing row. [afterWipe] may finish native/preference reset, but
  /// must not re-enter CalculationStore while this gate is held.
  static Future<T> resetWith<T>(
    Future<T> Function() deleteRows, {
    Future<void> Function()? afterWipe,
  }) => _serial(() async {
    final rows = await (await LocalDb.instance).query(
      'baselines',
      columns: ['key'],
      where: 'key LIKE ?',
      whereArgs: ['$prefix%'],
    );
    final keys = {
      for (final row in rows) (row['key'] as String).substring(prefix.length),
    };
    final result = await deleteRows();
    await _clearCache(additionalKeys: keys);
    await afterWipe?.call();
    return result;
  });

  static Future<void> clearCache() => _serial(_clearCache);
  static Future<void> _clearCache({
    Set<String> additionalKeys = const {},
  }) async {
    final p = await SharedPreferences.getInstance();
    final keys = p
        .getKeys()
        .where(
          (k) =>
              additionalKeys.contains(k) ||
              k == 'steps.goal_history' ||
              k == 'profile.calculation_history' ||
              k == 'streak.protection' ||
              k.startsWith('lift.') ||
              k.startsWith('workout.clock.') ||
              k.startsWith('motion.') ||
              k.startsWith('training.review.') ||
              k.startsWith('notification.report.'),
        )
        .toList();
    await Prefs.saveValues({for (final key in keys) key: null});
  }

  static Future<void> hydrate() => _serial(() async {
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
  });
}
