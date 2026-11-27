// Moves the installed SQLite store from its old file name to the owned one.
//
// The copy is staged, checked and published by one rename, so an interruption
// at any point leaves either the untouched original or a complete published
// store. The original family is never merged into an existing store and never
// deleted: it is moved aside under a unique name for a later, separately
// approved retirement.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// What one store resolution found and did.
enum StoreMove {
  /// No store under either name: the current name starts empty.
  fresh,

  /// Only the current store exists.
  current,

  /// The original was copied, checked and published under the current name.
  migrated,

  /// The copy failed; this launch keeps using the original name.
  keptLegacy,

  /// Both names existed: the current store stays the authority and the
  /// original family was moved aside without merging.
  retainedLegacy,
}

typedef StoreResolution = ({
  /// The file name to open this launch.
  String name,
  StoreMove move,

  /// Where the original family now lives, or null when it was not moved.
  String? retainedAs,

  /// Why the copy or the move aside failed, or null.
  String? error,
});

abstract final class StoreMigration {
  /// The files SQLite keeps beside a main database file, journals first so a
  /// main file is never moved away from its write-ahead log.
  static const _journals = ['-wal', '-shm', '-journal'];

  /// Test seam for interruption and refusal: called at each named step.
  static Future<void> Function(String step)? debugStep;

  static Future<void> _step(String step) async => debugStep?.call(step);

  /// Decide which store file [dir] opens, migrating [legacy] to [current]
  /// when only the original exists.
  static Future<StoreResolution> resolve(
    String dir, {
    required String current,
    required String legacy,
  }) async {
    final cur = p.join(dir, current);
    final old = p.join(dir, legacy);
    final staging = '$cur.migrating';
    // A staging copy is never published, so a leftover is an interrupted
    // attempt whose original is still intact.
    await _deleteFamily(staging);
    final hasOld = File(old).existsSync();
    if (File(cur).existsSync()) {
      if (!hasOld) {
        return (
          name: current,
          move: StoreMove.current,
          retainedAs: null,
          error: null,
        );
      }
      final (aside, error) = await _moveAside(old, 'retained');
      return (
        name: current,
        move: StoreMove.retainedLegacy,
        retainedAs: aside,
        error: error,
      );
    }
    if (!hasOld) {
      return (
        name: current,
        move: StoreMove.fresh,
        retainedAs: null,
        error: null,
      );
    }
    try {
      await _copyChecked(old, staging);
      await _step('publish');
      await File(staging).rename(cur);
    } catch (e) {
      await _deleteFamily(staging);
      return (
        name: legacy,
        move: StoreMove.keptLegacy,
        retainedAs: null,
        error: '$e',
      );
    }
    final (aside, error) = await _moveAside(old, 'migrated');
    return (
      name: current,
      move: StoreMove.migrated,
      retainedAs: aside,
      error: error,
    );
  }

  /// A transactionally consistent copy of [from] (its WAL included) at [to],
  /// refused unless it passes SQLite's check with the same schema version and
  /// the same row count in every table.
  static Future<void> _copyChecked(String from, String to) async {
    final src = await openDatabase(from, singleInstance: false);
    try {
      final version = await _version(src);
      final counts = await _counts(src);
      await _step('copy');
      await src.execute('VACUUM INTO ?', [to]);
      final dst = await openDatabase(to, singleInstance: false);
      try {
        await _step('check');
        final check = await dst.rawQuery('PRAGMA quick_check');
        final copied = await _counts(dst);
        final same =
            check.length == 1 &&
            check.single.values.single == 'ok' &&
            await _version(dst) == version &&
            copied.length == counts.length &&
            counts.entries.every((e) => copied[e.key] == e.value);
        if (!same) {
          throw StateError('The copied store did not match the original.');
        }
      } finally {
        await dst.close();
      }
    } finally {
      await src.close();
    }
  }

  static Future<int?> _version(Database db) async =>
      Sqflite.firstIntValue(await db.rawQuery('PRAGMA user_version'));

  static Future<Map<String, int?>> _counts(Database db) async {
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' "
      "AND name NOT LIKE 'sqlite_%'",
    );
    return {
      for (final t in tables)
        t['name'] as String: Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM "${(t['name'] as String).replaceAll('"', '""')}"',
          ),
        ),
    };
  }

  /// Move the [main] family to a unique `<main>.<label>-<ms>` name, journals
  /// first and the main file last. A refused move puts back what already
  /// moved and reports why; the original then stays where it was. If putting
  /// it back is refused too, the report says so and nothing is deleted.
  static Future<(String?, String?)> _moveAside(
    String main,
    String label,
  ) async {
    final aside = '$main.$label-${DateTime.now().millisecondsSinceEpoch}';
    final moved = <String>[];
    try {
      for (final suffix in [..._journals, '']) {
        final f = File('$main$suffix');
        if (!f.existsSync()) continue;
        await _step('aside$suffix');
        await f.rename('$aside$suffix');
        moved.add(suffix);
      }
      return (aside, null);
    } catch (e) {
      try {
        for (final suffix in moved.reversed) {
          await _step('restore$suffix');
          await File('$aside$suffix').rename('$main$suffix');
        }
      } catch (restore) {
        return (null, '$e; putting the original back failed: $restore');
      }
      return (null, '$e');
    }
  }

  /// Delete a never-published staging family. A file that cannot be deleted
  /// stays: the copy into it then fails and the original keeps serving.
  static Future<void> _deleteFamily(String main) async {
    for (final suffix in ['', ..._journals]) {
      final f = File('$main$suffix');
      if (f.existsSync()) await f.delete().catchError((Object _) => f);
    }
  }
}
