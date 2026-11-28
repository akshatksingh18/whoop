part of 'db.dart';

/// The `live_coverage` step windows (band 100 Hz and phone pedometer), the
/// resolved per-day step ladder, and wrist-off and charging spans, split out
/// of [LocalDb] by concern.
abstract final class StepCoverageStore {
  // Device-time windows the live AN-2554 pedometer actually counted (real steps).
  // The 1 Hz estimate excludes any minute that falls inside one of these windows
  // — 100 Hz is the real count and always wins; we never count a minute twice.
  // Times are device epoch SECONDS (same clock as raw_records.rec_ts, since the
  // band's RTC is SET_CLOCK'd to phone time on connect). `day` = local date label
  // of the window start (for per-day step attribution).
  //
  // HISTORICAL ROWS. Databases written before the window derivation was fixed
  // contain ZERO-WIDTH rows (`end_ts == start_ts`) — the old writer took both
  // ends from a band record timestamp that does not advance during a live
  // session. They are left as they are: their real durations were never
  // recorded, and widening them after the fact would replace one wrong extent
  // with another while silently changing already-derived days. Readers must
  // tolerate them — `windowsOverlapping` matches them (`end_ts >= lo`)
  // and the derivation's minute test (`s + 60 > start && s < end`) still
  // excludes the minute containing the row, so such a row under-excludes but
  // never crashes or double-adds its steps.
  static Future<void> _create(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS live_coverage (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        start_ts INTEGER NOT NULL,
        end_ts INTEGER NOT NULL,
        steps INTEGER NOT NULL,
        day TEXT NOT NULL,
        source TEXT NOT NULL DEFAULT '$kStepSourceBand',
        device_id TEXT NOT NULL DEFAULT '${LocalDb.kPrimaryDeviceId}'
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_live_coverage_day ON live_coverage(day)',
    );
    await LocalDb._addColumnIfMissing(
      db,
      'live_coverage',
      'distance_m',
      'REAL',
    );
  }

  /// Ensure `live_coverage.source` exists (v27).
  ///
  /// Uses the shared guarded helper — an unguarded ALTER TABLE on an
  /// already-migrated db bricks the upgrade (that has bitten this file twice).
  static Future<void> _ensureSource(Database db) async {
    await LocalDb._addColumnIfMissing(
      db,
      'live_coverage',
      'source',
      "TEXT NOT NULL DEFAULT '$kStepSourceBand'",
    );
  }

  /// Ensure `live_coverage.device_id` exists (v49).
  ///
  /// WHICH SENSOR counted, not which KIND of sensor — `source` already says
  /// band-or-phone. Without it two straps on the same 3,000-step walk both
  /// rank 2 in [resolveDaySteps], skip each other's overlap subtraction, and
  /// the day publishes 6,000: the resolver has handled that since the ladder
  /// gained `CoverageSpan.deviceId`, and could never fire because this column
  /// did not exist. Existing rows take the DEFAULT — the primary band — which
  /// is exactly what they have always meant, so no day's total moves.
  static Future<void> _ensureDeviceId(Database db) async {
    await LocalDb._addColumnIfMissing(
      db,
      'live_coverage',
      'device_id',
      "TEXT NOT NULL DEFAULT '${LocalDb.kPrimaryDeviceId}'",
    );
  }

  /// Step-count provenance for a `live_coverage` row.
  ///
  /// These are never summed together.
  static const String kStepSourceBand = 'band'; // band 100 Hz AN-2554 (wrist)
  static const String kStepSourcePhone = 'phone'; // phone pedometer (pocket)

  /// Record one imported band step window (device-time seconds) and its count.
  ///
  /// The window is normalised by [sanitizeCoverageWindow] first: a zero-width
  /// window that claims steps is widened to the shortest duration those steps
  /// could span rather than dropped; an inverted window is rejected.
  static Future<void> add(
    int startTs,
    int endTs,
    int steps,
    String day, {
    String source = kStepSourceBand,
    // WHICH physical sensor counted (see [_ensureDeviceId]). The
    // phone is the primary device's own pedometer, so it keeps `''` too —
    // `source` is what tells wrist from pocket.
    String deviceId = LocalDb.kPrimaryDeviceId,
  }) async {
    final w = sanitizeCoverageWindow(startTs, endTs, steps);
    if (w == null) return;
    final db = await LocalDb.instance;
    await db.insert('live_coverage', {
      'start_ts': w.startTs,
      'end_ts': w.endTs,
      'steps': steps,
      'day': day,
      'source': source,
      'device_id': deviceId,
    });
  }

