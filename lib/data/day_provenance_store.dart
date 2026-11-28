part of 'db.dart';

/// Which days this device measured itself and which arrived by import or from a
/// foreign band family, split out of [LocalDb] by concern.
abstract final class DayProvenanceStore {
  /// True when [dayId] holds a day this device DERIVED ITSELF from real 1 Hz —
  /// as opposed to absent, a skip marker, or an earlier import.
  ///
  /// THE guard every import must pass before writing a day.
  /// `DayResultStore.put` is INSERT OR REPLACE and imports write `finalized:
  /// 1`, so overwriting a measured day both destroys it and locks the
  /// replacement in — the raw it came from is pruned within days, and
  /// `DerivationEngine` never revisits a finalized row. Irreversible, and there
  /// is no per-source undo.
  ///
  /// It lived as a private static inside `WhoopImporter`, which is why exactly
  /// one of the four import paths honoured it.
  static Future<bool> isMeasured(String dayId) async =>
      isMeasuredRow(await DayResultStore.read(dayId));

  /// [isMeasured] over an already-fetched row. Pure.
  static bool isMeasuredRow(Map<String, dynamic>? row) {
    if (row == null) return false;
    if (((row['skipped'] as num?) ?? 0).toInt() == 1) return false;
    try {
      final p = SeriesCodec.decodePayloadJson(
        (row['payload_json'] as String?) ?? '{}',
      );
      if (p != null) {
        if (p['skipped'] == true) return false;
        // A prior import (any importer) is replaceable — all of them are
        // snapshots, none of them is measured on-device data.
        if (p['imported'] == true) return false;
      }
    } catch (_) {
      // Present but unreadable — treat as real and refuse to clobber it.
      return true;
    }
    return true;
  }

  /// SQL selecting the `date` of every day whose scalars were IMPORTED.
  /// A fragment so the mask and the filters that apply it cannot drift apart.
  ///
  /// TWO SIGNALS, because the exact one is younger than the data:
  ///
  ///  * `metric_series_version.source` — precise, but the column only exists
  ///    from schema v43 and is deliberately NEVER retro-filled (a guessed
  ///    provenance is worse than none). Every day written before v43 reads
  ///    NULL, which is most of any real user's history.
  ///  * `day_result.payload_json`'s `"imported": true` — the marker BOTH
  ///    importers have written since they existed, and the same flag
  ///    [isMeasuredRow] tests on the write path.
  ///
  /// The second is what makes a NULL `source` DECIDABLE rather than ambiguous:
  /// NULL means "the column did not exist yet", not "unknown vendor", and the
  /// bundle behind that day still says who wrote it. So NULL is resolved
  /// against the payload rather than treated as suspect — dropping every
  /// NULL-source day would delete the user's genuine pre-v43 history from
  /// their own baselines, i.e. fabricate a baseline out of a short recent
  /// window, which is the worse fault of the two.
  ///
  /// A substring match, not `json_extract`: `jsonEncode` emits no spaces and
  /// this app is the only writer of the flag, so the literal is exact, and it
  /// does not assume a JSON1-enabled sqlite on every platform we ship to.
  ///
  /// The `IS NOT NULL` guards are not decoration. SQLite does not enforce NOT
  /// NULL on a declared PRIMARY KEY column of a legacy rowid table, and a
  /// single NULL inside a `NOT IN (…)` list makes the whole predicate NULL for
  /// EVERY row — one stray row would silently empty every baseline in the app
  /// rather than filter one day out of it. THE SERVED VERSION ONLY on the
  /// `day_result` half, for the same reason every other reader uses
  /// [DayResultStore._servedDayJoin]: `PRIMARY KEY (day_id, algo_version)`
  /// makes versions siblings, so an imported day that the band LATER re-derived
  /// keeps its old imported row sitting beside the new measured one. Testing
  /// every row made that day imported FOREVER — masked out of the baselines it
  /// is now entitled to be in, with no way back short of deleting the
  /// superseded row. `metric_series_version` needs no such guard: it is
  /// `PRIMARY KEY (date)` and the last writer replaces it, which is exactly why
  /// the stamp exists.
  static const String _importedDatesSql =
      'SELECT date FROM metric_series_version '
      "WHERE date IS NOT NULL AND source IS NOT NULL AND source <> 'band' "
      'UNION '
      'SELECT r.day_id FROM day_result r '
      '${DayResultStore._servedDayJoin} '
      "WHERE r.day_id IS NOT NULL AND r.payload_json LIKE '%\"imported\":true%'";

  /// Day labels whose stored scalars are ANOTHER vendor's derived numbers.
  ///
  /// THE MASK for every baseline read, and the inverse of [isMeasured]:
  /// that one guards the WRITE path (an import must not clobber a measured
  /// day), and nothing guarded the read path — so imported days were feeding
  /// the readiness and illness baselines the user's own scores are measured
  /// against. A window that mixes them is not a baseline of this person.
  ///
  /// Returned as a set rather than applied inside each query on purpose: the
  /// scan behind it is over `day_result.payload_json` (whole day bundles), so
  /// a caller reading several series takes it ONCE and filters in Dart.
  static Future<Set<String>> importedDates() async {
    final db = await LocalDb.instance;
    return {
      for (final r in await db.rawQuery(_importedDatesSql)) r['date'] as String,
    };
  }

  /// The `metric_series` keys whose stored VALUES ARE IN THE BAND'S OWN UNITS,
  /// so a day measured by a different band family is not on the same scale as
  /// today's and must not sit in the same baseline.
  ///
  /// DELIBERATELY SHORT, and it is a list of UNIT MISMATCHES, not of things
  /// that got noisier. `skin_temp_adc` is a gen4 thermistor ADC COUNT on one
  /// side of a strap swap and a gen5 CENTI-DEGREE reading on the other — the
  /// same key holding two different quantities, which is a wrong number, not a
  /// less precise one. `rhr` and `rmssd` off a different wrist sensor are the
  /// same quantity measured slightly differently: masking those would delete
  /// the user's history from their own baseline to fix a bias smaller than the
  /// window it is measured over. Nothing joins this set without a measured unit
  /// difference behind it.
  static const Set<String> familySeamKeys = {'skin_temp_adc'};

  /// Day labels whose scalars were measured by a DIFFERENT band family than the
  /// most recent stamped day — the mask for [familySeamKeys] baselines.
  ///
  /// Two properties that make this safe to apply unconditionally:
  ///  * A NULL stamp is never foreign. Unknown provenance is its own case (see
  ///    [_createMetricSeriesVersion]); every day written before the column
  ///    existed reads NULL, and dropping those would delete a real user's whole
  ///    history from their own baseline.
  ///  * A single-family user gets the EMPTY SET, because nothing differs from
  ///    the newest stamp. So this changes no number until a strap actually
  ///    changes generation.
  static Future<Set<String>> foreignFamilyDates() async {
    final db = await LocalDb.instance;
    final rows = await db.rawQuery(
      'SELECT date FROM metric_series_version '
      'WHERE date IS NOT NULL AND device_family IS NOT NULL '
      'AND device_family <> ('
      '  SELECT device_family FROM metric_series_version '
      '  WHERE device_family IS NOT NULL ORDER BY date DESC LIMIT 1'
      ')',
    );
    return {for (final r in rows) r['date'] as String};
  }
}
