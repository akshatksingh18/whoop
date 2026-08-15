// ONE-SHOT BACKFILL — stored strain onto the recalibrated 0–21 scale.
//
// The headline strain map changed: it used to be `min(21, ln(TRIMP+1)/ln(1.5))`
// over whole-waking-day TRIMP, which charged ~180 TRIMP of simply being awake
// as training load and put an INACTIVE full-wear day at ~13/21. It is now the
// load earned ABOVE a quiet-waking baseline that scales with the wake window.
// Every day derived before that change carries a number on the old scale, so
// trends, v_daily/coach SQL and the day-detail screen would show a step change
// at the fix date rather than a real one in the user's training.
//
// WHY NOT JUST RE-DERIVE: raw 1 Hz substrate is pruned `rawRetentionDays` (3)
// behind the DATA EDGE. For anything older there is no substrate — the engine
// logs "no substrate (raw pruned) — kept" and keeps the old row — so a
// kAlgoVersion bump alone can only ever fix the last few days.
//
// It does not need raw. Strain is a pure function of (TRIMP, wake minutes,
// sex), and `metric_series` already stores `trimp`, `worn_min` and `tst_min`
// for every derived day, so the headline can be rebuilt exactly from what is
// on disk. (`series.strain_curve` carries one point per wake minute, and on a
// real bundle its length equals `worn_min − tst_min` — the reconstruction of
// the wake window used here is the same one the pipeline fed the scorer.)

import 'dart:convert';

import 'package:openstrap_analytics/onehz.dart' as ana;

import '../data/db.dart';
import 'derivation_engine.dart' show kAlgoVersion, rawRetentionDays;

/// `compute_freshness` key marking the rescale as already applied. Bumped with
/// the algo version so a future rescale is a new one-shot rather than a no-op.
const String kStrainRescaleKey = 'strain_rescale_v63';

class StrainBackfillResult {
  /// Days whose `metric_series` strain was rewritten (trends / v_daily).
  final int seriesDays;

  /// Days that got a fresh `day_result` row at the current algo version.
  final int bundleDays;

  /// Days left exactly as they were because they could not be rescaled.
  final int skipped;

  const StrainBackfillResult({
    required this.seriesDays,
    required this.bundleDays,
    required this.skipped,
  });

  bool get didWork => seriesDays > 0 || bundleDays > 0;
}

/// Rebuild one day's headline strain from its stored scalars.
///
/// Returns null when the day cannot be rescaled — no TRIMP to rescale from, or
/// no wake window to price the baseline over. A day that cannot be rescaled is
/// LEFT ALONE: an un-rescalable day must not silently become 0, which is a
/// number, not an absence.
double? rescaledStrain({
  required double? trimp,
  required double? wornMin,
  required double? tstMin,
  required bool female,
}) {
  if (trimp == null || wornMin == null) return null;
  final wake = wornMin - (tstMin ?? 0);
  if (wake <= 0) return null;
  return ana.strainScore(trimp, wakeMinutes: wake, female: female);
}

