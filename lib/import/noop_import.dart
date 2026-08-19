// noop_import.dart — import NOOP's own data into the local store.
//
// TWO SOURCES, ONE PIPELINE. NOOP exports its history two ways and users pick
// whichever their platform offers:
//   • the raw-sensor CSV (Android only — "Export → raw sensor CSV")
//   • `.noopbak`, a full backup: a ZIP around NOOP's own SQLite database, which
//     is the ONLY option on iOS
// Both carry the same 1 Hz signal family, so both stream through [NoopIngest]
// and derive at full fidelity, identical to a live band sync. This file owns the
// CSV reader and routes a backup to [NoopBackupImporter]; the day model, step
// banking and out-of-order contract live in noop_ingest.dart.
//
// CSV SCHEMA AS SHIPPED (observed 2026-08, NOOP 9.1/9.2 — OpenStrap/edge#160):
//   unix_s,iso_utc,stream,hr_bpm,rr_ms,grav_x,grav_y,grav_z,step_counter,
//   ppg_bpm,ppg_conf,spo2_red,spo2_ir,skintemp_raw,resp_raw,band_sleep_state,
//   event_kind,event_payload
// `band_sleep_state` was INSERTED at index 15, shifting event_kind/event_payload
// to 16/17 (the older documented layout, still in [_defaultCols], ends at
// event_payload=16). Columns are read by NAME from the header, never by fixed
// position — that is what absorbed this drift without misparsing. Streams now
// seen: hr, rr, gravity, skintemp, steps, band_sleep_state, ppghr, event. Note
// `spo2` and `resp` rows are no longer emitted at all even though their columns
// survive in the header.
//
// WHAT WE CONSUME, AND WHY NOT THE REST:
//   • hr / rr / gravity / skintemp / spo2 → the Substrate (full 1 Hz analytics).
//   • steps → `live_coverage` as a REAL step count.
//   • band_sleep_state → deliberately ignored. `segmentSleep` is the single sleep
//     source (a second one would contradict it), and in the real #160 export this
//     column was constant 0 across all 12,663 rows — no signal to gain.
//   • ppghr → deliberately ignored. The `hr` stream already covers every second
//     the export carries, and PPG-derived HR is not trusted as a substitute.
//   • resp_raw → ignored; respiration rate is derived from RR downstream.
// An unrecognised future `stream` also lands in the default branch and is skipped
// safely, so a further NOOP schema change degrades rather than throws.
//
// LARGE FILES: a 90-day export is hundreds of MB / tens of millions of rows, so
// we NEVER load the file or build one big Substrate. We STREAM it and derive in
// a 2-day sliding window (the day model needs the prior evening for a sleep that
// starts before midnight), writing + freeing each day as we go. Memory stays
// flat (~2 days) regardless of file size.

import 'dart:convert';
import 'dart:io';

import '../compute/derivation_engine.dart';
import '../compute/profile.dart';
import 'import_container.dart';
import 'noop_backup_import.dart';
import 'noop_ingest.dart';

export 'noop_ingest.dart' show StepRun, RowOrder;

/// Last path segment, for error messages (avoids a `package:path` import just
/// for this one use).
String _basenameOf(String path) =>
    path.contains('/') ? path.substring(path.lastIndexOf('/') + 1) : path;

class NoopImportResult {
  final int days;
  final int rows;

  /// Real steps recovered from the band's cumulative step counter and banked as
  /// `live_coverage` (0 when the source carries no steps).
  final int steps;

  /// Rows whose local date had ALREADY been derived and pruned by the time they
  /// appeared (a genuinely out-of-order source). They cannot be folded back in,
  /// so they are counted here rather than silently dropped — a non-zero value
  /// means the source was not fully time-ordered.
  final int lateRows;

  /// Dates the source presented out of order, after a later date had already
  /// opened. They were used as context for the following day but never derived
  /// in their own right, so they are missing from the import — reported so an
  /// unordered source is visible rather than quietly short.
  final Set<String> strandedDates;

  NoopImportResult(this.days, this.rows,
      [this.lateRows = 0, this.steps = 0, this.strandedDates = const {}]);
}

class NoopImporter {
  /// Import [path] — a raw-sensor CSV, a ZIP holding one, or a `.noopbak` full
  /// backup — and derive each day at full 1 Hz fidelity via [engine].
  /// [onProgress] reports days written so far. Never loads the whole source.
  static Future<NoopImportResult> importFile(
    String path,
    Profile profile,
    DerivationEngine engine, {
    void Function(int days)? onProgress,
  }) async {
    var file = File(path);
    if (!await file.exists()) {
      throw const FileSystemException('File not found');
    }
    // What did the user actually pick? Feeding a `.noopbak`'s bytes to
    // `utf8.decoder` is what produced "Invalid UTF-8 byte (at offset 10)" in
    // issues #160/#199. Resolve the container first: a backup goes to the
    // database reader, a ZIP of CSVs is unwrapped, and anything unusable throws
    // an [ImportFormatException] naming what we DO want.
    final db = await resolveNoopDatabase(path);
    if (db != null) {
      try {
        return await NoopBackupImporter.importDatabase(
          db.path,
          profile,
          engine,
          onProgress: onProgress,
        );
      } finally {
        await db.dispose();
      }
    }

    final resolved = await resolveImportCsvPaths([path], flavor: 'NOOP');
    if (resolved.paths.isEmpty) {
      await resolved.dispose();
      throw const ImportFormatException(
        'That archive holds no NOOP CSV export.',
      );
    }
    // A NOOP raw-sensor export is ONE CSV. An archive holding several is not
    // something to guess at: this importer streams a single file and derives in
    // a rolling two-day window, so silently taking the first match would import
    // a fraction of the archive and still report success.
    final candidates = resolved.paths
        .where((p) => p.toLowerCase().contains('raw-sensor'))
        .toList();
    final usable = candidates.isEmpty ? resolved.paths : candidates;
    if (usable.length > 1) {
      final names = usable.map(_basenameOf).take(4).join(', ');
      await resolved.dispose();
      throw ImportFormatException(
        'That archive holds ${usable.length} CSV files ($names…). Import the '
        'raw sensor CSV on its own so nothing is silently skipped.',
      );
    }
    file = File(usable.first);

    try {
      return await _importResolvedFile(
        file,
        profile,
        engine,
        onProgress: onProgress,
      );
    } finally {
      // Anything unpacked from an archive is ours to clean up, success or not.
      await resolved.dispose();
    }
  }