  /// Replace ALL phone-pedometer rows for [day] with [windows], atomically.
  ///
  /// Phone step data is a re-readable snapshot, not an append-only stream: the
  /// same day can be synced repeatedly as it fills in. So the phone sync is
  /// delete-then-insert scoped to `source = 'phone'`, which is idempotent by
  /// construction and needs no window-clipping. Band rows are untouched.
  ///
  /// A `steps == 0` window is stored deliberately: it is the phone confirming
  /// that it saw no motion over that hour. `resolveDaySteps` uses that evidence
  /// to veto a low-density wrist false-positive over the same window. Only a
  /// negative count or an inverted window is dropped.
  static Future<void> replacePhoneForDay(
    String day,
    List<({int startTs, int endTs, int steps})> windows, {
    Map<String, double?> distances = const {},
  }) async {
    final db = await LocalDb.instance;
    await db.transaction((txn) async {
      await txn.delete(
        'live_coverage',
        where: 'day = ? AND source = ?',
        whereArgs: [day, kStepSourcePhone],
      );
      for (final w in windows) {
        if (w.steps < 0 || w.endTs <= w.startTs) continue;
        await txn.insert('live_coverage', {
          'start_ts': w.startTs,
          'end_ts': w.endTs,
          'steps': w.steps,
          'day': day,
          'source': kStepSourcePhone,
          'distance_m': distances['${w.startTs}-${w.endTs}'],
        });
      }
    });
  }

  /// Phone-sourced steps already banked for [day].
  ///
  /// Used by the pedometer sync to tell "this day really had no steps" from
  /// "this read came back empty" before it replaces a day wholesale — see
  /// [replacePhoneForDay], which is delete-then-insert.
  ///
  /// Also the UI's source discriminator: it is the same quantity
  /// the derive tests to decide which source owns the day, so a screen
  /// can ask "did the phone actually cover today?" instead of approximating it
  /// with "is the toggle on". Those differ exactly when the toggle is on and
  /// the phone has no data, where the band still owns the day.
  static Future<int> phoneStepsForDay(String day) async {
    final db = await LocalDb.instance;
    final r = await db.rawQuery(
      'SELECT COALESCE(SUM(steps),0) s FROM live_coverage '
      'WHERE day = ? AND source = ?',
      [day, kStepSourcePhone],
    );
    return (r.first['s'] as num?)?.toInt() ?? 0;
  }

  /// Drop every phone-sourced coverage row (the user turned phone steps off).
  /// Band rows are untouched, so days fall back to the band count.
  static Future<int> clearPhone() async {
    final db = await LocalDb.instance;
    return db.delete(
      'live_coverage',
      where: 'source = ?',
      whereArgs: [kStepSourcePhone],
    );
  }

  /// [day]'s real pedometer steps, resolved PER WINDOW and split by sensor.
  ///
  /// Phone and band counts are never blindly added: both count the same walk,
  /// one from the pocket and one from the wrist, so summing a day whole doubles
  /// it. But they are not alternatives either — the strap streams only while a
  /// session runs, so it can only ever cover workout minutes, and letting
  /// either source take a whole day it only partly covered is the bug this
  /// replaces (it reported 622 steps against the phone's 18,856 on a real
  /// export). Each SPAN goes to the best source that actually covered it, and
  /// the spans sum. [resolveDaySteps] owns that decision, including why a wide
  /// band span with no gait in it does NOT outrank the phone (a wrist counter
  /// is documented emitting 22-27 false steps/min during dishes, reaching and
  /// driving while missing slow walking — O'Connell 2017,
  /// doi:10.1371/journal.pone.0169616).
  /// Steps are counted on the phone only (Akshat, Build 89): band rows are
  /// kept but never enter a day's total. Tests of the band ladder underneath
  /// switch it back on, as `resolveDaySteps(bandSteps:)` does.
  @visibleForTesting
  static bool debugBandSteps = false;

