// Local raw-first storage (SQLite via sqflite).
//
// Durable storage layers:
//   decoded_onehz — canonical per-second decoded substrate, keyed by rec_ts.
//   decoded_rr    — sparse RR beats for that substrate, keyed by (rec_ts, beat_index).
//   samples       — legacy header cache kept only for backward-compat fallback.
//
// `counter` (u32 @[3:7]) is still kept as the strap's record id, but analytics
// read from canonical decoded tables keyed by physiological time so replayed or
// duplicated historical seconds cannot bloat compute.

import 'package:whoop_companion/migration/legacy_names.dart';
import 'package:whoop_companion/migration/store_migration.dart';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:whoop_protocol/whoop_protocol.dart' as proto;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../compute/substrate.dart' show beatTimesMs;
// The ONE thing this layer takes from compute/: the running build's algo
// version, which every day_result read applies as a CEILING (see
// [DayResultStore.read]). `show` keeps the rest of the engine out of this
// namespace.
import '../compute/derivation_engine.dart' show kAlgoVersion;
import '../import/import_container.dart';
import 'day_label.dart';
import 'day_zone_store.dart';
import 'calculation_store.dart';
import '../gps/workout_clock.dart';
import 'journal_fields.dart';
import 'lift_log.dart' show LiftLogDb;
import 'body_log.dart' show BodyLogDb;
import 'pushups.dart' show PushupDb;
import 'live_coverage_policy.dart';
import 'models.dart';
import 'nutrition_store.dart';
import 'observation.dart';
import 'series_codec.dart';
import 'sleep_correction.dart';
import '../build_profile.dart';

part 'notif_fired_store.dart';
part 'sleep_nap_store.dart';
part 'journal_store.dart';
part 'sleep_override_store.dart';
part 'workout_route_store.dart';
part 'session_store.dart';
part 'workout_suggestion_store.dart';
part 'step_coverage_store.dart';
part 'sync_ledger_store.dart';
part 'diagnostics_store.dart';
part 'compute_job_store.dart';
part 'metric_series_store.dart';
part 'compute_freshness_store.dart';
part 'series_reencode_store.dart';
part 'sleep_intermediate_store.dart';
part 'storage_retention_store.dart';
part 'frozen_headline_store.dart';
part 'cursor_store.dart';
part 'device_store.dart';
part 'observation_store.dart';
part 'day_result_store.dart';
part 'day_provenance_store.dart';
part 'backup_import_store.dart';

/// The outcome of a database rebuild: why the old file would not open, where it
/// was parked, and how many rows came back per table.
typedef DbRebuild = ({
  String cause,
  String quarantinePath,
  Map<String, int> salvaged,
});

class DbImportException implements Exception {
  DbImportException(this.cause, Map<String, int> counts)
    : counts = Map.unmodifiable(counts);
  final Object cause;
  final Map<String, int> counts;
  int get records => counts.entries
      .where((e) => !e.key.startsWith('_'))
      .fold(0, (a, e) => a + e.value);
  @override
  String toString() =>
      '$records rows committed before restore stopped. Retry the same backup to continue. $cause';
}

// ── SUBSTRATE ADMISSION — the one predicate that decides what may become a
//    number ───────────────────────────────────────────────────────────────────
//
// THE THREE PROVENANCE COLUMNS ON `decoded_onehz` / `decoded_rr`, AND THE RULE
// THAT THEY DO NOT OVERLAP:
//
//   device_id      WHICH UNIT.       '' is the primary band, permanently
//                                    (see [_createDecodedStore]); a real id
//                                    belongs to a secondary.
//   device_family  THE CALIBRATION KEY. Which sensor's constants a metric must
//                                    look itself up under. NULL = unknown, and
//                                    unknown is its own case, never gen4.
//   source         THE ADMISSION FLAG. NULL = the primary band. Non-NULL names
//                                    the adapter that wrote the row.
//
// None of the three is a stand-in for another. `source` in particular is NOT a
// provenance id you may read to find out what a row came from — `device_id` and
// `device_family` are — it exists so this file can answer ONE question in SQL:
// may this row become a number?
//
// Why an adapter's rows are stored but not derived by default: correctness of a
// community decoder cannot be enforced by review, and a decoder with a 2x scale
// error reads a resting 50 bpm as 100 and passes every generic physiological
// bound. So an unverified adapter's seconds bank, sync, back up and show up in
// diagnostics — and produce no metric at all until the owner has held that
// hardware in his own hands (ASSUMPTIONS R6/E5/E6). Silent, on purpose: the
// alternative is a plausible wrong number, which is the one failure this
// project treats as worse than an absent one.
//
// NOTE THE DIFFERENCE FROM MULTIBAND_PLAN §3.3, which said a verified adapter
// would write `source IS NULL` and so need no read-side change. It is written
// the other way round here — every non-band writer stamps its id, always, and
// ADMISSION IS A READ-SIDE DECISION — for two reasons that only show up later:
// verification is then REVOCABLE (a decoder bug found in an adapter is one
// edit to [derivableSourceSql], not a data migration over rows that can no
// longer be told apart), and `source` keeps meaning something after a strap is
// verified, which is what lets [kPrimaryBandSourceSql] below still exist.

/// SQL fragment for every read whose rows may become a NUMBER — a metric, a
/// baseline, a session aggregate, a day that gets derived.
///
/// [col] is the column expression, so a joined query passes `'d.source'`.
///
/// Only the primary band (`source IS NULL`) is admitted: the WHOOP 4 is the
/// only band the owner has personally held and cross-confirmed (ASSUMPTIONS
/// R6), and it writes no source id. Admitting a verified adapter later is an
/// edit here (`... OR $col IN ('<id>')`), with SQL-safe `[a-z0-9_]` ids.
String derivableSourceSql([String col = 'source']) => '$col IS NULL';

/// SQL fragment for the reads that mean THE PRIMARY BAND SPECIFICALLY, not
/// "admitted to derive" — they look identical today and they are not the same
/// question, which is the whole reason both have names.
///
/// Three sites, one meaning each: where the band's own data starts and ends,
/// how far the band has synced, and what we are willing to write into the
/// operating system's health store under our name. A verified chest strap must
/// widen [derivableSourceSql] and must NOT widen this one.
const String kPrimaryBandSourceSql = 'source IS NULL';

class LocalDb {
  static Database? _db;
  // A restore belongs to the store lifetime in which it started. Reset clears
  // persistent cursors, so its cancellation generation must not live in them.
  static int _restoreResetGeneration = 0;
  static int _resetsInFlight = 0;
  static bool _restoreStillCurrent(int generation) =>
      _resetsInFlight == 0 && generation == _restoreResetGeneration;
  static StateError get _restoreResetError => StateError(
    'Restore stopped because your data was reset. The backup file is unchanged.',
  );

  /// The owned store file name. The installed original is migrated to it by
  /// [StoreMigration] the first time this name is opened.
  static const String kStoreFileName = 'whoop.db';
  static String dbName = kStoreFileName;

  /// What this process's store resolution did, for diagnostics. Null until
  /// the store is first opened, and for a test-chosen [dbName].
  static StoreResolution? lastStoreMove;

  // One resolution per databases directory, shared by concurrent openers so
  // two first opens never run two migrations.
  static (String, Future<String>)? _resolved;

  /// The store path to open: [dbName], or for the owned name the result of
  /// migrating the installed original to it.
  static Future<String> _storePath() async {
    final dir = await getDatabasesPath();
    if (dbName != kStoreFileName) return p.join(dir, dbName);
    final known = _resolved;
    final name = known != null && known.$1 == dir
        ? known.$2
        : (_resolved = (dir, _resolve(dir))).$2;
    return p.join(dir, await name);
  }

  static Future<String> _resolve(String dir) async {
    final r = await StoreMigration.resolve(
      dir,
      current: kStoreFileName,
      legacy: LegacyNames.databaseFile,
    );
    lastStoreMove = r;
    return r.name;
  }

  static Future<Database> get instance async {
    final db = _db;
    // `_db != null` is NOT enough: the platform can close the underlying
    // database on background teardown without our close() ever nulling
    // `_db`. A plain `_db ??=` then keeps handing back that dead handle, and
    // every write throws `DatabaseException(attempt to re-open an already-closed
    // object)` — a sustained crash burst (seen in the wild on background event
    // ingest). Reopen whenever the cached handle isn't actually open.
    if (db != null && db.isOpen) return db;
    final opened = await _openOrRebuild();
    await DayZoneStore.hydrate(opened);
    return _db = opened;
  }

  /// Set when [_openOrRebuild] had to quarantine an unopenable database and
  /// rebuild. Null on every normal launch. AppState reads it so the user is
  /// TOLD what happened and what survived — a rebuild that happens silently is
  /// indistinguishable from data vanishing.
  static DbRebuild? lastRebuild;

  // Order: independent tables; all use INSERT OR REPLACE so re-import is safe.
  static const _importTables = [
    // Hand-entered rows first. Nothing regenerates these, so if a merge is
    // ever cut short (an OOM, a damaged source) they are the ones already
    // banked. They were also simply MISSING here until now — nutrition,
    // medication, strength sets, symptoms and routes did not survive a
    // backup/restore round trip at all, the same omission `wipeAll` documents.
    'lift_log',
    'pushup_session',
    'body_measure',
    'body_photo',
    'journal',
    'journal_metric',
    'journal_field_def',
    'lab_result',
    'lab_marker_def',
    'strength_set',
    'exercise_def',
    'food_entry',
    'food_def',
    'meal_template',
    'food_day_mark',
    'food_day_count',
    'body_weight',
    'body_weight_reading',
    'day_zone',
    'zone_change',
    'live_coverage',
    'med_def',
    'med_dose',
    'cycle_log',
    'cycle_symptom',
    'breathing_session',
    // Vendor-computed, typed-in and imported scalars. In the hand-entered
    // block because a third of it IS hand-entered and nothing regenerates
    // any of it — a `reports` band trims its own history, and the app whose
    // export the imported rows came from may be uninstalled by now.
    'observation',
    'workout_route',
    'workout_split',
    'session_detail',
    // The user's sleep corrections. These are the ONLY copy of them — the
    // detector's output is deliberately not baked in, so a restore that
    // skipped these would silently reinstate every nap the user had deleted
    // and lose every one they logged.
    'sleep_override',
    'sleep_nap',
    'samples',
    'events',
    'decoded_onehz',
    'decoded_rr',
    // The only copy of what a paired sensor measured during a session — the
    // band cannot re-deliver it, so a restore that skipped it loses it.
    'external_hr',
    // Re-readable from the health store, but only for as long as that app is
    // installed and that permission is granted — cheaper to carry.
    'imported_measurement',
    // Same reasoning, and more so: a route is thousands of points that the
    // source app may have deleted since. `workout_route` is already in this
    // list above and carries the imported routes too.
    'imported_workout',
    // The never-pruned archive of frames we could not decode. exportCopy()
    // is a whole-database VACUUM INTO, so these rows DO leave the device —
    // leaving the table out here meant a backup/restore round trip silently
    // dropped them, in the one table whose entire purpose is that a frame is
    // never lost. Keyed by `hex`, so two same-counter frames from different
    // boots both survive the merge.
    'raw_archive',
    'band_events',
    'band_battery',
    'day_result',
    'metric_series',
    'metric_series_version',
    'sessions',
    'notifications',
    'baselines',
    // The devices this phone knows about — so a SECONDARY device's identity
    // survives a backup/restore round trip rather than leaving its rows in
    // `decoded_onehz` pointing at a `device_id` nothing can name. The PRIMARY
    // row is deliberately skipped on the way in; see the guard below.
    'device',
    'sync_cursor',
  ];

  /// Every table [BackupImportStore._mergeFromDbFile] carries, and the subset a
  /// damaged-file salvage carries; `test/data/table_coverage_test.dart` keeps
  /// them complete.
  @visibleForTesting
  static List<String> get salvageTablesForTest => _salvageTables;
  @visibleForTesting
  static List<String> get importTablesForTest => _importTables;

  /// What a rebuild tries to save, in the order it tries — most irreplaceable
  /// first, so a salvage that gets cut short (a genuinely corrupt file gives up
  /// partway) has already banked the rows nothing can regenerate.
  ///
  /// Everything in the first block was typed by a human. Nothing re-measures
  /// it, nothing re-derives it, and it is not in the band's flash. The second
  /// block is measured-once data whose raw substrate is pruned at
  /// `rawRetentionDays`, so it is equally unrecoverable in practice. The third
  /// is the 3-day substrate: re-syncable in principle, but the band trims its
  /// flash as we ACK, so in practice this is the only copy of those days too.
  static const _salvageTables = [
    // Hand-entered. The only copy that exists anywhere.
    'lift_log',
    'pushup_session',
    'body_measure',
    'body_photo',
    'journal',
    'journal_metric',
    'journal_field_def',
    'lab_result',
    'lab_marker_def',
    'strength_set',
    'exercise_def',
    'food_entry',
    'food_def',
    'meal_template',
    'food_day_mark',
    'food_day_count',
    'body_weight',
    'body_weight_reading',
    'day_zone',
    'zone_change',
    'live_coverage',
    'med_def',
    'med_dose',
    'cycle_log',
    'cycle_symptom',
    'sleep_override',
    'sleep_nap',
    'breathing_session',
    'sessions',
    'workout_route',
    'workout_split',
    'session_detail',
    // Imported or paired-sensor rows: the source app or sensor cannot
    // re-deliver them, so they are as irreplaceable as typed ones.
    'observation',
    'external_hr',
    'imported_measurement',
    'imported_workout',
    // Derived once, from raw that no longer exists.
    'day_result',
    'metric_series',
    'metric_series_version',
    'baselines',
    'raw_archive',
    'sync_cursor',
    // The retention window. Big, and last for that reason.
    'decoded_onehz',
    'decoded_rr',
    'samples',
    'events',
    'band_events',
    'band_battery',
  ];

  /// [_open], plus the one recovery that exists for a database that will not
  /// open at all.
  ///
  /// `onUpgrade` runs inside ONE exclusive transaction, so a step that throws
  /// rolls the whole ladder back, the on-disk `user_version` never advances,
  /// and the SAME step throws on the next launch, and the next. Every guard in
  /// the ladder above was added reactively, after a build shipped that bricked
  /// somebody — so the ladder will trip again. What was missing was what
  /// happens next: the app sat on the loading screen forever and reinstalling
  /// was the only way out, which takes the hand-typed entries with it.
  ///
  /// So: never delete, never wipe. Move the unopenable file aside, create a
  /// fresh one at the current schema, and merge back everything the old file
  /// will still hand over — [_salvageTables] order, each table guarded on its
  /// own, so one unreadable table costs that table and nothing else. The
  /// quarantined file STAYS on disk: if the salvage got less than everything,
  /// the rest is still in there and can be handed to a human.
  static Future<Database> _openOrRebuild() async {
    try {
      return await _open();
    } catch (e) {
      final path = await _storePath();
      // A UNIQUE quarantine name every time. A fixed one would let a SECOND
      // rebuild overwrite the first rebuild's file — the one holding whatever
      // the tolerant salvage could not read — which is the one outcome this
      // whole path exists to prevent. Disk is the cheaper thing to spend here.
      final quarantine =
          '$path.unopenable-${DateTime.now().millisecondsSinceEpoch}';
      // The -wal/-shm siblings belong to the file being moved. Leaving them
      // beside a FRESH database of the same name hands that database someone
      // else's journal, which is how a recovery corrupts the thing it just
      // created. All three move together or none of them do — a rebuild that
      // cannot quarantine cleanly must fail loudly rather than half-destroy.
      final moved = <String>[];
      final Database fresh;
      try {
        for (final suffix in const ['', '-wal', '-shm']) {
          final f = File('$path$suffix');
          if (!f.existsSync()) continue;
          await f.rename('$quarantine$suffix');
          moved.add(suffix);
        }
        fresh = await _open();
      } catch (_) {
        // A sibling move or the fresh open failed. Restore every file already
        // moved, including when quarantine stopped halfway; otherwise a retry
        // can create an empty main file beside the original WAL. The main file
        // returns last, after its journals. A refused rollback still throws and
        // leaves the unrecovered bytes in quarantine for manual recovery.
        for (final suffix in moved.reversed) {
          await File('$quarantine$suffix').rename('$path$suffix');
        }
        rethrow;
      }
      // Published BEFORE the salvage so `BackupImportStore._mergeFromDbFile`'s
      // own `instance` resolves to the new file instead of re-entering this
      // method.
      _db = fresh;
      var salvaged = const <String, int>{};
      try {
        // `_days` is the importer's bookkeeping key, not a table. The rebuild
        // card prints this map verbatim, so it read "Recovered: … _days 312 …"
        // as though a table by that name had survived — or "Empty: _days" as
        // though one had been lost. Drop it here; the card is the one surface
        // whose whole job is telling the truth about a data-loss event.
        salvaged = Map.of(
          await BackupImportStore._mergeFromDbFile(
            quarantine,
            only: _salvageTables,
            tolerant: true,
          ),
        )..remove('_days');
      } catch (_) {
        // The quarantined file gave us nothing. The app still opens, and the
        // file is still there — that is the whole point of not deleting it.
      }
      lastRebuild = (
        cause: '$e',
        quarantinePath: quarantine,
        salvaged: salvaged,
      );
      return fresh;
    }
  }

  static Future<void> close() async {
    _resolved = null;
    NutritionDb.resetCountingContext();
    DayClock.install([], []);
    if (_db != null) {
      await _db!.close();
      _db = null;
    }
  }

