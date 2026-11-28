part of 'db.dart';

/// Retention and space reclamation: pruning decoded rows past the retention
/// cutoff, superseded derive intermediates, and the freelist-gated VACUUM,
/// split out of [LocalDb] by concern.
abstract final class StorageRetentionStore {
  /// Delete decoded substrate / structured band signals / events whose RECORD
  /// TIME (epoch seconds) is strictly before [cutoffSec].
  static Future<int> pruneDecodedBefore(int cutoffSec) async {
    final db = await LocalDb.instance;
    // `deleted` used to just stay 0 forever - none of the txn.delete() calls'
    // return values (rows actually deleted) were ever added to it, so the
    // caller's `if (deleted > 0) log(...)` never fired even on a real prune.
    int deleted = 0;
    await db.transaction((txn) async {
      // decoded_rr shares the rec_ts key, so a plain rec_ts range delete covers
      // every beat in the window — no counter subquery, no orphan sweep (there
      // are no counter-orphans once parent and child are keyed the same way).
      deleted += await txn.delete(
        'decoded_rr',
        where: 'rec_ts < ?',
        whereArgs: [cutoffSec],
      );
      deleted += await txn.delete(
        'decoded_onehz',
        where: 'rec_ts < ?',
        whereArgs: [cutoffSec],
      );
      deleted += await txn.delete(
        'samples',
        where: 'ts < ?',
        whereArgs: [cutoffSec],
      );
      deleted += await txn.delete(
        'events',
        where: 'ts < ?',
        whereArgs: [cutoffSec],
      );
      // band_events keeps its WEAR AND CHARGE TRANSITIONS forever; everything
      // else in it goes at the cutoff. `detectNaps` rejects bouts that overlap
      // an off-wrist or on-charger span, and those spans are built by
      // `StepCoverageStore._toggleSpans` out of exactly these four ids — so
      // with them pruned at 3 days, any re-derive of an older day ran the nap
      // detector with BOTH rejection lists empty and a charging session on the
      // desk could score as a nap. Nap history rewrote itself, quietly, just
      // for being looked at.
      //
      // Same shape as the band_battery exemption below (a 3-day cap
      // structurally destroys a lifetime series), and the same size argument:
      // on the three real exports these four ids are 87, 22 and 12 rows across
      // 8 to 11 days — a few thousand a year. Event 33 alone is ~1900 A DAY,
      // which is why the exemption is four ids and not the whole table.
      deleted += await txn.delete(
        'band_events',
        where: 'ts < ? AND event_id NOT IN (?, ?, ?, ?)',
        whereArgs: [
          cutoffSec,
          proto.EventId.chargingOn,
          proto.EventId.chargingOff,
          proto.EventId.wristOn,
          proto.EventId.wristOff,
        ],
      );
      // THE UNDECODABLE ARCHIVE IS THINNED, NOT KEPT WHOLE. See
      // [thinRawArchiveBefore] — this is the only caller, so the archive is
      // capped by the same retention pass that caps the substrate.
      deleted += await LocalDb._thinRawArchiveVia(txn, cutoffSec * 1000);
      // band_battery is NOT pruned here. It was, at the 3-day substrate cutoff,
      // which structurally capped the battery-health series at 3 days — while
      // batteryHealth() reports `charge_cycles` (rising 0→1 charging edges) and
      // `full_charge_mv` (rolling max mV while charging), both of which only
      // mean anything across the life of the pack. A year-old band would have
      // reported 1 cycle. Six narrow columns a few minutes apart is not a
      // storage problem; the 1 Hz substrate is.
      // ponytail: unbounded, so give it its own multi-year cutoff if a real
      // install's table ever shows up big.
    });
    return deleted;
  }

  /// Bytes SQLite is holding in the free page list — deleted, reusable, and
  /// invisible to the user, who sees only the file size.
  static Future<int> freelistBytes() async {
    final db = await LocalDb.instance;
    final free =
        Sqflite.firstIntValue(await db.rawQuery('PRAGMA freelist_count')) ?? 0;
    final pageSize =
        Sqflite.firstIntValue(await db.rawQuery('PRAGMA page_size')) ?? 4096;
    return free * pageSize;
  }