  static Future<NoopImportResult> _importResolvedFile(
    File file,
    Profile profile,
    DerivationEngine engine, {
    void Function(int days)? onProgress,
  }) async {
    final ingest = NoopIngest(profile, engine, onProgress: onProgress);

    // Column name → index, parsed from the header row. Reading by NAME (not
    // fixed position) means added/reordered columns in a future export don't
    // misparse — as long as the known column names persist. Falls back to the
    // documented default layout if a header is somehow absent.
    var col = _defaultCols;
    String at(List<String> f, String name) {
      final i = col[name];
      return (i != null && i < f.length) ? f[i] : '';
    }

    // `allowMalformed` — a CSV exported under a non-UTF-8 locale should import
    // with a mangled character in a column we don't read, not abort the whole
    // file. (This is NOT what issues #160/#199 hit; those were ZIPs, handled
    // above. It is the smaller, real second-order problem underneath them.)
    final lines = file
        .openRead()
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter());
    var sawHeader = false;
    String? firstLine;
    await for (final line in lines) {
      if (line.isEmpty || line.startsWith('#')) continue;
      firstLine ??= line;
      if (line.startsWith(kNoopCsvHeader)) {
        sawHeader = true;
        // Header → (re)build the name→index map and skip.
        final h = line.split(',');
        col = {for (var i = 0; i < h.length; i++) h[i].trim(): i};
        continue;
      }
      final f = line.split(',');
      final ts = int.tryParse(at(f, 'unix_s'));
      if (ts == null) continue;
      if (!await ingest.offer(ts)) continue;

      switch (at(f, 'stream')) {
        case 'hr':
          final v = int.tryParse(at(f, 'hr_bpm'));
          if (v != null) ingest.hr(ts, v);
          break;
        case 'rr':
          final v = double.tryParse(at(f, 'rr_ms'));
          if (v != null) ingest.rr(ts, v);
          break;
        case 'gravity':
          ingest.gravity(
            ts,
            double.tryParse(at(f, 'grav_x')),
            double.tryParse(at(f, 'grav_y')),
            double.tryParse(at(f, 'grav_z')),
          );
          break;
        case 'spo2':
          ingest.spo2(
            ts,
            int.tryParse(at(f, 'spo2_red')),
            int.tryParse(at(f, 'spo2_ir')),
          );
          break;
        case 'skintemp':
          ingest.skinTemp(ts, int.tryParse(at(f, 'skintemp_raw')));
          break;
        case 'steps':
          final v = int.tryParse(at(f, 'step_counter'));
          if (v != null) ingest.stepCounter(ts, v);
          break;
        // band_sleep_state / ppghr / resp / event: intentionally not consumed —
        // see the stream inventory in the file header for why each is skipped.
        // An unknown future `stream` value also lands here and is skipped safely.
        default:
          break;
      }
    }

    // A file we could read but could not USE is a failure, not a "0 days"
    // success. Without a recognised header the positional fallback silently
    // misparses (it is the pre-drift layout), and a localized or unrelated CSV
    // simply drops every row — both used to end at "NOOP: imported 0 days",
    // which reads as "the app is broken" with nothing to act on.
    if (ingest.rows == 0) {
      final head = firstLine ?? '';
      final preview = head.isEmpty
          ? ''
          : ' (first line: "${head.length > 80 ? '${head.substring(0, 80)}…' : head}")';
      throw ImportFormatException(
        sawHeader
            ? 'That NOOP export has a header we recognise but no rows we could '
                'read — every row was empty or out of range.'
            : 'That file does not look like a NOOP raw-sensor export: no '
                '"unix_s,…" header row was found$preview. In NOOP, use '
                'Export → raw sensor CSV, or import a .noopbak backup.',
      );
    }

    await ingest.finish();
    return NoopImportResult(ingest.days, ingest.rows, ingest.lateRows,
        ingest.steps, ingest.strandedDates);
  }

  /// Documented default column order (used only if the export omits its header).
  static const Map<String, int> _defaultCols = {
    'unix_s': 0, 'iso_utc': 1, 'stream': 2, 'hr_bpm': 3, 'rr_ms': 4,
    'grav_x': 5, 'grav_y': 6, 'grav_z': 7, 'step_counter': 8, 'ppg_bpm': 9,
    'ppg_conf': 10, 'spo2_red': 11, 'spo2_ir': 12, 'skintemp_raw': 13,
    'resp_raw': 14, 'event_kind': 15, 'event_payload': 16,
  };

  /// Both live in [NoopIngest] now; kept here so existing callers and tests that
  /// reach for them through the importer keep working.
  static List<StepRun> stepRuns(
    Map<int, int> samples, {
    List<List<int>> covered = const [],
  }) =>
      NoopIngest.stepRuns(samples, covered: covered);

  static RowOrder decideRow(
          String date, String? curDate, Set<String> derived) =>
      NoopIngest.decideRow(date, curDate, derived);

  static const int stepRunMaxGapSec = NoopIngest.stepRunMaxGapSec;
}