  /// Runs a write against a guaranteed-open handle, reopening ONCE if the
  /// cached handle was closed under us mid-write.
  ///
  /// `instance` validates `isOpen` at acquisition, but the platform can tear
  /// the database down in the window between acquiring the handle and the
  /// write actually executing (a TOCTOU race — worst on background ingest that
  /// awaits non-DB work, e.g. event parsing, between acquiring `db` and using
  /// it). That surfaced as a sustained `DatabaseException(attempt to re-open an
  /// already-closed object)` burst on the `events` insert (Crashlytics 0.9.13,
  /// processState=BACKGROUND). On that exception we drop the dead handle so the
  /// retry reopens. For best-effort ingest ([bestEffort]) a still-closed DB
  /// after the retry is swallowed — the band re-sends these rows and crashing
  /// the app over a non-durable event write is never the right trade. The
  /// durable sync-commit path leaves it false so a genuine failure still throws
  /// and the HISTORY_END ACK is withheld (safe-trim invariant).
  static Future<T?> _guardedWrite<T>(
    Future<T> Function(Database db) op, {
    bool bestEffort = false,
  }) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      Database? handle;
      try {
        handle = await instance;
        return await op(handle);
      } on DatabaseException catch (e) {
        final closed =
            e.toString().contains('closed') || !(handle?.isOpen ?? false);
        if (closed && attempt == 0) {
          // Drop only the dead handle we actually used. A concurrent caller may
          // have already reopened `_db` to a fresh handle between our failure
          // and here — keep that one so `instance` reuses it on the retry
          // instead of forcing a redundant reopen.
          if (identical(_db, handle)) _db = null;
          continue;
        }
        if (bestEffort && closed) return null;
        rethrow;
      }
    }
    return null;
  }

  /// The live schema version — the ONE place it is declared. Every
  /// `openDatabase` this class performs (the app DB and the day-export DB) must
  /// pass it: sqflite throws `ArgumentError('onCreate must be null if no
  /// version is specified')` BEFORE opening anything when `onCreate` is given
  /// without `version` (sqflite_common database_mixin.dart).
  static const int schemaVersion = 50;

  /// SQLite caps host parameters per statement (`SQLITE_MAX_VARIABLE_NUMBER` —
  /// only 999 on older SQLite builds). Any `IN (?, ?, …)`
  /// built from row data MUST be chunked below this; a single day of
  /// `decoded_onehz` is 86 400 counters. Same reason `SyncLedgerStore.commitBatch` chunks.
  static const int _maxSqlVars = 500;

  /// THE PRIMARY BAND'S `device_id`, and it is reserved permanently.
  ///
  /// Not a migration default — a standing rule, load-bearing twice over:
  ///  * The newest-wins dedupe on `decoded_onehz` only works while every row
  ///    from the one physical band shares one key value, so a post-reboot
  ///    counter reset and a re-drained record still collide.
  ///  * A BLE `remoteId` is NOT a stable identity (a per-app CBPeripheral
  ///    UUID). Letting one reach the key would
  ///    fragment one band into N identities across reinstalls.
  ///
  /// A SECONDARY device gets a real id, issued by its adapter from something
  /// the band emits across the handshake — never from the link.
  static const String kPrimaryDeviceId = '';

  /// Split [items] into `_maxSqlVars`-sized chunks for `IN (…)` binding.
  static Iterable<List<T>> _sqlVarChunks<T>(List<T> items) sync* {
    for (var i = 0; i < items.length; i += _maxSqlVars) {
      yield items.sublist(
        i,
        i + _maxSqlVars > items.length ? items.length : i + _maxSqlVars,
      );
    }
  }

  static Future<Database> _open() async {
    final path = await _storePath();
    return openDatabase(
      path,
      onConfigure: (db) async {
        // WRITE PERFORMANCE. The default rollback journal (journal_mode=delete)
        // with synchronous=FULL fsyncs the whole DB on every commit — brutal for
        // the high-volume sync-ingest and the raw re-decode migration on a large
        // ledger. WAL + synchronous=NORMAL is the standard mobile config: writers
        // append to a -wal file and don't block readers, with one fsync per
        // checkpoint instead of per commit. journal_mode is persistent per-file;
        // synchronous/cache_size are per-connection so we set them every open.
        // Durability trade-off under NORMAL: a crash/power-loss can lose only the
        // last uncheckpointed transactions, never corrupt the DB — fine here since
        // raw is re-syncable from the band and derived is recomputable.
        //
        // CRITICAL: a perf PRAGMA must NEVER prevent the DB from opening (a throw
        // here fails openDatabase → the app is stuck on the loading screen). And
        // `PRAGMA journal_mode=WAL` RETURNS A ROW ("wal"), so on the iOS sqflite
        // Darwin backend it MUST be issued via rawQuery — `execute()` on a
        // value-returning pragma throws DatabaseException("not an error") and
        // bricks the open (confirmed on device). So: rawQuery + try/catch.
        try {
          await db.rawQuery('PRAGMA journal_mode=WAL');
        } catch (_) {
          /* keep the default journal — this is a perf tweak, not a requirement */
        }
        try {
          await db.execute('PRAGMA synchronous=NORMAL');
          // ~40 MB page cache (negative = KiB) so hot b-tree pages stay resident
          // on a 150 MB+ DB instead of being re-read from disk each query.
          await db.execute('PRAGMA cache_size=-40000');
        } catch (_) {
          /* non-fatal */
        }
      },
      onCreate: (db, version) async {
        await _createSamples(db);
        await _createDecodedStore(db);
        await db.execute('CREATE INDEX idx_samples_ts ON samples(ts)');
        await _createEvents(db);
        await _createBandSignals(db);
        await _createRawArchive(db);
        await _createDerived(db);
        await _createDayResult(db);
        await _createUserTables(db);
        await _createSyncState(db);
        await _createSyncCursor(db);
        await _createComputeState(db);
        await _createPrimitiveArtifacts(db);
        await StepCoverageStore._create(db);
        await _createDevice(db);
        await WorkoutSuggestionStore._create(db);
        await SleepOverrideStore._create(db);
        await SleepNapStore._create(db);
        await WorkoutRouteStore._create(db);
        await SessionStore._createDetail(db);
        await NotifFiredStore._create(db);
        await _ensureCoachViews(db);
      },
      onUpgrade: (db, oldV, newV) async {
        if (oldV < 2) await _createEvents(db);
        if (oldV < 3) {
          // Re-key raw_records by frame hex so LIVE packets (0x28/0x33) — which
          // have no per-record counter — can be queued without PK collisions.
          // Pending unuploaded raw is re-syncable from the band, so a clean
          // rebuild is acceptable.
          await db.execute('DROP TABLE IF EXISTS raw_records');
          await _createRaw(db);
        }
        if (oldV < 4) {
          // The old samples table cached decoded sensor fields (spo2/skin_temp) that
          // (a) were read from MISIDENTIFIED offsets and (b) nothing ever read. The
          // edge no longer decodes sensors — drop + recreate as a header-only index.
          await db.execute('DROP TABLE IF EXISTS samples');
          await _createSamples(db);
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_samples_ts ON samples(ts)',
          );
        }
        if (oldV < 5) {
          // LOCAL-FIRST re-layer: the on-device DerivationEngine now computes the
          // full 1 Hz analytics family from raw and stores PERMANENT derived rows.
          // Purely additive — raw tables are untouched.
          await _createDerived(db);
        }
        if (oldV < 6) {
          // BUCKET-BY-REAL-TIME fix. Add `rec_ts` (epoch SECONDS, the decoded
          // record time) to raw_records and backfill it for every existing row by
          // decoding the stored hex once. The DerivationEngine now buckets days by
          // rec_ts (not captured_at), so a multi-day flash backfill received in one
          // sync no longer collapses into a single "today" bucket. Additive + safe
          // on a populated DB.
          // GUARDED add: an oldV <= 2 DB already had raw_records DROPped and
          // re-created by the step-3 block above using the CURRENT `_createRaw`
          // DDL — which already carries rec_ts. A bare ALTER … ADD COLUMN then
          // threw "duplicate column name: rec_ts", and because onUpgrade runs
          // inside ONE exclusive transaction the whole ladder rolled back and
          // openDatabase rethrew → app stuck on the loading screen, forever.
          await _addRecTsColumn(db);
          await _backfillRecTs(db);
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_raw_rects ON raw_records(rec_ts)',
          );
        }
        if (oldV < 7) {
          // LOCAL-FIRST user-data layer: journal, menstrual cycle log, workout
          // sessions, and the notifications feed — all on-device, additive.
          await _createUserTables(db);
        }
        if (oldV < 8) {
          // RE-KEY raw_records by `counter` (drop the hex PRIMARY KEY, which
          // roughly DOUBLED on-disk size) and PURGE the live high-rate bloat
          // (0x28/0x2B/0x33). CRITICAL: we must NOT drop the 1 Hz historical
          // substrate (0x2F / R24) — the band will not re-send records its read
          // cursor has already passed, and they may not be derived yet, so a
          // blind rebuild would lose real data. Instead: rename aside, create the
          // new counter-keyed table, migrate the historical rows across (their
          // counters are unique), and discard only the live frames + the old
          // hex-PK overhead.
          await db.execute('ALTER TABLE raw_records RENAME TO _raw_old');
          await _createRaw(db);
          await db.execute(
            'INSERT OR IGNORE INTO raw_records '
            '(counter, hex, packet_type, captured_at, rec_ts, uploaded) '
            'SELECT counter, hex, packet_type, captured_at, rec_ts, uploaded '
            'FROM _raw_old WHERE packet_type = 47 AND counter IS NOT NULL',
          );
          await db.execute('DROP TABLE _raw_old');
        }
        if (oldV < 9) {
          // VERSIONED IMMUTABLE DERIVED STORE (ARCHITECTURE_V2 invariant 6).
          // Replace the single-row `derived_day` (PK date) with
          // `day_result(day_id, algo_version)` so an algo bump writes a NEW
          // version instead of mutating, and the serve seam reads the latest
          // version per day. Additive: create the new table and best-effort
          // migrate any existing derived_day rows across at the prior version, so
          // history survives the upgrade (raw is the source of truth regardless).
          await _createDayResult(db);
          try {
            await db.execute(
              'INSERT OR IGNORE INTO day_result '
              '(day_id, algo_version, payload_json, window_json, computed_at, '
              ' finalized, rhr, rmssd, readiness) '
              "SELECT date, 1, payload_json, '{}', computed_at, 0, rhr, rmssd, readiness "
              'FROM derived_day',
            );
          } catch (_) {
            /* derived_day may be absent — fine, raw rebuilds it */
          }
        }
        if (oldV < 10) {
          await _createSyncState(db);
          // RESUMABLE SYNC. Durable key→value cursor store so the historical
          // offload survives app restarts / disconnects: we persist the strap's
          // continuation token + counter/rec_ts high-water BEFORE ACKing a
          // HISTORY_END (the safe-trim invariant), and reconnect detectors read
          // it to tell a stalled cursor from a healthy one. Additive.
          await _createSyncCursor(db);
        }
        if (oldV < 11) {
          await _createDecodedStore(db);
          await _backfillDecodedStore(db);
          // Live workout steps (Tier-A pedometer over the session's 100 Hz
          // R10 accel). Additive nullable column — old rows read null.
          //
          // GUARDED add: an oldV <= 6 DB gets `sessions` from the step-7
          // `_createUserTables` block above, which uses the CURRENT DDL — and
          // that already declares `steps`. A bare ALTER … ADD COLUMN then threw
          // "duplicate column name: steps", rolling back the whole (single,
          // exclusive) onUpgrade transaction so openDatabase rethrew → app
          // permanently stuck on the loading screen.
          await _addColumnIfMissing(db, 'sessions', 'steps', 'INTEGER');
        }
        if (oldV < 12) {
          // PURGE the old 1 Hz step ESTIMATE. 1 Hz can't count steps (Nyquist),
          // and the prior ambulatory-minutes×cadence estimate inflated badly
          // (resting noise cleared the floor → ~100k/day). `steps` is recomputed
          // by the new hybrid (live 100 Hz real count + bounded 1 Hz estimate);
          // wipe the bogus history so trends don't carry it.
          await db.execute("DELETE FROM metric_series WHERE key = 'steps'");
        }
        if (oldV < 13) {
          // 100 Hz step coverage: the device-time windows the live pedometer
          // actually counted, so the 1 Hz estimate can EXCLUDE them (prefer the
          // real count, never double-count). Also drop the stale 'active_min'
          // trend — active-minutes was replaced by the steps hybrid.
          await _createBandSignals(db);
          await _ensureSyncStateSchema(db);
          await StepCoverageStore._create(db);
          await db.execute(
            "DELETE FROM metric_series WHERE key = 'active_min'",
          );
          await db.execute("DELETE FROM metric_series WHERE key = 'steps'");
        }
        if (oldV < 14) {
          await _createComputeState(db);
        }
        if (oldV < 16) {
          // Historically both the v15 and v16 steps called this (idempotent
          // CREATE IF NOT EXISTS); collapsed into one call — any pre-v16 DB
          // gets the primitive_artifacts table exactly once here.
          await _createPrimitiveArtifacts(db);
        }
        if (oldV < 17) {
          await _rebuildCanonicalDecodedStore(db);
        }
        if (oldV < 18) {
          // Menstrual symptom log (full cycle screen) — one row per date, a JSON
          // list of symptom tags + optional note. Separate from cycle_log (whose
          // `date` PK is a period-start marker) so a date can carry both.
          await _createCycleSymptom(db);
        }
        if (oldV < 19) {
          // The v17 step (or a v11-16 origin) may leave OLD counter-keyed decoded
          // tables here; the backfill below writes through the rec_ts-keyed
          // _queueDecodedOneHz, so convert to the current schema first (preserving
          // any existing rows), then reconstruct the rest from raw_records.
          await _rekeyDecodedStoreByRecTs(db);
          await _backfillDecodedStore(db);
          await _dropRawStore(db);
          await _ensureSessionSchema(db); // adds hrr_bpm
          await WorkoutSuggestionStore._create(db);
        }
        if (oldV < 20) {
          await SleepOverrideStore._create(db);
        }
        if (oldV < 21) {
          // FIRMWARE RESILIENCE: durable archive of historical records we could
          // NOT decode (unknown/unsupported version). They used to be dropped
          // unseen — lost forever. Now they land in raw_archive (never pruned)
          // so a future firmware's records can be re-decoded. Also add
          // `millivolts` to band_battery for the battery-health series. Both
          // additive.
          await _createRawArchive(db);
          await _ensureBandBatteryMillivolts(db);
        }
        if (oldV < 22) {
          // GPS workout routes (run/ride/walk). Additive, on-device only —
          // never uploaded, never touches derivation output (no kAlgoVersion
          // bump). Pruned with its session.
          await WorkoutRouteStore._create(db);
        }
        if (oldV < 23) {
          // Additive: per-point smoothed instantaneous speed (m/s), captured
          // for the live speed/pace readout and kept with the point for a
          // future finished-route speed graph. Existing rows get null (no
          // speed was ever recorded for them) — never backfilled/guessed.
          await WorkoutRouteStore._ensureSpeed(db);
        }
        if (oldV < 24) {
          // day_result rows written by _markDaySkipped (a day whose
          // derivation threw) look identical to a real derived day to
          // anything just checking "is there a row at this algo_version" -
          // which is exactly what the raw-pruning guard does. that let a day
          // that failed to derive get treated as safe-to-prune, deleting its
          // raw substrate for good. this column lets the guard tell the two
          // apart. existing rows default to 0 (not skipped) - can't know in
          // hindsight which old rows were skip markers, but going forward
          // this is right.
          await _ensureDayResultSkippedColumn(db);
        }
        if (oldV < 25) {
          // Same class of bug as `skipped` above, different failure mode: the
          // offloaded second-half day-blocks compute (naps/workouts/HRR/wear/
          // curves/wake-features) can throw or time out AFTER the first-half
          // headline scalars (readiness/RHR/RMSSD) already succeeded. That
          // path is non-fatal by design (the day still gets a real,
          // non-skipped day_result row so headline scalars display), but the
          // raw-pruning guard only excluded `skipped` rows - a headline-only
          // partial row still counted as "derived" and let the raw substrate
          // it would need to fill in those missing blocks get pruned for
          // good. This column lets the guard exclude partial rows too.
          // Existing rows default to 0 (not partial) - can't know in
          // hindsight which old rows were partial, but going forward this is
          // right.
          await _ensureDayResultPartialColumn(db);
        }
        if (oldV < 26) {
          // Cross-isolate fire-once for notifications. The dedupe guard used to
          // live entirely in SharedPreferences, where a check and a record are
          // two separate operations — so the foreground and WorkManager derive
          // isolates could both read "not fired" and both alert (issue #136's
          // tail). This table makes the claim a single atomic INSERT OR IGNORE.
          // Purely additive; the legacy prefs keys are migrated lazily on first
          // use by FiredKeyStore, so nothing is lost on upgrade.
          await NotifFiredStore._create(db);
        }
        if (oldV < 27) {
          // `live_coverage` gains a `source` column so a phone-pedometer count
          // can be told apart from the band's 100 Hz wrist count. Existing rows
          // default to 'band', which is what they are.
          //
          // This matters because the two sources must NEVER be summed: they
          // both count the same walk from different places on the body. The
          // reader prefers phone rows for a day when any exist (a
          // pocket-carried pedometer sees gait; a wrist one confuses arm work
          // for steps), and falls back to band rows otherwise.
          await StepCoverageStore._ensureSource(db);
        }
        if (oldV < 28) {
          // The numeric half of a journal entry, plus definitions for
          // user-invented fields. Purely new tables — the existing `journal`
          // row for a day is untouched, so an upgrade loses no tags and no
          // notes, and a day with only tags simply has no metric rows.
          await JournalStore._createMetric(db);
          await JournalStore._createFieldDef(db);
        }
        if (oldV < 29) {
          // Hand-entered blood work. Purely new tables; nothing existing is
          // read or rewritten.
          await _createLabTables(db);
        }
        if (oldV < 30) {
          // Paced-breathing history. New table only.
          await _createBreathingSessions(db);
        }
        if (oldV < 31) {
          // User edits to a day's naps. New table only — the detector's own
          // output is untouched and the edits replay over it.
          await SleepNapStore._create(db);
        }
        if (oldV < 32) {
          // Re-key raw_archive off the volatile `counter` onto frame `hex`.
          // `counter INTEGER PRIMARY KEY` + IGNORE silently DROPPED a distinct
          // undecodable frame whenever a post-reboot counter (reset to ~0)
          // collided with a still-present pre-reboot row — data loss in the
          // "never lose" table. Rebuild keyed by content. Existing rows have
          // unique counters, so the copy loses nothing; at most it collapses an
          // exact-duplicate hex, which is the dedup we want.
          //
          // raw_archive is normally created lazily in onOpen (_repairOpenSchema),
          // NOT in this ladder, so on an old DB it may not exist yet here — in
          // which case there is nothing to migrate and a fresh (hex-keyed) create
          // is all that's needed. DROP the old index name before the fresh CREATE
          // so it can't collide on the name the rename carried onto the aside
          // table (the leaked-`_new`-index footgun documented on the decoded
          // rebuild).
          await _rekeyRawArchiveByHex(db);
        }
        if (oldV < 33) {
          // RE-KEY the decoded ledger off the volatile record `counter` onto
          // rec_ts. The counter resets to ~0 on every reboot, so counter-as-PK
          // let a post-reboot second REPLACE-evict a pre-reboot one — silently,
          // unrecoverably deleting a 1 Hz row (raw_records is dropped).
          await _rekeyDecodedStoreByRecTs(db);
        }
        if (oldV < 34) {
          // Keep the per-second fields the band computes itself instead of
          // decoding and discarding them. Additive columns only — see
          // _ensureDecodedOneHzBandFields. MUST run after the v33 re-key, which
          // rebuilds decoded_onehz from an explicit column list.
          await _ensureDecodedOneHzBandFields(db);
        }
        if (oldV < 35) {
          // Nutrition. Purely new tables — nothing existing is read or
          // rewritten, and water stays in journal_metric.water_ml rather than
          // being duplicated here.
          await createNutritionTables(db);
        }
        if (oldV < 36) {
          // Medication and supplements. New tables only.
          await _createMedTables(db);
        }
        if (oldV < 38) {
          // Strength sets. New tables only — `sessions` is untouched and the
          // sets hang off its id. (37 is reserved for symptoms, UI_WIRING §5.3;
          // skipping it costs nothing, and _repairOpenSchema creates these
          // idempotently anyway if the ladder lands out of order.)
          await _createStrengthTables(db);
        }
        if (oldV < 39) {
          // Make ABSENCE representable in the decoded ledger: the six sensor
          // columns lose their NOT NULL so a record that carried no accel /
          // no optical / no thermal reading stops being written as a real zero.
          await _relaxDecodedSensorNulls(db);
        }
        if (oldV < 40) {
          // `sessions.private` — the per-workout "keep this off the shared
          // surfaces" flag. Existing rows read 0, which is what they have
          // always meant. ADD COLUMN only, deliberately NOT the whole
          // `_ensureSessionSchema`: that also creates an index, which throws on
          // a DB whose `sessions` table this ladder has not created yet — and a
          // throw in here rolls the ENTIRE ladder back and quarantines the
          // user's database. `_addColumnIfMissing` is a no-op on a missing
          // table, and `_repairOpenSchema` does the rest at onOpen.
          await _addColumnIfMissing(
            db,
            'sessions',
            'private',
            'INTEGER NOT NULL DEFAULT 0',
          );
        }
        if (oldV < 41) {
          // Which strap measured the row (see _ensureDeviceFamilyColumns).
          // ADD COLUMN only, idempotent, and a no-op on a table this ladder has
          // not created yet — a throw in here rolls the WHOLE ladder back.
          await _ensureDeviceFamilyColumns(db);
        }
        if (oldV < 42) {
          // ADDITIVE ONLY, and every step is a no-op on a table this ladder has
          // not created yet — a throw in here rolls the WHOLE ladder back.
          //
          //  * decoded_onehz.ambient_raw — the gen4 ambient-light channel,
          //    which until now was decoded and thrown away on every record.
          //  * sessions.trace_json / trace_samples — the frozen session trace.
          //  * metric_series_version — which build's maths wrote each day's
          //    scalars, backfilled from the version day_result already carries.
          //  * band_backlog — the strap's ring-buffer bookkeeping.
          //
          // No rewrite pass and no delete: `onUpgrade` runs inside openDatabase
          // under iOS's CPU watchdog (invariant 11). The raw_archive thinning
          // that lands with this version is deliberately NOT here — it runs on
          // the retention path, off the launch path, where a 500 MB back
          // catalogue can be cleared without a launch hang.
          await _ensureDecodedOneHzBandFields(db);
          await _ensureSessionTraceColumns(db);
          await _createMetricSeriesVersion(db);
          await _backfillMetricSeriesVersion(db);
          await _createBandBacklog(db);
        }
        if (oldV < 43) {
          // `decoded_onehz.source` / `decoded_rr.source` — which SENSOR produced
          // the row (see _ensureSourceColumns), plus the session-scoped landing
          // table for a standard Bluetooth heart-rate sensor. Both are ADD
          // COLUMN / CREATE TABLE only and no-ops on a table this ladder has not
          // created yet — a throw in here rolls the WHOLE ladder back.
          await _ensureSourceColumns(db);
          await _createExternalHr(db);
          await _createImportedMeasurement(db);
          // ADD COLUMN / CREATE TABLE only, each a no-op on a table this ladder
          // has not created yet:
          //  * decoded_onehz.temp_ch2_c / temp_ch3_c / signal_quality_logvar —
          //    the gen5 channels the mapper decoded and dropped (MT-12).
          //  * sessions.rpe — session-level self-reported exertion (TS-09).
          //  * metric_series_version.source — measured vs imported, in every
          //    export (export-provenance), on L13's existing side table.
          //  * workout_split — per-km splits frozen at finalize (CV-01/TS-07),
          //    because `decoded_onehz` is gone at 3 days and cannot be re-read.
          await _ensureDecodedOneHzBandFields(db);
          await _addColumnIfMissing(db, 'sessions', 'rpe', 'REAL');
          await _addColumnIfMissing(db, 'sessions', 'cadence_spm', 'INTEGER');
          await _addColumnIfMissing(
            db,
            'metric_series_version',
            'source',
            'TEXT',
          );
          await WorkoutRouteStore._createSplit(db);
          // LAST, and the only rewrite in this rung: `decoded_onehz.hr` loses
          // its NOT NULL. Runs after every ADD COLUMN above so the rebuild
          // carries them across.
          await _relaxDecodedHrNull(db);
        }
        if (oldV < 44) {
          // GATES 4b — NO SCHEMA CHANGE. The one rung on this ladder that is a
          // data recovery rather than a DDL step: archived records that this
          // build's decoders can now read are replayed into `decoded_onehz`.
          //
          // Here and not on the retention path (where `thinRawArchiveBefore`
          // runs) for two reasons: the recovered seconds are OLDER than the
          // retention edge, so a prune-time replay would insert them and delete
          // them in the same pass; and derivation has to see them, which means
          // landing before the next derive, not after it.
          //
          // Bounded by `redrivableArchiveReasons` precisely so it is not the
          // heavy pass the v42 rung refuses to do here: it is 1,035 short
          // frames on the largest real export, not the 492 MB of v20 hex
          // sitting beside them.
          await redriveArchivedRecords(db);
        }
        if (oldV < 45) {
          // `band_battery.charge_units` — ADD COLUMN, idempotent, a no-op on a
          // table this ladder has not created yet — plus the one-time replay of
          // stored band events into the series that had a reader, a widget and
          // no writer. Both bounded; see _backfillBandBatteryFromEvents for why
          // the replay is safe to run on the launch path and the v42 rung's
          // rewrite was not.
          await _ensureBandBatteryChargeUnits(db);
          await _backfillBandBatteryFromEvents(db);
        }
        if (oldV < 46) {
          // Retire the disproven gen5 columns that v34-era dev builds banked
          // (`on_wrist` / `hr_valid`, plus the -50.00 °C skin-temp sentinel).
          // Data-only: the DDL is untouched, so this does NOT diverge an
          // upgraded install's schema from a fresh one. See
          // _retireDisprovenOneHzColumns for the evidence.
          await _retireDisprovenOneHzColumns(db);
        }
        if (oldV < 47) {
          // Put `device_id` in front of the key of the three stores whose
          // identity was a WHOOP-shaped quantity (a record second, the band's
          // flash counter). The one item on the band-agnostic list that cannot
          // be done after a second device has written — see
          // [_rekeyStoresByDeviceId]. Rewrites no value and moves no derived
          // number, so it ships without a kAlgoVersion bump.
          //
          // LAST on the ladder, after every ADD COLUMN above, because the
          // rebuild reconstructs its DDL from `PRAGMA table_info` and so
          // carries across exactly the columns that exist when it runs.
          await _rekeyStoresByDeviceId(db);
        }
        if (oldV < 48) {
          // The observation store — vendor-computed, typed-in and imported
          // scalars. CREATE TABLE IF NOT EXISTS + two indexes and NOTHING
          // else: no backfill, no rewrite, no ADD COLUMN, nothing read. It is
          // a new empty table, so the CHECK and the UNIQUE index have no
          // existing row to fail on — which matters, because a throw in here
          // rolls the WHOLE ladder back and quarantines the user's database
          // (invariant 11), and this rung runs after the v47 re-key that every
          // upgrading install is already paying for on the launch path.
          //
          // Ships without a kAlgoVersion bump, deliberately: nothing writes
          // this table, nothing reads it, and no derived number can move.
          await _createObservation(db);
        }
        if (oldV < 49) {
          // The device store, and the `live_coverage` column that lets the step
          // ladder tell two sensors apart. CREATE TABLE IF NOT EXISTS + ONE
          // guarded ADD COLUMN: no backfill, no rewrite, nothing read, and both
          // are no-ops on a table this ladder has not created yet — which is
          // what keeps it off the wrong side of invariant 11 (a throw in here
          // rolls the WHOLE ladder back and quarantines the user's database).
          //
          // ADD COLUMN with a constant DEFAULT does not rewrite the table, so
          // this rung is O(1) in `live_coverage` rows rather than O(n) — unlike
          // the v47 re-key every upgrading install is already paying for.
          //
          // Ships without a kAlgoVersion bump: every existing row takes
          // `device_id = ''`, one id is one sensor, and [resolveDaySteps]
          // returns exactly the totals it returned yesterday.
          await _createDevice(db);
          await StepCoverageStore._ensureDeviceId(db);
        }
        if (oldV < 50) {
          await createNutritionTables(db);
          await BodyLogDb.createTables(db);
          await _createBuild90Tables(db);
        }
      },
      onOpen: (db) async {
        await _repairOpenSchema(db);
      },
      version: schemaVersion,
    );
  }

  static Future<void> _repairOpenSchema(Database db) async {
    // Same-version merged builds can still need additive schema repair on an
    // existing install. Keep this idempotent and cheap: create missing tables,
    // indexes, and additive columns the current code assumes are present.
    await _createSamples(db);
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_samples_ts ON samples(ts)',
    );
    await _createEvents(db);
    await _createBandSignals(db);
    await _ensureBandBatteryMillivolts(db);
    await _ensureBandBatteryChargeUnits(db);
    await _createRawArchive(db);
    await _createDerived(db);
    await _createDayResult(db);
    await _createUserTables(db);
    await _createSyncState(db);
    await _createSyncCursor(db);
    await _createComputeState(db);
    await _createPrimitiveArtifacts(db);
    await _createDecodedStore(db);
    // Drop leftover DUPLICATE indexes from an old canonical-store rebuild. When
    // `_rebuildCanonicalDecodedStore` renamed `_decoded_*_new` → `decoded_*`, the
    // temp `_new`-named indexes rode along and now shadow the canonical ones on
    // the SAME columns — so every decoded insert (the hottest write path) updated
    // twice as many b-trees as needed. The canonical indexes are (re)created by
    // _createDecodedStore just above; these `_new` duplicates are pure write tax.
    //
    // Plus `idx_decoded_onehz_counter`, which was never on a read path at all —
    // see _createDecodedStore for why it is gone rather than merely unused.
    for (final ix in const [
      'idx_decoded_onehz_new_rects',
      'idx_decoded_onehz_new_rec_ts_unique',
      'idx_decoded_rr_new_counter',
      'idx_decoded_rr_new_ts',
      'idx_decoded_rr_new_ts_beat_unique',
      'idx_decoded_onehz_counter',
    ]) {
      await db.execute('DROP INDEX IF EXISTS $ix');
    }
    // Older builds stored the rollup's inputs as `crossday_input`; nothing has
    // read it since the rollup builds them fresh on every pass.
    await db.delete(
      'baselines',
      where: 'key = ?',
      whereArgs: ['crossday_input'],
    );
    await StepCoverageStore._create(db);
    await StepCoverageStore._ensureSource(db);
    await StepCoverageStore._ensureDeviceId(db);
    await _createDevice(db);
    await _createExternalHr(db);
    await _createImportedMeasurement(db);
    // CREATE TABLE IF NOT EXISTS on the every-open repair path, and NO schema
    // version bump: this table is additive with no backfill, so the repair pass
    // creates it on a fresh install and on an existing one alike. Spending a
    // version number here would collide with the other branches reaching for
    // the next one, and buy nothing a no-op CREATE does not already do.
    await _createImportedWorkout(db);
    await _createObservation(db);
    await _createCycleSymptom(db);
    await _ensureSessionSchema(db);
    await _ensureSyncStateSchema(db);
    await WorkoutSuggestionStore._create(db);
    await SleepOverrideStore._create(db);
    await SleepNapStore._create(db);
    await WorkoutRouteStore._create(db);
    await SessionStore._createDetail(db);
    await WorkoutRouteStore._ensureSpeed(db);
    await WorkoutRouteStore._createSplit(db);
    await _ensureBreathingWindowColumns(db);
    // Self-skipping (one PRAGMA) unless the table really is still NOT NULL —
    // the same-version merged-build case this whole method exists for.
    await _relaxDecodedHrNull(db);
    await _ensureDayResultSkippedColumn(db);
    await _ensureDayResultPartialColumn(db);
    await NotifFiredStore._create(db);
    // Views LAST — they depend on metric_series / day_result / baselines / sessions
    // / notifications all existing. DROP+CREATE so a shape change takes effect.
    await _ensureCoachViews(db);
    await _dropRawStore(db);
  }

  /// Build 90's additive storage contract. Units/timestamps are unchanged:
  /// all *_ts values here are Unix seconds; offsets are seconds east of UTC.
  static Future<void> _createBuild90Tables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS day_zone (
        date TEXT PRIMARY KEY,
        zone_id TEXT NOT NULL,
        start_offset_sec INTEGER NOT NULL,
        end_offset_sec INTEGER NOT NULL,
        start_ts INTEGER NOT NULL,
        end_ts INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS day_zone_start ON day_zone(start_ts)',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS zone_change (
        at_ts INTEGER PRIMARY KEY,
        zone_id TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS body_weight_reading (
        id TEXT PRIMARY KEY,
        date TEXT NOT NULL,
        at_ts INTEGER NOT NULL,
        kg REAL NOT NULL,
        source TEXT NOT NULL,
        history_only INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        unit TEXT NOT NULL DEFAULT 'kg',
        entered REAL,
        origin_id TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_body_reading_date_time '
      'ON body_weight_reading(date, at_ts, id)',
    );
    await createFoodCountingTables(db);
    // The seed below writes the current cursor shape, including updated_at.
    // Repair an old same-version table before any writer can reach it.
    await _ensureSyncCursorSchema(db);
    final seeded = await db.query(
      'sync_cursor',
      columns: ['name'],
      where: 'name = ?',
      whereArgs: ['b90_body_reading_seed'],
    );
    if (seeded.isEmpty) {
      await _seedLegacyWeightReadings(db);
      await db.insert('sync_cursor', {
        'name': 'b90_body_reading_seed',
        'value': 'done',
        'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  static Future<void> _seedLegacyWeightReadings(DatabaseExecutor db) async {
    // Deterministic IDs make interrupted/repeated migration idempotent. The
    // reading time and input representation are preserved verbatim. created_at
    // dates the migration row, not an invented original creation timestamp.
    await db.rawInsert(
      '''
      INSERT OR IGNORE INTO body_weight_reading
        (id, date, at_ts, kg, source, history_only, created_at,
         unit, entered, origin_id)
      SELECT 'legacy:' || w.date, w.date, w.at_ts, w.kg, w.source,
        w.history_only, ?, w.unit, w.entered, w.origin_id
      FROM body_weight w
      WHERE NOT EXISTS
        (SELECT 1 FROM body_weight_reading r WHERE r.date = w.date)
    ''',
      [DateTime.now().millisecondsSinceEpoch ~/ 1000],
    );
  }

  /// The column names [table] currently has (empty if the table is absent).
  static Future<Set<String>> _columnsOf(Database db, String table) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    return {
      for (final c in info)
        if (c['name'] is String) c['name'] as String,
    };
  }

  /// THE ONLY sanctioned way to add a column in a migration step.
  ///
  /// A bare `ALTER TABLE … ADD COLUMN` in the ladder is a latent brick: the
  /// `_create*` helpers are MODERNIZED IN PLACE (they always emit the current
  /// DDL), so any DB old enough to have a table created by a LATER-numbered
  /// step already has the column an EARLIER-numbered ALTER tries to add. That
  /// throws "duplicate column name", and since `onUpgrade` runs inside ONE
  /// exclusive transaction the entire ladder rolls back and `openDatabase`
  /// rethrows — the app is stuck on the loading screen on EVERY launch, with no
  /// way out. Check first; swallow a lost race (SQLite does statement-level
  /// rollback, so a caught failure never poisons the surrounding transaction).
  static Future<void> _addColumnIfMissing(
    Database db,
    String table,
    String column,
    String ddlType,
  ) async {
    if ((await _columnsOf(db, table)).contains(column)) return;
    try {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $ddlType');
    } catch (_) {
      /* another opener won the race — the column exists now */
    }
  }

  /// v34: the per-second fields a gen5 band computes on its own and reports in
  /// every record — its pedometer's cumulative step count and cadence, its
  /// activity class, a calibrated skin temperature in °C, its on-wrist
  /// determination, and the HR-validity flag plus the second HR byte that
  /// corroborates the primary one. They used to be decoded and dropped.
  ///
  /// v42 adds `ambient_raw` here rather than in its own helper. It is the other
  /// direction (gen4-only — gen5 has no per-second equivalent), but it needs
  /// the exact same treatment for the exact same reason: the mid-ladder
  /// `_backfillDecodedStore` writes through `_queueDecodedOneHz`, which names
  /// the column, so every rebuild path has to hand it back before the backfill
  /// runs or the whole exclusive ladder rolls back. That is what this helper is
  /// for, and every rebuild already calls it.
  ///
  /// Additive and safe on a populated DB: eight nullable columns, no rewrite of
  /// the (million-row) table, no backfill. Existing rows read NULL — which is
  /// the truth for them, since the values were never stored. `skin_temp_raw`,
  /// `skin_contact` and the `spo2_*` columns are deliberately left alone; they
  /// hold real historical data regardless of what the names now suggest.
  static Future<void> _ensureDecodedOneHzBandFields(Database db) async {
    const cols = {
      'step_count': 'INTEGER',
      'step_cadence': 'INTEGER',
      'activity_class': 'INTEGER',
      'skin_temp_c': 'REAL',
      'on_wrist': 'INTEGER',
      'hr_valid': 'INTEGER',
      'hr_alt': 'INTEGER',
      // Ambient-light ADC, u16 @inner[70] on a gen4 R24 record. A RELATIVE
      // count on the user's own scale, never lux — and one-sided: bright means
      // bright, dark means nothing (a sleeve or a duvet reads dark in a lit
      // room). 0 is the absent sentinel, not a reading — see _queueDecodedOneHz.
      'ambient_raw': 'INTEGER',
      // v43 (MT-12): the gen5 record's SECOND and THIRD temperature channels
      // (i16 ÷10 °C), decoded by protocol and dropped by the mapper until now.
      //
      // DELIBERATELY NOT NAMED AFTER A BODY PART. protocol itself calls their
      // semantics loose, and naming one of them is exactly how gen4's
      // `skin_temp_raw` came to feed readiness as if it were a skin
      // temperature. `temp_ch2` / `temp_ch3` is the channel index and nothing
      // else. If they turn out to be die or battery temperature they are not
      // body signals and stay unread — persisting them claims NOTHING, which
      // is the entire point of the column. Assume dual-heat-flux core temp is
      // UNAVAILABLE: that method needs two characterised sensors and a known
      // thermal resistance, and we have neither.
      'temp_ch2_c': 'REAL',
      'temp_ch3_c': 'REAL',
      // The band's own per-second signal-quality figure (log-variance, f32).
      // Its scale is the band's, so it can only ever be a WITHIN-NIGHT rank or
      // a weight — never a percentage, never a bar, never "HRV confidence 82%".
      'signal_quality_logvar': 'REAL',
      // MT-12's last channel: the band's own gravity-removed motion magnitude
      // for this second (f32 g). Named for what protocol says it is and
      // nothing more. It is NOT our ENMO — we do not know the band's window,
      // filter or statistic — so it may not be substituted for one, and
      // nothing reads it. Same contract as the two temp channels: persisting
      // claims nothing, and that is what makes it possible to find out later
      // whether it agrees with the ENMO we compute over the same seconds.
      //
      // Not a ladder rung. `_ensureDecodedOneHzBandFields` runs from
      // `_createDecodedStore`, which `_repairOpenSchema` calls on EVERY open,
      // so an existing install gets the column for one PRAGMA without
      // spending a schema version other branches are also reaching for.
      'dyn_accel_g': 'REAL',
      // The record's own sub-second, u16 in units of 1/32768 s. BOTH
      // GENERATIONS SEND IT and both decoders have always read it; nothing
      // carried it past the decoder, so every record in this table was pinned
      // to a whole second. Stored as the strap's own ticks, NOT converted to
      // ms: the conversion is lossy and the raw count is what the strap said.
      // See Sample.tsSubsec and beatTimesMs.
      'ts_subsec': 'INTEGER',
      // The band's own coarse wake/sleep code (2 bits: 0 wake, 1 still,
      // 2 sleep, 3 up) — GEN5/MG ONLY, null on gen4.
      //
      // AN ENVELOPE, NOT A STAGE, and the column may only ever be read as one:
      // deep, light and REM all read `sleep`, and it lags true onset by ~10
      // minutes. It cannot improve a hypnogram and must never be written into
      // one. Its value is that it is an OUTSIDE OPINION on a staging pipeline
      // that is otherwise single-source — the disagreement between our sleep
      // window and the band's is a thing this app currently cannot even see.
      // Stored as the raw code rather than a name: a name freezes a meaning.
      // See Sample.bandSleepState for the evidence that it varies and means
      // what it says.
      'band_sleep_state': 'INTEGER',
    };
    final have = await _columnsOf(db, 'decoded_onehz');
    if (have.isEmpty) return; // table not created yet — the DDL carries them
    for (final e in cols.entries) {
      if (have.contains(e.key)) continue;
      await _addColumnIfMissing(db, 'decoded_onehz', e.key, e.value);
    }
  }

  /// v41: `device_family` — WHICH STRAP MEASURED THIS ROW.
  ///
  /// Stamped AT INGEST from the link that produced it (`ble_engine` pins the
  /// generation at service discovery), because that is the only moment anyone
  /// actually knows. It is never inferred from the data afterwards and never
  /// backfilled with a guess: a gen4 skin-temp ADC count and a gen5 centi-°C
  /// reading share `decoded_onehz`'s columns, so a wrong stamp is worse than no
  /// stamp. Existing rows — and anything imported, which came from no link at
  /// all — read NULL, meaning UNKNOWN PROVENANCE, which readers must treat as
  /// its own case (analytics: `calibrationFor` → null → refuse) rather than as
  /// gen4.
  ///
  /// Nullable TEXT, no DEFAULT, ever: a default would turn "we don't know" into
  /// a claim about the sensor.
  static Future<void> _ensureDeviceFamilyColumns(Database db) async {
    for (final t in const ['decoded_onehz', 'decoded_rr', 'sessions']) {
      await _addColumnIfMissing(db, t, 'device_family', 'TEXT');
    }
  }

  /// v43: `source` — WHICH SENSOR PRODUCED THIS ROW, as distinct from which
  /// strap generation ([_ensureDeviceFamilyColumns]).
  ///
  /// NULL means the band — every row ever written before this column existed,
  /// every import, every raw replay, and every byte the WHOOP link will ever
  /// deliver. A non-NULL value means a peripheral that is NOT the band (today:
  /// a standard Bluetooth heart-rate sensor, `0x180D`).
  ///
  /// This lands BEFORE the first 0x180D byte does, and it exists for exactly
  /// one reason: resting HR from a chest strap and resting HR from wrist PPG
  /// differ SYSTEMATICALLY. Quietly folding both into one baseline puts a step
  /// change into every long-horizon number the app keeps, which surfaces to the
  /// user as readiness reading wrong with no visible cause and no way to find
  /// it. So every read that feeds a baseline, a derive page or the data edge
  /// filters on provenance, and the filter is in place while the answer is
  /// still trivially "all of them".
  ///
  /// THE COLUMN IS AN ADMISSION FLAG, NOT A PROVENANCE ID — see the
  /// SUBSTRATE ADMISSION block at the top of this file, which states the
  /// non-overlap rule for all three provenance columns and owns the two SQL
  /// fragments ([derivableSourceSql], [kPrimaryBandSourceSql]) that every
  /// reader must use instead of writing the predicate by hand.
  ///
  /// Nullable TEXT, no DEFAULT: the same reason `device_family` has none.
  static Future<void> _ensureSourceColumns(Database db) async {
    for (final t in const ['decoded_onehz', 'decoded_rr']) {
      await _addColumnIfMissing(db, t, 'source', 'TEXT');
    }
  }

  /// `decoded_rr.beat_ts_ms` — where the beat actually was, beside the
  /// whole-second `rr_ts_ms` rather than instead of it. NULL on every row
  /// written before this column existed, and that NULL is the honest value: the
  /// sub-second it is built from was never stored and the frames it could be
  /// re-read from are pruned. See [beatTimesMs].
  ///
  /// Not a ladder rung, same as `dyn_accel_g`: `_ensureDecodedStore` runs from
  /// `_repairOpenSchema` on every open, so an existing install gets the column
  /// for one PRAGMA without spending a schema version.
  static Future<void> _ensureBeatTimeColumn(Database db) =>
      _addColumnIfMissing(db, 'decoded_rr', 'beat_ts_ms', 'INTEGER');

  /// v46: retire what v34 banked into `on_wrist` / `hr_valid`, and any
  /// `skin_temp_c` that is really the sensor's unavailable sentinel.
  ///
  /// v34 filled `on_wrist` from gen5 v18 body 60 bits 0-1 and `hr_valid` from
  /// body 15 bit7. Both readings are disproven: bits 0-1 are the primary-flags
  /// bit-8 snapshot (not wear), and bit7 toggles ~50/50 independently of HR
  /// presence across 1,587,671 retained records (not validity). `skin_temp_c`
  /// could likewise hold the AS6221 -50.00 °C unavailable/error code, which is
  /// not a temperature. The writer stopped emitting all three
  /// (`sampleFromGen5Historical`); this clears what it already stored, so no
  /// future reader can pick up a confident answer the data never supported.
  ///
  /// DDL-NEUTRAL on purpose: the columns stay, nullable, exactly as v34 created
  /// them, so a fresh install and an upgraded one still end at the same schema
  /// (the fields remain the right shape should an honest source ever appear).
  /// Idempotent — a second run matches no rows. Cheap enough for the iOS
  /// open-database watchdog: `decoded_onehz` is bounded by `rawRetentionDays`,
  /// this is one scan, and it writes only the rows that carry a value.
  static Future<void> _retireDisprovenOneHzColumns(Database db) async {
    final have = await _columnsOf(db, 'decoded_onehz');
    // Pre-v34 tables never had the columns; nothing to retire.
    if (!have.contains('on_wrist')) return;
    await db.execute(
      'UPDATE decoded_onehz SET '
      'on_wrist = NULL, '
      'hr_valid = NULL, '
      'skin_temp_c = CASE WHEN skin_temp_c <= -49.995 THEN NULL '
      'ELSE skin_temp_c END '
      'WHERE on_wrist IS NOT NULL OR hr_valid IS NOT NULL '
      'OR skin_temp_c <= -49.995',
    );
  }

  static Future<void> _ensureDayResultSkippedColumn(Database db) =>
      _addColumnIfMissing(
        db,
        'day_result',
        'skipped',
        'INTEGER NOT NULL DEFAULT 0',
      );

  static Future<void> _ensureDayResultPartialColumn(Database db) =>
      _addColumnIfMissing(
        db,
        'day_result',
        'partial',
        'INTEGER NOT NULL DEFAULT 0',
      );

  // ── MENSTRUAL SYMPTOM LOG ──────────────────────────────────────────────────
  static Future<void> _createCycleSymptom(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cycle_symptom (
        date TEXT PRIMARY KEY,
        symptoms_json TEXT NOT NULL,
        note TEXT,
        updated_at INTEGER
      )
    ''');
  }

  // ── RESUMABLE-SYNC CURSOR (durable KV) ──────────────────────────────────────
  // A tiny key→value store for sync bookkeeping that must survive process death.
  // Keys we use (durable resumable-sync cursor semantics):
  //   strap_trim       — hex of the last ACKed HISTORY_END 8-byte token
  //   counter_hw       — highest record `counter` we have durably persisted
  //   rec_ts_hw        — highest record `rec_ts` (epoch sec) durably persisted
  //   data_range_lo/hi — strap's own oldest/newest banked record unix (GET_DATA_RANGE)
  // The "safe-trim invariant" is: persist decoded+raw → persist this cursor →
  // ACK with-response. The band only trims its flash once the ACK is link-layer
  // confirmed, so a crash anywhere before the ACK re-delivers the batch.
  static Future<void> _createSyncCursor(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_cursor (
        name TEXT PRIMARY KEY,
        value TEXT,
        updated_at INTEGER NOT NULL
      )
    ''');
  }

  // ── IMPORTED MEASUREMENTS FROM DEVICES WE ARE NOT ───────────────────────────
  /// Readings a CLEARED device took and wrote to the phone's health store: a
  /// blood-pressure cuff, a CGM, a thermometer.
  ///
  /// THE WHOLE VALUE IS THAT WHOOP DID NOT MEASURE IT. The source name is
  /// mandatory and travels with every row, and these never blend into a
  /// composite of ours — there is no "combined" anything, and no derived number
  /// takes one of these as an input.
  ///
  /// ⚠️ READ-ONLY INPUTS TO DISPLAY. NEVER TRAINING TARGETS. ⚠️
  /// The moment a cuff series exists in the same database as a wrist PPG
  /// series, someone will want to fit a wrist→blood-pressure mapping on it.
  /// That is a cuffless-blood-pressure claim from a device cleared for nothing
  /// of the kind, and that path ends at a regulator's warning letter. These
  /// rows may be SHOWN next to ours and may never be REGRESSED against ours.
  /// This comment lives here, at the table, and not only in a document,
  /// because the document is not what the next person reads.
  ///
  /// Keyed by the store's own record uuid, so re-reading the same window is
  /// idempotent and an edit made in the source app lands as an update.
  /// Readings taken by a device that is CLEARED to take them — a BP cuff, a
  /// CGM, a thermometer. `source` is NOT NULL because the whole value of these
  /// rows is that WHOOP did not measure them.
  ///
  /// READ-ONLY INPUTS TO DISPLAY. NEVER TRAINING TARGETS. the moment a cuff
  /// series and a wrist PPG series live in one database, the obvious next idea
  /// is to fit one to the other — and a wrist→BP mapping is a cuffless blood
  /// pressure claim from an uncleared device, which is the exact category that
  /// earned WHOOP an FDA Warning Letter in Jul 2025 (trend-only, no units, and
  /// the general-wellness defence was rejected anyway). so: this table may be
  /// JOINed for display. it may not be joined to `decoded_onehz`, `decoded_rr`
  /// or `metric_series` to fit, calibrate, validate or regress anything of
  /// ours, and no derived value may take one of these rows as an input.
  ///
  /// NEVER BLENDED either — no combined series, no averaging an imported
  /// reading with one of ours, no "your blood pressure" without the cuff's name
  /// attached. see health/health_measurement_import.dart, which states the same
  /// guard on the write side; it is in both places on purpose.
  static Future<void> _createImportedMeasurement(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS imported_measurement (
        uuid TEXT PRIMARY KEY,
        ts INTEGER NOT NULL,
        kind TEXT NOT NULL,
        value REAL NOT NULL,
        unit TEXT NOT NULL,
        source TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_imported_measurement_kind '
      'ON imported_measurement(kind, ts)',
    );
  }

  // ── DEVICES (the things that measure) ─────────────────────────────────────
  /// The devices this phone knows about, one row each.
  ///
  /// Until now a "device" was TWO SharedPreferences scalars (`paired_remote_id`
  /// / `paired_serial`), which can hold exactly one band, carries no state
  /// beside the id, and cannot be joined to anything. `decoded_onehz`,
  /// `decoded_rr` and `samples` have been keyed by `device_id` since v47 with
  /// nothing on the other end of that key — this is the other end.
  ///
  /// `id` IS the `device_id` those tables carry, so [kPrimaryDeviceId] (`''`)
  /// is this table's primary row, permanently (ASSUMPTIONS A1). That is what
  /// keeps an unstable BLE `remoteId` — a per-app CBPeripheral UUID — out of
  /// the key: it lives in `remote_id`, a plain
  /// column that may change under the same row as often as the OS likes.
  ///
  ///  * `adapter_id` — the `BandEntry.id` from the registry (`gen4`/`gen5`), or
  ///    NULL when the link has not said yet. NULL is a refusal, not a default:
  ///    every metric that looks its constants up per family abstains on it
  ///    rather than borrowing gen4's numbers, and the device screen says so.
  ///  * `label` — the band's own advertising name / serial, already passed
  ///    through `cleanDeviceLabel`. Never junk, never a placeholder.
  ///  * `tier` — the `SourceTier` enum NAME (measurement quality, which is the
  ///    only thing that decides precedence between two sources).
  ///  * `first_seen` / `last_seen` — epoch seconds.
  ///
  /// ponytail: no `UPSERT`. `INSERT … ON CONFLICT DO UPDATE` needs SQLite 3.24
  /// and minSdk 26 ships 3.18 (the same floor the `observation` index reasons
  /// about), so [DeviceStore.upsert] is INSERT OR IGNORE + UPDATE.
  static Future<void> _createDevice(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS device (
        id          TEXT PRIMARY KEY,
        adapter_id  TEXT,
        remote_id   TEXT,
        label       TEXT,
        tier        TEXT,
        first_seen  INTEGER NOT NULL,
        last_seen   INTEGER NOT NULL
      )
    ''');
  }

  // ── OBSERVATIONS (vendor-computed / typed-in / imported scalars) ───────────
  /// Everything that is NOT a raw sensor sample and NOT computed by us:
  /// a `reports` band's own conclusions, the user's typed-in numbers, and
  /// another app's history. See docs/OBSERVATION_SPEC.md.
  ///
  /// THE SINGLE INVARIANT, and it is the whole safety story: **nothing reads
  /// this table into a baseline, into a trend that also carries derived
  /// values, or into any input to a derivation.** Held the same way
  /// `imported_measurement` holds its own version of the rule — a SEPARATE
  /// table, so the only way to violate it is to name it somewhere new, and
  /// `data/observation_isolation_test.dart` fails the moment anyone does. If it is
  /// ever violated the failure is SILENT: an unexplained step change in a
  /// long-horizon number, months later, with no way to tell which day broke it.
  ///
  /// IDENTITY IS AN EXPRESSION INDEX, NOT A PRIMARY KEY, and that is not a
  /// stylistic choice. The spec's key is
  /// `(device_id, ts_ms, source_kind, COALESCE(vendor_key, key))`, and SQLite
  /// takes no expression in a table-level PRIMARY KEY. The two obvious repairs
  /// both fail:
  ///
  ///  * A `GENERATED ALWAYS AS (COALESCE(...)) STORED` column is rejected
  ///    outright — "generated columns cannot be part of the PRIMARY KEY" — and
  ///    generated columns need SQLite 3.31 (2020) besides.
  ///  * A plain composite `PRIMARY KEY (…, vendor_key, key)` COMPILES AND IS
  ///    WRONG. A PRIMARY KEY on a rowid table is a UNIQUE INDEX, and SQLite
  ///    treats NULLs in one as DISTINCT — so two rows with the same
  ///    `vendor_key` and a NULL `key` do not collide, `INSERT OR REPLACE` does
  ///    not replace, and a re-import silently doubles every composite it
  ///    carries. Proven, not assumed.
  ///
  /// A UNIQUE INDEX may hold an expression (SQLite 3.9, 2015), `INSERT OR REPLACE` resolves against it exactly as
  /// it would against a PRIMARY KEY, and `COALESCE` is non-NULL whenever the
  /// CHECK holds, so the NULL-distinctness trap never arms. The CHECK is what
  /// makes that true, which is why it is a DB constraint and not a Dart assert.
  ///
  /// `device_id = ''` is the primary band, permanently — the standing rule
  /// established for `decoded_onehz` at v47, and for the same reason: a BLE
  /// remoteId is not a stable identity.
  ///
  /// ponytail: scalars only (`value REAL` + `unit TEXT`). A vendor hypnogram
  /// or a vendor GPS track is not a scalar and has no consumer — give it a
  /// table of its own when something is actually going to read it.
  static Future<void> _createObservation(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS observation (
        device_id    TEXT NOT NULL DEFAULT '',
        ts_ms        INTEGER NOT NULL,
        date         TEXT NOT NULL,
        source_kind  TEXT NOT NULL,
        vendor_key   TEXT,
        key          TEXT,
        value        REAL,
        unit         TEXT,
        attribution  TEXT NOT NULL,
        CHECK (vendor_key IS NOT NULL OR key IS NOT NULL)
      )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_observation_identity '
      'ON observation(device_id, ts_ms, source_kind, COALESCE(vendor_key, key))',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_observation_date '
      'ON observation(date, source_kind)',
    );
  }

  // ── IMPORTED WORKOUTS (no current writer; older exports may carry rows) ──
  /// A workout some OTHER app recorded, held in its own table for the same
  /// reason `imported_measurement` is: so that it CANNOT become one of ours.
  ///
  /// It is deliberately NOT a row in `sessions`. Everything that reads
  /// `sessions` treats what it finds as measured — strain, the day rollup, the
  /// workout list, the personal records — and a table this app does not own is
  /// the wrong input to every one of them. A separate table makes that
  /// structural instead of a flag someone has to remember to check: there is no
  /// WHERE clause to forget, because the rows are not there.
  ///
  /// DISPLAY ONLY, and `source` is NOT NULL for it — a workout shown without
  /// the app that recorded it is a workout this app is implicitly claiming.
  ///
  /// `uuid` is the health store's own identifier, so a re-import updates in
  /// place rather than stacking duplicates of the same run.
  ///
  /// ROUTES REUSE `workout_route`, keyed by this uuid as its `session_id`. That
  /// table is an opaque-id → lat/lng store with no notion of who measured it,
  /// and a coordinate is not an input to any metric, so there is nothing to
  /// keep apart. What it buys is the existing map: no second route table, no
  /// second reader, no second renderer. [deleteImportedWorkout] cascades, since
  /// [SessionStore.delete] never sees these ids.
  static Future<void> _createImportedWorkout(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS imported_workout (
        uuid TEXT PRIMARY KEY,
        start_ts INTEGER NOT NULL,
        end_ts INTEGER NOT NULL,
        kind TEXT NOT NULL,
        energy_kcal REAL,
        distance_m REAL,
        steps INTEGER,
        source TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_imported_workout_start '
      'ON imported_workout(start_ts)',
    );
  }

  // ── EXTERNAL HEART-RATE SENSOR (0x180D) ─────────────────────────────────────
  /// What a standard Bluetooth heart-rate sensor delivered during ONE workout.
  ///
  /// A SCRATCH LEDGER, deliberately: this is not the substrate. Nothing derives
  /// from it, no baseline reads it, no daily number is computed from it. It
  /// exists so a session can show the sensor's HR and RR *durations* next to
  /// the band's, and so the first question — does a second GATT link fight the
  /// band's? — can be answered against real rows.
  ///
  /// `source` is NOT NULL and carries the peripheral's advertised name, because
  /// the whole point is that the reader always knows this did not come from the
  /// wrist. `rr_ms` is a JSON list of BEAT DURATIONS in milliseconds as the
  /// sensor reported them in one notification — durations, not beat times: a
  /// sub-second beat timeline is a change to `decoded_rr`'s key and to every
  /// consumer of beat times, and is out of scope here.
  ///
  /// One row per (second, sensor). A sensor notifies about once per second; two
  /// notifications inside the same second REPLACE, which loses a beat count but
  /// never invents one.
  static Future<void> _createExternalHr(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS external_hr (
        ts INTEGER NOT NULL,
        source TEXT NOT NULL,
        hr INTEGER NOT NULL,
        rr_ms TEXT,
        session_id TEXT,
        PRIMARY KEY (ts, source)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_external_hr_session '
      'ON external_hr(session_id)',
    );
  }

  // ── DERIVED STORE (permanent, rich) ────────────────────────────────────────
  // The on-device analytics output, keyed by physiological day (wake-to-wake;
  // the `date` label is edge-supplied, display-only). These rows are PERMANENT —
  // raw is pruned after derivation (rawRetentionDays) but the derived bundle is
  // the long-term system of record the UI reads from. See lib/compute/.
  static Future<void> _createDerived(Database db) async {
    // derived_day — one row per physiological day. `payload_json` is the full
    // result bundle (all clinical/sleep/respiration/motion/wellness/human metrics,
    // each keeping its tier/confidence/inputs_used) PLUS the per-minute/curve
    // series the UI needs (HR curve, HRV timeline, hypnogram). Frequently queried
    // scalars are indexed into columns for cheap trends.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS derived_day (
        date TEXT PRIMARY KEY,
        payload_json TEXT NOT NULL,
        version INTEGER NOT NULL,
        last_raw_ts INTEGER NOT NULL,
        computed_at INTEGER NOT NULL,
        rhr REAL,
        rmssd REAL,
        readiness REAL
      )
    ''');
    // baselines — rolling personal baselines, so a derivation pass reuses stored
    // state instead of refolding full history each time.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS baselines (
        key TEXT PRIMARY KEY,
        payload_json TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    // metric_series — long-format scalars for trends / sparklines.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS metric_series (
        date TEXT NOT NULL,
        key TEXT NOT NULL,
        value REAL,
        PRIMARY KEY (date, key)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_metric_series_key ON metric_series(key, date)',
    );
    await _createMetricSeriesVersion(db);
  }

  /// metric_series_version — which build's maths produced a day's scalars.
  ///
  /// `day_result` is versioned (PK day_id, algo_version); `metric_series` is
  /// not, and cannot become so — `v_metric` and `v_daily` are pivots over it
  /// and `v_daily` is in the coach's allow-list, so widening the PK changes
  /// what the coach sees. So the stamp lives beside it, one row per day.
  ///
  /// WHAT IT IS FOR. Days lock at finalized ~48 h after wake and are never
  /// recomputed on a bump, and the 1 Hz substrate is gone at 3 days, so a March
  /// day physically cannot be re-derived in December. `kAlgoVersion` moved
  /// 65 → 66 → 68 inside two weeks. A 12-month chart therefore splices values
  /// from several different algorithms with nothing marking the seams. This
  /// does NOT make those values comparable — nothing can. It makes the
  /// incomparability VISIBLE, so a change-point search can refuse to run across
  /// a seam instead of reporting the day the maths changed as a finding about
  /// the user.
  static Future<void> _createMetricSeriesVersion(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS metric_series_version (
        date TEXT PRIMARY KEY,
        algo_version INTEGER NOT NULL,
        source TEXT
      )
    ''');
    // v43 (export-provenance): `source` — WHO produced this day's scalars.
    // ONE table with L13, not two: same day key, same write, same read.
    //
    // `v_daily` is a pure pivot over `metric_series` with no source and no
    // version, so an imported vendor snapshot day and a 1 Hz-derived day are
    // BYTE-IDENTICAL in an export. A file presenting another vendor's derived
    // score beside your band's measured one, unlabelled, is the export
    // surface's version of the fabricated-number law.
    //
    // 'band' means this app derived the day from 1 Hz records. NULL means
    // UNKNOWN and is NEVER retro-filled with a guess — every day written before
    // this column existed reads NULL, and `csvField` already renders that as an
    // empty cell rather than a claim.
    //
    // Hand it back on a table an older build created without it. This helper
    // takes a `DatabaseExecutor` (it is called from inside a transaction), so
    // it cannot use `_addColumnIfMissing`; the throw when the column is already
    // there is the check.
    try {
      await db.execute(
        'ALTER TABLE metric_series_version ADD COLUMN source TEXT',
      );
    } catch (_) {
      /* already present */
    }
    // WHICH BAND'S UNITS this day's scalars are in (B5). Same table, same
    // write, same read as `source` — and the same rules: nullable, no DEFAULT,
    // NEVER retro-filled, because a guessed provenance is worse than none.
    //
    // This is live TODAY on a gen4→gen5 swap, with no second device involved:
    // `skin_temp_adc` holds gen4 ADC COUNTS on one side of the swap and gen5
    // CENTI-DEGREES on the other, under one `metric_series` key, feeding one
    // 28-day baseline that every nightly z-score is taken against. The seam is
    // a step change in the units, not in the person.
    //
    // NOT the same as [DayProvenanceStore._importedDatesSql]'s question.
    // Imported days are ANOTHER ALGORITHM'S OUTPUT and are masked out of every
    // baseline. A foreign family is this app's own maths over a different
    // sensor, so it is masked PER-METRIC — only where the seam makes the number
    // WRONG (different units), never merely noisier. See
    // [DayProvenanceStore.foreignFamilyDates].
    try {
      await db.execute(
        'ALTER TABLE metric_series_version ADD COLUMN device_family TEXT',
      );
    } catch (_) {
      /* already present */
    }
  }

  /// Backfill the stamp from `day_result`, which has carried the version all
  /// along. `INSERT OR IGNORE`, so a stamp already written by
  /// [DayResultStore.put] wins — that one is exact, this one infers.
  ///
  /// `skipped`/`partial` rows are excluded because those passes do not write
  /// `metric_series` at all (see [DayResultStore.put]), so their version never
  /// produced the values being stamped. MAX per day is the same rule the serve
  /// seam uses; it is only wrong for a day last written by a ROLLED-BACK build,
  /// and going forward [DayResultStore.put] records that case exactly.
  static Future<void> _backfillMetricSeriesVersion(Database db) async {
    // `day_result` may not exist yet on an upgrade path that has not reached
    // the rung which creates it (or on a DB that never had it). A SELECT from a
    // missing table throws, and a throw inside onUpgrade rolls the WHOLE ladder
    // back and quarantines the user's database — the standing trap this file is
    // full of guards against. Nothing to infer from, so infer nothing.
    if ((await _columnsOf(db, 'day_result')).isEmpty) return;
    await db.execute(
      'INSERT OR IGNORE INTO metric_series_version (date, algo_version) '
      'SELECT day_id, MAX(algo_version) FROM day_result '
      'WHERE skipped = 0 AND partial = 0 GROUP BY day_id',
    );
  }

  /// The algo version behind each day's `metric_series` scalars, oldest first.
  /// Days with no stamp are simply absent — never guessed at.
  static Future<List<Map<String, dynamic>>> metricSeriesVersions() async {
    final db = await instance;
    return db.query('metric_series_version', orderBy: 'date ASC');
  }

  // ── VERSIONED IMMUTABLE DERIVED STORE (ARCHITECTURE_V2 invariant 6) ─────────
  // day_result — one row per (physiological day, algo_version). Derived rows are
  // IMMUTABLE per version: an algo_version bump writes a NEW row (never mutates).
  // The serve seam reads the LATEST algo_version per day_id. A day stays
  // recomputable for ~48 h after its wake (finalized=0); then it LOCKS
  // (finalized=1) and is no longer recomputed even on a version bump.
  static Future<void> _createDayResult(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS day_result (
        day_id TEXT NOT NULL,
        algo_version INTEGER NOT NULL,
        payload_json TEXT NOT NULL,
        window_json TEXT NOT NULL DEFAULT '{}',
        computed_at INTEGER NOT NULL,
        finalized INTEGER NOT NULL DEFAULT 0,
        rhr REAL,
        rmssd REAL,
        readiness REAL,
        skipped INTEGER NOT NULL DEFAULT 0,
        partial INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (day_id, algo_version)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_day_result_day ON day_result(day_id, algo_version)',
    );
  }

  /// lab_result — hand-entered blood work, and definitions for user-defined
  /// markers.
  ///
  /// Keyed on (marker, taken_on) so re-entering the same draw corrects it
  /// rather than stacking duplicates; two genuinely different draws on one day
  /// are rare enough that correcting a typo is the case worth optimising for.
  ///
  /// `unit` is stored per row rather than looked up from the catalogue, so a
  /// value keeps the unit it was entered under even if a later release changes
  /// the marker's canonical unit. Silently reinterpreting 400 ng/mL as
  /// 400 nmol/L would be a fabrication of the worst kind.
  ///
  /// NOT day-scoped, NOT pruned, and deliberately NOT removed by `deleteDays`.
  /// A lab result belongs to the date the blood was drawn, not to a band-data
  /// day. "Delete this day" in the data manager is about reclaiming space from
  /// sensor data; a blood test is neither sensor data nor large, it was typed
  /// in by hand on a different screen, and it has its own delete there. Losing
  /// a year-old blood panel because the band data from that date was cleared
  /// would be a genuinely surprising deletion.
  ///
  /// Indexed by its PRIMARY KEY alone — `(marker, taken_on)` already gives
  /// SQLite an implicit index on exactly the columns every read here filters
  /// and orders by, so a second one would only be another b-tree to maintain.
  static Future<void> _createLabTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS lab_result (
        marker TEXT NOT NULL,
        taken_on TEXT NOT NULL,
        value REAL NOT NULL,
        unit TEXT NOT NULL,
        note TEXT NOT NULL DEFAULT '',
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (marker, taken_on)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS lab_marker_def (
        key TEXT PRIMARY KEY,
        label TEXT NOT NULL,
        unit TEXT NOT NULL,
        category TEXT NOT NULL,
        decimals INTEGER NOT NULL DEFAULT 1,
        ref_low REAL,
        ref_high REAL,
        created_at INTEGER NOT NULL
      )
    ''');
  }

  /// breathing_session — one row per completed paced-breathing session.
  ///
  /// The coherence score was computed live and then thrown away, so the
  /// feature could tell you how a session went and never whether it was going
  /// anywhere. A score is only meaningful for a pattern that is TRYING to
  /// drive heart-rate oscillation at the paced frequency, so `coherence` is
  /// null for the others rather than a number that grades box breathing on
  /// resonance breathing's exam.
  ///
  /// `pre_rmssd` / `post_rmssd` (MIND-06) are RMSSD over the two QUIET windows
  /// either side of the paced block — never during it. RMSSD rises during slow
  /// breathing as a mechanical consequence of respiratory sinus arrhythmia, so
  /// a during-session number measures the pacing, not any effect of it. Only
  /// the pre→post pair carries information, and only across many sessions.
  /// Both null on every session run without the windows, which is the default.
  static Future<void> _createBreathingSessions(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS breathing_session (
        started_at INTEGER PRIMARY KEY,
        ended_at INTEGER NOT NULL,
        pattern TEXT NOT NULL,
        seconds INTEGER NOT NULL,
        coherence REAL,
        confidence REAL,
        pre_rmssd REAL,
        post_rmssd REAL
      )
    ''');
  }

  /// The MIND-06 window columns on an existing `breathing_session`.
  ///
  /// Additive only, and NOT a ladder rung: `_addColumnIfMissing` is a no-op on
  /// a table this build has not created yet and costs one PRAGMA at open, so
  /// the onOpen repair covers every existing install without spending a schema
  /// version that three other branches are also reaching for.
  static Future<void> _ensureBreathingWindowColumns(Database db) async {
    await _addColumnIfMissing(db, 'breathing_session', 'pre_rmssd', 'REAL');
    await _addColumnIfMissing(db, 'breathing_session', 'post_rmssd', 'REAL');
  }

  /// strength_set / exercise_def — the sets a lift is made of.
  ///
  /// Nothing measures a bench press, so this is the one part of a workout the
  /// user types, and until now there was nowhere to put it: `sessions` has no
  /// exercise, set, rep, load or RPE column, which made every number on the
  /// strength screens unbacked. Hangs off `sessions.id` so strain, calories,
  /// zones and heart rate keep coming from the existing pipeline rather than
  /// being duplicated here.
  ///
  /// `load_kg` is NULLABLE and that is the whole point: a bodyweight pull-up
  /// stored as 0 would make session volume (Σ load × reps) report zero for a
  /// real session. Volume is derived on read and excludes null-load sets,
  /// which the UI states in as many words.
  ///
  /// Derived on read, never stored: total volume, set/rep counts, 1RM
  /// estimates, per-muscle volume, "vs last session", PR detection.
  static Future<void> _createStrengthTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS strength_set (
        session_id TEXT NOT NULL,
        seq INTEGER NOT NULL,
        exercise_key TEXT NOT NULL,
        set_index INTEGER NOT NULL,
        reps INTEGER,
        load_kg REAL,
        rpe INTEGER,
        hold_sec INTEGER,
        rest_sec INTEGER,
        at_ts INTEGER,
        note TEXT NOT NULL DEFAULT '',
        PRIMARY KEY (session_id, seq)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_strength_set_ex '
      'ON strength_set(exercise_key, at_ts)',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS exercise_def (
        key TEXT PRIMARY KEY,
        label TEXT NOT NULL,
        muscles_json TEXT NOT NULL DEFAULT '{}',
        equipment TEXT NOT NULL DEFAULT '',
        unilateral INTEGER NOT NULL DEFAULT 0,
        custom INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      )
    ''');
  }

  // ── USER-DATA STORE (journal / cycle / workouts / notifications) ────────────
  // On-device user-entered + locally-generated data. All keyed for idempotent
  // upserts; none of it round-trips to a server (cloud excised).
  static Future<void> _createUserTables(Database db) async {
    // journal — one row per day; tags is a JSON string list, note free text.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS journal (
        date TEXT PRIMARY KEY,
        tags_json TEXT NOT NULL DEFAULT '[]',
        note TEXT NOT NULL DEFAULT '',
        updated_at INTEGER NOT NULL
      )
    ''');
    await JournalStore._createMetric(db);
    await JournalStore._createFieldDef(db);
    await _createLabTables(db);
    await _createBreathingSessions(db);
    await _createStrengthTables(db);
    // Nutrition (food_entry + food_def) lives with its models and rollup
    // logic; the retired medication tables are created below.
    await createNutritionTables(db);
    await _createMedTables(db);
    // Lift Log inside the WHOOP workout (build 86): one JSON row per workout.
    // Added in place on the open path, like body_weight: no schema version.
    await LiftLogDb.createTables(db);
    // Body (build 86): tape sessions, photo records, and the in-place
    // body_weight columns that keep imported/backdated weights history only.
    await BodyLogDb.createTables(db);
    await _createBuild90Tables(db);
    // Pushups (build 86): one JSON row per movement-break day.
    await PushupDb.createTables(db);
    // cycle_log — menstrual cycle markers; `kind` is 'start' (cycle start) etc.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cycle_log (
        date TEXT PRIMARY KEY,
        kind TEXT NOT NULL,
        note TEXT
      )
    ''');
    // sessions — manual/live/auto workouts; status 'live'|'done', zone tallies JSON.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sessions (
        id TEXT PRIMARY KEY,
        start_ts INTEGER NOT NULL,
        end_ts INTEGER,
        type TEXT NOT NULL,
        status TEXT NOT NULL,
        calories REAL,
        strain REAL,
        max_hr INTEGER,
        duration_min INTEGER,
        zone_min_json TEXT,
        steps INTEGER,
        cadence_spm INTEGER,
        hrr_bpm REAL,
        source TEXT NOT NULL DEFAULT 'manual',
        private INTEGER NOT NULL DEFAULT 0,
        device_family TEXT,
        trace_json TEXT,
        trace_samples INTEGER,
        rpe REAL,
        calories_basis TEXT,
        created_at INTEGER NOT NULL
      )
    ''');
    // workout_suggestions — opt-in "did you work out?" auto-detections. Never a
    // real session until the user confirms; `dismissed` hides a rejected one.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS workout_suggestions (
        id TEXT PRIMARY KEY,
        date TEXT NOT NULL,
        start_ts INTEGER NOT NULL,
        end_ts INTEGER NOT NULL,
        avg_bpm INTEGER,
        peak_bpm INTEGER,
        duration_min INTEGER,
        sport TEXT,
        dismissed INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      )
    ''');
    // notifications — locally-generated insight feed (illness/anomaly/temp/readiness).
    await db.execute('''
      CREATE TABLE IF NOT EXISTS notifications (
        id TEXT PRIMARY KEY,
        kind TEXT NOT NULL,
        title TEXT NOT NULL,
        body TEXT NOT NULL,
        date TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        read INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  static Future<void> _createSyncState(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_ledger (
        chunk_id TEXT PRIMARY KEY,
        kind TEXT NOT NULL,
        status TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        acked_at INTEGER,
        last_error TEXT,
        meta_json TEXT NOT NULL DEFAULT '{}'
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_quarantine (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        kind TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        reason TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sync_quarantine_created ON sync_quarantine(created_at)',
    );
  }

  static Future<void> _createComputeState(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS compute_freshness (
        key TEXT PRIMARY KEY,
        payload_json TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS compute_jobs (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        scope TEXT NOT NULL,
        priority INTEGER NOT NULL DEFAULT 0,
        state TEXT NOT NULL,
        reason TEXT,
        depends_on TEXT,
        input_from_ts INTEGER,
        input_to_ts INTEGER,
        algo_version INTEGER,
        attempts INTEGER NOT NULL DEFAULT 0,
        next_run_at INTEGER,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_compute_jobs_state_pri ON compute_jobs(state, priority DESC, updated_at ASC)',
    );
  }

  static Future<void> _createPrimitiveArtifacts(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sleep_session_candidates (
        day_id TEXT NOT NULL,
        algo_version INTEGER NOT NULL,
        payload_json TEXT NOT NULL,
        computed_at INTEGER NOT NULL,
        PRIMARY KEY(day_id, algo_version)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS wake_day_features (
        day_id TEXT NOT NULL,
        algo_version INTEGER NOT NULL,
        payload_json TEXT NOT NULL,
        computed_at INTEGER NOT NULL,
        PRIMARY KEY(day_id, algo_version)
      )
    ''');
  }

  static Future<void> _ensureSyncStateSchema(Database db) async {
    await _ensureSyncCursorSchema(db);
    await _ensureSyncLedgerSchema(db);
    await _ensureSyncQuarantineSchema(db);
  }

  static Future<void> _dropRawStore(Database db) async {
    await db.execute('DROP TABLE IF EXISTS raw_records');
  }

  /// v42 — THE FROZEN SESSION TRACE. Everything the detail screen draws that is
  /// rebuilt from the 1 Hz substrate on every open: the minute HR curve, the
  /// zone bands, drift, time-to-peak, the recovery curve. `decoded_onehz` is
  /// pruned at `rawRetentionDays`, so every one of those went permanently blank
  /// on a session's fourth day — the summary scalars survived in their own
  /// columns and the whole chart half of the screen did not.
  ///
  /// `trace_samples` is the 1 Hz sample COUNT the trace was built from, kept
  /// with it so a session the band only partly handed over reads as partial
  /// instead of drawing a confident thin line over a sync gap. NOT backfilled —
  /// those seconds are gone; a session that aged out before this shipped has no
  /// trace and never will.
  ///
  /// Its own helper, and NOT [_ensureSessionSchema], because the ladder rung
  /// must not run that one: it also creates an index, which throws on a DB
  /// whose `sessions` table this ladder has not created yet, and a throw inside
  /// onUpgrade quarantines the whole database. `_addColumnIfMissing` is a no-op
  /// on a missing table.
  static Future<void> _ensureSessionTraceColumns(Database db) async {
    await _addColumnIfMissing(db, 'sessions', 'trace_json', 'TEXT');
    await _addColumnIfMissing(db, 'sessions', 'trace_samples', 'INTEGER');
  }

  static Future<void> _ensureSessionSchema(Database db) async {
    await _addColumnIfMissing(db, 'sessions', 'steps', 'INTEGER');
    await _addColumnIfMissing(db, 'sessions', 'hrr_bpm', 'REAL');
    // Mean HR over the session window. Stored rather than recomputed because
    // the 1 Hz substrate it comes from is pruned after 3 days: without a column
    // every workout older than that permanently loses its average, while
    // `max_hr` (already a column) survives. Additive + nullable, so old rows
    // read NULL — the truth for them — and the read path still recomputes from
    // the substrate while it is there.
    await _addColumnIfMissing(db, 'sessions', 'avg_hr', 'INTEGER');
    // v43 (TS-09) — SESSION RPE. A SELF-REPORT, and labelled as one everywhere
    // it is ever shown. It exists to score the sessions heart rate cannot see
    // (lifting, climbing, anything intermittent) and its real value is the
    // DISAGREEMENT with TRIMP — a feeling compared against a measurement.
    //
    // NULLABLE WITH NO DEFAULT, and that is load-bearing: the set-level picker
    // already defaults to 7, which is a garbage-data mechanism already running.
    // A session nobody rated must read as UNRATED, not as a 7 somebody typed.
    // Skippable forever.
    await _addColumnIfMissing(db, 'sessions', 'rpe', 'REAL');
    // Build 90: what `calories` means — 'active' (net, the shown method),
    // 'legacy' (pre-Build 90, may include resting energy, not recalculable)
    // or NULL (not yet examined / vendor import). Additive and nullable on the
    // open path, no schema bump: old rows read NULL until the repair pass
    // (`repairSessionCalorieBasis`) examines them. See `kCaloriesBasisActive`.
    await _addColumnIfMissing(db, 'sessions', 'calories_basis', 'TEXT');
    // Private session (v40): the user's "don't surface this one" flag. NOT NULL
    // DEFAULT 0 because every session that already exists was not marked
    // private — absence here is a real answer, not a missing measurement.
    await _addColumnIfMissing(
      db,
      'sessions',
      'private',
      'INTEGER NOT NULL DEFAULT 0',
    );
    // Which strap measured this workout (v41) — see _ensureDeviceFamilyColumns.
    // NULL on every existing row, on a hand-entered session, and on an import:
    // no link produced them, so their provenance is genuinely unknown.
    await _addColumnIfMissing(db, 'sessions', 'device_family', 'TEXT');
    // Measured walking cadence for the session (v43, steps/min). No current
    // writer: live sessions never stream wrist motion, so rows saved since
    // then leave it NULL; older rows keep the value they were saved with.
    await _addColumnIfMissing(db, 'sessions', 'cadence_spm', 'INTEGER');
    // Set only by `_reconcileOrphanedLiveWorkout` on a stale `status='live'`
    // row it finalizes without ever having seen the real finish: `end_ts` there
    // is reconcile-time, not a measurement, so every duration, pace and
    // calorie reader skips a row with this set. NOT NULL DEFAULT 0: every existing/normal row really did finish for real.
    await _addColumnIfMissing(
      db,
      'sessions',
      'end_ts_fabricated',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _ensureSessionTraceColumns(db);
    // `sessions` is keyed by a TEXT id, so every read that matters — the
    // workouts list, the activity tab, both `decoded_onehz` HR joins,
    // [SessionStore.inRange], [SessionStore.live] — was a full table scan plus a full
    // sort on an unindexed column. Nothing prunes `sessions` either (only an
    // explicit day delete), so the scan grows for the life of the install.
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sessions_start ON sessions(start_ts)',
    );
  }

  // ── DERIVED-ONLY SQL VIEWS (the CSV export reads these) ────────────────────
  // Re-created on every open (DROP+CREATE) so a view-shape change takes effect on
  // upgrade. These flatten DERIVED data only, never raw_records / decoded_*.
  // Every view over day_result selects the LATEST algo_version per day_id.
  static Future<void> _ensureCoachViews(Database db) async {
    const views = [
      'v_metric',
      'v_daily',
      'v_series',
      'v_hypnogram',
      'v_sessions',
      'v_baselines',
      'v_insights',
    ];
    for (final v in views) {
      await db.execute('DROP VIEW IF EXISTS $v');
    }
    // Long-form scalar trends — the natural per-metric time series.
    await db.execute('''
      CREATE VIEW v_metric AS
      SELECT date, key, value FROM metric_series
    ''');
    // One row per day, common scalars pivoted from metric_series (no JSON path
    // drift; metric_series is the canonical scalar store).
    await db.execute('''
      CREATE VIEW v_daily AS
      SELECT date,
        MAX(CASE WHEN key='rhr' THEN value END)            AS resting_hr,
        MAX(CASE WHEN key='rmssd' THEN value END)          AS hrv,
        MAX(CASE WHEN key='sdnn' THEN value END)           AS sdnn,
        MAX(CASE WHEN key='readiness' THEN value END)      AS readiness,
        MAX(CASE WHEN key='strain' THEN value END)         AS strain,
        MAX(CASE WHEN key='resp_rate' THEN value END)      AS resp_rate,
        MAX(CASE WHEN key='stress' THEN value END)         AS stress,
        MAX(CASE WHEN key='efficiency' THEN value END)     AS sleep_efficiency,
        MAX(CASE WHEN key='tst_min' THEN value END)        AS sleep_min,
        MAX(CASE WHEN key='deep_min' THEN value END)       AS deep_min,
        MAX(CASE WHEN key='rem_min' THEN value END)        AS rem_min,
        MAX(CASE WHEN key='light_min' THEN value END)      AS light_min,
        MAX(CASE WHEN key='nap_min' THEN value END)        AS nap_min,
        MAX(CASE WHEN key='steps' THEN value END)          AS steps,
        MAX(CASE WHEN key='calories' THEN value END)       AS active_calories,
        MAX(CASE WHEN key='calories_total' THEN value END) AS total_calories,
        MAX(CASE WHEN key='skin_temp_z' THEN value END)    AS skin_temp_z,
        MAX(CASE WHEN key='lf_hf' THEN value END)          AS lf_hf,
        MAX(CASE WHEN key='hrv_cv' THEN value END)         AS hrv_cv,
        MAX(CASE WHEN key='dip_pct' THEN value END)        AS dip_pct,
        MAX(CASE WHEN key='odi_per_hour' THEN value END)   AS odi_per_hour,
        MAX(CASE WHEN key='worn_min' THEN value END)       AS worn_min,
        MAX(CASE WHEN key='hrr_bpm' THEN value END)        AS hrr_bpm,
        MAX(CASE WHEN key='brv_cv' THEN value END)         AS brv_cv,
        MAX(CASE WHEN key='irregular_rhythm_flag' THEN value END) AS irregular_flag
      FROM metric_series GROUP BY date
    ''');
    // Intra-day curves UNNESTED from the latest day_result bundle. HEAVY — always
    // filter by date AND series. zone_timeline uses 'z'; activity_curve is root.
    //
    // THREE SHAPES, one row each. A curve is stored either legacy
    // (`[{t,v},…]`), grid (`{t0,dt,v[]}`) or offset (`{t0,to[],v[]}`) — see
    // data/series_codec.dart for why. Old rows keep their legacy shape forever,
    // so this view must read all three, and the branch guards are what keep a
    // row from being emitted twice: legacy requires an `array`, grid requires
    // `.dt`, offset requires `.to` AND no `.dt`. The codec never writes both,
    // but "never" is not enforced by the storage layer — a foreign or corrupted
    // curve carrying both fields matched the grid and offset branches at once
    // and silently doubled the curve. The `.dt` precedence also matches
    // SeriesCodec.decodeCurve, so SQL and Dart resolve an ambiguous curve the
    // same way rather than disagreeing.
    //
    // `latest` filters on json_valid first: json_extract raises on a malformed
    // document, and without the guard ONE corrupt payload fails the entire
    // v_series query instead of dropping that one day.
    //
    // The grid branch needs no running sum because json_each exposes an array's
    // index as `key`, so t = t0 + key*dt. Verified row-for-row against the
    // pre-codec view on the three tracked bundle fixtures, including a database
    // holding both shapes at once (test/data/coach_views_series_shapes_test.dart).
    //
    // The offset branch walks `.v` ONCE and indexes into `.to` by that key. The
    // obvious form — json_each over `.to` joined to json_each over `.v` on
    // `key` — is quadratic: SQLite cannot index a table-valued function, so the
    // join degrades to a full cross product of the two and the cost grows with
    // the SQUARE of the curve length. hrv_day, hrv_timeline and resp_day are
    // all irregularly sampled and therefore all offset-encoded, so this is the
    // hot path, not a corner: on 365 real days a `SELECT AVG(v)` measured 877 ms
    // against 89 ms, and on 1440-point curves a 30-day slice took 2.1 s. The
    // `e.key < json_array_length(.to)` bound is what keeps the rewrite
    // row-for-row identical rather than merely equivalent on well-formed data —
    // the join emitted min(len(to), len(v)) rows, and without the bound a `to`
    // shorter than `v` would gain rows with a NULL `t`. Pinned by a query-plan
    // assertion in test/data/coach_views_series_shapes_test.dart: two nested virtual
    // table scans in this branch is the regression.
    await db.execute('''
      CREATE VIEW v_series AS
      WITH latest AS (
        SELECT r.day_id, r.payload_json FROM day_result r
        ${DayResultStore._servedDayJoin}
        WHERE json_valid(r.payload_json)
      ),
      curve(sk, pth, vk) AS (
        SELECT 'hr_curve','\$.series.hr_curve','\$.v'
        UNION ALL SELECT 'strain_curve','\$.series.strain_curve','\$.v'
        UNION ALL SELECT 'hrv_timeline','\$.series.hrv_timeline','\$.v'
        UNION ALL SELECT 'hrv_day','\$.series.hrv_day','\$.v'
        UNION ALL SELECT 'resp_day','\$.series.resp_day','\$.v'
        UNION ALL SELECT 'skin_temp_day','\$.series.skin_temp_day','\$.v'
        UNION ALL SELECT 'zone_timeline','\$.series.zone_timeline','\$.z'
        UNION ALL SELECT 'activity_curve','\$.activity_curve','\$.v'
      )
      SELECT l.day_id AS date, c.sk AS series,
             json_extract(e.value,'\$.t') AS t,
             json_extract(e.value, c.vk) AS v
      FROM latest l JOIN curve c
      JOIN json_each(json_extract(l.payload_json, c.pth)) e
      WHERE json_type(json_extract(l.payload_json, c.pth)) = 'array'
      UNION ALL
      SELECT l.day_id, c.sk,
             json_extract(l.payload_json, c.pth||'.t0')
               + e.key * json_extract(l.payload_json, c.pth||'.dt'),
             e.value
      FROM latest l JOIN curve c
      JOIN json_each(json_extract(l.payload_json, c.pth||'.v')) e
      WHERE json_extract(l.payload_json, c.pth||'.dt') IS NOT NULL
      UNION ALL
      SELECT l.day_id, c.sk,
             json_extract(l.payload_json, c.pth||'.t0')
               + json_extract(l.payload_json, c.pth||'.to['||e.key||']'),
             e.value
      FROM latest l JOIN curve c
      JOIN json_each(json_extract(l.payload_json, c.pth||'.v')) e
      WHERE json_extract(l.payload_json, c.pth||'.dt') IS NULL
        AND json_extract(l.payload_json, c.pth||'.to') IS NOT NULL
        AND e.key < json_array_length(json_extract(l.payload_json, c.pth||'.to'))
    ''');
    // Sleep stage segments (different element shape from the {t,v} curves).
    // Same json_valid guard as v_series and for the same reason: without it one
    // malformed payload_json anywhere in day_result makes this view THROW, so a
    // single corrupt row takes every day's sleep stages away from the coach
    // instead of just its own.
    await db.execute('''
      CREATE VIEW v_hypnogram AS
      WITH latest AS (
        SELECT r.day_id, r.payload_json FROM day_result r
        ${DayResultStore._servedDayJoin}
        WHERE json_valid(r.payload_json)
      )
      SELECT l.day_id AS date,
             json_extract(e.value,'\$.start') AS start_ts,
             json_extract(e.value,'\$.end')   AS end_ts,
             json_extract(e.value,'\$.stage') AS stage
      FROM latest l, json_each(json_extract(l.payload_json,'\$.series.hypnogram')) e
    ''');
    // Workouts (incl. HRR + steps). `date` is the session's LOCAL calendar day
    // (device-local, same 'localtime' pattern as dataHistoryDays()) — added so
    // "today's workout" can be resolved with `WHERE date = 'YYYY-MM-DD'`
    // instead of the coach having to convert a local day back into a raw
    // start_ts/end_ts epoch range itself, which silently drifted to UTC
    // (issue #129: coach mis-dated workouts near local-midnight boundaries).
    await db.execute('''
      CREATE VIEW v_sessions AS
      SELECT id, start_ts, end_ts,
             ${storedDayLabelSql('sessions.start_ts')} AS date,
             type, status, calories, strain, max_hr,
             duration_min, steps, hrr_bpm, source, zone_min_json
      FROM sessions
    ''');
    // Rolling personal baselines (json_extract; missing paths return NULL safely).
    await db.execute('''
      CREATE VIEW v_baselines AS
      SELECT key,
             json_extract(payload_json,'\$.value')           AS value,
             json_extract(payload_json,'\$.mean')            AS mean,
             json_extract(payload_json,'\$.z')               AS z,
             json_extract(payload_json,'\$.delta')           AS delta,
             json_extract(payload_json,'\$.ratio')           AS ratio,
             json_extract(payload_json,'\$.n')               AS n,
             updated_at
      FROM baselines
    ''');
    // Locally-generated insight / notification feed.
    await db.execute('''
      CREATE VIEW v_insights AS
      SELECT id, kind, title, body, date, created_at, read FROM notifications
    ''');
  }

  /// Run a rename → recreate → copy legacy-shape migration ATOMICALLY and
  /// IDEMPOTENTLY.
  ///
  /// The three callers below used to do `ALTER … RENAME`, then `CREATE`, then a
  /// row-by-row copy, then `DROP` — all OUTSIDE any transaction. That is fine
  /// under `onUpgrade` (sqflite wraps the whole ladder in one exclusive txn) but
  /// these also run from `_repairOpenSchema` in `onOpen`, which is NOT wrapped.
  /// A crash / OS kill between the rename and the end of the copy left
  /// `<table>` present AND correctly shaped, so the next open hit the
  /// "already current" early-return and `<table>_legacy` sat there orphaned with
  /// its rows never migrated — losing `strap_trim` / `counter_hw` / `rec_ts_hw`,
  /// i.e. the whole resumable-sync cursor and the safe-trim high-water.
  ///
  /// Now: one transaction — which sqflite JOINS to the already-open `onUpgrade`
  /// transaction when called from the ladder, and opens for real from `onOpen`
  /// — plus an explicit RESUME of an orphan left behind by any older build.
  ///
  /// [isCurrent] decides whether an existing `<table>` is already the new shape.
  /// [copy] must be idempotent (INSERT OR REPLACE on a natural key); set
  /// [copyOnlyIntoEmpty] for a destination with no natural key (autoincrement
  /// id), where re-running a resume would otherwise duplicate rows. If that
  /// destination is populated, retain the legacy table too: a nonempty copy
  /// does not establish that an older interrupted migration copied every row.
  static Future<void> _migrateLegacyTable(
    Database db, {
    required String table,
    required bool Function(Set<String> columns) isCurrent,
    required Future<void> Function(DatabaseExecutor ex) create,
    required Future<void> Function(
      DatabaseExecutor ex,
      List<Map<String, Object?>> legacyRows,
      int nowMs,
    )
    copy,
    bool copyOnlyIntoEmpty = false,
  }) async {
    final legacy = '${table}_legacy';
    await db.transaction((txn) async {
      Future<bool> exists(String t) async => (await txn.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
        [t],
      )).isNotEmpty;
      Future<Set<String>> columnsOf(String t) async {
        final info = await txn.rawQuery('PRAGMA table_info($t)');
        return {
          for (final c in info)
            if (c['name'] is String) c['name'] as String,
        };
      }

      if (!await exists(legacy)) {
        // Normal path.
        if (!await exists(table)) {
          await create(txn);
          return;
        }
        if (isCurrent(await columnsOf(table))) return;
        await txn.execute('ALTER TABLE $table RENAME TO $legacy');
      }
      // From here on `<table>_legacy` holds the rows of record. `<table>` is
      // either absent (crash between RENAME and CREATE) or the new shape
      // (possibly half-copied, or fully copied by an older build that then
      // died before the DROP) — create it if needed and re-copy; the copy is
      // idempotent, so a repeat is a no-op rather than a duplication.
      if (!await exists(table)) await create(txn);
      final skipCopy =
          copyOnlyIntoEmpty &&
          (Sqflite.firstIntValue(
                    await txn.rawQuery('SELECT COUNT(*) FROM $table'),
                  ) ??
                  0) >
              0;
      if (skipCopy) return;
      await copy(
        txn,
        await txn.query(legacy),
        DateTime.now().millisecondsSinceEpoch,
      );
      await txn.execute('DROP TABLE $legacy');
    });
  }

  static Future<void> _ensureSyncCursorSchema(Database db) =>
      _migrateLegacyTable(
        db,
        table: 'sync_cursor',
        isCurrent: (c) =>
            c.contains('name') &&
            c.contains('value') &&
            c.contains('updated_at'),
        create: _createSyncCursor,
        copy: (ex, legacyRows, now) async {
          for (final row in legacyRows) {
            final name = row['name'] as String?;
            if (name == null || name.isEmpty) continue;
            await ex.insert('sync_cursor', {
              'name': name,
              'value': row['value']?.toString(),
              'updated_at': (row['updated_at'] as num?)?.toInt() ?? now,
            }, conflictAlgorithm: ConflictAlgorithm.replace);
          }
        },
      );

  static Future<void> _ensureSyncLedgerSchema(Database db) =>
      _migrateLegacyTable(
        db,
        table: 'sync_ledger',
        isCurrent: (c) => c.contains('chunk_id'),
        create: _createSyncState,
        copy: (ex, legacyRows, now) async {
          for (final row in legacyRows) {
            final meta = <String, dynamic>{
              'last_batch_token': row['last_batch_token'],
              'last_batch_id': row['last_batch_id'],
              'last_batch_records': row['last_batch_records'],
              'last_history_complete_at': row['last_history_complete_at'],
              'last_trim_cutoff_ms': row['last_trim_cutoff_ms'],
              'last_trimmed_at': row['last_trimmed_at'],
              if (row['note'] != null) 'legacy_note': row['note'],
            };
            await ex.insert('sync_ledger', {
              'chunk_id': (row['id'] as String?) ?? 'capture',
              'kind': 'historical',
              'status': row['last_history_complete_at'] != null
                  ? 'complete'
                  : row['last_batch_acked_at'] != null
                  ? 'acknowledged'
                  : 'legacy',
              'created_at': (row['updated_at'] as num?)?.toInt() ?? now,
              'updated_at': (row['updated_at'] as num?)?.toInt() ?? now,
              'acked_at': (row['last_batch_acked_at'] as num?)?.toInt(),
              'last_error': null,
              'meta_json': jsonEncode(meta),
            }, conflictAlgorithm: ConflictAlgorithm.replace);
          }
        },
      );

  static Future<void> _ensureSyncQuarantineSchema(Database db) =>
      _migrateLegacyTable(
        db,
        table: 'sync_quarantine',
        isCurrent: (c) => c.contains('payload_json'),
        create: _createSyncState,
        // `id INTEGER PRIMARY KEY AUTOINCREMENT` — no natural key to REPLACE
        // on, so a resume must not re-copy into a destination that already has
        // rows or the quarantine log would double on every retry.
        copyOnlyIntoEmpty: true,
        copy: (ex, legacyRows, now) async {
          for (final row in legacyRows) {
            await ex.insert('sync_quarantine', {
              'kind': (row['source_role'] as String?) ?? 'legacy',
              'payload_json': jsonEncode({
                'fingerprint': row['fingerprint'],
                'packet_type': row['packet_type'],
                'hex': row['hex'],
                'counter': row['counter'],
                'captured_at': row['captured_at'],
              }),
              'reason': (row['reason'] as String?) ?? 'legacy_migrated',
              'created_at': (row['created_at'] as num?)?.toInt() ?? now,
            });
          }
        },
      );

  // samples — LEGACY header-only record index (counter, ts, hr). Retained only
  // so pre-v11 databases stay readable if decoded_onehz backfill was partial.
  // New writes should go to decoded_onehz instead.
  //
  // v47: re-keyed off `counter` for the same reason decoded_onehz was re-keyed
  // off it at v33 and off rec_ts now — `counter` is a WHOOP FLASH RECORD
  // COUNTER, so a second offloading band's counter 500 is a different reading
  // that collides with the first band's. The insert is IGNORE, so the collision
  // DROPPED the newer row rather than replacing the older one, and
  // [latestSample]'s fallback then served a stale second.
  static Future<void> _createSamples(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS samples (
        device_id TEXT NOT NULL DEFAULT '',
        ts_ms INTEGER NOT NULL DEFAULT 0,
        counter INTEGER,
        ts INTEGER NOT NULL,
        hr INTEGER,
        PRIMARY KEY (device_id, ts_ms)
      )
    ''');
  }

  // decoded_onehz / decoded_rr — durable canonical decoded substrate, additive
  // beside raw_records. This is the canonical query surface for on-device
  // analytics: one row per real second (`rec_ts`) plus sparse RR beats for that
  // second. raw_records stays as the replay/debug ledger and upgrade fallback.
  static Future<void> _createDecodedStore(Database db) async {
    // KEYED BY rec_ts, NOT the band's record `counter`. The strap resets its
    // per-record counter to ~0 on every reboot, so `counter INTEGER PRIMARY KEY`
    // let a post-reboot record (counter=c, rec_ts=T2) REPLACE-evict a still-present
    // pre-reboot row (counter=c, rec_ts=T1) — silently and UNRECOVERABLY deleting
    // T1's only decoded 1 Hz row (raw_records is DROPped, so this store is the sole
    // system of record). rec_ts is unique per real second, so newest-wins REPLACE
    // on rec_ts is safe. `counter` is demoted to a NOT NULL forensic column (also
    // the keyset-cursor tiebreak in decodedOneHzBatchByRecTsRange, which never
    // fires now that rec_ts is unique).
    //
    // v47: KEYED BY (device_id, ts_ms), NOT rec_ts alone. `rec_ts` stays as the
    // indexed READ key — every query in this file ranges over it — but it can no longer be the identity, because a second device
    // measuring the same second is a DIFFERENT reading, and REPLACE on a
    // shared rec_ts silently deletes the first one (raw prunes at 3 days, so
    // that loss is permanent). See [_rekeyTableByDevice].
    //
    // `device_id = ''` IS RESERVED PERMANENTLY FOR THE PRIMARY BAND. Not a
    // migration default — a standing rule, and it is load-bearing twice over:
    //  * The newest-wins dedupe above only works if every row from the one
    //    physical band shares one key value. A post-reboot counter reset and a
    //    re-drained record must still collide on (device_id, ts_ms).
    //  * A BLE `remoteId` is NOT STABLE (a per-app CBPeripheral UUID).
    //    Letting one reach this column would
    //    fragment one band into N identities across reinstalls, each with its
    //    own baseline. Only a SECONDARY device gets a real id, and only one an
    //    adapter issues from something the band emits across the handshake.
    //
    // `ts_ms` is `rec_ts * 1000` for every WHOOP row and for every row this
    // migration rewrites, so the key is EXACTLY as unique as it was — no
    // number moves. The millisecond resolution is there so a source faster
    // than 1 Hz has somewhere to land instead of REPLACE-ing itself down to
    // one row per second, which is the same defect in a different table.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS decoded_onehz (
        device_id TEXT NOT NULL DEFAULT '',
        ts_ms INTEGER NOT NULL DEFAULT 0,
        -- NOT re-asserted NOT NULL, deliberately: [_rekeyTableByDevice] copies
        -- this column verbatim out of a table where SQLite never enforced it
        -- (a declared PRIMARY KEY on a legacy rowid table does not imply NOT
        -- NULL), and a constraint failure inside onUpgrade's one exclusive
        -- transaction quarantines the whole database (invariant 11).
        rec_ts INTEGER,
        counter INTEGER NOT NULL,
        hr INTEGER,
        ax REAL,
        ay REAL,
        az REAL,
        spo2_red_raw INTEGER,
        spo2_ir_raw INTEGER,
        skin_temp_raw INTEGER,
        step_count INTEGER,
        step_cadence INTEGER,
        activity_class INTEGER,
        skin_temp_c REAL,
        on_wrist INTEGER,
        hr_valid INTEGER,
        hr_alt INTEGER,
        ambient_raw INTEGER,
        device_family TEXT,
        source TEXT,
        temp_ch2_c REAL,
        temp_ch3_c REAL,
        signal_quality_logvar REAL,
        dyn_accel_g REAL,
        PRIMARY KEY (device_id, ts_ms)
      )
    ''');
    // v43: `hr` IS NULLABLE TOO, and it is the last sensor column to get there.
    //
    // `hr == 0` is this app's OFF-SKIN SENTINEL, and the NOT NULL forced every
    // record carrying no heart-rate field at all to be written as one. That is
    // a different claim — "the band was off your wrist" instead of "this record
    // has no HR" — and it is the reason the gen4 v25 record is archived instead
    // of banked: a 24 Hz PPG burst with a decoder-validated gravity vector and
    // genuinely no beat anywhere in it (ble_engine's own note says so), ~50 000
    // seconds per real export. NULL says the honest thing, and the app already
    // agrees with it everywhere: every SQL read of this column is gated
    // `hr > 0` (which NULL fails) or is an aggregate (which skips NULL), and
    // every Dart read lands NULL on the same 0 the substrate has always used
    // for "no heart rate this second".
    //
    // What it does NOT buy: a NULL-hr second is observed for the REST window
    // and UNOBSERVED for staging. It carries no beat, so it can never
    // contribute to a stage, an RHR, an HRV or the cardiac-evidence test —
    // analytics' observed mask is `sampled[i] && hrNear[i]` and only `sampled`
    // flips. Expect a 1-5 pp lift in observed fraction plus denser gravity.
    //
    // Every band-computed column above is NULLABLE ON PURPOSE: only a gen5 band
    // sends them, and a gen4 row must read back as "not reported", not as zero
    // steps / 0 °C / "off wrist". No DEFAULT, ever.
    //
    // v39: the SENSOR columns (ax/ay/az, spo2_*, skin_temp_raw) are nullable for
    // the same reason. They were `NOT NULL`, so `SyncLedgerStore.commitBatch` coerced an
    // absent reading to `?? 0` and the ledger stored a fabricated measurement —
    // a real 0 g gravity vector and a real ADC count of 0. A record can
    // legitimately carry HR without accel (gen5 v18, and the gen4 R10-historical
    // path decodes HR/counter only), and gen5 has no equivalent of the gen4
    // optical/thermal ADCs at all, so those three are ALWAYS absent there.
    // Absence now lands as NULL. `_relaxDecodedSensorNulls` (v39) rebuilds the
    // table on existing installs.
    // `on_wrist` and `hr_valid` currently have NO honest writer at all — the
    // gen5 v18 bits once mapped onto them are disproven (see
    // `sampleFromGen5Historical` and _retireDisprovenOneHzColumns), so every
    // row written since that mapping change stores NULL. The columns are kept, nullable and
    // correctly shaped, for a source that can actually supply them; they are
    // NOT a place to park a plausible-looking bit.
    await _ensureDecodedOneHzBandFields(db);
    // NO index on `counter`. There was one, described as a forensic-only
    // lookup — and nothing in the app ever filtered or ordered by `counter`
    // alone (every decoded read is `ORDER BY rec_ts, counter`, which a
    // single-column counter index cannot serve). It cost a b-tree insert per
    // 1 Hz record on the hottest write path in the app, ~1.7 MB/day of disk,
    // and the inserts were NON-SEQUENTIAL because `counter` resets to ~0 on a
    // band reboot — so it was paying page splits on the ingest path for a
    // query nobody makes. Dropped for existing installs in _repairOpenSchema.
    // decoded_rr shares its parent's key EXACTLY, one level deeper: PRIMARY KEY
    // (device_id, ts_ms, beat_index) against the parent's (device_id, ts_ms).
    // Parent and child still delete/replace by the SAME key, so no orphan guard
    // is needed — and that is the whole reason the two keys must move together.
    // Before v47 `_queueRrBeats` cleared the second with an unscoped
    // `DELETE ... WHERE rec_ts = ?`, which for a second device deleted the
    // FIRST band's beats for that second and could not be undone.
    // rr_ts_ms (= rec_ts*1000) stays as the per-beat timestamp the compute
    // worker reads; `rec_ts` stays as the indexed range key.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS decoded_rr (
        device_id TEXT NOT NULL DEFAULT '',
        ts_ms INTEGER NOT NULL DEFAULT 0,
        rec_ts INTEGER NOT NULL,
        beat_index INTEGER NOT NULL,
        rr_ts_ms INTEGER NOT NULL,
        rr_ms INTEGER NOT NULL,
        device_family TEXT,
        source TEXT,
        PRIMARY KEY (device_id, ts_ms, beat_index)
      )
    ''');
    // rec_ts USED TO BE THE KEY, and the key was the only index — every read in
    // this file ranges over it. Without these the v47
    // re-key turns each of them into a full table scan.
    //
    // GUARDED ON THE COLUMN, not on IF NOT EXISTS. This helper runs MID-LADDER
    // too (`_rekeyDecodedStoreByRecTs`, oldV<33), where `decoded_rr` is still
    // the counter-keyed shape and has no `rec_ts` at all — and an index on a
    // missing column throws inside onUpgrade's one exclusive transaction and
    // quarantines the whole database (invariant 11).
    //
    // TWO COLUMNS EACH, matching each table's `ORDER BY` exactly — `rec_ts,
    // counter` on the parent and `rec_ts, beat_index` on the child — so the
    // ordering comes out of the index and the planner needs no temp b-tree.
    //
    // ponytail: rec_ts kept as a second, indexed time axis. `ts_ms` is
    // `rec_ts * 1000` for every row this app writes, so these reads COULD range
    // on ts_ms and ride the PK for free — measured ~4.5 MB per 3-day store per
    // index, on the hottest write path. Not done here because ~20 call sites in
    // this file range on rec_ts, and phase 2 is meant to
    // change no read. Fold it in when a reader is being touched anyway.
    for (final t in const {
      'decoded_onehz': 'rec_ts, counter',
      'decoded_rr': 'rec_ts, beat_index',
    }.entries) {
      if ((await _columnsOf(db, t.key)).contains('rec_ts')) {
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_${t.key}_rects ON ${t.key}(${t.value})',
        );
      }
    }
    // Existing installs get these here (ADD COLUMN, idempotent).
    await _ensureDeviceFamilyColumns(db);
    await _ensureSourceColumns(db);
    await _ensureBeatTimeColumn(db);
  }

  /// Rebuild the decoded substrate into noop-style canonical time-keyed rows:
  /// keep exactly one decoded row per record second and one RR beat per
  /// (second, beat_index). Older duplicate counters remain in raw_records for
  /// forensics, but analytics no longer sees them.
  static Future<void> _rebuildCanonicalDecodedStore(Database db) async {
    // FROZEN v17 step: it dedups the OLD counter-keyed decoded tables by rec_ts
    // via a `decoded_rr.counter` join. If the store is ALREADY rec_ts-keyed (the
    // ladder created it fresh at v11 with the current schema, so decoded_rr has
    // no `counter` column), it is already canonical — this rebuild is impossible
    // and unnecessary, so skip it. A genuinely old (counter-keyed) store still
    // gets the original rebuild here, and the v33 re-key converts it afterward.
    final rrCols = await db.rawQuery('PRAGMA table_info(decoded_rr)');
    if (rrCols.isNotEmpty && !rrCols.any((c) => c['name'] == 'counter')) return;
    // Guarantee the OLD-schema source tables exist before we SELECT from them.
    // On upgrade paths from before the decoded store landed they were never
    // created, so this rebuild threw "no such table" and bricked openDatabase.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS decoded_onehz (
        counter INTEGER PRIMARY KEY, rec_ts INTEGER NOT NULL,
        hr INTEGER NOT NULL, ax REAL NOT NULL, ay REAL NOT NULL, az REAL NOT NULL,
        spo2_red_raw INTEGER NOT NULL, spo2_ir_raw INTEGER NOT NULL,
        skin_temp_raw INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS decoded_rr (
        counter INTEGER NOT NULL, beat_index INTEGER NOT NULL,
        rr_ts_ms INTEGER NOT NULL, rr_ms INTEGER NOT NULL,
        PRIMARY KEY (counter, beat_index)
      )
    ''');
    await db.execute('DROP TABLE IF EXISTS _decoded_onehz_new');
    await db.execute('DROP TABLE IF EXISTS _decoded_rr_new');
    // Drop any leftover temp-named indexes BEFORE recreating them. SQLite index
    // names are database-GLOBAL, and a prior rebuild's `ALTER TABLE _decoded_*_new
    // RENAME TO decoded_*` leaks these `_new` index names onto the FINAL tables
    // (a renamed table keeps its indexes, names and all). On a re-run the plain
    // `CREATE INDEX idx_decoded_onehz_new_rects ...` then throws "index already
    // exists", which fails openDatabase → the upgrade never commits → the rebuild
    // re-runs every launch → app stuck on the loading screen. Dropping the names
    // first makes this rebuild fully idempotent and breaks that loop.
    for (final ix in const [
      'idx_decoded_onehz_new_rects',
      'idx_decoded_onehz_new_rec_ts_unique',
      'idx_decoded_rr_new_counter',
      'idx_decoded_rr_new_ts',
      'idx_decoded_rr_new_ts_beat_unique',
    ]) {
      await db.execute('DROP INDEX IF EXISTS $ix');
    }
    await db.execute('''
      CREATE TABLE _decoded_onehz_new (
        counter INTEGER PRIMARY KEY,
        rec_ts INTEGER NOT NULL,
        -- `hr` IS NULLABLE ON EVERY INTERMEDIATE TABLE OF THE LADDER, not just
        -- the final one. These rebuilds are copy TARGETS for rows an EARLIER
        -- rung already wrote, and since v43 `_queueDecodedOneHz` writes NULL
        -- for a record with no heart rate (`hr == 0` was the off-skin
        -- sentinel — ordinary, not rare). A NOT NULL here fails the copy,
        -- throws inside the one exclusive onUpgrade transaction, and
        -- quarantines the database. See _relaxDecodedHrNull.
        hr INTEGER,
        ax REAL NOT NULL,
        ay REAL NOT NULL,
        az REAL NOT NULL,
        spo2_red_raw INTEGER NOT NULL,
        spo2_ir_raw INTEGER NOT NULL,
        skin_temp_raw INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_decoded_onehz_new_rects ON _decoded_onehz_new(rec_ts, counter)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX idx_decoded_onehz_new_rec_ts_unique '
      'ON _decoded_onehz_new(rec_ts)',
    );
    await db.execute('''
      CREATE TABLE _decoded_rr_new (
        counter INTEGER NOT NULL,
        beat_index INTEGER NOT NULL,
        rr_ts_ms INTEGER NOT NULL,
        rr_ms INTEGER NOT NULL,
        PRIMARY KEY (counter, beat_index)
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_decoded_rr_new_counter ON _decoded_rr_new(counter, beat_index)',
    );
    await db.execute(
      'CREATE INDEX idx_decoded_rr_new_ts ON _decoded_rr_new(rr_ts_ms)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX idx_decoded_rr_new_ts_beat_unique '
      'ON _decoded_rr_new(rr_ts_ms, beat_index)',
    );
    await db.execute(
      'INSERT OR IGNORE INTO _decoded_onehz_new '
      '(counter, rec_ts, hr, ax, ay, az, spo2_red_raw, spo2_ir_raw, skin_temp_raw) '
      'SELECT d.counter, d.rec_ts, d.hr, d.ax, d.ay, d.az, '
      'd.spo2_red_raw, d.spo2_ir_raw, d.skin_temp_raw '
      'FROM decoded_onehz d '
      'JOIN ('
      '  SELECT rec_ts, MIN(counter) AS keep_counter '
      '  FROM decoded_onehz GROUP BY rec_ts'
      ') k '
      'ON k.rec_ts = d.rec_ts AND k.keep_counter = d.counter '
      'ORDER BY d.rec_ts ASC, d.counter ASC',
    );
    await db.execute(
      'INSERT OR IGNORE INTO _decoded_rr_new(counter, beat_index, rr_ts_ms, rr_ms) '
      'SELECT rr.counter, rr.beat_index, rr.rr_ts_ms, rr.rr_ms '
      'FROM decoded_rr rr '
      'JOIN _decoded_onehz_new onehz ON onehz.counter = rr.counter '
      'ORDER BY rr.rr_ts_ms ASC, rr.beat_index ASC, rr.counter ASC',
    );
    await db.execute('DROP TABLE IF EXISTS decoded_rr');
    await db.execute('DROP TABLE IF EXISTS decoded_onehz');
    await db.execute('ALTER TABLE _decoded_onehz_new RENAME TO decoded_onehz');
    await db.execute('ALTER TABLE _decoded_rr_new RENAME TO decoded_rr');
  }

  /// v33: re-key the decoded store off the volatile record `counter` onto rec_ts.
  ///
  /// Rebuilds BOTH decoded tables FROM THE EXISTING decoded tables ONLY. It must
  /// NOT backfill from raw_records (that table is DROPped — a raw-backfill would
  /// zero the store, total loss). Existing rows have a unique rec_ts, so the copy
  /// loses nothing; any pre-fix duplicate counters collapse to newest-wins per
  /// rec_ts. Idempotent: a crash mid-migration re-runs cleanly (the temp tables
  /// are dropped up front, and every write is INSERT OR REPLACE keyed on identity).
  ///
  /// All copies are INSERT ... SELECT (server-side, ZERO host-bound variables),
  /// so the iOS SQLITE_MAX_VARIABLE_NUMBER (999) never applies — no chunking is
  /// needed. Mirrors [_rebuildCanonicalDecodedStore]'s rename-aside shape.
  /// v39: drop `NOT NULL` from the six SENSOR columns of `decoded_onehz`.
  ///
  /// SQLite cannot relax a constraint in place, so this is the standard
  /// rebuild — same shape as [_rekeyDecodedStoreByRecTs], but `decoded_rr` is
  /// untouched and no row is rewritten: the copy is a straight column-for-column
  /// SELECT, so it is safe on a populated table and existing values (including
  /// the historical fabricated zeros, which readers already treat as absent)
  /// survive verbatim. A pre-v34 DB reaching this step has already had the band
  /// columns added by the v34 rung above, so the explicit column list is valid.
  static Future<void> _relaxDecodedSensorNulls(Database db) async {
    // No table yet (fresh-ish upgrade path) ⇒ the current DDL already carries
    // the nullable columns and there is nothing to rebuild.
    if ((await _columnsOf(db, 'decoded_onehz')).isEmpty) return;
    await _ensureDecodedOneHzBandFields(db);
    await db.execute('DROP TABLE IF EXISTS _decoded_onehz_v39');
    await db.execute('''
      CREATE TABLE _decoded_onehz_v39 (
        rec_ts INTEGER PRIMARY KEY,
        counter INTEGER NOT NULL,
        hr INTEGER, -- nullable on every intermediate: see _decoded_onehz_new
        ax REAL,
        ay REAL,
        az REAL,
        spo2_red_raw INTEGER,
        spo2_ir_raw INTEGER,
        skin_temp_raw INTEGER,
        step_count INTEGER,
        step_cadence INTEGER,
        activity_class INTEGER,
        skin_temp_c REAL,
        on_wrist INTEGER,
        hr_valid INTEGER,
        hr_alt INTEGER
      )
    ''');
    const cols =
        'rec_ts, counter, hr, ax, ay, az, spo2_red_raw, spo2_ir_raw, '
        'skin_temp_raw, step_count, step_cadence, activity_class, skin_temp_c, '
        'on_wrist, hr_valid, hr_alt';
    await db.execute(
      'INSERT OR REPLACE INTO _decoded_onehz_v39 ($cols) '
      'SELECT $cols FROM decoded_onehz ORDER BY rec_ts ASC',
    );
    await db.execute('DROP TABLE IF EXISTS decoded_onehz');
    await db.execute('ALTER TABLE _decoded_onehz_v39 RENAME TO decoded_onehz');
  }

  /// One `CREATE TABLE (…)` body reconstructed from a live `PRAGMA
  /// table_info`, for the rebuild-aside migrations in this file.
  ///
  /// DERIVED, NEVER HARDCODED. These tables' column sets are genuinely in flux
  /// (`ambient_raw` v42, `device_family` v41, `source` + the MT-12 channels
  /// v43, `ts_subsec` / `band_sleep_state` off-ladder), and a hardcoded list
  /// silently DROPS every column added after it was written — data loss, in a
  /// rung that runs once and cannot be re-run.
  ///
  /// THE PRIMARY KEY IS THE PART THAT NEEDS CARE. `PRAGMA table_info.pk` is a
  /// 1-based POSITION, not a flag, so a composite key reports several columns.
  /// A one-column key is emitted INLINE (`x INTEGER PRIMARY KEY`) because that
  /// is the only spelling that keeps SQLite's rowid-alias behaviour; anything
  /// wider must be a table-level `PRIMARY KEY (a, b)` clause, and emitting the
  /// inline form for each of them instead throws "table has more than one
  /// primary key".
  ///
  /// [prepend] columns are emitted first, verbatim, and are NOT in [info] — a
  /// re-key adds its new key columns that way. [primaryKey] replaces the old
  /// key entirely; omit it to carry the table's own key across.
  /// [dropNotNull] relaxes named columns. Nothing here ever ADDS a constraint:
  /// a constraint failure inside `onUpgrade`'s single exclusive transaction
  /// rolls the whole ladder back and quarantines the database (invariant 11),
  /// so a rebuild may only ever loosen.
  static String _rebuildDdlBody(
    List<Map<String, Object?>> info, {
    Set<String> dropNotNull = const {},
    List<String> prepend = const [],
    List<String>? primaryKey,
  }) {
    final own =
        [
          for (final c in info)
            if ((((c['pk'] as num?)?.toInt()) ?? 0) > 0) c,
        ]..sort(
          (a, b) =>
              ((a['pk'] as num).toInt()).compareTo((b['pk'] as num).toInt()),
        );
    final key = primaryKey ?? [for (final c in own) c['name'] as String];
    final inline = key.length == 1 ? key.first : null;
    final defs = <String>[...prepend];
    for (final c in info) {
      final name = c['name'] as String;
      final dflt = c['dflt_value'];
      final notNull =
          (((c['notnull'] as num?)?.toInt()) ?? 0) == 1 &&
          !dropNotNull.contains(name);
      defs.add(
        '$name ${(c['type'] as String?) ?? ''}'
        '${name == inline ? ' PRIMARY KEY' : ''}'
        '${notNull ? ' NOT NULL' : ''}'
        '${dflt == null ? '' : ' DEFAULT $dflt'}',
      );
    }
    if (inline == null && key.isNotEmpty) {
      defs.add('PRIMARY KEY (${key.join(', ')})');
    }
    return defs.join(', ');
  }

  /// v47: put `device_id` in front of the key of every table whose identity was
  /// a WHOOP-shaped quantity — a record second, or the band's flash counter.
  ///
  /// WHY THIS ONE IS NOT DEFERRABLE. `decoded_onehz` was `rec_ts INTEGER
  /// PRIMARY KEY` written with REPLACE and `decoded_rr` was cleared by an
  /// unscoped `DELETE … WHERE rec_ts = ?`, so a second device measuring the
  /// same second did not merge with the first — it DELETED it, row and beats.
  /// `raw_archive` prunes at `rawRetentionDays = 3`, so within three days the
  /// bytes that could rebuild the evicted row are gone too. Every other item on
  /// the band-agnostic roadmap can be done after a second device has written;
  /// this one cannot.
  ///
  /// WHAT IT DOES NOT CHANGE. Every existing row is copied under
  /// `device_id = ''` with `ts_ms = rec_ts * 1000`, which is exactly as unique
  /// as `rec_ts` was — one row per second per device, same newest-wins REPLACE,
  /// same dedupe. No stored value is rewritten and no derived number moves, so
  /// there is no `kAlgoVersion` bump with it.
  ///
  /// Cheap enough for the launch-path CPU watchdog `onUpgrade` runs inside:
  /// the decoded store is retention-capped at `rawRetentionDays`, ~260 k rows,
  /// and every copy is a server-side `INSERT … SELECT` with zero host-bound
  /// variables (so the iOS `SQLITE_MAX_VARIABLE_NUMBER` never applies and no
  /// chunking is needed).
  static Future<void> _rekeyStoresByDeviceId(Database db) async {
    await _rekeyTableByDevice(db, 'decoded_onehz');
    await _rekeyTableByDevice(db, 'decoded_rr', keyTail: const ['beat_index']);
    await _rekeyTableByDevice(db, 'samples', timeCol: 'ts');
  }

  /// The rename-aside rebuild behind [_rekeyStoresByDeviceId], for one table.
  ///
  /// Self-skipping and idempotent: a table that already carries `device_id` is
  /// left alone (so a fresh install at v47+ does no work at all), the temp
  /// table is dropped up front so a crash mid-migration re-runs cleanly, and
  /// the copy is keyed on identity.
  static Future<void> _rekeyTableByDevice(
    Database db,
    String table, {
    String timeCol = 'rec_ts',
    List<String> keyTail = const [],
  }) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    // Table absent on this upgrade path ⇒ the current DDL already carries the
    // new key and there is nothing to rebuild.
    if (info.isEmpty) return;
    final names = [for (final c in info) c['name'] as String];
    if (names.contains('device_id')) return;
    final tmp = '_${table}_v47';
    await db.execute('DROP TABLE IF EXISTS $tmp');
    await db.execute(
      'CREATE TABLE $tmp (${_rebuildDdlBody(info, prepend: const ["device_id TEXT NOT NULL DEFAULT ''", 'ts_ms INTEGER NOT NULL DEFAULT 0'], primaryKey: ['device_id', 'ts_ms', ...keyTail])})',
    );
    final cols = names.join(', ');
    // COALESCE because a declared PRIMARY KEY on a legacy rowid table does NOT
    // enforce NOT NULL — a NULL time column would put a NULL in the new key,
    // where it compares unequal to itself and escapes the retention prune
    // forever. 0 is behind every cutoff, so such a row is pruned on the next
    // pass instead of leaking.
    await db.execute(
      'INSERT OR REPLACE INTO $tmp (device_id, ts_ms, $cols) '
      "SELECT '', COALESCE($timeCol, 0) * 1000, $cols "
      'FROM $table ORDER BY $timeCol ASC',
    );
    // The COPIED column is normalised too, or the row escapes anyway:
    // `StorageRetentionStore.pruneDecodedBefore` and `deleteDays` both filter
    // the ORIGINAL time column (`rec_ts < ?`), never the key, and `NULL < ?` is
    // NULL. Without this the row is immortal AND invisible — every read gates
    // on > 0.
    await db.execute('UPDATE $tmp SET $timeCol = 0 WHERE $timeCol IS NULL');
    await db.execute('DROP TABLE IF EXISTS $table');
    await db.execute('ALTER TABLE $tmp RENAME TO $table');
  }

  /// v43 (SLP-05): drop `NOT NULL` from `decoded_onehz.hr`.
  ///
  /// See [_createDecodedStore] for WHY. This is the same rebuild shape as
  /// [_relaxDecodedSensorNulls] with one difference: the new table's DDL is
  /// DERIVED from the old table's `PRAGMA table_info` rather than hardcoded.
  /// That column set is genuinely in flux (`ambient_raw` at v42, `device_family`
  /// at v41, `source` and the MT-12 channels at v43, and whatever lands next),
  /// and a hardcoded list here silently DROPS any column added after it was
  /// written — data loss, in a rung that runs once and cannot be re-run. The
  /// copy is column-for-column with no row rewritten, so it is safe on a
  /// populated table and existing values (including the historical `hr = 0`
  /// rows, which every reader already treats as absent) survive verbatim.
  ///
  /// Self-skipping: a database whose `hr` is already nullable — every fresh
  /// create at v43+ — does no work at all. That also keeps it cheap under the
  /// launch-path CPU watchdog `onUpgrade` runs inside (invariant 11); the table
  /// is retention-capped at ~3 days, so the one-time copy is bounded.
  static Future<void> _relaxDecodedHrNull(Database db) async {
    final info = await db.rawQuery('PRAGMA table_info(decoded_onehz)');
    // No table yet on this upgrade path ⇒ the current DDL already carries a
    // nullable `hr` and there is nothing to rebuild.
    if (info.isEmpty) return;
    final hr = info.where((c) => c['name'] == 'hr');
    if (hr.isEmpty || (hr.first['notnull'] as num?)?.toInt() != 1) return;

    final names = [for (final c in info) c['name'] as String];
    await db.execute('DROP TABLE IF EXISTS _decoded_onehz_v43');
    await db.execute(
      'CREATE TABLE _decoded_onehz_v43 '
      '(${_rebuildDdlBody(info, dropNotNull: const {'hr'})})',
    );
    final cols = names.join(', ');
    await db.execute(
      'INSERT OR REPLACE INTO _decoded_onehz_v43 ($cols) '
      'SELECT $cols FROM decoded_onehz ORDER BY rec_ts ASC',
    );
    await db.execute('DROP TABLE IF EXISTS decoded_onehz');
    await db.execute('ALTER TABLE _decoded_onehz_v43 RENAME TO decoded_onehz');
  }

  static Future<void> _rekeyDecodedStoreByRecTs(Database db) async {
    // The source tables may not exist on a pre-decoded-store upgrade path; a
    // create (new schema, IF NOT EXISTS) makes the copy a safe no-op there. On a
    // normal path the OLD-schema tables already exist and this is a no-op — the
    // columns we SELECT (rec_ts, counter, hr, …; beat_index, rr_ts_ms, rr_ms)
    // are present in both the old and new decoded schemas.
    await _createDecodedStore(db);
    await db.execute('DROP TABLE IF EXISTS _decoded_onehz_v33');
    await db.execute('DROP TABLE IF EXISTS _decoded_rr_v33');
    await db.execute('''
      CREATE TABLE _decoded_onehz_v33 (
        rec_ts INTEGER PRIMARY KEY,
        counter INTEGER NOT NULL,
        hr INTEGER, -- nullable on every intermediate: see _decoded_onehz_new
        ax REAL,
        ay REAL,
        az REAL,
        spo2_red_raw INTEGER,
        spo2_ir_raw INTEGER,
        skin_temp_raw INTEGER
      )
    ''');
    // Sensor columns nullable from the start (the v39 shape). They used to be
    // NOT NULL here, which bricked step 19: the rung backfills straight into
    // this rebuilt table via _queueDecodedOneHz, which writes a real NULL for
    // an absent reading. Same reason as _relaxDecodedSensorNulls — absence is
    // not a zero g vector and not an ADC count of 0.
    await db.execute('''
      CREATE TABLE _decoded_rr_v33 (
        rec_ts INTEGER NOT NULL,
        beat_index INTEGER NOT NULL,
        rr_ts_ms INTEGER NOT NULL,
        rr_ms INTEGER NOT NULL,
        PRIMARY KEY (rec_ts, beat_index)
      )
    ''');
    // Deterministic newest-wins: ORDER BY rec_ts, counter so INSERT OR REPLACE on
    // the rec_ts PK keeps the highest-counter (latest-offloaded) row per second.
    await db.execute(
      'INSERT OR REPLACE INTO _decoded_onehz_v33 '
      '(rec_ts, counter, hr, ax, ay, az, spo2_red_raw, spo2_ir_raw, skin_temp_raw) '
      'SELECT rec_ts, counter, hr, ax, ay, az, spo2_red_raw, spo2_ir_raw, skin_temp_raw '
      'FROM decoded_onehz ORDER BY rec_ts ASC, counter ASC',
    );
    // rec_ts derived from rr_ts_ms (= rec_ts*1000 by construction). Pre-fix orphan
    // beats (owning row evicted) re-home onto their real second here.
    await db.execute(
      'INSERT OR REPLACE INTO _decoded_rr_v33 (rec_ts, beat_index, rr_ts_ms, rr_ms) '
      'SELECT rr_ts_ms / 1000, beat_index, rr_ts_ms, rr_ms '
      'FROM decoded_rr ORDER BY rr_ts_ms ASC, beat_index ASC',
    );
    await db.execute('DROP TABLE IF EXISTS decoded_rr');
    await db.execute('DROP TABLE IF EXISTS decoded_onehz');
    await db.execute('ALTER TABLE _decoded_onehz_v33 RENAME TO decoded_onehz');
    await db.execute('ALTER TABLE _decoded_rr_v33 RENAME TO decoded_rr');
    // The rebuild drops the band-computed columns, so put them straight back.
    // Step 33 got away with it because step 34 re-adds them on the next rung;
    // step 19 does NOT — it backfills through _queueDecodedOneHz on the very
    // next line, which names step_count/…/hr_alt, so SQLite threw `no such
    // column: step_count`, the whole exclusive ladder rolled back, and every
    // upgrade from schema <= 18 went down the quarantine-and-rebuild path.
    // Idempotent (ADD COLUMN only when missing), so step 34 stays a no-op.
    await _ensureDecodedOneHzBandFields(db);
    // The rec_ts PK auto-indexes and nothing reads by `counter`, so the rebuilt
    // tables carry no secondary index at all.
  }

  // raw_records — keyed by the band's per-record u32 `counter` (the natural
  // idempotency key; re-draining the same flash region inserts nothing new). Only
  // the 1 Hz historical substrate (0x2F / R24) is persisted here — LIVE high-rate
  // frames are ephemeral (routed to an in-memory sink, never stored). Keying by
  // counter instead of the full hex string roughly HALVES on-disk size.
  static Future<void> _createRaw(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS raw_records (
        counter INTEGER PRIMARY KEY,
        hex TEXT NOT NULL,
        packet_type INTEGER,
        captured_at INTEGER NOT NULL,
        rec_ts INTEGER NOT NULL DEFAULT 0,
        uploaded INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_raw_unuploaded ON raw_records(uploaded, captured_at) WHERE uploaded = 0',
    );
    // rec_ts is the bucketing/window key for the DerivationEngine.
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_raw_rects ON raw_records(rec_ts)',
    );
  }

  /// Add the additive `rec_ts` column to an EXISTING raw_records table (upgrade
  /// path only). NOT NULL with a DEFAULT 0 so legacy rows are well-formed until
  /// the backfill rewrites them.
  /// GUARDED (see [_addColumnIfMissing]): the step-3 rebuild already creates
  /// raw_records from the CURRENT `_createRaw` DDL, which carries rec_ts — so on
  /// an oldV <= 2 upgrade this column is already there.
  static Future<void> _addRecTsColumn(Database db) => _addColumnIfMissing(
    db,
    'raw_records',
    'rec_ts',
    'INTEGER NOT NULL DEFAULT 0',
  );

  /// Backfill `rec_ts` for every existing raw row by decoding its hex once. Runs
  /// inside the migration on a populated DB. Falls back to captured_at/1000 when a
  /// frame is undecodable or yields a non-positive ts — rec_ts is never left at 0.
  static Future<void> _backfillRecTs(Database db) async {
    final rows = await db.query(
      'raw_records',
      columns: ['hex', 'captured_at'],
      where: 'rec_ts = 0 OR rec_ts IS NULL',
    );
    if (rows.isEmpty) return;
    final batch = db.batch();
    for (final r in rows) {
      final hex = r['hex'] as String;
      final capturedSec = ((r['captured_at'] as int?) ?? 0) ~/ 1000;
      final ts = decodeRecTs(hex, fallbackSec: capturedSec);
      batch.update(
        'raw_records',
        {'rec_ts': ts},
        where: 'hex = ?',
        whereArgs: [hex],
      );
    }
    await batch.commit(noResult: true);
  }

  /// Decode a frame's REAL record timestamp (epoch seconds) from its inner hex.
  /// Cheap (reads the ts field only via the protocol decoders). Returns
  /// [fallbackSec] when undecodable or the decoded ts is non-positive — so callers
  /// never store a 0/negative rec_ts. Used at insert and during the v6 backfill.
  static int decodeRecTs(String hex, {required int fallbackSec}) {
    // decodeRecord reads the same ts field realtimeRr would for 0x28 and R10,
    // plus every historical layout, so it is the one timing path.
    try {
      final s = proto.decodeRecord(hex);
      if (s != null && s.ts > 0) return s.ts;
    } catch (_) {
      /* fall through */
    }
    return fallbackSec;
  }

  static Future<void> _writeCaptureFreshness(List<RawRecord> raws) async {
    if (raws.isEmpty) return;
    var latest = 0;
    for (final raw in raws) {
      final recTs = _recTsFor(raw);
      if (recTs > latest) latest = recTs;
    }
    if (latest <= 0) return;
    final prev = await ComputeFreshnessStore.read('capture');
    Map<String, dynamic> payload = const {};
    final rawJson = prev?['payload_json'];
    if (rawJson is String && rawJson.isNotEmpty) {
      try {
        final d = jsonDecode(rawJson);
        if (d is Map) payload = d.cast<String, dynamic>();
      } catch (_) {
        payload = const {};
      }
    }
    payload = {
      ...payload,
      'latest_raw_rec_ts': latest,
      'latest_raw_day': _localDayLabelFromEpoch(latest),
    };
    await ComputeFreshnessStore.put('capture', jsonEncode(payload));
  }

  // Canonical LOCAL day label — shared with the UI/coach via day_label.dart so
  // every layer computes "today" identically (never in UTC).
  static String _localDayLabel(DateTime dt) =>
      dayLabelAtSec(dt.millisecondsSinceEpoch ~/ 1000);

  static String _localDayLabelFromEpoch(int epochSec) =>
      _localDayLabel(DateTime.fromMillisecondsSinceEpoch(epochSec * 1000));

  /// Gen4 historical R10-lite (hr-only, no accel/optical) must stay out of
  /// `decoded_onehz` — they belong in the legacy `samples` table only.
  ///
  /// Matched on the hex prefix rather than decoded bytes: this runs once per
  /// record inside the offload transaction, and parsing 240 hex chars to read
  /// two of them costs ~13 ms per 50k records plus a Uint8List of garbage each.
  static final _gen4R10LitePrefix =
      '${proto.PacketType.historicalData.toRadixString(16).padLeft(2, '0')}'
      '${proto.Record.r10.toRadixString(16).padLeft(2, '0')}';
  static bool _isGen4R10LiteHistorical(String hex) =>
      hex.length >= 4 &&
      hex.substring(0, 4).toLowerCase() == _gen4R10LitePrefix;

  static Sample? _decodeOneHzSample(RawRecord raw, {Sample? preferred}) {
    // Reject Gen4 R10-lite even when a complete preferred Sample is supplied.
    // Invalid/placeholder hex (test fixtures, corrupt imports) must NOT abort
    // before the preferred paths — commit 1f85b10 returned null on hexToBytes
    // failure and zeroed decoded_onehz for every insertRecord that used non-hex
    // placeholders. The bytes are now parsed lazily, below, for that reason too.
    if (_isGen4R10LiteHistorical(raw.hex)) return null;
    if (preferred != null && preferred.hasDecodedOneHz) return preferred;
    // The band's OWN decode outranks the other generation's decoder. A gen5 v18
    // has no gen4 optics so hasDecodedOneHz is false, and feeding it to the v24
    // map is not harmless: HR sits at byte 14 in both layouts and gravity is
    // exactly one byte off, so whenever an axis lands in |g| ∈ [0.746, 0.75)
    // the misread collapses into a believable vector instead of failing the
    // plausibility gate — about 0.6% of records, ~550 rows a day. Those rows
    // keep the right hr and ts (so they look fine) while carrying a fabricated
    // gravity vector, fabricated optics, and none of the gen5 RR beats.
    if (preferred != null && preferred.tsEpoch > 0) return preferred;
    Uint8List? bytes;
    try {
      bytes = proto.hexToBytes(raw.hex);
    } catch (_) {}
    if (bytes != null) {
      // GEN5 FIRST — and only on a full gen5 decode. This whole fallback used
      // to be gen4-only, so any gen5 frame arriving without a pre-decoded
      // sample (a raw replay, an archive re-drive, a raw-hex import) was fed
      // to the R24 map, which is precisely the misread the comment above
      // describes: same HR byte, gravity one byte off, a believable-looking
      // fabricated vector.
      //
      // Order is safe in this direction and not the other:
      // `parseGen5Historical` dispatches off the record version and returns
      // null for anything it does not recognise, so a gen4 R24/R12 frame
      // (version 24/12) falls straight through to the chain below.
      try {
        final g = proto.parseGen5Historical(bytes);
        // Only the per-second v18 record maps onto a 1 Hz Sample; the deep
        // buffers (v20/v21/v26) are correctly identified and deliberately not
        // storable here — same contract as the live drain's mapper in
        // ble_engine.dart, which this duplicates because lib/data must not
        // depend on lib/ble.
        if (g is proto.Gen5HistorySample && g.unix > 0) {
          return Sample(
            tsEpoch: g.unix,
            counter: g.recordIndex,
            hr: g.heartRate,
            rrIntervalsMs: List<int>.from(g.rrIntervalsMs),
            ax: g.gravityG.isNotEmpty ? g.gravityG[0] : null,
            ay: g.gravityG.length > 1 ? g.gravityG[1] : null,
            az: g.gravityG.length > 2 ? g.gravityG[2] : null,
            stepCount: g.stepMotionCounter,
            stepCadence: g.stepCadence,
            activityClass: g.activityClassKnown,
            // Same honesty contract as the live mapper: the -50.00 °C code is
            // the sensor's unavailable sentinel, and body-60 bits 0-1 / body-15
            // bit7 are disproven as wear / HR-validity (see
            // sampleFromGen5Historical) — a replay must not resurrect them.
            skinTempC: g.skinTempCOrNull,
            hrAlt: g.heartRateAlt,
            // MT-12's three columns exist (v43) and the write below names
            // them. Carried here because they are free and the point of
            // storing them is to make it possible to find out later whether
            // they mean anything — see Sample.tempCh2C for why they are not
            // named after a body part.
            tempCh2C: g.tempAux1C,
            tempCh3C: g.tempAux2C,
            signalQualityLogVar: g.signalQualityLogVariance,
            dynAccelG: g.dynamicAccelerationG,
            tsSubsec: g.tsSubsec,
            bandSleepState: g.sleepStateRawNibble,
          );
        }
      } catch (_) {}
      try {
        // Legacy decoder first, firmware-fallback chain second — see
        // FirmwareAwareR24Decoder. This path only runs when no pre-decoded
        // `preferred` sample was supplied (e.g. a raw-hex import/merge), so a
        // fresh per-call instance is fine — no session state to preserve.
        final r = proto.FirmwareAwareR24Decoder().decode(bytes);
        // v25 NEVER BECOMES A SECOND, on any path into this table.
        //
        // The live drain already excludes it (see `_ingestHistoricalFrame`),
        // but this seam is the one every OTHER path shares — the mid-ladder
        // `_backfillDecodedStore` replay of `raw_records`, `insertRecord` with
        // no pre-decoded sample, a raw-hex import, `redriveArchivedRecords` —
        // and `FirmwareAwareR24Decoder` routes v25 straight to `_parseV25`,
        // which returns a gravity vector that ISN'T ONE: measured across all
        // 28,395 v25 records in `whoop-4.db`, its "z" takes three distinct
        // values, its "y" seventeen, its "x" is the high half of an f32, and
        // the median angle to the real v24 gravity at the SAME second is 83°.
        // A near-constant vector reads downstream as a perfectly still wrist,
        // which is the one thing the nullable accel columns exist to prevent.
        //
        // Banking it would also REPLACE (rec_ts is the PK) the v24 row for
        // that second on 49% of records, deleting real HR and R-R. Refused at
        // the seam so no future caller can reintroduce it by accident. The
        // bytes stay in `raw_archive`, whole and unpruned.
        if (r != null && r.histVersion == 25) return null;
        if (r != null && r.tsEpoch > 0) {
          return Sample(
            tsEpoch: r.tsEpoch,
            counter: r.counter,
            hr: r.hr,
            rrIntervalsMs: List<int>.from(r.rrIntervalsMs),
            // ABSENT ACCEL STAYS ABSENT. These used to coalesce to 0, which is
            // a reading — a perfectly still wrist — and it is the same
            // fabricated stillness the nullable columns and the v25 refusal
            // above exist to prevent. protocol now returns an empty `accelG`
            // for a record whose accelerometer it will not vouch for, so the
            // fallback is null, exactly as the gen5 `gravityG` path above does.
            ax: r.accelG.isNotEmpty ? r.accelG[0] : null,
            ay: r.accelG.length > 1 ? r.accelG[1] : null,
            az: r.accelG.length > 2 ? r.accelG[2] : null,
            spo2RedRaw: r.spo2RedRaw,
            spo2IrRaw: r.spo2IrRaw,
            // raw column passthrough, same as the ble path. not read as a temp.
            // ignore: deprecated_member_use
            skinTempRaw: r.skinTempRaw,
            // gen4 ambient-light ADC. 0 (unconfirmed optical block) is turned
            // into NULL at the write, not here — see _queueDecodedOneHz.
            ambientRaw: r.ambientRaw,
            tsSubsec: r.tsSubsec,
          );
        }
      } catch (_) {}
    }
    return null;
  }

  /// Queues the decoded_onehz + decoded_rr writes for one raw onto [batch].
  /// Returns the number of batch operations added, so a caller committing a
  /// large offload can chunk the batch to bound the native argument-list size
  /// (see [SyncLedgerStore.commitBatch]).
  static int _queueDecodedOneHz(
    Batch batch,
    RawRecord raw,
    Sample? sample, {
    String? deviceFamily,
    String deviceId = kPrimaryDeviceId,
    // TRUE ONLY FROM A MID-LADDER REPLAY, and it is not a style choice. This
    // map is also written by `_backfillDecodedStore` (rungs oldV<11 / oldV<20)
    // and `redriveArchivedRecords` (rung oldV<44), both of which run BEFORE the
    // v47 rung hands `device_id` / `ts_ms` back — and naming a column that does
    // not exist yet throws inside onUpgrade's one exclusive transaction and
    // quarantines the whole database. Their rows are re-keyed by
    // [_rekeyTableByDevice] a few rungs later, from `rec_ts`, which is the same
    // value this path would have written.
    //
    // The default is FALSE and the key columns are named, deliberately: the
    // opposite default would let a forgotten argument write every row at
    // ('', 0), where REPLACE collapses the entire store to ONE row.
    bool preDeviceKey = false,
  }) {
    final decoded = _decodeOneHzSample(raw, preferred: sample);
    if (decoded == null) {
      // Gen4 R10-lite has no accel/optical, so it stays out of decoded_onehz —
      // but it DOES carry an R-R block (protocol 539a97b), and dropping it here
      // is permanent, not degraded: the record commits as decoded, so it is
      // never archived, and the band is then acked to trim it. Persist the
      // beats on their own. `samples` cannot hold them — it is (counter, ts, hr).
      if (sample != null &&
          sample.rrIntervalsMs.isNotEmpty &&
          _isGen4R10LiteHistorical(raw.hex)) {
        return _queueRrBeats(
          batch,
          _recTsFrom(raw, sample),
          sample,
          deviceFamily: deviceFamily,
          deviceId: deviceId,
          preDeviceKey: preDeviceKey,
        );
      }
      return 0;
    }
    final recTs = _recTsFrom(raw, decoded);
    final ambient = decoded.ambientRaw;
    // TIME-KEYED, NEWEST-WINS (noop/WHOOP-4 model: dedupe records by their
    // embedded timestamp, not by the volatile counter). decoded_onehz is keyed
    // by rec_ts and decoded_rr by (rec_ts, beat_index). We use REPLACE, not
    // IGNORE: a freshly-offloaded record for a given second should win over a
    // stale one. Because rec_ts is the key, the strap's per-reboot counter reset
    // can no longer make one second's record evict another's (the pre-fix
    // counter-PK eviction that silently, unrecoverably deleted 1 Hz rows).
    batch.insert('decoded_onehz', {
      // v47: WHICH DEVICE, in front of the key. '' is the primary band and
      // nothing else may ever use it — see _createDecodedStore for why an
      // unstable BLE remoteId must never reach this column.
      'device_id': ?(preDeviceKey ? null : deviceId),
      // `rec_ts * 1000` EXACTLY, never `+ tsSubsec`. The key has to stay as
      // unique as `rec_ts` was or the newest-wins dedupe splits into one row
      // per sub-second and every count in the app changes. The millisecond
      // resolution is headroom for a faster-than-1-Hz source, not a place to
      // put this record's own sub-second (which already has `ts_subsec`).
      'ts_ms': ?(preDeviceKey ? null : recTs * 1000),
      'rec_ts': recTs,
      'counter': raw.counter,
      // v43: ABSENCE IS NULL HERE TOO. `hr == 0` is the off-skin sentinel, so
      // writing a 0 for a record that simply has no heart-rate field asserts
      // the band was off the wrist. Every reader gates `hr > 0` (SQL) or maps
      // NULL to the same 0 (Dart), so this changes no number — it stops the
      // ledger from claiming something the record never said, and it is what
      // lets an accel-only record (gen4 v25) be banked at all. See
      // _createDecodedStore.
      'hr': decoded.hr > 0 ? decoded.hr : null,
      // NO `?? 0` on ANY of these (schema v39 made the sensor columns
      // nullable): a null must land in the DB as NULL. Zeroing invented a real
      // 0 g gravity vector, a real ADC count of 0, a 0-step second and a 0 °C
      // skin temperature for every record that simply did not carry the field.
      'ax': decoded.ax,
      'ay': decoded.ay,
      'az': decoded.az,
      'spo2_red_raw': decoded.spo2RedRaw,
      'spo2_ir_raw': decoded.spo2IrRaw,
      'skin_temp_raw': decoded.skinTempRaw,
      'step_count': decoded.stepCount,
      'step_cadence': decoded.stepCadence,
      'activity_class': decoded.activityClass,
      'skin_temp_c': decoded.skinTempC,
      'on_wrist': decoded.onWrist,
      'hr_valid': decoded.hrValid == null ? null : (decoded.hrValid! ? 1 : 0),
      'hr_alt': decoded.hrAlt,
      // MT-12 — gen5's second/third temperature channels and its own
      // signal-quality figure. Stored, unnamed, unread. See Sample.tempCh2C.
      'temp_ch2_c': decoded.tempCh2C,
      'temp_ch3_c': decoded.tempCh3C,
      'signal_quality_logvar': decoded.signalQualityLogVar,
      // OMITTED when null, unlike the three above: this column is newer than
      // the mid-ladder `_backfillDecodedStore`, which writes through this map
      // on the oldV<11 / oldV<20 rungs — before any step has handed the column
      // back. Naming a column that does not exist yet throws inside
      // onUpgrade's single transaction and quarantines the database. Only a
      // gen5 record carries a value, and no gen5 record is in a pre-v11
      // `raw_records`, so omitting-when-null loses nothing.
      'dyn_accel_g': ?decoded.dynAccelG,
      // The record's own sub-second. Omitted-when-null for the same
      // mid-ladder-backfill reason as `dyn_accel_g` directly above.
      'ts_subsec': ?decoded.tsSubsec,
      // The band's own wake/sleep envelope. gen5/MG only, so it is null on
      // everything the mid-ladder backfill can replay — but omitted-when-null
      // regardless, for the same reason.
      'band_sleep_state': ?decoded.bandSleepState,
      // Unconfirmed layouts now emit NULL; confirmed raw zero stays zero.
      // Omit NULL for mid-ladder backfills before this column exists.
      'ambient_raw': ?ambient,
      // Which strap measured this second. Stamped from the live link; unknown
      // provenance is NULL, never a guess. See _ensureDeviceFamilyColumns.
      //
      // OMITTED when null rather than written as null — same stored value (the
      // column has no DEFAULT), but this map is also used by the MID-LADDER
      // `_backfillDecodedStore`, which runs before the v41 rung adds the
      // column. Naming a column that does not exist yet throws inside
      // onUpgrade's single transaction and quarantines the whole database.
      'device_family': ?deviceFamily,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return 1 /* the decoded_onehz insert */ +
        _queueRrBeats(
          batch,
          recTs,
          decoded,
          deviceFamily: deviceFamily,
          deviceId: deviceId,
          preDeviceKey: preDeviceKey,
        );
  }

  /// `rec_ts` for one raw+decoded pair.
  ///
  /// `??` substitutes on NULL only, and `rec_ts` is the primary key now. The
  /// legacy `raw_records.rec_ts` column is `NOT NULL DEFAULT 0`, so every
  /// undated row [_backfillDecodedStore] replays arrives here as an explicit
  /// 0 — which under the old counter PK coexisted harmlessly and under this
  /// one REPLACE-evicts all the others down to a single row. Same `> 0`
  /// fallback [_recTsFor] uses (the decoded sample already carries the
  /// timestamp, so going through it would re-decode the hex for nothing).
  static int _recTsFrom(RawRecord raw, Sample decoded) {
    final rawRecTs = raw.recTs;
    return (rawRecTs != null && rawRecTs > 0) ? rawRecTs : decoded.tsEpoch;
  }

  /// Replaces this second's RR beats. Returns the ops queued.
  ///
  /// Clear the second before reinserting so a SHRINKING beat count can't strand
  /// stale high-index beats — parent and child share the rec_ts key, so this
  /// single DELETE replaces the old counter-based orphan guard.
  static int _queueRrBeats(
    Batch batch,
    int recTs,
    Sample decoded, {
    String? deviceFamily,
    String deviceId = kPrimaryDeviceId,
    bool preDeviceKey = false,
  }) {
    // SCOPED TO THE WRITING DEVICE (v47). Unscoped, this cleared every device's
    // beats for the second — so a second band writing one row deleted the
    // first band's R-R for that second, permanently (raw prunes at 3 days).
    // Same key prefix as the parent row, so the PK serves the delete.
    if (preDeviceKey) {
      batch.rawDelete('DELETE FROM decoded_rr WHERE rec_ts = ?', [recTs]);
    } else {
      batch.rawDelete(
        'DELETE FROM decoded_rr WHERE device_id = ? AND ts_ms = ?',
        [deviceId, recTs * 1000],
      );
    }
    final beatTs = beatTimesMs(recTs, decoded.tsSubsec, decoded.rrIntervalsMs);
    var ops = 1;
    for (var i = 0; i < decoded.rrIntervalsMs.length; i++) {
      final rr = decoded.rrIntervalsMs[i];
      if (rr <= 0) continue;
      batch.insert('decoded_rr', {
        // Same key prefix as the parent row — see _createDecodedStore. Omitted
        // on the mid-ladder replay for the reason _queueDecodedOneHz gives.
        'device_id': ?(preDeviceKey ? null : deviceId),
        'ts_ms': ?(preDeviceKey ? null : recTs * 1000),
        'rec_ts': recTs,
        'beat_index': i,
        // UNCHANGED, DELIBERATELY. `rr_ts_ms` stays `rec_ts * 1000` and
        // `beat_ts_ms` lands beside it instead of replacing it, for one
        // concrete reason: the sub-second is NOT RECOVERABLE for a row already
        // on disk. Nothing stores it, and the raw frames it could be re-read
        // from are pruned at the retention edge — so redefining this column
        // would leave two different quantities living in it with nothing able
        // to tell them apart. A nullable column beside it says the true thing:
        // NULL is "we did not keep the sub-second for this beat", which is
        // exactly the case for every row written before today.
        //
        // The compute layer (substrate.dart, derive_prepare.dart) now prefers
        // `beat_ts_ms` and falls back to this column, so `rr_ts_ms` stays the
        // honest answer for every row that has no sub-second — which is every
        // row written before the column existed.
        'rr_ts_ms': recTs * 1000,
        'rr_ms': rr,
        // Omitted when null — see _queueDecodedOneHz. Also newer than the
        // mid-ladder backfill, same trap.
        'beat_ts_ms': ?beatTs[i],
        'device_family': ?deviceFamily,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      ops++;
    }
    return ops;
  }

  static Future<void> _backfillDecodedStore(Database db) async {
    // MUST run before the first insert. This backfill writes through
    // `_queueDecodedOneHz`, which since v43 writes NULL for a record with no
    // heart rate — and it is called from the oldV<11 and oldV<20 rungs, where
    // `decoded_onehz.hr` is still `NOT NULL`. An off-skin record (hr = 0, which
    // is ordinary, not rare) would then fail the constraint, throw inside
    // `onUpgrade`, roll the WHOLE ladder back and quarantine the database — the
    // standing trap this file is full of guards against. Self-skipping (one
    // PRAGMA) once the column is already nullable.
    await _relaxDecodedHrNull(db);
    // SAME REASON, THE OTHER DIRECTION: these two columns are NEWER than this
    // backfill, and unlike `ambient_raw` / `dyn_accel_g` (which are null on
    // everything a pre-v11 `raw_records` can hold, so the omit-when-null form
    // never names them) the sub-second is present on every real gen4 record
    // being replayed here. Naming a column the ladder has not handed back yet
    // throws inside onUpgrade's single transaction and quarantines the whole
    // database. Both are ADD COLUMN, idempotent, and no-ops on a missing table.
    await _addColumnIfMissing(db, 'decoded_onehz', 'ts_subsec', 'INTEGER');
    await _ensureBeatTimeColumn(db);
    // raw_records is retired after this replay. Preserve undecodable bytes in
    // the existing archive first, keyed by content so rebooted counters cannot
    // evict distinct evidence. This may run before the archive's v32 rung.
    await _rekeyRawArchiveByHex(db);
    const pageSize = 1000;
    int afterCounter = -1;
    while (true) {
      final rows = await db.query(
        'raw_records',
        columns: ['counter', 'hex', 'packet_type', 'captured_at', 'rec_ts'],
        where: 'counter > ? AND packet_type = ?',
        whereArgs: [afterCounter, 47],
        orderBy: 'counter ASC',
        limit: pageSize,
      );
      if (rows.isEmpty) return;
      final batch = db.batch();
      for (final row in rows) {
        final raw = RawRecord(
          counter: (row['counter'] as num?)?.toInt() ?? 0,
          packetType: (row['packet_type'] as num?)?.toInt() ?? 0,
          hex: row['hex'] as String,
          capturedAt: (row['captured_at'] as num?)?.toInt() ?? 0,
          recTs: (row['rec_ts'] as num?)?.toInt(),
        );
        // MID-LADDER: `device_id` / `ts_ms` do not exist yet (v47 rung). See
        // _queueDecodedOneHz's `preDeviceKey`.
        if (_queueDecodedOneHz(batch, raw, null, preDeviceKey: true) == 0) {
          batch.insert('raw_archive', {
            'hex': raw.hex,
            'counter': raw.counter,
            'packet_type': raw.packetType,
            'rec_ts': raw.recTs,
            'captured_at': raw.capturedAt,
            'reason': 'legacy_undecodable',
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      }
      await batch.commit(noResult: true);
      afterCounter = (rows.last['counter'] as num?)?.toInt() ?? afterCounter;
      if (rows.length < pageSize) return;
    }
  }

  // Events (wrist on/off, charging, battery, double-tap, …) — live OR from sync.
  // Keyed by the full frame hex so re-delivered identical events dedupe. Retained
  // until uploaded, then deleted (same guarantee as raw_records).
  static Future<void> _createEvents(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS events (
        hex TEXT PRIMARY KEY,
        event_id INTEGER,
        ts INTEGER,
        captured_at INTEGER NOT NULL
      )
    ''');
    // The PK is the frame hex, so a `ts` window (the timeline's day query, and
    // the retention prune) was a full table scan. Cheap to build — `events` is
    // pruned to the retention window.
    await db.execute('CREATE INDEX IF NOT EXISTS idx_events_ts ON events(ts)');
  }

  // band_events / band_battery — structured local history for device-state
  // signals that were previously only ephemeral or raw-only. Additive beside
  // the upload-queue `events` table.
  static Future<void> _createBandSignals(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS band_events (
        hex TEXT PRIMARY KEY,
        event_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        ts INTEGER NOT NULL,
        payload_json TEXT NOT NULL DEFAULT '{}',
        captured_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_band_events_ts ON band_events(ts, event_id)',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS band_battery (
        ts INTEGER NOT NULL,
        battery_pct REAL,
        charging INTEGER,
        wrist_on INTEGER,
        millivolts INTEGER,
        charge_units INTEGER,
        source TEXT NOT NULL,
        PRIMARY KEY (ts, source)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_band_battery_ts ON band_battery(ts DESC)',
    );
    await _createBandBacklog(db);
  }

  /// band_backlog — the strap's own ring-buffer bookkeeping, one row per
  /// connect. `pages_behind` is fully parsed by the protocol
  /// (`control.dart:652`) and arrives on a response edge already reads; until
  /// now it had zero readers anywhere in the app and was decoded and dropped.
  ///
  /// DEVICE STATE, NOT PHYSIOLOGY. It can claim exactly what it says: how much
  /// the band is still holding, and whether its ring has wrapped. That is the
  /// one distinction the app currently cannot draw — a STALLED offload versus
  /// an idle one — and `wrap_count` moving between two connects is a hard fact
  /// that data was overwritten before we ever saw it.
  ///
  /// NOT PRUNED, for the band_battery reason: a 3-day cap on a series whose
  /// only use is comparing today's reading to the last one destroys it. Six
  /// narrow columns per connect is not a storage problem.
  ///
  /// `device_family` rides along because a page and a record mean different
  /// things on different straps — `free_records` on gen4 and on gen5 must never
  /// be put on the same axis or divided by the same records-per-day.
  ///
  /// `batchId` is deliberately NOT stored: it is a ring wrap count, not a
  /// unique batch id, so nothing here may be used to dedupe a batch.
  static Future<void> _createBandBacklog(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS band_backlog (
        ts INTEGER PRIMARY KEY,
        written INTEGER,
        used INTEGER,
        capacity INTEGER,
        trim_page INTEGER,
        wrap_count INTEGER,
        free_records INTEGER,
        device_family TEXT
      )
    ''');
  }

  /// Record one connect's `pages_behind` reading. [ts] is epoch SECONDS.
  ///
  /// LOGGING ONLY for now, by instruction: no copy, no notification, no
  /// headroom estimate. `free_records / records-per-day` is the headroom in
  /// days and `wrap_count` moving means a loss already happened, but the
  /// records-per-day divisor is per-device and has to be established from real
  /// logged data before any number goes in front of a user. This is what
  /// establishes it.
  static Future<void> putBandBacklog({
    required int ts,
    int? written,
    int? used,
    int? capacity,
    int? trimPage,
    int? wrapCount,
    int? freeRecords,
    String? deviceFamily,
  }) async {
    final db = await instance;
    await db.insert('band_backlog', {
      'ts': ts,
      'written': written,
      'used': used,
      'capacity': capacity,
      'trim_page': trimPage,
      'wrap_count': wrapCount,
      'free_records': freeRecords,
      // Unknown provenance stays NULL — never defaulted to gen4.
      'device_family': deviceFamily,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// The most recent [limit] backlog readings, newest first.
  static Future<List<Map<String, dynamic>>> bandBacklog({
    int limit = 60,
  }) async {
    final db = await instance;
    return db.query('band_backlog', orderBy: 'ts DESC', limit: limit);
  }

  /// Additive: add the `millivolts` column to an existing band_battery table.
  /// Guarded — the column already exists on fresh installs (see _createBandSignals)
  /// and ALTER … ADD COLUMN throws if it's already there.
  static Future<void> _ensureBandBatteryMillivolts(Database db) =>
      _addColumnIfMissing(db, 'band_battery', 'millivolts', 'INTEGER');

  /// Additive: the strap's own charge counter. Same guard, same reason as
  /// [_ensureBandBatteryMillivolts]. See [extendedChargeUnits] for what it is
  /// and — more importantly — what it is not.
  static Future<void> _ensureBandBatteryChargeUnits(Database db) =>
      _addColumnIfMissing(db, 'band_battery', 'charge_units', 'INTEGER');

  /// Replay stored band events into `band_battery`.
  ///
  /// The point of running this at all: the writer added alongside it only fills
  /// the series from here forward, and `batteryHealth` reports a full-charge
  /// voltage and a charge count that only mean anything ACROSS the life of the
  /// pack. Everything needed to fill the past is already on disk — `band_events`
  /// keeps the whole frame — so an existing install gets its history rather than
  /// starting the series at this upgrade.
  ///
  /// BOUNDED, because this runs inside `openDatabase` under iOS's CPU watchdog
  /// (invariant 11): the two ids together are ~2,400 rows over 9 days on the
  /// largest real export, and non-charge/wear band events are pruned at the
  /// retention edge anyway, so the cap is a backstop and not the normal case.
  /// INSERT OR IGNORE, so it can never overwrite a row the live writer already
  /// wrote.
  static Future<void> _backfillBandBatteryFromEvents(
    DatabaseExecutor db,
  ) async {
    // A DB whose ladder has not created these yet (or is mid-ladder) must
    // NO-OP rather than throw. `redriveArchivedRecords` guards the same way and
    // for the same reason: a throw in here rolls the WHOLE upgrade back and
    // quarantines the database.
    for (final t in const ['band_events', 'band_battery']) {
      final present = await db.rawQuery(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",
        [t],
      );
      if (present.isEmpty) return;
    }
    const cap = 20000;
    final rows = await db.query(
      'band_events',
      columns: ['hex'],
      where: 'event_id IN (?, ?)',
      whereArgs: [proto.EventId.batteryLevel, kExtendedBatteryInfoEventId],
      orderBy: 'ts DESC',
      limit: cap,
    );
    if (rows.isEmpty) return;
    final batch = db.batch();
    var queued = 0;
    for (final r in rows) {
      final hex = r['hex'] as String?;
      if (hex == null) continue;
      Map<String, Object?>? row;
      try {
        final e = proto.parseEvent(proto.hexToBytes(hex));
        row = e == null ? null : batteryRowFromEvent(e);
      } catch (_) {
        // A frame this build cannot parse is one battery row we do not get.
        // It must never take the upgrade down with it.
        continue;
      }
      if (row == null) continue;
      batch.insert(
        'band_battery',
        row,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      queued++;
    }
    if (queued > 0) await batch.commit(noResult: true);
  }

  /// Durable archive for historical records we received but could not decode
  /// (unknown/unsupported version). Thinned to a stated SAMPLE RATE behind the
  /// retention edge and otherwise kept forever — the point is that a future
  /// firmware's records survive until we understand the format, and a sample is
  /// what a decode needs. See [thinRawArchiveBefore] for the numbers. Keyed by
  /// frame `hex` (content identity), like `events`/`band_events` — NOT by
  /// `counter`. The strap resets its record counter to ~0 on every reboot, so
  /// two DISTINCT undecodable frames from different boots can collide on a
  /// reused counter; a `counter`-PK + IGNORE silently DROPPED the second, in
  /// the one table whose whole purpose is to never lose a frame. Hashing on the
  /// bytes means an identical re-flood (missed-ACK redelivery) still dedups,
  /// while genuinely distinct frames both survive a counter collision. `counter`
  /// is retained as a plain forensic column.
  static Future<void> _createRawArchive(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS raw_archive (
        hex TEXT PRIMARY KEY,
        counter INTEGER,
        packet_type INTEGER NOT NULL,
        rec_ts INTEGER,
        captured_at INTEGER NOT NULL,
        reason TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_raw_archive_captured '
      'ON raw_archive(captured_at DESC)',
    );
  }

  /// The v32 archive migration also precedes ancient raw-record replay: a
  /// counter-keyed archive would otherwise drop a distinct unknown frame.
  /// Both callers run in the existing upgrade transaction. Already-current
  /// archives retain their rows and need no rename on the later ladder rung.
  static Future<void> _rekeyRawArchiveByHex(Database db) async {
    final info = await db.rawQuery('PRAGMA table_info(raw_archive)');
    final primary = info.where((row) => (row['pk'] as num) > 0).toList();
    if (info.isEmpty ||
        (primary.length == 1 && primary.single['name'] == 'hex')) {
      await _createRawArchive(db);
      return;
    }
    await db.execute('ALTER TABLE raw_archive RENAME TO _raw_archive_old');
    await db.execute('DROP INDEX IF EXISTS idx_raw_archive_captured');
    await _createRawArchive(db);
    await db.execute(
      'INSERT OR IGNORE INTO raw_archive '
      '(hex, counter, packet_type, rec_ts, captured_at, reason) '
      'SELECT hex, counter, packet_type, rec_ts, captured_at, reason '
      'FROM _raw_archive_old',
    );
    await db.execute('DROP TABLE _raw_archive_old');
  }

  static Future<void> insertEvent(int eventId, int ts, String hex) async {
    final capturedAt = DateTime.now().millisecondsSinceEpoch;
    // Parse BEFORE acquiring the handle so both inserts run back-to-back on one
    // validated `db` with no intervening await — minimizing the closed-DB race
    // window. Best-effort: a background teardown that closes the DB mid-write
    // must not crash the app (the band re-sends events).
    final parsed = () {
      try {
        return proto.parseEvent(proto.hexToBytes(hex));
      } catch (_) {
        return null;
      }
    }();
    final battery = parsed == null ? null : batteryRowFromEvent(parsed);
    await _guardedWrite((db) async {
      await db.insert('events', {
        'hex': hex,
        'event_id': eventId,
        'ts': ts,
        'captured_at': capturedAt,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      await db.insert('band_events', {
        'hex': hex,
        'event_id': eventId,
        'name': parsed?.name ?? proto.EventId.name(eventId),
        'ts': parsed?.tsEpoch ?? ts,
        'payload_json': jsonEncode(
          parsed?.decoded ?? const <String, dynamic>{},
        ),
        'captured_at': capturedAt,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      if (battery != null) {
        await db.insert(
          'band_battery',
          battery,
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    }, bestEffort: true);
  }

  /// The `band_battery` row an incoming band event carries, or null when it
  /// carries none.
  ///
  /// WHY THIS EXISTS. `band_battery.millivolts` has had a column, a reader
  /// ([batteryHealth]) and a rendered widget since it was added, and NO WRITER:
  /// the only insert was AppState's `DeviceState` tick, which has no voltage.
  /// It was 0-filled on all four real exports (0 of 433 / 413 / 626 / 171 rows),
  /// so the device screen's charge-history line has been blank on every install
  /// there has ever been. The number was on the wire the whole time — the band
  /// sends BATTERY_LEVEL every few minutes and the protocol already decodes
  /// `battery_mv` out of it; nothing carried it the last four inches into the
  /// series table. This is that write, on the funnel every event already goes
  /// through (live AND headless — see AppState._onLiveEvent and
  /// background_sync).
  ///
  /// Two events land here, under two SOURCES rather than one merged row: they
  /// arrive 1:1 at the same strap second, and `band_battery` is keyed
  /// `(ts, source)`, so one source would make each overwrite the other's
  /// columns. Split, each row states only what its own event said.
  ///
  ///  * BATTERY_LEVEL — `battery_pct` / `millivolts` / `charging`, all three
  ///    already decoded by the protocol. Source `band_event`.
  ///  * EXTENDED_BATTERY_INFORMATION — [extendedChargeUnits]. Source
  ///    `band_event_ext`.
  ///
  /// ON THE `charging` FLAG. It rides on the BATTERY_LEVEL row (the event's own
  /// byte), NOT on a chargingOn/chargingOff transition, and the strap can
  /// replay these out of its flash backlog hours late — which is exactly why
  /// [batteryHealth] counts charge edges PER SOURCE and takes the max rather
  /// than walking one interleaved series.
  @visibleForTesting
  static Map<String, Object?>? batteryRowFromEvent(proto.EventInfo e) {
    if (e.tsEpoch <= 0) return null;
    if (e.eventId == proto.EventId.batteryLevel) {
      final pct = e.decoded['battery_pct'];
      final mv = e.decoded['battery_mv'];
      final charging = e.decoded['charging'];
      if (pct == null && mv == null) return null;
      return {
        'ts': e.tsEpoch,
        'battery_pct': pct is num ? pct.toDouble() : null,
        'charging': charging is bool ? (charging ? 1 : 0) : null,
        'wrist_on': null,
        'millivolts': mv is num ? mv.toInt() : null,
        'charge_units': null,
        'source': 'band_event',
      };
    }
    if (e.eventId == kExtendedBatteryInfoEventId) {
      final units = extendedChargeUnits(e.body);
      if (units == null) return null;
      return {
        'ts': e.tsEpoch,
        'battery_pct': null,
        'charging': null,
        'wrist_on': null,
        'millivolts': null,
        'charge_units': units,
        'source': 'band_event_ext',
      };
    }
    return null;
  }

  /// EXTENDED_BATTERY_INFORMATION. Named here rather than taken from
  /// `proto.EventId` because the sealed protocol has no constant for it.
  static const int kExtendedBatteryInfoEventId = 63;

  /// The strap's own charge counter out of an EXTENDED_BATTERY_INFORMATION
  /// body, or null when the body is not one this reads.
  ///
  /// WHAT THE EVIDENCE IS. The event arrives paired 1:1 with BATTERY_LEVEL and
  /// its body was dropped whole (`payload_json = '{}'` on 3,372 stored rows
  /// across the four real exports). Decoding the stored bodies and joining each
  /// to the BATTERY_LEVEL it arrived beside:
  ///
  ///   rev 3 (gen5/MG, 12-byte body), u16 LE @ [9]:
  ///     r = +1.0000 against `battery_pct` over 263 pairs (whoop-mg) and 85
  ///     (whoop-5); range 977-1915 against 50.9-99.7 %, i.e. 977/1915 = 0.5100
  ///     against 0.5106 — the same quantity at ~19x the resolution of the
  ///     deci-percent.
  ///   rev 1 (gen4, 28-byte body), u16 LE @ [11]:
  ///     r = +0.9992 against `battery_pct` over 273 pairs; range 790-1750.
  ///     (That body ALSO carries the millivolts at [5], r = +1.0000 against
  ///     BATTERY_LEVEL's own `battery_mv`. Not read here — it is the same
  ///     number from the same second, and one source for it is enough.)
  ///
  /// WHAT IS NOT CLAIMED. THE UNIT IS UNPINNED. It is linear in state of
  /// charge and that is the whole claim — it is not mAh, not coulombs, not a
  /// capacity, and it must never be rendered with a unit or compared against a
  /// cell spec. What a ratio of two of them supports (this reading over the
  /// full-charge reading) is a fraction, which needs no unit; anything else
  /// needs a unit nobody has established. The two signed words at [1] and [3]
  /// are negative while discharging and look like instantaneous and averaged
  /// current — deliberately NOT decoded, for the same reason: a current in
  /// unknown units is a number that invites "mA" and cannot support it.
  @visibleForTesting
  static int? extendedChargeUnits(Uint8List body) {
    if (body.isEmpty) return null;
    // Offset is per BODY REVISION, never per length: a future revision that
    // happens to be 12 or 28 bytes long would otherwise be read at an offset
    // that was only ever verified for this one.
    final at = switch (body[0]) {
      3 => 9, // gen5 / MG
      1 => 11, // gen4
      _ => null,
    };
    if (at == null || body.length < at + 2) return null;
    final units = body[at] | (body[at + 1] << 8);
    // 0 is the absent/uninitialised read, not a flat pack — a strap reporting a
    // real battery level in the same second has not measured zero charge.
    return units > 0 ? units : null;
  }

  static Future<void> insertBandBatterySample({
    required int ts,
    double? batteryPct,
    bool? charging,
    bool? wristOn,
    int? millivolts,
    required String source,
  }) async {
    // Best-effort background ingest — same closed-DB teardown race as
    // insertEvent; never crash over a battery row (it re-arrives on the poll).
    await _guardedWrite((db) async {
      await db.insert('band_battery', {
        'ts': ts,
        'battery_pct': batteryPct,
        'charging': charging == null ? null : (charging ? 1 : 0),
        'wrist_on': wristOn == null ? null : (wristOn ? 1 : 0),
        'millivolts': millivolts,
        'source': source,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }, bestEffort: true);
  }

  /// Recent battery samples (newest first), for the battery-health series.
  static Future<List<Map<String, dynamic>>> recentBandBatterySamples({
    int limit = 500,
  }) async {
    final db = await instance;
    return db.query('band_battery', orderBy: 'ts DESC', limit: limit);
  }

  /// A simple, honest battery-health readout derived from the stored series.
  ///   - `full_charge_mv`: the highest millivolts ever seen while charging (a
  ///     pack's full-charge voltage sags over its life);
  ///   - `charge_cycles`: how many times the band has been put on the charger
  ///     (a coarse proxy — a top-up is not a cycle);
  ///   - `latest_pct` / `latest_mv`: the most recent sample.
  /// All fields are nullable (absent input → null, never fabricated).
  ///
  /// BOTH LIFETIME FACTS COME OUT OF SQL, NOT A ROW WINDOW. They only mean
  /// anything across the life of the pack, and the row window they used to be
  /// computed over was a `LIMIT` on a table that now takes a row every few
  /// minutes rather than every few state changes — the same window that used to
  /// span a month would span days, quietly shrinking "the highest ever seen"
  /// into "the highest this week".
  ///
  /// `charge_cycles` counts CHARGING_ON events rather than rising edges in this
  /// series, which is both cheaper and truer: the events are one of the four ids
  /// `band_events` keeps forever, so the count is lifetime; and an edge walk
  /// over a SAMPLED series misses any charge that began and ended between two
  /// samples, while double-counting one that two sources disagree about at the
  /// boundary — a real hazard now that the strap's own (replayable, possibly
  /// hours-late) battery events land in the same table as the live device tick.
  static Future<Map<String, dynamic>> batteryHealth({
    int lookback = 2000,
  }) async {
    final db = await instance;
    final rows = await recentBandBatterySamples(limit: lookback);
    final fullCharge = await db.rawQuery(
      'SELECT MAX(millivolts) AS mv FROM band_battery WHERE charging = 1',
    );
    final cycleRows = await db.rawQuery(
      'SELECT COUNT(*) AS n FROM band_events WHERE event_id = ?',
      [proto.EventId.chargingOn],
    );
    final fullChargeMv = (fullCharge.first['mv'] as num?)?.toInt();
    final cycles = (cycleRows.first['n'] as num?)?.toInt() ?? 0;
    // The most recent reading of each — NOT of the newest row. The sources
    // write different columns (the device tick has no voltage, the strap's
    // extended event has no percentage), so the newest row is routinely missing
    // one of the two and reading it alone reported "no voltage" on a series
    // that had one a few seconds earlier.
    T? newest<T>(String column, T? Function(Object?) read) {
      for (final r in rows) {
        final v = read(r[column]);
        if (v != null) return v;
      }
      return null;
    }

    return {
      'samples': rows.length,
      'full_charge_mv': fullChargeMv,
      'charge_cycles': cycles,
      'latest_pct': newest('battery_pct', (v) => (v as num?)?.toDouble()),
      'latest_mv': newest('millivolts', (v) => (v as num?)?.toInt()),
    };
  }

  /// Persist an undecodable historical record to the durable archive (never
  /// pruned). Used by the immediate fallback path; the drain path archives inside
  /// the same commit transaction as the batch (see [SyncLedgerStore.commitBatch]).
  static Future<void> archiveRawRecord(ArchiveRecord a) async {
    final db = await instance;
    await db.insert('raw_archive', {
      'counter': a.counter,
      'hex': a.hex,
      'packet_type': a.packetType,
      'rec_ts': a.recTs,
      'captured_at': a.capturedAt,
      'reason': a.reason,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  /// The `raw_archive.reason` values [redriveArchivedRecords] will retry.
  ///
  /// A reason names the RECORD VERSION a build could not decode, and only the
  /// per-second records map onto 1 Hz rows at all: gen5's v20/v21/v26 and
  /// gen4's v25 are deep buffers this build IDENTIFIES correctly and
  /// deliberately does not store as seconds (see `_ingestHistoricalFrame`), so
  /// retrying them re-reads half a gigabyte of hex to re-learn the same answer.
  /// MEASURED on the real MG export: `undecodable_rec_v20` alone is 115,672
  /// rows and 492 MB. A future format that becomes re-drivable gets a line
  /// here, by name.
  static const List<String> redrivableArchiveReasons = [
    // gen5's per-second summary. 1,035 of these sit in the MG export, archived
    // before this month's decoder fixes under a gravity window that was gen4's
    // — 0.5-1.8 g on a NORMALISED vector, applied to gen5's raw per-axis means.
    // All 1,035 decode today, gravity included.
    'undecodable_rec_v18',
    // The same records under a reason string an older build wrote and nothing
    // writes any more. Both labels are stale, which is the whole point.
    'partial_decode_v18_no_gravity',
    // gen4's R24, for symmetry — a record the R24 chain rejected once may
    // decode under a later firmware fallback. Zero rows carry it on any of the
    // three real exports; it costs nothing to include and is the case this
    // would otherwise have to be rewritten for.
    'undecodable_rec_v24',
  ];

  /// GATES 4b — replay the archive through the CURRENT decoders, into
  /// `decoded_onehz` / `decoded_rr`. Returns the seconds recovered.
  ///
  /// `raw_archive` holds frames a BUILD could not turn into a [Sample]. That is
  /// a statement about the build, not about the bytes — and nothing ever went
  /// back to re-read them, so the archive silently became a graveyard rather
  /// than the recovery store it was created to be. On the real MG export that
  /// is 1,035 seconds of gen5 history the app already owns, carrying HR, R-R,
  /// steps, sleep state and a skin temperature populated on 1,035 of 1,035.
  ///
  /// Run ONCE, from the migration ladder: off the ACK-critical sync path, and
  /// never on the launch path of a DB that has already had it.
  ///
  /// THREE THINGS IT DOES NOT DO:
  ///
  ///  * It does not touch a second `decoded_onehz` already holds.
  ///    [_queueDecodedOneHz] writes REPLACE (newest-wins, for a re-offload of a
  ///    live second) and a replay is the opposite case: a frame that FAILED to
  ///    decode must never evict one that succeeded. Collisions are skipped.
  ///  * It does not stamp `device_family`. A replay has no live link to ask,
  ///    and the record version does not answer it either — v18 exists on BOTH
  ///    generations (gen4 lists v7/v9/v18 as unconfirmed field maps). NULL is
  ///    the documented value for exactly this case, and the metrics that need
  ///    the family will correctly refuse rather than assume gen4.
  ///  * It does not delete, thin or relabel the archived row. The bytes stay
  ///    exactly where they are, under the reason they were captured with.
  static Future<int> redriveArchivedRecords(Database db) async {
    // Both are cheap and both are required: a DB whose ladder has not created
    // the archive yet (or is mid-ladder) must no-op rather than throw — a throw
    // in here rolls the WHOLE upgrade back and quarantines the database.
    for (final t in const ['raw_archive', 'decoded_onehz']) {
      final present = await db.rawQuery(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",
        [t],
      );
      if (present.isEmpty) return 0;
    }
    // SELF-DETECTING, because this runs from BOTH sides of the v47 rung: from
    // the oldV<44 ladder step, where `decoded_onehz` is still keyed by rec_ts
    // alone and naming `device_id` would throw inside onUpgrade (quarantining
    // the database), and from the app/tests on a re-keyed table. One PRAGMA.
    final preDeviceKey = !(await _columnsOf(
      db,
      'decoded_onehz',
    )).contains('device_id');

    final marks = List.filled(redrivableArchiveReasons.length, '?').join(',');
    // Paged on `hex`, which is the table's PRIMARY KEY — a stable, total order
    // that needs no extra index and no offset scan.
    var afterHex = '';
    var recovered = 0;
    while (true) {
      final rows = await db.rawQuery(
        'SELECT hex, counter, packet_type, rec_ts, captured_at '
        'FROM raw_archive WHERE reason IN ($marks) AND hex > ? '
        'ORDER BY hex ASC LIMIT 500',
        [...redrivableArchiveReasons, afterHex],
      );
      if (rows.isEmpty) return recovered;
      afterHex = rows.last['hex'] as String;

      // Decode first, keyed by the second each record claims. Two archived
      // frames for the same second collapse here rather than fighting over the
      // primary key inside the batch.
      final byRecTs = <int, (RawRecord, Sample)>{};
      for (final r in rows) {
        final raw = RawRecord(
          counter: (r['counter'] as num?)?.toInt() ?? 0,
          packetType: (r['packet_type'] as num?)?.toInt() ?? 0,
          hex: r['hex'] as String,
          capturedAt: (r['captured_at'] as num?)?.toInt() ?? 0,
          recTs: (r['rec_ts'] as num?)?.toInt(),
        );
        final s = _decodeOneHzSample(raw);
        // Still undecodable under today's decoders. Left in the archive,
        // untouched, for the build that can read it.
        if (s == null) continue;
        final recTs = _recTsFrom(raw, s);
        // `rec_ts` is NULL on every archived row on all three real exports (we
        // archive a frame precisely because we never learned its time), so this
        // is the decoded timestamp — and a record with no plausible time has
        // nowhere to land in a table keyed by one.
        if (recTs <= 0) continue;
        byRecTs[recTs] = (raw, s);
      }
      if (byRecTs.isEmpty) continue;

      final keys = byRecTs.keys.toList();
      final taken = <int>{};
      for (var i = 0; i < keys.length; i += 400) {
        final end = i + 400 < keys.length ? i + 400 : keys.length;
        final slice = keys.sublist(i, end);
        for (final e in await db.rawQuery(
          'SELECT rec_ts FROM decoded_onehz WHERE rec_ts IN '
          '(${List.filled(slice.length, '?').join(',')})',
          slice,
        )) {
          taken.add((e['rec_ts'] as num).toInt());
        }
      }

      final batch = db.batch();
      var queued = 0;
      for (final e in byRecTs.entries) {
        if (taken.contains(e.key)) continue;
        final (raw, sample) = e.value;
        // `sample` is handed back as `preferred` so the hex is decoded once,
        // not twice; `_queueDecodedOneHz` returns it straight back out.
        // `deviceFamily` is deliberately omitted — see the doc comment.
        if (_queueDecodedOneHz(batch, raw, sample, preDeviceKey: preDeviceKey) >
            0) {
          queued++;
          recovered++;
        }
      }
      if (queued > 0) await batch.commit(noResult: true);
    }
  }

  /// One in this many `undecodable_rec_v20` frames is kept behind the retention
  /// edge. A STATED RATE, not a byte budget, so what survives is auditable: a
  /// future decode gets 1 record a minute of whatever the band was banking,
  /// which is a sample, not a recording.
  ///
  /// Sampled on `counter`, which resets to ~0 on a band reboot — that makes the
  /// sample slightly uneven across reboots and does not matter at all; what it
  /// buys is a rule you can re-run and get the same rows back.
  static const int rawArchiveKeepEvery = 60;

  /// The one `reason` this thinning applies to, and the reason it exists.
  ///
  /// MEASURED on the real MG export: `undecodable_rec_v20` is 115,672 rows of
  /// 4,256-char hex = 492 MB of the 538 MB `raw_archive` holds, banked in 11
  /// days. That is ~45 MB/day, ~16 GB/year, and `auto_backup.dart` gzips the
  /// whole database on a schedule. Nothing else in the table is close: v26 is
  /// 25,804 rows for 3.9 MB and gen4's v25 is 28,395 rows for 4.3 MB — both
  /// 152-char frames, and v25 is a channel we have since identified, so
  /// thinning either would cost real evidence and save nothing. One `reason`,
  /// one WHERE clause. A future format that turns out to be this big gets its
  /// own line here, by name — the diagnostics already break the table down by
  /// reason, so it shows up before it hurts.
  static const String _thinnedArchiveReason = 'undecodable_rec_v20';

  /// Thin the undecodable archive: drop all but 1-in-[rawArchiveKeepEvery]
  /// `undecodable_rec_v20` frames captured before [beforeMs]. Returns the rows
  /// deleted.
  ///
  /// Gated on `captured_at` and NOT `rec_ts`: `rec_ts` is NULL for every row in
  /// this table on all three real exports (142,511 of 142,511), which is not an
  /// accident — we archive a frame precisely BECAUSE we could not decode it, so
  /// we never learned its record time. When we received it is the only time we
  /// have.
  ///
  /// Called only from [StorageRetentionStore.pruneDecodedBefore], so full-rate
  /// frames live exactly as long as the 1 Hz substrate they arrived with, and
  /// the sample lives forever.
  static Future<int> thinRawArchiveBefore(int beforeMs) async {
    final db = await instance;
    return db.transaction((txn) => _thinRawArchiveVia(txn, beforeMs));
  }

  static Future<int> _thinRawArchiveVia(
    DatabaseExecutor txn,
    int beforeMs,
  ) async {
    return txn.delete(
      'raw_archive',
      // `counter` is NOT NULL in practice but the column is nullable, and
      // `NULL % 60` is NULL — so a counter-less row would never match and would
      // be kept. Keeping an unsampleable frame is the safe direction.
      where: 'reason = ? AND captured_at < ? AND counter % ? != 0',
      whereArgs: [_thinnedArchiveReason, beforeMs, rawArchiveKeepEvery],
    );
  }

  /// Events whose `ts` (epoch SECONDS) is in the half-open window
  /// `[fromTs, toTs)`, oldest first. Bounded BY THE WINDOW, not by an unrelated
  /// global page, so a day's markers can never be crowded out by older rows.
  /// [limit] is a defensive cap on a pathological window only.
  static Future<List<Map<String, dynamic>>> eventsInRange(
    int fromTs,
    int toTs, {
    int limit = 5000,
  }) async {
    final db = await instance;
    return db.query(
      'events',
      where: 'ts >= ? AND ts < ?',
      whereArgs: [fromTs, toTs],
      orderBy: 'ts ASC',
      limit: limit,
    );
  }

  /// Store a raw record (+ optional decoded sample). Idempotent on frame hex.
  /// Raw is written FIRST (raw-first invariant). Returns true if newly inserted.
  /// LIVE packets pass sample=null — the backend field-decodes them from raw.
  /// Resolve the rec_ts (epoch sec) to store: reuse the already-decoded value from
  /// [raw] (ble_engine sets it from the record it parsed) to avoid a double-decode,
  /// else decode the hex here, else fall back to captured_at/1000.
  /// The timestamp allowed to advance the `rec_ts_hw` "newest band data"
  /// frontier (B88-05): the record's OWN time only — never the phone-capture
  /// fallback [_recTsFor] uses for an untimed record — and never more than
  /// 10 minutes in the future. The frontier is monotone, so one plausible-but-
  /// wrong stamp used to pin "Band data: just now" and silence staleness.
  static int? _frontierTsFor(RawRecord raw) {
    final own = (raw.recTs != null && raw.recTs! > 0)
        ? raw.recTs!
        : decodeRecTs(raw.hex, fallbackSec: 0);
    if (own <= 0) return null;
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return own > nowSec + 600 ? null : own;
  }

  /// Recorded 1 Hz seconds in [startSec, endSec), or null when that span is
  /// older than the retained decoded window (B88-04 correction guard).
  static Future<int?> recordedSecondsBetween(int startSec, int endSec) async {
    final db = await instance;
    final oldest = Sqflite.firstIntValue(
      await db.rawQuery('SELECT MIN(ts_ms) FROM decoded_onehz'),
    );
    if (oldest == null || oldest > startSec * 1000) return null;
    return Sqflite.firstIntValue(
      await db.rawQuery(
        'SELECT COUNT(*) FROM decoded_onehz WHERE ts_ms >= ? AND ts_ms < ?',
        [startSec * 1000, endSec * 1000],
      ),
    );
  }

  static int _recTsFor(RawRecord raw) {
    if (raw.recTs != null && raw.recTs! > 0) return raw.recTs!;
    return decodeRecTs(raw.hex, fallbackSec: raw.capturedAt ~/ 1000);
  }

  static Future<bool> insertRecord(RawRecord raw, Sample? sample) async {
    final db = await instance;
    var inserted = false;
    await db.transaction((txn) async {
      final batch = txn.batch();
      _queueDecodedOneHz(batch, raw, sample);
      await batch.commit(noResult: true);
      inserted = true;
    });
    return inserted;
  }

  /// Insert many records in ONE transaction. During a historical drain this is
  /// far faster than a transaction-per-record (one fsync instead of thousands).
  /// `samples` is now purely an ingest carrier for decoded fields; rows are
  /// persisted into decoded_onehz/decoded_rr, not into the legacy `samples`
  /// table. Raw-first is preserved — callers flush this before ACKing a sync batch.
  static Future<void> insertRecordsBatch(
    List<RawRecord> raws,
    List<Sample?> samples,
  ) async {
    if (raws.isEmpty) return;
    final db = await instance;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (var i = 0; i < raws.length; i++) {
        final raw = raws[i];
        final sample = samples[i];
        _queueDecodedOneHz(batch, raw, sample);
      }
      await batch.commit(noResult: true);
    });
  }

  static Future<Map<String, dynamic>?> syncLedgerEntry([
    String chunkId = 'capture',
  ]) async {
    final db = await instance;
    final rows = await db.query(
      'sync_ledger',
      where: 'chunk_id = ?',
      whereArgs: [chunkId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// Merge a diagnostic/sync snapshot into the durable capture ledger row.
  /// `meta_json` is treated as a shallow object and patched, not replaced.
  static Future<void> upsertSyncLedgerEntry({
    String chunkId = 'capture',
    String kind = 'historical',
    required String status,
    int? ackedAt,
    String? lastError,
    Map<String, dynamic>? metaPatch,
  }) async {
    final db = await instance;
    final existing = await syncLedgerEntry(chunkId);
    final now = DateTime.now().millisecondsSinceEpoch;
    final meta = <String, dynamic>{};
    if (existing != null) {
      final rawMeta = existing['meta_json'];
      if (rawMeta is String && rawMeta.isNotEmpty) {
        try {
          final decoded = jsonDecode(rawMeta);
          if (decoded is Map) {
            meta.addAll(decoded.cast<String, dynamic>());
          }
        } catch (_) {
          /* keep empty */
        }
      }
    }
    if (metaPatch != null) meta.addAll(metaPatch);
    await db.insert('sync_ledger', {
      'chunk_id': chunkId,
      'kind': kind,
      'status': status,
      'created_at': (existing?['created_at'] as num?)?.toInt() ?? now,
      'updated_at': now,
      'acked_at': ackedAt ?? (existing?['acked_at'] as num?)?.toInt(),
      'last_error': lastError,
      'meta_json': jsonEncode(meta),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// B88-12 (C5): stamp the latest background wake ([source] is
  /// `ble_restore`, `bg_task` or `bg_refresh`) for the Status sync-health
  /// panel. One fixed row, replaced; never a history.
  static Future<void> noteBackgroundWake(String source) =>
      upsertSyncLedgerEntry(chunkId: 'wake', kind: 'diag', status: source);

  /// B88-12 (C5): the four sync-health facts, newest first, each with its
  /// epoch-ms time or null: last background wake (and what woke it), last
  /// band transfer (and how it ended), last calculation of today.
  static Future<
    ({
      int? wakeAt,
      String? wakeSource,
      int? transferAt,
      String? transferStatus,
      int? calculatedAt,
    })
  >
  syncHealth() async {
    final wake = await syncLedgerEntry('wake');
    final capture = await syncLedgerEntry('capture');
    int? calculated;
    final today = await ComputeFreshnessStore.read('today');
    final raw = today?['payload_json'];
    if (raw is String) {
      try {
        final m = jsonDecode(raw);
        if (m is Map) {
          final a = (m['activity_computed_at'] as num?)?.toInt();
          final o = (m['overnight_computed_at'] as num?)?.toInt();
          calculated = [
            ?a,
            ?o,
          ].fold<int?>(null, (x, y) => x == null || y > x ? y : x);
        }
      } catch (_) {}
    }
    return (
      wakeAt: (wake?['updated_at'] as num?)?.toInt(),
      wakeSource: wake?['status'] as String?,
      transferAt: (capture?['updated_at'] as num?)?.toInt(),
      transferStatus: capture?['status'] as String?,
      calculatedAt: calculated,
    );
  }

  static Future<void> quarantineSyncChunk({
    required String kind,
    required String payloadJson,
    required String reason,
  }) async {
    final db = await instance;
    await db.insert('sync_quarantine', {
      'kind': kind,
      'payload_json': payloadJson,
      'reason': reason,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Columns [Sample.fromDecodedRow] reads. Deliberately NOT `*`: the accel /
  /// spo2 / raw-skin-temp columns are bulk and latestSample does not use
  /// them (the derive path has its own wider query).
  static const List<String> _decodedSampleColumns = [
    'counter',
    'rec_ts',
    'hr',
    'step_count',
    'step_cadence',
    'activity_class',
    'skin_temp_c',
    'on_wrist',
    'hr_valid',
    'hr_alt',
  ];

  /// [kPrimaryBandSourceSql]:the app keeps this as `lastSynced`,whose
  /// `tsEpoch` is the fallback frontier behind the `rec_ts_hw` cursor — how
  /// fresh the BAND is. A peripheral sensor's second must not make a band
  /// that has not synced in two days read as current.
  static Future<Sample?> latestSample() async {
    final db = await instance;
    final decodedRows = await db.query(
      'decoded_onehz',
      columns: _decodedSampleColumns,
      where: kPrimaryBandSourceSql,
      orderBy: 'rec_ts DESC, counter DESC',
      limit: 1,
    );
    if (decodedRows.isNotEmpty) {
      return Sample.fromDecodedRow(decodedRows.first);
    }
    final rows = await db.query('samples', orderBy: 'ts DESC', limit: 1);
    return rows.isEmpty ? null : Sample.fromDbMap(rows.first);
  }

  static Future<Map<String, int>> counts() async {
    final db = await instance;
    final oneHz =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM decoded_onehz'),
        ) ??
        0;
    final rr =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM decoded_rr'),
        ) ??
        0;
    return {
      'raw': oneHz,
      'pending': 0,
      'decoded_onehz': oneHz,
      'decoded_rr': rr,
    };
  }

  /// `(firstRecTs, lastRecTs)` in unix seconds over canonical decoded 1 Hz rows,
  /// or `(null, null)` when nothing has been decoded yet.
  ///
  /// Its ONE production caller is [decodedRecTsMaxByDay], which uses it purely
  /// as the span to walk — so this is an ADMISSION read ([derivableSourceSql]),
  /// not a band-edge one. Band-only here would clip a verified second source's
  /// days out of derivation entirely, before any of them reached the day walk.
  /// (The old doc comment claimed the onboarding progress bar; that call site
  /// is gone.)
  static Future<(int?, int?)> firstAndLastRecordTs() async {
    final db = await instance;
    final rows = await db.rawQuery(
      // rec_ts > 0, matching DiagnosticsStore.rawStats()/lastDecodedRecTs() —
      // a stray rec_ts=0 row (e.g. via _queueDecodedOneHz's `raw.recTs ??
      // decoded.tsEpoch`, which only substitutes on null, not on an explicit 0)
      // would otherwise make MIN(rec_ts) return 0 and render "Data from Jan 1"
      // (1970 epoch).
      'SELECT MIN(rec_ts) AS lo, MAX(rec_ts) AS hi FROM decoded_onehz '
      'WHERE rec_ts > 0 AND ${derivableSourceSql()}',
    );
    if (rows.isEmpty) return (null, null);
    final lo = (rows.first['lo'] as num?)?.toInt();
    final hi = (rows.first['hi'] as num?)?.toInt();
    return (lo, hi);
  }

  /// `{localDayLabel -> MAX(rec_ts)}` over canonical decoded 1 Hz rows, grouped
  /// by the LOCAL calendar day of the record's real time.
  ///
  /// One bounded `MAX(rec_ts)` per local day in the retained span, NOT one
  /// `GROUP BY strftime(…, 'localtime')` over the whole table. That grouping key
  /// is a function of the column, so SQLite could use no index for it: it was a
  /// full scan of every retained second plus a temp b-tree — 91 ms on a 3-day
  /// (259 k row) table on desktop, and the derive calls this up to three times
  /// a pass. `rec_ts` is the INTEGER PRIMARY KEY (the rowid), so a bounded
  /// `MAX(rec_ts) WHERE rec_ts >= a AND rec_ts < b` is a single index seek, and
  /// the span is bounded by `rawRetentionDays` in any healthy install.
  ///
  /// The day walk goes through [localDayEndSec] rather than `+ 86400` for the
  /// reason that helper documents: a local calendar day is 23 h on a
  /// spring-forward and 25 h on a fall-back, and the old `strftime('localtime')`
  /// grouping got that right, so the replacement has to as well.
  static Future<Map<String, int>> decodedRecTsMaxByDay() async {
    final (lo, hi) = await firstAndLastRecordTs();
    if (lo == null || hi == null) return {};
    await DayZoneStore.ensureRange(lo, hi);
    final db = await instance;
    final out = <String, int>{};
    var day = dayLabelAtSec(lo);
    // Bounded by the number of days actually present. `localDayEndSec` returns
    // null only for a malformed label, which `dayLabelOf` cannot produce — the
    // guard is there so a future change can never spin here.
    for (var guard = 0; guard < 4000; guard++) {
      final end = localDayEndSec(day);
      if (end == null) break;
      final rows = await db.rawQuery(
        'SELECT MAX(rec_ts) AS mx FROM decoded_onehz '
        'WHERE rec_ts > 0 AND ${derivableSourceSql()} '
        'AND rec_ts >= ? AND rec_ts < ?',
        [localDayStartSec(day) ?? 0, end],
      );
      final mx = rows.isEmpty ? null : (rows.first['mx'] as num?)?.toInt();
      if (mx != null) out[day] = mx;
      if (end > hi) break;
      day = dayLabelAtSec(end);
    }
    return out;
  }

  /// Decoded 1 Hz frames in record-time order. This is the preferred derive
  /// read path: smaller than raw hex, directly queryable, and already split into
  /// canonical columns.
  static Future<List<Map<String, dynamic>>> decodedOneHzBatchByRecTsRange({
    required int limit,
    required int fromRecTs,
    required int toRecTs,
    int? afterRecTs,
    int? afterCounter,
  }) async {
    final db = await instance;
    if (afterRecTs == null || afterCounter == null) {
      return db.rawQuery(
        'SELECT counter, rec_ts, hr, ax, ay, az, '
        'spo2_red_raw, spo2_ir_raw, skin_temp_raw, '
        'step_count, step_cadence, activity_class, skin_temp_c, '
        'on_wrist, hr_valid, hr_alt, device_family '
        'FROM decoded_onehz '
        'WHERE rec_ts >= ? AND rec_ts <= ? AND ${derivableSourceSql()} '
        'ORDER BY rec_ts ASC, counter ASC LIMIT ?',
        [fromRecTs, toRecTs, limit],
      );
    }
    return db.rawQuery(
      'SELECT counter, rec_ts, hr, ax, ay, az, '
      'spo2_red_raw, spo2_ir_raw, skin_temp_raw, '
      'step_count, step_cadence, activity_class, skin_temp_c, '
      'on_wrist, hr_valid, hr_alt, device_family '
      'FROM decoded_onehz '
      'WHERE rec_ts >= ? AND rec_ts <= ? AND ${derivableSourceSql()} '
      'AND (rec_ts > ? OR (rec_ts = ? AND counter > ?)) '
      'ORDER BY rec_ts ASC, counter ASC LIMIT ?',
      [fromRecTs, toRecTs, afterRecTs, afterRecTs, afterCounter, limit],
    );
  }

  /// Sparse RR beats for one contiguous decoded 1 Hz page, by its rec_ts window.
  ///
  /// [fromRecTs] / [toRecTs] are the page's first and last record seconds (the
  /// page is ordered `rec_ts ASC`, so first = min, last = max). decoded_rr shares
  /// the rec_ts key with decoded_onehz, so `[fromRecTs, toRecTs]` on the PK
  /// contains exactly the page's beats — bounded, indexed, and immune to the
  /// strap's reboot counter reset (the old counter-span read could degenerate to
  /// `counter >= high AND counter <= low` = zero rows, silently dropping a whole
  /// page's RR).
  static Future<List<Map<String, dynamic>>> decodedRrByRecTsRange({
    required int fromRecTs,
    required int toRecTs,
  }) async {
    final db = await instance;
    final lo = fromRecTs <= toRecTs ? fromRecTs : toRecTs;
    final hi = fromRecTs <= toRecTs ? toRecTs : fromRecTs;
    return db.rawQuery(
      // `beat_ts_ms` is the MEASURED beat instant (`beatTimesMs`); `rr_ts_ms` is
      // `rec_ts * 1000`, a whole-second staircase that says every beat inside
      // one record happened at the same millisecond. Both are returned because
      // `beat_ts_ms` is NULL on every row banked before the column existed and
      // on every source that carries no sub-second — the reader coalesces.
      'SELECT rec_ts, beat_index, rr_ts_ms, rr_ms, beat_ts_ms FROM decoded_rr '
      'WHERE rec_ts >= ? AND rec_ts <= ? AND ${derivableSourceSql()} '
      'ORDER BY rec_ts ASC, beat_index ASC',
      [lo, hi],
    );
  }

  /// Write a consistent, compacted snapshot of the DB to a temp file for export.
  /// Uses `VACUUM INTO` (NOT a raw file copy) so the snapshot is transactionally
  /// consistent — a plain copy of a live SQLite file can produce torn pages
  /// (a corrupt export). VACUUM INTO also defragments, so the file is small.
  static Future<String> exportCopy() async {
    await WorkoutClock.flushWrites();
    final db = await instance;
    final tmp = await getTemporaryDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final dest = p.join(tmp.path, 'whoop_export_$stamp.db');
    final f = File(dest);
    if (await f.exists()) await f.delete(); // VACUUM INTO requires a fresh path
    await db.execute('VACUUM INTO ?', [dest]);
    return dest;
  }

  static Future<List<Map<String, dynamic>>> dataHistoryDays() async {
    final db = await instance;
    final (lo, hi) = await firstAndLastRecordTs();
    if (lo != null && hi != null) await DayZoneStore.ensureRange(lo, hi);
    final rawRows = await db.rawQuery(
      DayClock.days.isNotEmpty
          ? 'SELECT z.date AS day_id, COUNT(*) AS raw_count, '
                'MIN(d.rec_ts) AS min_rec_ts, MAX(d.rec_ts) AS max_rec_ts '
                'FROM day_zone z JOIN decoded_onehz d ON d.rec_ts >= z.start_ts '
                'AND d.rec_ts < z.end_ts WHERE d.rec_ts > 0 AND ${derivableSourceSql('d.source')} '
                'GROUP BY z.date ORDER BY z.date DESC'
          : "SELECT strftime('%Y-%m-%d', rec_ts, 'unixepoch', 'localtime') AS day_id, "
                'COUNT(*) AS raw_count, MIN(rec_ts) AS min_rec_ts, MAX(rec_ts) AS max_rec_ts '
                'FROM decoded_onehz WHERE rec_ts > 0 AND ${derivableSourceSql()} '
                'GROUP BY day_id ORDER BY day_id DESC',
    );
    final derivedRows = await db.rawQuery(
      'SELECT r.day_id, r.algo_version, r.computed_at, r.finalized '
      'FROM day_result r '
      '${DayResultStore._servedDayJoin} '
      'ORDER BY r.day_id DESC',
    );
    final metricRows = await db.rawQuery(
      'SELECT date AS day_id, COUNT(*) AS metric_count '
      'FROM metric_series GROUP BY date',
    );
    final sessionRows = await db.rawQuery(
      "SELECT ${storedDayLabelSql('sessions.start_ts')} AS day_id, "
      'COUNT(*) AS session_count '
      'FROM sessions GROUP BY day_id',
    );
    final byDay = <String, Map<String, dynamic>>{};
    Map<String, dynamic> ensure(String dayId) => byDay.putIfAbsent(
      dayId,
      () => {
        'day_id': dayId,
        'raw_count': 0,
        'min_rec_ts': null,
        'max_rec_ts': null,
        'has_derived': false,
        'algo_version': null,
        'computed_at': null,
        'finalized': 0,
        'metric_count': 0,
        'session_count': 0,
      },
    );
    for (final row in rawRows) {
      final dayId = row['day_id']?.toString();
      if (dayId == null || dayId.isEmpty) continue;
      final m = ensure(dayId);
      m['raw_count'] = (row['raw_count'] as num?)?.toInt() ?? 0;
      m['min_rec_ts'] = (row['min_rec_ts'] as num?)?.toInt();
      m['max_rec_ts'] = (row['max_rec_ts'] as num?)?.toInt();
    }
    for (final row in derivedRows) {
      final dayId = row['day_id']?.toString();
      if (dayId == null || dayId.isEmpty) continue;
      final m = ensure(dayId);
      m['has_derived'] = true;
      m['algo_version'] = (row['algo_version'] as num?)?.toInt();
      m['computed_at'] = (row['computed_at'] as num?)?.toInt();
      m['finalized'] = (row['finalized'] as num?)?.toInt() ?? 0;
    }
    for (final row in metricRows) {
      final dayId = row['day_id']?.toString();
      if (dayId == null || dayId.isEmpty) continue;
      ensure(dayId)['metric_count'] =
          (row['metric_count'] as num?)?.toInt() ?? 0;
    }
    for (final row in sessionRows) {
      final dayId = row['day_id']?.toString();
      if (dayId == null || dayId.isEmpty) continue;
      ensure(dayId)['session_count'] =
          (row['session_count'] as num?)?.toInt() ?? 0;
    }
    final out = byDay.values.toList()
      ..sort(
        (a, b) => (b['day_id'] as String).compareTo(a['day_id'] as String),
      );
    return out;
  }

  /// The half-open LOCAL window `[startSec, endSec)` covering day [dayId].
  ///
  /// `endSec` is the NEXT local midnight, NOT `startSec + 86400`: a local
  /// calendar day is 23 h on spring-forward and 25 h on fall-back. With the
  /// flat +86400 this returned a window that overran into the next day's first
  /// hour (deleteDays silently deleted the following day's first hour of
  /// decoded_onehz / sessions / band_* / events) or fell an hour short
  /// (fall-back left the last hour behind, and the export dropped it). Shared
  /// with the UI/coach via day_label.dart so every layer agrees.
  static (int, int) _localDayWindow(String dayId) {
    final lo = localDayStartSec(dayId);
    final hi = localDayEndSec(dayId);
    if (lo == null || hi == null) {
      throw ArgumentError.value(dayId, 'dayId', 'not a YYYY-MM-DD day label');
    }
    return (lo, hi);
  }

  static Future<String> exportDaysDb(Set<String> dayIds) async {
    final sorted = dayIds.toList()..sort();
    if (sorted.isEmpty) {
      throw ArgumentError('No days selected');
    }
    final src = await instance;
    final tmp = await getTemporaryDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final dest = p.join(tmp.path, 'whoop_days_$stamp.db');
    await deleteDatabase(dest);
    final out = await openDatabase(
      dest,
      // `version:` is MANDATORY here. Without it sqflite throws
      // ArgumentError('onCreate must be null if no version is specified')
      // before opening anything — so this whole export path (Profile → Data
      // history → Export) had never once produced a file.
      version: schemaVersion,
      onCreate: (db, _) async {
        await _createSamples(db);
        await _createDecodedStore(db);
        await db.execute('CREATE INDEX idx_samples_ts ON samples(ts)');
        await _createEvents(db);
        await _createBandSignals(db);
        await _createDerived(db);
        await _createDayResult(db);
        await _createUserTables(db);
        await _createSyncState(db);
        await _createSyncCursor(db);
        await _createComputeState(db);
        await _createPrimitiveArtifacts(db);
        await StepCoverageStore._create(db);
      },
    );

    try {
      // Every source read on the export path is PAGED on rowid. A day-ranged
      // `SELECT *` over `decoded_onehz` is 86,400 rows, and sqflite materialises
      // a whole result set as Java objects before any of it reaches Dart — the
      // same platform-heap exhaustion that OOMed the import path. Keyset, not
      // OFFSET, so paging stays linear.
      const exportPageSize = 2000;
      const rowidKey = '_rowid';

      /// Streams `table` (optionally filtered) into [out] one page at a time,
      /// calling [onPage] with each page after it has been written.
      ///
      /// [onPage] receives rows with the `$rowidKey` cursor column ALREADY
      /// stripped, so a callback can insert what it is handed without tripping
      /// over a column no destination table has. The cursor is read off the raw
      /// page here and never leaves this function.
      ///
      /// PAGING COLUMN: rowid, not the filtered column, so one helper serves
      /// every table regardless of what it is filtered on. That means a filtered
      /// page walks the rowid chain and tests the predicate per row rather than
      /// driving off the `rec_ts`/`ts` index. It stays cheap because both factors
      /// are small: `decoded_onehz` is bounded by `rawRetentionDays` (days, not
      /// years — it is pruned behind the data edge), and the never-pruned tables
      /// paged per day here are hundreds to thousands of rows. Measured on a real
      /// 435k-row ledger the worst case — the exhaustion page that scans to the
      /// end of the table — is ~10 ms. Revisit only if retention grows a lot;
      /// per-table cursors would need a composite `(ts, rowid)` key for the
      /// non-unique columns, which is not worth the complexity today.
      Future<void> copyPaged(
        String table, {
        String? where,
        List<Object?> whereArgs = const [],
        Future<void> Function(List<Map<String, Object?>> page)? onPage,
      }) async {
        var lastRowid = 0;
        while (true) {
          final clause = where == null ? '' : 'AND ($where) ';
          final page = await src.rawQuery(
            'SELECT rowid AS $rowidKey, * FROM $table '
            'WHERE rowid > ? $clause'
            'ORDER BY rowid ASC LIMIT ?',
            [lastRowid, ...whereArgs, exportPageSize],
          );
          if (page.isEmpty) return;
          final clean = [
            for (final row in page)
              <String, Object?>{
                for (final e in row.entries)
                  if (e.key != rowidKey) e.key: e.value,
              },
          ];
          await out.transaction((txn) async {
            final batch = txn.batch();
            for (final row in clean) {
              batch.insert(
                table,
                row,
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
            }
            await batch.commit(noResult: true);
          });
          if (onPage != null) await onPage(clean);
          lastRowid = (page.last[rowidKey] as num).toInt();
          if (page.length < exportPageSize) return;
        }
      }

      Future<void> copyRows(
        String table, {
        String? where,
        List<Object?> whereArgs = const [],
      }) => copyPaged(table, where: where, whereArgs: whereArgs);

      Future<void> copyRawRange(int startSec, int endSec) async {
        // The day's 1 Hz rows stream page by page, and each page's RR beats are
        // pulled and written before the next page is read — so peak residency is
        // one page of `decoded_onehz` plus its beats, not a whole day of both.
        await copyPaged(
          'decoded_onehz',
          where: 'rec_ts >= ? AND rec_ts < ?',
          whereArgs: [startSec, endSec],
          onPage: (page) async {
            final recTsList = <Object?>[
              for (final row in page)
                if (row['rec_ts'] != null) row['rec_ts'],
            ];
            if (recTsList.isEmpty) return;
            // CHUNKED `IN (…)`: even one page's seconds can approach
            // SQLITE_MAX_VARIABLE_NUMBER, and a full day is 86,400 — two orders
            // of magnitude past it, so one giant statement could never bind.
            // Keyed on rec_ts (decoded_rr's key), which pulls exactly this page's
            // beats — a counter `IN` could over-match a reboot-reused counter.
            for (final chunk in _sqlVarChunks(recTsList)) {
              final placeholders = List.filled(chunk.length, '?').join(',');
              final rr = await src.rawQuery(
                'SELECT * FROM decoded_rr WHERE rec_ts IN ($placeholders)',
                chunk,
              );
              if (rr.isEmpty) continue;
              await out.transaction((txn) async {
                final batch = txn.batch();
                for (final row in rr) {
                  batch.insert(
                    'decoded_rr',
                    Map<String, Object?>.from(row),
                    conflictAlgorithm: ConflictAlgorithm.replace,
                  );
                }
                await batch.commit(noResult: true);
              });
            }
          },
        );
        await copyRows(
          'samples',
          where: 'ts >= ? AND ts < ?',
          whereArgs: [startSec, endSec],
        );
        await copyRows(
          'events',
          where: 'ts >= ? AND ts < ?',
          whereArgs: [startSec, endSec],
        );
        await copyRows(
          'band_events',
          where: 'ts >= ? AND ts < ?',
          whereArgs: [startSec, endSec],
        );
        await copyRows(
          'band_battery',
          where: 'ts >= ? AND ts < ?',
          whereArgs: [startSec, endSec],
        );
        await copyRows(
          'sessions',
          where: 'start_ts >= ? AND start_ts < ?',
          whereArgs: [startSec, endSec],
        );
        await copyRows(
          'live_coverage',
          where: 'end_ts > ? AND start_ts < ?',
          whereArgs: [startSec, endSec],
        );
      }

      for (final dayId in sorted) {
        final (startSec, endSec) = _localDayWindow(dayId);
        await copyRawRange(startSec, endSec);
        await copyRows('day_result', where: 'day_id = ?', whereArgs: [dayId]);
        await copyRows('metric_series', where: 'date = ?', whereArgs: [dayId]);
        await copyRows(
          'metric_series_version',
          where: 'date = ?',
          whereArgs: [dayId],
        );
        await copyRows('journal', where: 'date = ?', whereArgs: [dayId]);
        await copyRows('journal_metric', where: 'date = ?', whereArgs: [dayId]);
        await copyRows('cycle_log', where: 'date = ?', whereArgs: [dayId]);
        for (final table in const [
          'body_weight_reading',
          'food_day_count',
          'day_zone',
        ]) {
          await copyRows(table, where: 'date = ?', whereArgs: [dayId]);
        }
        final (zoneStart, zoneEnd) = _localDayWindow(dayId);
        await copyRows(
          'zone_change',
          where:
              'at_ts = (SELECT MAX(at_ts) FROM zone_change WHERE at_ts <= ?) '
              'OR (at_ts > ? AND at_ts < ?)',
          whereArgs: [zoneStart, zoneStart, zoneEnd],
        );
        await copyRows('notifications', where: 'date = ?', whereArgs: [dayId]);
        await copyRows(
          'sleep_session_candidates',
          where: 'day_id = ?',
          whereArgs: [dayId],
        );
        await copyRows(
          'wake_day_features',
          where: 'day_id = ?',
          whereArgs: [dayId],
        );
      }
      // Custom journal field definitions are not day-scoped, so they ride along
      // whole. Without them an exported day carries numbers under keys like
      // `custom_magnesium` with no label, no unit and no idea what scale they
      // are on — the values survive the export and their meaning does not.
      await copyRows('journal_field_def');
      return dest;
    } finally {
      await out.close();
    }
  }

  static Future<int> deleteDays(Set<String> dayIds) async {
    final sorted = dayIds.toList()..sort();
    if (sorted.isEmpty) return 0;
    final db = await instance;
    int deleted = 0;
    Future<void> deleteByIn(
      Transaction txn,
      String table,
      String column,
      List<String> values,
    ) async {
      // Chunked: "select all" on a multi-year history binds one day label per
      // parameter, which would blow SQLITE_MAX_VARIABLE_NUMBER.
      for (final chunk in _sqlVarChunks(values)) {
        final placeholders = List.filled(chunk.length, '?').join(',');
        deleted += await txn.rawDelete(
          'DELETE FROM $table WHERE $column IN ($placeholders)',
          chunk,
        );
      }
    }

    await db.transaction((txn) async {
      for (final dayId in sorted) {
        final (startSec, endSec) = _localDayWindow(dayId);
        deleted += await txn.delete(
          'decoded_rr',
          where: 'rec_ts >= ? AND rec_ts < ?',
          whereArgs: [startSec, endSec],
        );
        deleted += await txn.delete(
          'decoded_onehz',
          where: 'rec_ts >= ? AND rec_ts < ?',
          whereArgs: [startSec, endSec],
        );
        deleted += await txn.delete(
          'samples',
          where: 'ts >= ? AND ts < ?',
          whereArgs: [startSec, endSec],
        );
        deleted += await txn.delete(
          'events',
          where: 'ts >= ? AND ts < ?',
          whereArgs: [startSec, endSec],
        );
        deleted += await txn.delete(
          'band_events',
          where: 'ts >= ? AND ts < ?',
          whereArgs: [startSec, endSec],
        );
        deleted += await txn.delete(
          'band_battery',
          where: 'ts >= ? AND ts < ?',
          whereArgs: [startSec, endSec],
        );
        // CASCADE the GPS route and the typed sets BEFORE their session row
        // disappears — otherwise the join key is gone and every lat/lng point
        // of a deleted run (and every logged set) stays on disk forever. Must
        // run first: once `sessions` is deleted the subquery is empty and the
        // children are unreachable.
        for (final child in const [
          'workout_route',
          'workout_split',
          'session_detail',
          'strength_set',
        ]) {
          deleted += await txn.rawDelete(
            'DELETE FROM $child WHERE session_id IN '
            '(SELECT id FROM sessions WHERE start_ts >= ? AND start_ts < ?)',
            [startSec, endSec],
          );
        }
        deleted += await txn.delete(
          'sessions',
          where: 'start_ts >= ? AND start_ts < ?',
          whereArgs: [startSec, endSec],
        );
        deleted += await txn.delete(
          'live_coverage',
          where: 'end_ts > ? AND start_ts < ?',
          whereArgs: [startSec, endSec],
        );
      }
      await deleteByIn(txn, 'day_result', 'day_id', sorted);
      await deleteByIn(txn, 'metric_series', 'date', sorted);
      await deleteByIn(txn, 'metric_series_version', 'date', sorted);
      await deleteByIn(txn, 'journal', 'date', sorted);
      await deleteByIn(txn, 'journal_metric', 'date', sorted);
      await deleteByIn(txn, 'cycle_log', 'date', sorted);
      await deleteByIn(txn, 'notifications', 'date', sorted);
      await deleteByIn(txn, 'sleep_session_candidates', 'day_id', sorted);
      await deleteByIn(txn, 'wake_day_features', 'day_id', sorted);
      // Day-keyed USER rows. Same class of leak as workout_route: "delete this
      // day" must not leave the user's own logged health data behind.
      await deleteByIn(txn, 'cycle_symptom', 'date', sorted);
      await deleteByIn(txn, 'workout_suggestions', 'date', sorted);
      await deleteByIn(txn, 'sleep_override', 'day_id', sorted);
      await deleteByIn(txn, 'sleep_nap', 'day_id', sorted);
      for (final date in sorted) {
        for (final prefix in [
          'nap_proposals:',
          'nap_dirty:',
          'nap_corrected:',
        ]) {
          await txn.delete(
            'baselines',
            where: 'key = ?',
            whereArgs: ['$prefix$date'],
          );
        }
      }
    });
    return deleted;
  }

  /// Empty EVERY table — the honest reading of "Delete everything".
  ///
  /// Enumerated from `sqlite_master`, never from a hand-written list. The
  /// hand-written list is exactly how the old reset missed about twenty tables
  /// (labs, nutrition, medication, breathing sessions, strength sets, the
  /// rolling baselines) while telling the user it had deleted them: a table
  /// added later has to be REMEMBERED here, and it never is. This way a new
  /// table cannot escape the wipe by being forgotten.
  ///
  /// `sync_cursor` IS cleared, deliberately. It is the band's "you already have
  /// everything up to here" mark, and the band trims its flash as we ACK — so
  /// the history is unrecoverable either way, cursor or no cursor. Keeping it
  /// would only leave a wiped phone silently draining nothing on the next sync,
  /// because every record the band still holds sits behind the frontier. A
  /// reset that leaves the cursor is not a reset.
  ///
  /// The SCHEMA is untouched: no DROP, no re-open, no re-migration (migrations
  /// run inside `openDatabase` on iOS's CPU watchdog — not somewhere to be on
  /// the tail of a destructive user action). Views are `type='view'` and are
  /// not matched; SQLite's and older exports' internal tables are skipped by name.
  static Future<int> wipeAll({Future<void> Function()? afterWipe}) async {
    _restoreResetGeneration++;
    _resetsInFlight++;
    try {
      await WorkoutClock.flushWrites();
      final db = await instance;
      final rows = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name NOT LIKE 'sqlite_%' AND name != 'android_metadata'",
      );
      return await CalculationStore.resetWith(() async {
        var deleted = 0;
        await db.transaction((txn) async {
          for (final r in rows) {
            final t = r['name'];
            if (t is String) deleted += await txn.delete(t);
          }
        });
        DayClock.install([], []);
        return deleted;
      }, afterWipe: afterWipe);
    } finally {
      _resetsInFlight--;
    }
  }

  /// Every table this database owns, for callers that need to reason about the
  /// whole store rather than one part of it (the reset test, [wipeAll]).
  static Future<List<String>> tableNames() async {
    final db = await instance;
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' "
      "AND name NOT LIKE 'sqlite_%' AND name != 'android_metadata' "
      'ORDER BY name',
    );
    return [for (final r in rows) r['name'] as String];
  }

  static String localDayLabelNow() => todayLabel();

  // ── cycle log I/O ─────────────────────────────────────────────────────────────

  /// All cycle markers, oldest first.
  static Future<List<Map<String, dynamic>>> cycleLogs() async {
    final db = await instance;
    return db.query('cycle_log', orderBy: 'date ASC');
  }

  // NOTE: the in-app notifications feed (putNotification/notifications/
  // markNotificationsRead/unreadCount, + the `notifications` table) was
  // removed — OS-level notifications (NotificationCenter.emit's
  // NotificationService.presentEvent path) are the only surface now. The
  // `notifications` table itself is left in the schema (unused, harmless)
  // rather than risk a DROP TABLE migration for no real benefit.

  /// The DATA EDGE — the timestamp (epoch seconds) of the last canonical 1 Hz
  /// record we've durably stored.
  static Future<int?> lastDecodedRecTs() async {
    final db = await instance;
    return Sqflite.firstIntValue(
      await db.rawQuery(
        // [kPrimaryBandSourceSql], NOT [derivableSourceSql]: the data edge is
        // the BAND's edge. A peripheral sensor's second is not evidence the
        // strap synced, and letting it move this would tell the sync engine it
        // made progress it did not make.
        //
        // ponytail: the derive engine reads this as "now, in data time" (its
        // finalization anchor, and `dataNowSec <= 0` short-circuits the whole
        // pass), which is a DIFFERENT question — an install with a verified
        // strap and no band would derive nothing. The upgrade is a sibling
        // `lastAdmittedRecTs()` on [derivableSourceSql] for the derive callers,
        // added when a second admitted source actually exists; splitting it now
        // would be two names for one query.
        'SELECT MAX(rec_ts) FROM decoded_onehz '
        'WHERE rec_ts > 0 AND $kPrimaryBandSourceSql',
      ),
    );
  }
}

/// One batch of curve re-encodes: for each input bundle, the compacted
/// replacement, or null when the row must be left exactly as it is.
///
/// TOP-LEVEL and pure so it can be handed to `Isolate.run` — it touches nothing
/// but `SeriesCodec`, which has no I/O, no plugins and no Flutter. The null
/// cases are all "leave it legacy": already encoded, not provably lossless
/// (see `verifyLossless` — this OVERWRITES durable user data, and a day past
/// `rawRetentionDays` has no substrate left to re-derive from), or an encode
/// that did not actually shrink the row.
List<String?> _reencodeBatch(List<String> payloads) {
  final out = <String?>[];
  for (final pj in payloads) {
    if (pj.isEmpty ||
        !SeriesCodec.needsReencode(pj) ||
        !SeriesCodec.verifyLossless(pj)) {
      out.add(null);
      continue;
    }
    final encoded = SeriesCodec.encodePayloadJson(pj);
    out.add(encoded.length < pj.length ? encoded : null);
  }
  return out;
}

/// The medication tables (schemaVersion 36). The reminders and checklist
/// that wrote them are gone; the tables stay so a stored history and a
/// backup restore keep their shape.
Future<void> _createMedTables(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS med_def (
      key           TEXT PRIMARY KEY,
      label         TEXT NOT NULL,
      dose_value    REAL,
      dose_unit     TEXT NOT NULL DEFAULT '',
      kind          TEXT NOT NULL DEFAULT 'medication',
      schedule_json TEXT NOT NULL DEFAULT '[]',
      active        INTEGER NOT NULL DEFAULT 1,
      note          TEXT NOT NULL DEFAULT '',
      created_at    INTEGER NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS med_dose (
      med_key     TEXT NOT NULL,
      date        TEXT NOT NULL,
      slot_min    INTEGER NOT NULL,
      taken_ts    INTEGER,
      skipped     INTEGER NOT NULL DEFAULT 0,
      dose_value  REAL,
      note        TEXT NOT NULL DEFAULT '',
      updated_at  INTEGER NOT NULL,
      PRIMARY KEY (med_key, date, slot_min)
    )
  ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_med_dose_date ON med_dose(date)',
  );
}