  /// Return free pages to the FILESYSTEM when there are enough of them to be
  /// worth a full rewrite. Returns the bytes reclaimed, or 0 if it declined.
  ///
  /// A delete only moves pages to the freelist; the file never shrinks below
  /// its all-time high-water mark. That is normally fine — the freelist is
  /// reused by the next day's ingest, so steady state is bounded — but two
  /// things put a permanent step in the mark: an install that let the substrate
  /// backlog build before the retention prune ran on every derive, and the v39
  /// migrations, each of which builds a full shadow copy of `decoded_onehz`
  /// before dropping the original. A 170 MB file stays 170 MB forever.
  ///
  /// WHY A FULL `VACUUM` AND NOT `auto_vacuum`:
  ///   * `auto_vacuum` cannot be turned on for an existing database without a
  ///     full `VACUUM` anyway, so it does not avoid this cost — it adds to it.
  ///   * `auto_vacuum=FULL` moves pages on EVERY commit, on a store taking
  ///     ~86 400 inserts a day. `INCREMENTAL` is cheaper but still adds
  ///     pointer-map pages to every write.
  ///   * Both would tax the hottest write path in the app, forever, to fix
  ///     something that happens once.
  ///
  /// A full `VACUUM` rewrites the whole file under an exclusive lock and needs
  /// roughly twice the file size free on disk, so it must NEVER run on the
  /// sync/ACK path, during a live session, or in the background. That gating is
  /// the caller's job — see `AppState._maybeReclaimDiskSpace`, which runs it
  /// only on a foreground heavy derive with nothing else in flight.
  static Future<int> vacuumIfBloated({int minFreeBytes = 64 << 20}) async {
    final free = await freelistBytes();
    if (free < minFreeBytes) return 0;
    final db = await LocalDb.instance;
    await db.execute('VACUUM');
    return free;
  }

  /// Drop recomputable per-day intermediates left behind by superseded
  /// algorithm versions.
  ///
  /// `sleep_session_candidates` and `wake_day_features` are keyed
  /// (day_id, algo_version), so every kAlgoVersion bump writes a whole new
  /// generation beside the old one and nothing ever removed the old one — the
  /// tables grow without bound across releases. Neither is durable ledger:
  /// both are derived from `decoded_*` and rewritten whenever a day is
  /// re-derived.
  ///
  /// [keepVersions] generations are retained per day_id, newest first.
  /// Keeping more than one matters: a user on a GitHub release can roll back
  /// to the previous build, and pruning down to only the current version
  /// would leave that build with nothing to read for a day it never
  /// re-derives (raw retention is 3 days; a day older than that only gets a
  /// fresh-version row if something forces a re-derive).
  ///
  /// Scoped PER day_id, not table-wide. A table-wide "keep the 2 highest
  /// versions present ANYWHERE" cutoff deletes a day's only cached
  /// generation the moment any two OTHER days reach newer versions — not
  /// when this day does — because a day whose raw substrate has already
  /// aged out never re-enters the derive pipeline to write a newer row of
  /// its own. That silently orphaned still-needed rows for days that can
  /// never be re-derived.
  static Future<int> pruneSupersededIntermediates({
    int keepVersions = 2,
  }) async {
    if (keepVersions < 1) return 0;
    final db = await LocalDb.instance;
    var deleted = 0;
    for (final table in const [
      'sleep_session_candidates',
      'wake_day_features',
    ]) {
      final rows = await db.rawQuery(
        'SELECT DISTINCT day_id, algo_version FROM $table',
      );
      final versionsByDay = <String, List<int>>{};
      for (final r in rows) {
        final day = r['day_id'] as String;
        final v = r['algo_version'] as int;
        (versionsByDay[day] ??= <int>[]).add(v);
      }
      // One transaction per table instead of one round-trip per day_id —
      // right after a kAlgoVersion bump forces a bulk re-derive (or a user
      // runs "Re-analyze data"), many days can cross the keepVersions
      // threshold in the same pass, and un-batched deletes on iOS run under
      // the same CPU-watchdog constraint the rest of derivation is careful
      // about.
      await db.transaction((txn) async {
        for (final entry in versionsByDay.entries) {
          final versions = entry.value..sort((a, b) => b.compareTo(a));
          if (versions.length <= keepVersions) continue;
          final cutoff = versions[keepVersions - 1];
          deleted += await txn.delete(
            table,
            where: 'day_id = ? AND algo_version < ?',
            whereArgs: [entry.key, cutoff],
          );
        }
      });
    }
    return deleted;
  }
}