  static Future<ResolvedDaySteps> resolvedStepsForDay(String day) async {
    final lo = localDayStartSec(day), hi = localDayEndSec(day);
    if (lo == null || hi == null) return ResolvedDaySteps.none;
    return resolvedStepsForWindow(
      DateTime.fromMillisecondsSinceEpoch(lo * 1000),
      DateTime.fromMillisecondsSinceEpoch(hi * 1000),
    );
  }

  /// Clip the same source policy to an exact active interval, including older
  /// rows whose stored day did not match their cross-midnight extent.
  static Future<ResolvedDaySteps> resolvedStepsForWindow(
    DateTime from,
    DateTime to,
  ) async {
    final lo = from.millisecondsSinceEpoch ~/ 1000,
        hi = to.millisecondsSinceEpoch ~/ 1000;
    if (hi <= lo) return ResolvedDaySteps.none;
    final db = await LocalDb.instance;
    final rows = await db.rawQuery(
      'SELECT start_ts,end_ts,steps,source,device_id FROM live_coverage '
      'WHERE start_ts < ? AND MAX(end_ts,start_ts+1) > ?',
      [hi, lo],
    );
    return _resolveStepRows(rows, lo, hi);
  }

  /// One retained-coverage read for historical charts, instead of one query
  /// for every metric date. No history cap; the source policy is unchanged.
  static Future<Map<String, ResolvedDaySteps>> resolvedStepsByDay() async {
    final rows = await (await LocalDb.instance).rawQuery(
      'SELECT start_ts,end_ts,steps,source,device_id FROM live_coverage',
    );
    final byDay = <String, List<Map<String, Object?>>>{};
    final storedDays = DayClock.days;
    int? nextStoredStart(int t) {
      var lo = 0, hi = storedDays.length;
      while (lo < hi) {
        final mid = (lo + hi) ~/ 2;
        if (storedDays[mid].startSec <= t) {
          lo = mid + 1;
        } else {
          hi = mid;
        }
      }
      return lo < storedDays.length ? storedDays[lo].startSec : null;
    }

    for (final row in rows) {
      final start = (row['start_ts'] as num).toInt();
      final end = math.max(start + 1, (row['end_ts'] as num).toInt());
      var t = start;
      final seen = <String>{};
      while (t < end) {
        final date = dayLabelAtSec(t);
        if (seen.add(date)) (byDay[date] ??= []).add(row);
        final assigned = DayClock.at(t);
        final local = DateTime.fromMillisecondsSinceEpoch(t * 1000);
        var boundary =
            assigned?.endSec ??
            DateTime(
                  local.year,
                  local.month,
                  local.day + 1,
                ).millisecondsSinceEpoch ~/
                1000;
        if (assigned == null) {
          final next = nextStoredStart(t);
          if (next != null) boundary = math.min(boundary, next);
        }
        if (boundary <= t) break;
        t = math.min(end, boundary);
      }
    }
    return {
      for (final e in byDay.entries)
        e.key: _resolveStepRows(
          e.value,
          localDayStartSec(e.key)!,
          localDayEndSec(e.key)!,
        ),
    };
  }

  static ResolvedDaySteps _resolveStepRows(
    List<Map<String, Object?>> rows,
    int lo,
    int hi,
  ) {
    final spans = <CoverageSpan>[];
    for (final row in rows) {
      final start = (row['start_ts'] as num).toInt();
      final end = math.max(start + 1, (row['end_ts'] as num).toInt());
      final count = (row['steps'] as num).toInt();
      final left = math.max(lo, start), right = math.min(hi, end);
      if (right <= left) continue;
      // Cumulative rounding conserves counts across adjacent day/session cuts.
      final clipped =
          (count * (right - start) / (end - start)).round() -
          (count * (left - start) / (end - start)).round();
      spans.add(
        CoverageSpan(
          startTs: left,
          endTs: right,
          steps: clipped,
          fromBand: row['source'] != kStepSourcePhone,
          deviceId: (row['device_id'] as String?) ?? LocalDb.kPrimaryDeviceId,
        ),
      );
    }
    return resolveDaySteps(spans, bandSteps: debugBandSteps);
  }

