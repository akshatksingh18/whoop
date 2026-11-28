part of 'db.dart';

/// Versioned `day_result` reads and writes (one immutable row per day and
/// algorithm version; main isolate only), split out of [LocalDb] by concern.
abstract final class DayResultStore {
  /// Upsert one (day_id, algo_version) result + its indexed scalars in one
  /// transaction. Immutable PER VERSION: a version bump writes a new row. The
  /// `finalized` flag locks a day from further recompute (~48 h after wake).
  static Future<bool> put({
    required String dayId,
    required int algoVersion,
    required String payloadJson,
    required String windowJson,
    bool finalized = false,
    bool skipped = false,
    // A day whose offloaded second-half compute (naps/workouts/HRR/wear/
    // curves/wake-features) failed or timed out AFTER the headline scalars
    // already succeeded — the row is real (not a skip marker) so headline
    // scalars still display, but it must never count as "derived" for the
    // raw-pruning guard (see ids). Callers should also avoid passing
    // `finalized: true` alongside `partial: true` unless there genuinely is
    // no raw substrate to ever retry from (e.g. the force-finalized import
    // path), since a finalized row is never revisited on a version bump.
    bool partial = false,
    double? rhr,
    double? rmssd,
    double? readiness,
    Map<String, double?> series = const {},
    // WHO produced these scalars — 'band' for a day this app derived from 1 Hz
    // records, a vendor tag for an importer. NULL is the default and means
    // UNKNOWN; it is never filled in with a guess, because the whole point of
    // the column is that a guessed provenance is worse than none. See
    // [_createMetricSeriesVersion].
    String? source,
    // WHICH BAND'S UNITS these scalars are in — the substrate's own
    // `device_family` stamp, which is already null when the window spans two
    // straps or carries no stamp at all. Same rule as [source]: never guessed.
    // See [_createMetricSeriesVersion] and
    // [DayProvenanceStore.foreignFamilyDates].
    String? deviceFamily,
    int? sleepIntentGeneration,
    int? sleepRevision,
  }) async {
    final db = await LocalDb.instance;
    final now = DateTime.now().millisecondsSinceEpoch;
    // THE write seam for the compact curve format. All four callers
    // (DerivationEngine x2, cloud_import, whoop_import) funnel through here, so
    // no producer needs to know the wire format exists — earlier code keeps
    // merging and patching plain [{t,v}] lists in memory. Lossless or no-op:
    // SeriesCodec leaves anything it cannot encode exactly as it found it.
    final encodedPayload = SeriesCodec.encodePayloadJson(payloadJson);
    return db.transaction((txn) async {
      final intent = await SleepOverrideStore._correctionVia(txn, dayId);
      if ((intent?['generation'] as num?)?.toInt() != sleepIntentGeneration ||
          (sleepRevision != null &&
              (await CursorStore._readIntVia(
                        txn,
                        'sleep_correction_revision',
                      ) ??
                      0) !=
                  sleepRevision)) {
        return false;
      }
      var effectivePayload = encodedPayload;
      if (intent != null) {
        final bundle = SeriesCodec.decodePayloadJson(encodedPayload)!;
        final sleep = bundle['sleep'];
        final accounting = sleep is Map ? sleep['accounting'] : null;
        final value = accounting is Map ? accounting['value'] : null;
        final window = sleep is Map && sleep['window'] is Map
            ? (sleep['window'] as Map)['value']
            : null;
        final usable =
            intent['action'] != 'rejected' &&
            (intent['action'] != 'clear' ||
                const [
                  'auto',
                  'auto_fallback',
                  'none',
                ].contains(bundle['sleep_source'])) &&
            value is Map &&
            value['tst_sec'] is num &&
            (value['tst_sec'] as num) > 0 &&
            window is Map &&
            window['onset_ms'] is num &&
            window['offset_ms'] is num &&
            (window['offset_ms'] as num) > (window['onset_ms'] as num);
        final next = {...intent, 'pending': false, 'usable': usable};
        final current = usable
            ? {
                ...bundle,
                'sleep_correction': {
                  for (final key in [
                    'generation',
                    'action',
                    'pending',
                    'usable',
                  ])
                    key: next[key],
                },
              }
            : SleepCorrection.unknown(bundle, next);
        effectivePayload = SeriesCodec.encodePayloadJson(jsonEncode(current));
        if (!usable) {
          finalized = false;
          partial = true;
          rhr = rmssd = readiness = null;
        }
        await txn.update(
          'baselines',
          {'payload_json': jsonEncode(next), 'updated_at': now},
          where: 'key = ?',
          whereArgs: ['sleep_correction:$dayId'],
        );
      }
      await txn.insert('day_result', {
        'day_id': dayId,
        'algo_version': algoVersion,
        'payload_json': effectivePayload,
        'window_json': windowJson,
        'computed_at': now,
        'finalized': finalized ? 1 : 0,
        'skipped': skipped ? 1 : 0,
        'partial': partial ? 1 : 0,
        'rhr': rhr,
        'rmssd': rmssd,
        'readiness': readiness,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      // A `partial` row already doesn't count as "derived" for the raw-pruning
      // guard (see above) — extend the same caution to the rolling baselines:
      // don't let a day whose second-half compute failed/timed out overwrite
      // (or seed, for a brand-new day) the value tomorrow's readiness/illness
      // baseline reads via metric_series. The next successful (non-partial)
      // pass writes the real value once it lands.
      if (!partial) {
        for (final e in series.entries) {
          await txn.insert('metric_series', {
            'date': dayId,
            'key': e.key,
            'value': e.value,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        // Whose maths wrote those scalars (see _createMetricSeriesVersion).
        // REPLACE, not IGNORE: the last pass to write the series is the one
        // that owns the stamp, including a ROLLED-BACK build writing a lower
        // version over a higher one — that is the case a MAX() over day_result
        // gets wrong, and the reason this is a stamp and not a query.
        //
        // Inside the same transaction as the values, so the stamp and what it
        // describes can never disagree. Skipped when the series map is empty:
        // an empty map wrote nothing, so there is nothing to attribute.
        if (series.isNotEmpty) {
          await txn.insert('metric_series_version', {
            'date': dayId,
            'algo_version': algoVersion,
            // The last pass to write the series owns the stamp — provenance
            // included, so a caller that does not know its own writes NULL
            // here rather than inheriting the previous writer's claim.
            'source': source,
            'device_family': deviceFamily,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
      return true;
    });
  }

  /// The version a `day_result` read is allowed to serve at most: the algo
  /// version of the build doing the reading.
  ///
  /// `PRIMARY KEY (day_id, algo_version)` makes versions SIBLINGS, not
  /// replacements, so a day can hold several generations at once. Picking the
  /// highest one present is right on the way up and wrong on the way down: a
  /// user who rolls back a store build, or leaves TestFlight for release, has
  /// rows from a version this build no longer implements, and `MAX()` serves
  /// them forever. A re-derive does not repair it — it writes a row at the
  /// LOWER version that `MAX()` then ignores — so day-detail (reading the
  /// bundle) and trends (reading the unversioned, always-overwritten
  /// `metric_series`) disagree about the same day permanently. Worse, if the
  /// newer version reinterpreted a field under the same key, the older UI reads
  /// it as a real number.
  ///
  /// A ceiling, not an equality test: rows from OLDER versions are still
  /// served, which is the existing (correct) behaviour for a day whose raw has
  /// aged out and which therefore never gets a fresh-version row. The rows
  /// above the ceiling are not deleted either — re-upgrading brings them back.
  ///
  /// `local_repository_impl.crossDayStaleReason` applies the same discipline to
  /// the cross-day artifact, with a comment calling the ungated case "the bug".
  static const int _servedAlgoCeiling = kAlgoVersion;

  /// The served-version join, in SQL: bind a `day_result r` to its highest row
  /// at or below [_servedAlgoCeiling]. Every reader (and the coach views) uses
  /// THIS rather than writing its own `MAX(algo_version)` — the pattern had
  /// already reappeared at five readers and two views, and the ceiling has to
  /// be on all of them or it is on none of them.
  static const String _servedDayJoin =
      'JOIN (SELECT day_id, MAX(algo_version) AS v FROM day_result '
      'WHERE algo_version <= $_servedAlgoCeiling GROUP BY day_id) m '
      'ON r.day_id = m.day_id AND r.algo_version = m.v';

  /// The result row for one day_id at the highest version this build serves
  /// (see [_servedAlgoCeiling]), with a normalized `date` alias for callers.
  /// Null if absent.
  static Future<Map<String, dynamic>?> read(String dayId) async {
    final db = await LocalDb.instance;
    final rows = await db.query(
      'day_result',
      where: 'day_id = ? AND algo_version <= ?',
      whereArgs: [dayId, _servedAlgoCeiling],
      orderBy: 'algo_version DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : _withDate(rows.first);
  }

  /// The most recent day (highest day_id label), latest version, or null.
  static Future<Map<String, dynamic>?> latest() async {
    final rows = await recent(1);
    return rows.isEmpty ? null : rows.first;
  }

  /// The N most recent days (newest day_id first), each at its LATEST version.
  static Future<List<Map<String, dynamic>>> recent(int limit) async {
    final db = await LocalDb.instance;
    // For each day_id pick MAX(algo_version), then join back for the full row.
    final rows = await db.rawQuery(
      'SELECT r.* FROM day_result r '
      '$_servedDayJoin '
      'ORDER BY r.day_id DESC LIMIT ?',
      [limit],
    );
    return [for (final r in rows) _withDate(r)];
  }

  /// The stored sleep WINDOW for each of the [limit] most recent days, newest
  /// first, WITHOUT touching `payload_json`.
  ///
  /// `day_result.window_json` already holds the sleep-window Metric envelope
  /// (`{value: {onset_ms, offset_ms, …}, confidence, tier, …}`) in its own
  /// column, so onset/offset are one small projected read — no bundle decode,
  /// no per-day round trip. Rows: `{day_id, window_json}`.
  /// [before] (a day label) keeps only nights before that day, so a past
  /// night's comparison never reads later nights (Build 91, Codex audit F07).
  static Future<List<Map<String, dynamic>>> sleepWindowRows(
    int limit, {
    String? before,
  }) async {
    final db = await LocalDb.instance;
    return db.rawQuery(
      'SELECT r.day_id AS day_id, r.window_json AS window_json '
      'FROM day_result r '
      '$_servedDayJoin '
      'WHERE r.skipped = 0 '
      '${before == null ? '' : 'AND r.day_id < ? '}'
      'ORDER BY r.day_id DESC LIMIT ?',
      [?before, limit],
    );
  }

  /// Every day label ('YYYY-MM-DD') the lookback screen can actually RENDER —
  /// exactly the days [read]/`_bundleForDate` would return a real bundle
  /// for, newest first. That is: the LATEST-`algo_version` `day_result` row per
  /// day that is NOT a derivation skip-marker. A day whose minute-detail was
  /// pruned still qualifies (its curves live in the persisted bundle payload,
  /// so it renders a summary); but a raw-only day (`decoded_onehz` with no
  /// derived row) and a skip-marker day both render EMPTY, so neither must
  /// bound navigation. Skips are excluded via the `skipped` column, which
  /// `_markDaySkipped` sets alongside the `{skipped:true}` payload.
  static Future<List<String>> availableDayIds() async {
    final db = await LocalDb.instance;
    // Latest version per day (matches [read]), then drop skip-markers.
    final rows = await db.rawQuery(
      'SELECT r.day_id FROM day_result r '
      '$_servedDayJoin '
      'WHERE r.skipped = 0 '
      'ORDER BY r.day_id DESC',
    );
    return [
      for (final r in rows)
        if (r['day_id'] is String && (r['day_id'] as String).isNotEmpty)
          r['day_id'] as String,
    ];
  }

  /// The set of day_id labels that already have a REAL, COMPLETE result at
  /// [algoVersion]. Used by the raw-pruning guard to decide what's safe to
  /// prune - a day that only ever got a skip-marker (its derivation threw)
  /// or a partial row (headline scalars only; the offloaded second-half
  /// blocks failed/timed out) must NOT count as "derived" here, or its raw
  /// substrate gets pruned with no way left to ever fill in the missing
  /// data correctly.
  static Future<Set<String>> ids(int algoVersion) async {
    final db = await LocalDb.instance;
    final rows = await db.query(
      'day_result',
      columns: ['day_id'],
      where: 'algo_version = ? AND skipped = 0 AND partial = 0',
      whereArgs: [algoVersion],
    );
    return {for (final r in rows) r['day_id'] as String};
  }

  /// The set of day_id labels that are FINALIZED at [algoVersion] (locked). A
  /// finalized day is never recomputed even on a version bump.
  static Future<Set<String>> finalizedIds(int algoVersion) async {
    final db = await LocalDb.instance;
    final rows = await db.query(
      'day_result',
      columns: ['day_id'],
      where: 'algo_version = ? AND finalized = 1',
      whereArgs: [algoVersion],
    );
    return {for (final r in rows) r['day_id'] as String};
  }

  /// Normalize a day_result row to also carry a `date` key (== day_id) so legacy
  /// readers that keyed on `date` keep working.
  static Map<String, dynamic> _withDate(Map<String, dynamic> row) {
    final m = Map<String, dynamic>.from(row);
    m['date'] = m['day_id'];
    return m;
  }
}
