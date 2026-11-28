part of 'db.dart';

/// Restoring another device's exported database (plain or gzipped) by merging
/// its rows into this one, split out of [LocalDb] by concern.
abstract final class BackupImportStore {
  /// Import another device's exported WHOOP DB ([path], from [exportCopy] +
  /// share) by MERGING its rows into this one (INSERT-OR-REPLACE). Covers derived
  /// results, the metric series, user data, and the raw ledger so the receiving
  /// device has the full history (and can re-derive). Same app ⇒ same schema; a
  /// table missing in the source is skipped. Locally FINALIZED day_result rows
  /// are protected — an import never overwrites them. Returns per-table counts
  /// of rows actually copied.
  ///
  /// The picked file may be COMPRESSED. Auto-backups are written gzipped, so
  /// the file a user reinstalling onto a new phone reaches for is a `.db.gz`,
  /// and handing that straight to `openDatabase` fails with "file is not a
  /// database" — the app could write backups it could not restore. Detected by
  /// MAGIC BYTES, not by extension: a file manager or a sync client that
  /// renames on the way through is exactly the situation a restore has to
  /// survive. Plain `.db` files (older backups, and `exportCopy` output) take
  /// the same path they always did.
  static Future<Map<String, int>> importFromFile(String path) async {
    final resetGeneration = LocalDb._restoreResetGeneration;
    if (!LocalDb._restoreStillCurrent(resetGeneration)) {
      throw DbImportException(LocalDb._restoreResetError, const {});
    }
    if (!await File(path).exists()) {
      throw const FileSystemException('Backup file not found');
    }
    if (await sniffFile(path) != ImportContainer.gzip) {
      return _mergeFromDbFile(path, resetGeneration: resetGeneration);
    }
    final work = await Directory.systemTemp.createTemp('whoop_restore_');
    try {
      final inflated = await inflateGzip(path, work);
      if (inflated == null ||
          await sniffFile(inflated) != ImportContainer.sqlite) {
        throw const ImportFormatException(
          'That file unpacked to something that is not a $kAppName database.',
        );
      }
      return await _mergeFromDbFile(inflated, resetGeneration: resetGeneration);
    } finally {
      // The inflated copy is a full second copy of the database, so it goes
      // whether the import worked or not.
      try {
        if (work.existsSync()) await work.delete(recursive: true);
      } catch (_) {
        /* the OS reclaims the temp dir eventually */
      }
    }
  }