/// Rescale every stored day that can no longer be re-derived from raw.
///
/// [female] selects the Banister constant for the quiet-waking baseline; it has
/// to match the constant the stored TRIMP was scored with or the subtraction is
/// off by the male/female coefficient. Runs once — set [force] to re-run.
Future<StrainBackfillResult> backfillStrainScale({
  required bool female,
  bool force = false,
}) async {
  const none = StrainBackfillResult(seriesDays: 0, bundleDays: 0, skipped: 0);
  if (!force && await LocalDb.computeFreshness(kStrainRescaleKey) != null) {
    return none;
  }

  final strainRows = await LocalDb.metricSeries('strain');
  if (strainRows.isEmpty) {
    await _markDone();
    return none;
  }

  final trimpBy = await _byDate('trimp');
  final wornBy = await _byDate('worn_min');
  final tstBy = await _byDate('tst_min');

  // The DATA EDGE is the newest day on disk, matching how the pruner measures
  // retention (never the wall clock — a multi-day flash backfill received in
  // one sync must not be treated as old). Days at or after the cutoff still
  // have raw and are LEFT for a real re-derive: writing a patched row at
  // kAlgoVersion here would satisfy the derive gate, which matches
  // algo_version EXACTLY, and a partial patch would stand in for a full
  // re-derivation of the day.
  final days = <String>[
    for (final r in strainRows) ?(r['date'] as String?),
  ]..sort();
  final cutoff = _shiftDays(days.last, -rawRetentionDays);

  var seriesDays = 0;
  var bundleDays = 0;
  var skipped = 0;

  // Days already complete at the current version were rescaled on a prior
  // pass. Read as ONE query so the loop below does not open a `day_result` row
  // just to close it again: this runs once per install-history, and the day
  // this fires is the launch right after an update.
  final alreadyCurrent = await LocalDb.dayResultIds(kAlgoVersion);

  for (final day in days) {
    if (day.compareTo(cutoff) >= 0) continue;
    if (alreadyCurrent.contains(day)) continue;

    // PURE first, DB second. A day with no TRIMP or no wake window cannot be
    // rescaled at all, and reading its bundle to discover that was a whole
    // round trip plus a payload materialisation per unrescalable day.
    final next = rescaledStrain(
      trimp: trimpBy[day],
      wornMin: wornBy[day],
      tstMin: tstBy[day],
      female: female,
    );
    if (next == null) {
      skipped++;
      continue;
    }

    final row = await LocalDb.dayResult(day);
    // A partial/skipped row at the current version is not in `alreadyCurrent`
    // but is still rescaled — same check as before, just reached less often.
    if (row != null &&
        ((row['algo_version'] as num?)?.toInt() ?? 0) >= kAlgoVersion) {
      continue;
    }

    if (row == null) {
      // A series row with no bundle behind it: still worth fixing the trend.
      await LocalDb.putMetricSeriesValue(day, 'strain', next);
      seriesDays++;
      continue;
    }

    final payload = _decode(row['payload_json']);
    if (payload == null) {
      skipped++;
      continue;
    }
    final scalars = payload['scalars'];
    if (scalars is! Map) {
      skipped++;
      continue;
    }
    scalars['strain'] = next;

    // The intraday curve is cumulative strain, one point per wake minute, built
    // from per-sample HR that no longer exists — it cannot be rescaled, and its
    // last point IS the old headline. A curve ending at 12.79 under a headline
    // of 9.03 contradicts itself, so it is DROPPED rather than left to disagree.
    final series = payload['series'];
    if (series is Map) series.remove('strain_curve');

    final partial = (row['partial'] as num?)?.toInt() == 1;
    await LocalDb.putDayResult(
      dayId: day,
      algoVersion: kAlgoVersion,
      payloadJson: jsonEncode(payload),
      windowJson: (row['window_json'] as String?) ?? '{}',
      finalized: (row['finalized'] as num?)?.toInt() == 1,
      skipped: (row['skipped'] as num?)?.toInt() == 1,
      partial: partial,
      rhr: (row['rhr'] as num?)?.toDouble(),
      rmssd: (row['rmssd'] as num?)?.toDouble(),
      readiness: (row['readiness'] as num?)?.toDouble(),
      // `putDayResult` skips the series write for a partial row, so only count
      // the trend as rewritten when it actually was.
      series: {'strain': next},
    );
    bundleDays++;
    if (!partial) seriesDays++;
  }

  await _markDone();
  return StrainBackfillResult(
    seriesDays: seriesDays,
    bundleDays: bundleDays,
    skipped: skipped,
  );
}

Future<void> _markDone() =>
    LocalDb.putComputeFreshness(kStrainRescaleKey, jsonEncode({'done': true}));

Future<Map<String, double>> _byDate(String key) async {
  final out = <String, double>{};
  for (final r in await LocalDb.metricSeries(key)) {
    final d = r['date'] as String?;
    final v = (r['value'] as num?)?.toDouble();
    if (d != null && v != null) out[d] = v;
  }
  return out;
}

Map<String, dynamic>? _decode(Object? json) {
  if (json is! String) return null;
  try {
    final v = jsonDecode(json);
    return v is Map ? v.cast<String, dynamic>() : null;
  } catch (_) {
    return null;
  }
}

/// Shift a 'YYYY-MM-DD' label by [days] calendar days.
String _shiftDays(String day, int days) {
  final t = DateTime.parse(day).add(Duration(days: days));
  final mm = t.month.toString().padLeft(2, '0');
  final dd = t.day.toString().padLeft(2, '0');
  return '${t.year}-$mm-$dd';
}
