part of 'db.dart';

/// Workout sessions (the `sessions` rows, their typed-in `session_detail`
/// and per-session heart-rate reads), split out of [LocalDb] by concern.
abstract final class SessionStore {
  /// Upsert a workout session row (INSERT OR REPLACE — idempotent on id).
  ///
  /// The privacy flag and the effort rating are the user's, not the
  /// recorder's: a row written without them keeps the stored values, so a
  /// live tick, the finish or a retime can never make a private workout
  /// public (Build 94, Codex N01/N03).
  static Future<void> put(Map<String, dynamic> row) async {
    final db = await LocalDb.instance;
    await db.transaction((tx) async {
      final out = Map<String, dynamic>.of(row);
      final id = row['id'];
      if (id != null &&
          (!row.containsKey('private') || !row.containsKey('rpe'))) {
        final kept = await tx.query(
          'sessions',
          columns: ['private', 'rpe'],
          where: 'id = ?',
          whereArgs: [id],
        );
        if (kept.isNotEmpty) {
          out.putIfAbsent('private', () => kept.first['private']);
          out.putIfAbsent('rpe', () => kept.first['rpe']);
        }
      }
      await tx.insert(
        'sessions',
        out,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  /// Update ONLY a session's derived score columns.
  ///
  /// Deliberately not `putSession`: that is INSERT-OR-REPLACE over the whole
  /// row, so a re-score computed from a snapshot would also rewrite columns it
  /// never read — `hrr_bpm` (backfilled by the derivation engine) and `type`
  /// (the athlete correcting a mislabelled workout) are both written by their
  /// own narrow UPDATEs and would be reverted. Returns the number of rows
  /// changed (0 when the session was deleted or its expected window moved).
  /// A staged split replacement shares this transaction with trace completion;
  /// null preserves existing splits,while an explicit empty list clears them.
  static Future<int> setScores(
    String id, {
    required double? strain,
    required double? calories,
    required int? maxHr,
    required String zoneMinJson,
    String? caloriesBasis,
    int? avgHr,
    String? traceJson,
    int? traceSamples,
    List<Map<String, Object?>>? stagedSplits,
    ({int startTs, int endTs, String status})? expectedWindow,
  }) async {
    final db = await LocalDb.instance;
    return db.transaction((txn) async {
      final changed = await txn.update(
        'sessions',
        {
          'strain': strain,
          'calories': calories,
          'calories_basis': caloriesBasis,
          'max_hr': maxHr,
          'zone_min_json': zoneMinJson,
          // Only when the re-score actually measured one. Writing null over a
          // previously-banked average because THIS pass found no substrate would
          // delete a real measurement.
          'avg_hr': ?avgHr,
          // Same rule for the frozen trace: only ever written when this pass
          // actually read a window. A pass that found no substrate must not wipe
          // the trace banked by an earlier one — the substrate is gone for good.
          'trace_json': ?traceJson,
          'trace_samples': ?traceSamples,
        },
        where: expectedWindow == null
            ? 'id = ?'
            : 'id = ? AND start_ts = ? AND end_ts = ? AND status = ?',
        whereArgs: [
          id,
          if (expectedWindow != null) ...[
            expectedWindow.startTs,
            expectedWindow.endTs,
            expectedWindow.status,
          ],
        ],
      );
      // The completion marker cannot outlive a refused split replacement. A
      // deleted/retimed owner must not publish child rows for the old window.
      if (changed > 0 && stagedSplits != null) {
        await WorkoutRouteStore._replaceSplits(txn, id, stagedSplits);
      }
      return changed;
    });
  }

  static Future<Map<String, dynamic>?> byId(String id) async {
    final db = await LocalDb.instance;
    final rows = await db.query(
      'sessions',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// The one session row (if any) still `status='live'` — i.e. its
  /// `stopWorkout`/finalize write never happened, most likely because the app
  /// was killed mid-workout. On a healthy run there is at most one (a second
  /// `startWorkout` can't begin while `activeWorkout` is already set), but a
  /// crash could in principle strand more than one across restarts, so this
  /// returns every match, newest first, rather than assuming exactly one.
  /// Used at startup to reconcile the orphaned-live-workout bug (issue: "can't
  /// stop workout, only delete" — activeWorkout was never rehydrated from this
  /// row, so the in-app stop control was unreachable after a restart).
  static Future<List<Map<String, dynamic>>> live() async {
    final db = await LocalDb.instance;
    return db.query(
      'sessions',
      where: "status = 'live'",
      orderBy: 'start_ts DESC',
    );
  }

  /// Sessions whose `start_ts` (epoch SECONDS) is in [fromTs, toTs], newest first.
  /// How many FINISHED sessions exist, ever. Counted in SQL: the Workouts tab
  /// awaits this while it opens, and it used to pull every session row an
  /// install had ever written (full payload, sorted) back across the platform
  /// channel to add up one integer.
  static Future<int> finishedCount() async {
    final db = await LocalDb.instance;
    final r = await db.rawQuery(
      "SELECT COUNT(*) c FROM sessions WHERE status IS NOT 'live'",
    );
    return (r.first['c'] as num?)?.toInt() ?? 0;
  }

  /// TS-03 — the highest heart rate the band has ever OBSERVED on this user,
  /// and the local day it was held on. Null when no day ever produced one.
  ///
  /// Every value in the `hr_ceiling_bpm` series already passed the hold +
  /// corroborating-motion guard in analytics' `observed_max_hr.dart`. THE MAX
  /// MUST ONLY EVER BE TAKEN OVER THAT SERIES: a max over `sessions.max_hr`
  /// would be one PPG artifact away from dragging every zone boundary in the
  /// app up forever, with nothing on screen to say why.
  ///
  /// All-time, not a trailing window. This is "highest we've seen"; a ceiling
  /// that silently aged out of a window would move every zone edge with no
  /// visible cause. The date rides along so an old one is attributable.
  /// Recorded heart rate as per-minute means over `[fromSec, toSec)`, from
  /// durable 1 Hz rows only (never the RAM live stream). A minute needs at
  /// least [minSamples] readings to count; a thin or empty minute is left out,
  /// so gaps stay gaps. For the minutes recorded since the last calculation.
  static Future<List<Map<String, num>>> recordedHrPerMinute(
    int fromSec,
    int toSec, {
    int minSamples = 20,
  }) async {
    if (toSec <= fromSec) return const [];
    final db = await LocalDb.instance;
    final rows = await db.rawQuery(
      'SELECT (rec_ts / 60) * 60 AS t, AVG(hr) AS v, COUNT(hr) AS n '
      'FROM decoded_onehz WHERE rec_ts >= ? AND rec_ts < ? '
      'AND hr IS NOT NULL AND hr > 0 AND $kPrimaryBandSourceSql '
      'GROUP BY rec_ts / 60 ORDER BY t',
      [fromSec, toSec],
    );
    return [
      for (final r in rows)
        if (((r['n'] as num?) ?? 0) >= minSamples)
          {
            't': (r['t'] as num).toInt(),
            'v': ((r['v'] as num) * 10).round() / 10,
          },
    ];
  }

  static Future<({double bpm, String date})?> observedHrCeiling() async {
    final db = await LocalDb.instance;
    final rows = await db.rawQuery(
      "SELECT date, value FROM metric_series "
      "WHERE key = 'hr_ceiling_bpm' AND value IS NOT NULL "
      'ORDER BY value DESC LIMIT 1',
    );
    if (rows.isEmpty) return null;
    final d = rows.first['date'], v = rows.first['value'];
    if (d is! String || v is! num) return null;
    return (bpm: v.toDouble(), date: d);
  }

  /// The `device_family` of the most recent session that carries one, or null.
  ///
  /// The zone ceiling is a per-family constant, so a screen that prints zone
  /// EDGES has to say which strap they belong to — and it has to be able to say
  /// it for a user who has not synced in a week (`decoded_onehz` is pruned at
  /// ~3 days; `sessions` is not). NULL is unknown and stays unknown: a
  /// pre-schema-41 session, an import and a raw replay all carry none, and an
  /// uncalibrated strap is never gen4 with a different badge.
  static Future<String?> latestDeviceFamily() async {
    final db = await LocalDb.instance;
    final rows = await db.rawQuery(
      "SELECT device_family FROM sessions "
      "WHERE device_family IS NOT NULL AND device_family <> '' "
      'ORDER BY start_ts DESC LIMIT 1',
    );
    return rows.isEmpty ? null : rows.first['device_family'] as String?;
  }

  static Future<List<Map<String, dynamic>>> inRange(
    int fromTs,
    int toTs,
  ) async {
    final db = await LocalDb.instance;
    return db.query(
      'sessions',
      where: 'start_ts >= ? AND start_ts <= ?',
      whereArgs: [fromTs, toTs],
      orderBy: 'start_ts DESC',
    );
  }

  static Future<void> delete(String id) async {
    final db = await LocalDb.instance;
    // One transaction: a failure part-way must not leave a route, splits or
    // sets behind a session that is gone, or the reverse (B86-06).
    await db.transaction((txn) => _deleteRows(txn, id));
  }

  static Future<void> _deleteRows(Transaction db, String id) async {
    await db.delete('sessions', where: 'id = ?', whereArgs: [id]);
    // Cascade: a route belongs to its session (on-device only, no FK enforced).
    await db.delete('workout_route', where: 'session_id = ?', whereArgs: [id]);
    // …and its frozen per-km splits (CV-01), same reason.
    await db.delete('workout_split', where: 'session_id = ?', whereArgs: [id]);
    // …and so do sets typed in earlier builds, which would otherwise keep
    // exporting under a dead session_id.
    await db.delete('strength_set', where: 'session_id = ?', whereArgs: [id]);
    // …and the session's Lift Log (build 86). An imported, unlinked log has
    // no session and is untouched.
    await db.delete('lift_log', where: 'session_id = ?', whereArgs: [id]);
    // …and what the user typed during it (Build 93).
    await db.delete('session_detail', where: 'session_id = ?', whereArgs: [id]);
  }

  /// Build 93 (Codex full-flow audit F01): what the user TYPED during a
  /// workout that no sensor records (laps, pool length, stroke, interval
  /// rounds, poses, breathing pace, a game score), as JSON by session id. A
  /// table of its own because `putSession` replaces the whole session row.
  static Future<void> _createDetail(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS session_detail (
        session_id TEXT PRIMARY KEY,
        json TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
  }

  static Future<void> putDetail(String id, String json) async {
    final db = await LocalDb.instance;
    await db.insert('session_detail', {
      'session_id': id,
      'json': json,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<String?> detail(String id) async {
    final db = await LocalDb.instance;
    final r = await db.query(
      'session_detail',
      columns: ['json'],
      where: 'session_id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return r.isEmpty ? null : r.first['json'] as String?;
  }

  /// 1 Hz heart-rate samples in [fromTs, toTs] (epoch SECONDS), ascending, used
  /// to colour a route and average HR per split. Only worn seconds (hr > 0).
  ///
  /// Admitted rows only ([derivableSourceSql]), for the same reason
  /// [hrStats] states below: an unverified adapter writes its own
  /// seconds into this table with `source` set, and averaging the two together
  /// reports a session HR that is neither sensor's. Today nothing writes a
  /// non-null source, so this filter is a no-op — it is here so the six call
  /// sites are already correct on the day one does.
  static Future<List<Map<String, dynamic>>> hrSamplesInRange(
    int fromTs,
    int toTs,
  ) async {
    final db = await LocalDb.instance;
    return db.query(
      'decoded_onehz',
      columns: ['rec_ts', 'hr'],
      where:
          'rec_ts >= ? AND rec_ts <= ? AND hr > 0 AND ${derivableSourceSql()}',
      whereArgs: [fromTs, toTs],
      orderBy: 'rec_ts ASC',
    );
  }

  /// Per-session HR aggregates over the 1 Hz substrate for every session in
  /// [fromTs, toTs] (epoch SECONDS): {session_id: {n, avg_hr, min_hr, max_hr}}.
  /// One indexed range join — powers the workout list's avg-bpm / no-data
  /// heuristic without a query per row. Sessions whose window has been pruned
  /// (14-day raw retention) simply don't appear.
  /// [maxHrCeiling] / [minHrFloor] physiologically bound the SQL MAX/MIN(d.hr):
  /// a coarse guard so a gross artefact can't define a session that has no
  /// on-read smoothed extreme (imported/legacy rows). Spike-suppressed
  /// max/min come from [hrSamplesBySession] + the shared smoother; these
  /// aggregates are a last fallback only. 0/unset disables each bound.
  static Future<Map<String, Map<String, num>>> hrStats(
    int fromTs,
    int toTs, {
    int maxHrCeiling = 0,
    int minHrFloor = 0,
  }) async {
    final db = await LocalDb.instance;
    final ceilClause = maxHrCeiling > 0 ? 'AND d.hr <= $maxHrCeiling ' : '';
    final floorClause = minHrFloor > 0 ? 'AND d.hr >= $minHrFloor ' : '';
    final rows = await db.rawQuery(
      'SELECT s.id AS id, COUNT(d.rec_ts) AS n, AVG(d.hr) AS avg_hr, '
      '       MIN(CASE WHEN 1=1 $floorClause THEN d.hr END) AS min_hr, '
      '       MAX(CASE WHEN 1=1 $ceilClause THEN d.hr END) AS max_hr '
      'FROM sessions s '
      'JOIN decoded_onehz d ON d.rec_ts >= s.start_ts '
      '  AND d.rec_ts <= COALESCE(s.end_ts, s.start_ts) AND d.hr > 0 '
      // Admitted rows only. An unverified adapter writes its own seconds into
      // this table with `source` set; averaging the two together would report a
      // session HR that is neither sensor's.
      '  AND ${derivableSourceSql('d.source')} '
      'WHERE s.start_ts >= ? AND s.start_ts <= ? '
      'GROUP BY s.id',
      [fromTs, toTs],
    );
    return {
      for (final r in rows)
        if (r['id'] != null)
          r['id'] as String: {
            'n': (r['n'] as num?) ?? 0,
            'avg_hr': (r['avg_hr'] as num?) ?? 0,
            'min_hr': (r['min_hr'] as num?) ?? 0,
            'max_hr': (r['max_hr'] as num?) ?? 0,
          },
    };
  }

  /// Worn 1 Hz HR samples for every session in [fromTs, toTs] (epoch SECONDS),
  /// grouped {session_id: [hr, …]} in ascending time — one indexed range join.
  /// Feeds the workout list's spike-suppressed max (the shared smoother runs in
  /// the repo, not here). Sessions whose window has been pruned (14-day raw
  /// retention) simply don't appear, and the caller falls back to the stored
  /// column.
  static Future<Map<String, List<int>>> hrSamplesBySession(
    int fromTs,
    int toTs,
  ) async {
    final db = await LocalDb.instance;
    final rows = await db.rawQuery(
      'SELECT s.id AS id, d.hr AS hr '
      'FROM sessions s '
      'JOIN decoded_onehz d ON d.rec_ts >= s.start_ts '
      '  AND d.rec_ts <= COALESCE(s.end_ts, s.start_ts) AND d.hr > 0 '
      // Admitted rows only. An unverified adapter writes its own seconds into
      // this table with `source` set; averaging the two together would report a
      // session HR that is neither sensor's.
      '  AND ${derivableSourceSql('d.source')} '
      'WHERE s.start_ts >= ? AND s.start_ts <= ? '
      'ORDER BY s.id, d.rec_ts ASC',
      [fromTs, toTs],
    );
    final out = <String, List<int>>{};
    for (final r in rows) {
      final id = r['id'] as String?;
      if (id == null) continue;
      (out[id] ??= <int>[]).add((r['hr'] as num).toInt());
    }
    return out;
  }

  /// Backfill a session's heart-rate-recovery (bpm), computed retrospectively
  /// from the 1 Hz substrate around the session's end during derivation.
  static Future<void> setHrr(String id, double hrrBpm) async {
    final db = await LocalDb.instance;
    await db.update(
      'sessions',
      {'hrr_bpm': hrrBpm},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<void> setType(String id, String type) async {
    final db = await LocalDb.instance;
    await db.update(
      'sessions',
      {'type': type},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Mark a session private (or not). Its own narrow UPDATE for the same reason
  /// [setType] is one: `putSession` is INSERT-OR-REPLACE over the whole
  /// row, so a re-score would revert a flag it never read.
  static Future<void> setPrivate(String id, bool private) async {
    final db = await LocalDb.instance;
    final written = await db.update(
      'sessions',
      {'private': private ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
    if (written != 1) throw StateError('The workout no longer exists');
  }

  /// Set (or clear, with null) a session's self-reported RPE. Its own narrow
  /// UPDATE for the same reason [setType] is one, and because the user's
  /// own word must survive every re-score.
  ///
  /// The caller must pass what the user actually chose. There is no default and
  /// no pre-selection: an unrated session stays NULL forever, which is the
  /// honest reading of "they skipped it".
  static Future<void> setRpe(String id, double? rpe) async {
    final db = await LocalDb.instance;
    final written = await db.update(
      'sessions',
      {'rpe': rpe},
      where: 'id = ?',
      whereArgs: [id],
    );
    if (written != 1) throw StateError('The workout no longer exists');
  }
}