  /// Merge every table [tables] names from the database file at [path] into
  /// this one.
  ///
  /// [only] overrides the table list and its ORDER — used by [_openOrRebuild],
  /// which wants the irreplaceable tables first. [tolerant] isolates each table
  /// behind its own catch: a rebuild salvaging a genuinely damaged file must
  /// lose that table and keep going, where a user-initiated restore of a file
  /// they chose must still fail loudly rather than report a partial success.
  static Future<Map<String, int>> _mergeFromDbFile(
    String path, {
    List<String>? only,
    bool tolerant = false,
    int? resetGeneration,
  }) async {
    final restoreGeneration =
        resetGeneration ?? LocalDb._restoreResetGeneration;
    if (!LocalDb._restoreStillCurrent(restoreGeneration)) {
      throw DbImportException(LocalDb._restoreResetError, const {});
    }
    final src = await openDatabase(path, readOnly: true);
    final db = await LocalDb.instance;
    const tables = LocalDb._importTables;
    // Columns this app's schema actually has, per table — so a row from a NEWER
    // export carrying extra columns this build doesn't know about is filtered
    // down (dropped) instead of throwing "no such column". A column the source
    // LACKS simply isn't in the map → the dest default applies. Forward- and
    // backward-compatible across schema versions.
    Future<Set<String>> destCols(String t) async {
      final info = await db.rawQuery('PRAGMA table_info($t)');
      return {for (final c in info) (c['name'] as String)};
    }

    final counts = <String, int>{};
    final sourceReadingDates = <String>{};
    Object? mergeError;
    // DISTINCT DAYS ACTUALLY WRITTEN — the number the caller reports as
    // "N days imported".
    //
    // `day_result`'s primary key is (day_id, algo_version), so a row count is
    // not a day count: a history that has lived through two algo bumps has two
    // rows for the same day. This used to be a COUNT(DISTINCT day_id) asked of
    // the SOURCE before anything was copied, which over-reported the other way
    // — a re-import where every local row is finalized (all skipped by the
    // protectedKeys guard below) still claimed the full source day count. Stays
    // null when day_result could not be read at all, so the caller can tell
    // "nothing imported" from "we don't know".
    Set<String>? importedDays;
    // The days this phone already finalized, read BEFORE anything merges: a
    // protected day keeps its chart values and their provenance as well as
    // its bundle, so Today, Trends and the baselines stay in agreement with
    // it (Build 94, Codex N06).
    final finalizedDays = <String>{};
    try {
      for (final r in await db.query(
        'day_result',
        columns: ['day_id'],
        where: 'finalized = 1',
      )) {
        if (r['day_id'] is String) finalizedDays.add(r['day_id'] as String);
      }
    } catch (_) {
      /* no day_result yet: nothing to protect */
    }
    try {
      var expectedSleepRevision = await SleepOverrideStore.correctionRevision();
      await _checkSleepCorrectionImport(db, src);
      if ((await src.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='body_weight_reading'",
      )).isNotEmpty) {
        sourceReadingDates.addAll([
          for (final r in await src.rawQuery(
            'SELECT DISTINCT date FROM body_weight_reading',
          ))
            r['date'] as String,
        ]);
      }

      for (final t in (only ?? tables)) {
        try {
          // PAGED SOURCE READ — never `SELECT *` a whole table.
          //
          // This used to be a single `src.query(t)`. sqflite serialises an entire
          // result set into Java objects on the platform side BEFORE any of it
          // crosses the channel, so importing another device's `decoded_onehz`
          // (86,400 rows per day of history) materialised the whole table on the
          // 256 MB Dalvik heap at once — and then held it live for the duration
          // of the insert loop below. That is the production
          // `java.lang.OutOfMemoryError` seen on 0.9.19 from ImportScreen
          // ("target footprint 268435456, growth limit 268435456"); the OOM
          // surfaced on whichever thread happened to allocate next, which is why
          // it was blamed on a BLE binder callback.
          //
          // Keyset pagination on `rowid` (none of these tables is WITHOUT ROWID),
          // NOT LIMIT/OFFSET — OFFSET re-scans the skipped prefix on every page,
          // which is quadratic over a full history.
          // `_rowid` is aliased into the projection so the cursor can advance;
          // it is filtered straight back out when the row is rebuilt below,
          // because the `cols.contains(e.key)` guard only admits real
          // destination columns and no table has a column by that name.
          const pageSize = 2000;
          const rowidKey = '_rowid';
          var lastRowid = 0;
          Future<List<Map<String, Object?>>> nextPage() => src.rawQuery(
            'SELECT rowid AS $rowidKey, * FROM $t '
            'WHERE rowid > ? ORDER BY rowid ASC LIMIT ?',
            [lastRowid, pageSize],
          );

          List<Map<String, Object?>> firstPage;
          try {
            firstPage = await nextPage();
          } on DatabaseException catch (e) {
            // ONLY "this export doesn't carry that table" is skippable. A blanket
            // catch here made every read failure — corruption, a truncated or
            // malformed source file, an I/O error — look identical to an absent
            // table: the table was skipped, `counts[t]` was never set, and the
            // summed total then reported a PARTIAL import as a success. Silent
            // partial success on someone's health history is the worst available
            // outcome, so anything that is not a missing table now propagates.
            if (e.isNoSuchTableError()) continue;
            rethrow;
          }
          if (t == 'day_result') importedDays = <String>{};
          if (firstPage.isEmpty) {
            counts[t] = 0;
            continue;
          }
          final cols = await destCols(t);
          if (cols.isEmpty) continue; // table absent in THIS build
          // FINALIZED-DAY PROTECTION: a local day_result row with finalized=1 is
          // LOCKED (this device's own fully-derived history — the long-term
          // system of record). A foreign export merged with REPLACE must never
          // clobber it on a (day_id, algo_version) collision; non-finalized rows
          // keep the plain REPLACE behavior (the import may well be fresher).
          var protectedKeys = const <String>{};
          if (t == 'day_result') {
            final fin = await db.query(
              'day_result',
              columns: ['day_id', 'algo_version'],
              where: 'finalized = 1',
            );
            protectedKeys = {
              for (final r in fin) '${r['day_id']}|${r['algo_version']}',
            };
          }
          var copied = 0;
          var page = firstPage;
          // ONE TRANSACTION PER PAGE, not per table. The whole-table transaction
          // this replaces could only ever commit if the entire table fit in
          // memory first, which is the bug. Per-page commits keep peak residency
          // at one page, and the import stays safe to interrupt or repeat: every
          // write is INSERT OR REPLACE keyed on the row's own identity, so a
          // re-run converges to the same state, and each decoded_onehz row's
          // orphan guard is still queued in the SAME transaction as the row it
          // guards — the invariant that matters is per-row, not per-table.
          while (page.isNotEmpty) {
            expectedSleepRevision = await db.transaction((txn) async {
              if (!LocalDb._restoreStillCurrent(restoreGeneration)) {
                throw LocalDb._restoreResetError;
              }
              if ((await CursorStore._readIntVia(
                        txn,
                        'sleep_correction_revision',
                      ) ??
                      0) !=
                  expectedSleepRevision) {
                throw StateError(
                  'Sleep history changed during restore. Both stores are preserved; review the conflict before merging.',
                );
              }
              var nextSleepRevision = expectedSleepRevision;
              // CHUNKED, for the same reason SyncLedgerStore.commitBatch chunks: sqflite
              // serialises a whole batch's args into ONE platform message, and
              // the orphan guard below adds an op per decoded_onehz row on top.
              const chunkOps = 4000;
              var batch = txn.batch();
              var ops = 0;
              Future<void> flush() async {
                if (ops == 0) return;
                await batch.commit(noResult: true);
                batch = txn.batch();
                ops = 0;
              }

              final rows = <Map<String, Object?>>[];
              for (final r in page) {
                final row = <String, Object?>{
                  for (final e in r.entries)
                    if (cols.contains(e.key)) e.key: e.value,
                };
                if (row.isEmpty) continue;
                if (t == 'sync_cursor' &&
                    row['name'] == 'sleep_correction_revision') {
                  final incoming = int.tryParse('${row['value']}');
                  if (incoming == null || incoming < 0) {
                    throw StateError(
                      'Backup has an invalid sleep correction revision',
                    );
                  }
                  // This is a local publication generation, not a portable
                  // device cursor. Restoring a lower or equal number would
                  // make an obsolete worker eligible again (the ABA problem).
                  final current =
                      await CursorStore._readIntVia(
                        txn,
                        'sleep_correction_revision',
                      ) ??
                      0;
                  nextSleepRevision = math.max(current, incoming) + 1;
                  row['value'] = '$nextSleepRevision';
                }
                // A modern backup's daily row is only a projection. Merge its
                // timed readings, then rebuild once using the shared rule.
                if (t == 'body_weight' &&
                    sourceReadingDates.contains(row['date'])) {
                  continue;
                }
                if (t == 'decoded_onehz') {
                  // A pre-v46 export still carries the retired columns as
                  // VALUES (the disproven on_wrist/hr_valid reads and the
                  // -50.00 °C skin-temp error sentinel). Importing them
                  // verbatim would reinstate exactly the rows the v46
                  // data-retirement cleaned, so the same rule applies at this
                  // boundary — the migration only runs on version bumps and
                  // never sees imported rows.
                  if (cols.contains('on_wrist')) row['on_wrist'] = null;
                  if (cols.contains('hr_valid')) row['hr_valid'] = null;
                  final st = row['skin_temp_c'];
                  if (st is num && st <= -49.995) row['skin_temp_c'] = null;
                }
                // THE PRIMARY DEVICE IS NOT PORTABLE. Its `remote_id` is a
                // per-install handle — a CBPeripheral UUID that is unique to
                // the phone AND the app install — so a foreign export's copy names a peripheral this
                // phone cannot connect to. Importing it would REPLACE the local
                // pairing (id `''` is the primary, permanently) and leave the
                // app claiming a band that is not there. A restore onto the
                // same install needs nothing from here: the row is already
                // present, and the SharedPreferences mirror re-establishes it
                // if the database was rebuilt.
                if (t == 'device' && row['id'] == LocalDb.kPrimaryDeviceId) {
                  continue;
                }
                if ((t == 'metric_series' || t == 'metric_series_version') &&
                    finalizedDays.contains(row['date'])) {
                  continue; // a locally finalized day keeps its projection
                }
                if (t == 'day_result') {
                  if (protectedKeys.contains(
                    '${row['day_id']}|${row['algo_version']}',
                  )) {
                    continue; // locally finalized — never overwritten by import
                  }
                  importedDays?.add('${row['day_id']}');
                }
                // A LEGACY export's decoded_rr carries no rec_ts column; derive
                // it from rr_ts_ms (= rec_ts*1000) so the NOT NULL PK column is
                // always populated. SQLite storage classes are per VALUE, not per
                // column, so a foreign export can hand back a String where
                // INTEGER is declared — a bare `as num` there throws inside the
                // transaction and takes the whole restore down with it. Leave a
                // non-numeric value alone and let the row fail its own NOT NULL
                // check instead of aborting every other row's import.
                if (t == 'decoded_rr' && row['rec_ts'] == null) {
                  final rrTsMs = row['rr_ts_ms'];
                  if (rrTsMs is! num) {
                    // Nothing to key this beat by. Dropping the one row keeps the
                    // rest of the restore alive; letting it through would fail
                    // the NOT NULL check inside the transaction and take every
                    // other row on the page down with it.
                    continue;
                  }
                  row['rec_ts'] = rrTsMs.toInt() ~/ 1000;
                }
                // A PRE-v47 EXPORT CARRIES NO `device_id` / `ts_ms`. Left
                // alone they take the column DEFAULTS — ('', 0) — so every
                // imported row would collide on ONE primary key and REPLACE
                // the whole table down to a single row. Derive the key exactly
                // as [_rekeyTableByDevice] does: the primary band, and the
                // row's own time in ms. AFTER the rec_ts recovery above, which
                // is what decoded_rr's key is built from.
                // NAMED, not sniffed off `ts_ms`: `workout_route` declares that
                // column too and is in the merge list, but it was never re-keyed —
                // it has no `device_id` and no `rec_ts`, so a null `ts_ms` there
                // falls to the `t0 is! num` drop below and the route point vanishes
                // without a word. NOT NULL keeps that unreachable from a database
                // this app wrote; the table NAME is what keeps it unreachable after
                // the next schema change.
                const deviceKeyed = {'samples', 'decoded_onehz', 'decoded_rr'};
                if (deviceKeyed.contains(t) && row['ts_ms'] == null) {
                  row['device_id'] ??= LocalDb.kPrimaryDeviceId;
                  final t0 = row[t == 'samples' ? 'ts' : 'rec_ts'];
                  // Non-numeric (storage classes are per VALUE in a foreign
                  // export) ⇒ drop the one row rather than key it at 0, where
                  // it would REPLACE another row that genuinely belongs there.
                  if (t0 is! num) continue;
                  row['ts_ms'] = t0.toInt() * 1000;
                }
                rows.add(row);
              }
              // REPLACE the beat set for a colliding second, don't patch it.
              // decoded_rr is keyed by (rec_ts, beat_index), so a row-by-row
              // replace-insert only overwrites the indices the foreign export
              // actually reaches: importing [500] over a local [700, 710, 720]
              // leaves beats 1 and 2 behind and hands that second a spliced
              // foreign/local RR series — silently wrong RMSSD, out of a restore.
              // [_queueDecodedOneHz] guards the identical hazard on the write
              // path with a DELETE ahead of its inserts.
              //
              // Here the delete has to TRAIL the inserts and be bounded by the
              // highest index this page carried, because a second's beats can
              // straddle a page boundary: a leading `DELETE WHERE rec_ts = ?` on
              // page 2 would wipe the beats page 1 just imported. Trailing +
              // bounded is idempotent across the split — page 1 inserts 0,1 and
              // clears >1; page 2 inserts 2,3 and clears >3 — and beat_index is
              // dense by construction, so "everything past the last one" is
              // exactly the stale local tail.
              // v47: keyed on (device_id, ts_ms), the beat's real key — so the
              // tail sweep can only ever clear the WRITING device's stale
              // beats, never the other band's for the same second.
              final highestBeat = <(Object?, Object?), int>{};
              for (final row in rows) {
                batch.insert(
                  t,
                  row,
                  conflictAlgorithm: ConflictAlgorithm.replace,
                );
                copied++;
                if (t == 'decoded_rr') {
                  final idx = row['beat_index'];
                  final key = (row['device_id'], row['ts_ms']);
                  if (key.$2 != null && idx is num) {
                    final n = idx.toInt();
                    final prev = highestBeat[key];
                    if (prev == null || n > prev) highestBeat[key] = n;
                  }
                }
                if (++ops >= chunkOps) await flush();
              }
              for (final e in highestBeat.entries) {
                batch.delete(
                  'decoded_rr',
                  where: 'device_id = ? AND ts_ms = ? AND beat_index > ?',
                  whereArgs: [e.key.$1, e.key.$2, e.value],
                );
                if (++ops >= chunkOps) await flush();
              }
              await flush();
              return nextSleepRevision;
            }, exclusive: true);
            counts[t] = copied; // only fully committed pages contribute
            // Advance past the last row this page actually delivered. Read the
            // cursor BEFORE dropping the page, and stop on a short page rather
            // than issuing one more query to discover the end.
            lastRowid = (page.last[rowidKey] as num).toInt();
            if (page.length < pageSize) break;
            page = await nextPage();
          }
          counts[t] = copied;
        } catch (_) {
          // One table's worth of loss, not the whole salvage. A user-initiated
          // restore still rethrows: reporting a partial import as a success is
          // the worst available outcome there, whereas a rebuild has no better
          // file to fall back to.
          if (!tolerant) rethrow;
          counts.putIfAbsent(t, () => 0);
        }
      }
    } catch (e) {
      mergeError = e;
    } finally {
      await src.close();
    }
    // Old exports have only the daily weight table. Preserve those readings
    // when restoring into an already-migrated install; modern per-reading IDs
    // and existing days win rather than acquiring an extra aggregate reading.
    try {
      // Reset shares this SQL ordering. It either clears these follow-up
      // writes afterwards, or the generation check refuses them before writing.
      await db.transaction((txn) async {
        if (!LocalDb._restoreStillCurrent(restoreGeneration)) {
          throw LocalDb._restoreResetError;
        }
        if ((counts['body_weight'] ?? 0) > 0) {
          await LocalDb._seedLegacyWeightReadings(txn);
        }
        if ((counts['body_weight'] ?? 0) > 0 ||
            (counts['body_weight_reading'] ?? 0) > 0) {
          await BodyLogDb.rebuildDailyWeights(txn);
        }
        // Imported day results bypass the curve-encode seam. Rewind its
        // forward-only cursor so legacy restored rows are encoded as well.
        if ((counts['day_result'] ?? 0) > 0) {
          await txn.insert('compute_freshness', {
            'key': SeriesReencodeStore.kCursorKey,
            'payload_json': jsonEncode({}),
            'updated_at': DateTime.now().millisecondsSinceEpoch,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }, exclusive: true);
      // Last, so it can never be mistaken for a table row count by anything that
      // walks this map in order.
      if (importedDays != null && mergeError == null) {
        counts['_days'] = importedDays.length;
      }
      // CalculationStore already serializes hydration with resetWith. Keep
      // day-zone reads/installation inside SQL ordering too, so a later wipe
      // cannot be followed by an old in-memory timeline installation: a wipe
      // queued behind this transaction installs the empty timeline after it,
      // and one already finished left nothing to read. Checking once after
      // the install covers a reset that began before or during it.
      await CalculationStore.hydrate();
      await db.transaction((txn) async {
        await DayZoneStore.hydrate(txn);
        if (!LocalDb._restoreStillCurrent(restoreGeneration)) {
          throw LocalDb._restoreResetError;
        }
      }, exclusive: true);
    } catch (e) {
      mergeError ??= e;
    }
    if (mergeError != null) throw DbImportException(mergeError, counts);
    return counts;
  }

  /// A merge must not replace a durable correction with another history.
  /// Refuse before copying any page; retain both complete stores for review.
  static Future<void> _checkSleepCorrectionImport(
    Database db,
    Database src,
  ) async {
    Future<Set<String>> correctionDays(DatabaseExecutor ex) async {
      try {
        final rows = await ex.query(
          'baselines',
          columns: ['key'],
          where: 'key LIKE ?',
          whereArgs: ['sleep_correction:%'],
        );
        return {
          for (final r in rows)
            (r['key'] as String).substring('sleep_correction:'.length),
        };
      } on DatabaseException catch (e) {
        if (e.isNoSuchTableError()) return {};
        rethrow;
      }
    }

    Future<Set<String>> storedDays(DatabaseExecutor ex) async {
      final out = <String>{};
      for (final (table, column) in [
        ('day_result', 'day_id'),
        ('sleep_override', 'day_id'),
        ('metric_series', 'date'),
        ('metric_series_version', 'date'),
      ]) {
        try {
          out.addAll(
            (await ex.query(
              table,
              columns: [column],
              distinct: true,
            )).map((r) => r[column] as String),
          );
        } on DatabaseException catch (e) {
          if (!e.isNoSuchTableError()) rethrow;
        }
      }
      try {
        final pins = await ex.query(
          'sync_cursor',
          columns: ['value'],
          where: 'name = ?',
          whereArgs: [FrozenHeadlineStore.kCursorKey],
          limit: 1,
        );
        if (pins.isNotEmpty && pins.first['value'] is String) {
          try {
            final pin = jsonDecode(pins.first['value'] as String);
            if (pin is Map && pin['day'] is String) {
              out.add(pin['day'] as String);
            }
          } on FormatException {
            // An unparseable display cache supplies no day to serve or merge.
          }
        }
      } on DatabaseException catch (e) {
        if (!e.isNoSuchTableError()) rethrow;
      }
      return out;
    }

    final current = await correctionDays(db);
    final incoming = await correctionDays(src);
    if (current.isEmpty && incoming.isEmpty) return;
    final overlaps = current.intersection(await storedDays(src))
      ..addAll(incoming.intersection(await storedDays(db)))
      ..addAll(current.intersection(incoming));
    if (overlaps.isNotEmpty) {
      throw StateError(
        'Backup overlaps corrected sleep history. Both stores are preserved; review the conflict before merging.',
      );
    }
  }
}