  /// Coverage windows ([startSec, endSec]) overlapping [loSec, hiSec), for ONE
  /// [source] (band by default).
  ///
  /// The 1 Hz-estimate exclusion this originally served is gone along with the
  /// estimator. Its only remaining caller is the NOOP importer, which reads back
  /// the spans it has already banked so `stepRuns` can clip them out and a
  /// re-import over an overlapping span cannot double-count.
  ///
  /// THE SOURCE FILTER IS LOAD-BEARING for that caller. Phone-pedometer rows now
  /// share this table and cover the same wall-clock hours, so an unfiltered read
  /// let a user with phone steps enabled import a NOOP backup whose BAND step
  /// runs were clipped against the PHONE's windows and silently dropped — the
  /// import reporting success while banking nothing for those days. Band clips
  /// against band. Phone coverage needs no clipping at all: it is replaced
  /// wholesale per day (see [replacePhoneForDay]).
  static Future<List<List<int>>> windowsOverlapping(
    int loSec,
    int hiSec, {
    String source = kStepSourceBand,
  }) async {
    final db = await LocalDb.instance;
    final rows = await db.query(
      'live_coverage',
      where: 'end_ts >= ? AND start_ts < ? AND source = ?',
      whereArgs: [loSec, hiSec, source],
    );
    return [
      for (final r in rows)
        [(r['start_ts'] as num).toInt(), (r['end_ts'] as num).toInt()],
    ];
  }

  /// Spans ([startSec, endSec]) in [loSec, hiSec) during which the band was NOT
  /// on the wrist, from the strap's own WRIST_OFF/WRIST_ON events.
  ///
  /// A band sitting on a table is PERFECTLY still and reads as deep rest to any
  /// motion-based detector — it is the dominant nap false positive. The strap
  /// already tells us; these events have been decoded and persisted all along,
  /// and `AdvancedSleepStager.detectSleep` has always accepted a `wristOff`
  /// argument, but nothing ever supplied one.
  ///
  /// State is carried in from BEFORE [loSec] so a window that opens mid-removal
  /// is still covered, and an unterminated removal extends to [hiSec] rather
  /// than being dropped (absent evidence of return is not evidence of return).
  static Future<List<List<int>>> wristOffSpans(int loSec, int hiSec) =>
      _toggleSpans(
        loSec,
        hiSec,
        onId: proto.EventId.wristOn,
        offId: proto.EventId.wristOff,
      );

  /// Spans ([startSec, endSec]) in [loSec, hiSec) during which the band was on
  /// the charger — off-wrist by definition, and motionless.
  static Future<List<List<int>>> chargingSpans(int loSec, int hiSec) =>
      _toggleSpans(
        loSec,
        hiSec,
        onId: proto.EventId.chargingOff,
        offId: proto.EventId.chargingOn,
      );

  /// Build "state active" spans from a pair of toggle events, clipped to
  /// [loSec, hiSec). [offId] opens a span; [onId] closes it.
  static Future<List<List<int>>> _toggleSpans(
    int loSec,
    int hiSec, {
    required int onId,
    required int offId,
  }) async {
    if (hiSec <= loSec) return const [];
    final db = await LocalDb.instance;
    // One row before the window establishes the state we open in.
    final prior = await db.query(
      'band_events',
      columns: ['ts', 'event_id'],
      where: 'ts < ? AND event_id IN (?, ?)',
      whereArgs: [loSec, onId, offId],
      orderBy: 'ts DESC',
      limit: 1,
    );
    final rows = await db.query(
      'band_events',
      columns: ['ts', 'event_id'],
      where: 'ts >= ? AND ts < ? AND event_id IN (?, ?)',
      whereArgs: [loSec, hiSec, onId, offId],
      orderBy: 'ts ASC',
    );

    final spans = <List<int>>[];
    int? openAt =
        (prior.isNotEmpty && (prior.first['event_id'] as num).toInt() == offId)
        ? loSec
        : null;
    for (final r in rows) {
      final ts = (r['ts'] as num).toInt();
      final id = (r['event_id'] as num).toInt();
      if (id == offId) {
        openAt ??= ts;
      } else if (openAt != null) {
        if (ts > openAt) spans.add([openAt, ts]);
        openAt = null;
      }
    }
    if (openAt != null && hiSec > openAt) spans.add([openAt, hiSec]);
    return spans;
  }
}
