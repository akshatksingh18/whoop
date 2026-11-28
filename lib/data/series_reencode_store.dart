part of 'db.dart';

/// The one-time, forward-only walk that re-encodes pre-codec `day_result`
/// bundles into the compact curve format, split out of [LocalDb] by concern.
abstract final class SeriesReencodeStore {
  /// Bookkeeping key for the one-time walk in [run].
  static const String kCursorKey = 'series_reencode';

  /// Test seam: awaited inside [run] between the batch
  /// prepare and the write transaction. Null in production, and the only cost
  /// there is one null check per batch.
  ///
  /// It exists because the race the compare-and-set guards is a placement
  /// problem, not a timing one: a competing derive has to land in that exact
  /// window. Pinning it with a sleep meant the test asserted a real property
  /// only as long as the runner stayed inside the delay, which is the shape of
  /// a test that passes on a laptop and goes red on a loaded CI box.
  @visibleForTesting
  static Future<void> Function()? debugAfterPrepare;

  /// Re-encode a BOUNDED batch of pre-codec `day_result` rows into the compact
  /// curve format, newest first. Returns how many rows were rewritten.
  ///
  /// WHY A BACKFILL AT ALL. `SeriesCodec` reads the legacy shape forever, so
  /// nothing breaks without this — but a user's existing history would stay at
  /// ~88 KB/day while only new days shrank, and `day_result` is precisely the
  /// store that grows without bound. This converts the back catalogue once.
  ///
  /// WHERE IT RUNS. Called from the derivation engine's post-derive
  /// housekeeping, beside `StorageRetentionStore.pruneSupersededIntermediates`
  /// — off the path to a durable commit, and NEVER inside a migration:
  /// `onUpgrade` runs inside `openDatabase` under iOS's CPU watchdog, where
  /// rewriting a year of bundles would be a launch hang (invariant 11).
  ///
  /// A FORWARD-ONLY CURSOR, not a rescan. Progress is stored in
  /// `compute_freshness`, so each call walks strictly older days than the last
  /// and the whole history costs one pass. Re-scanning from the newest day
  /// every time would re-read (and re-parse) every already-converted bundle
  /// forever — tens of MB of I/O per derivation.
  ///
  /// IMMUTABILITY. `day_result` rows are immutable PER VERSION, meaning their
  /// derived VALUES never change without a `kAlgoVersion` bump. This rewrite
  /// changes only how those same values are spelled, and every row is gated on
  /// [SeriesCodec.verifyLossless] before it is touched — a bundle whose
  /// round-trip is not provably exact is skipped and left legacy. Nothing but
  /// `payload_json` is written: `computed_at`, `finalized`, `partial` and the
  /// indexed scalars are untouched, so no day is re-finalized or re-dated.
  static Future<int> run({int limit = 40}) async {
    final db = await LocalDb.instance;

    String? cursorDay;
    int? cursorVersion;
    final prev = await ComputeFreshnessStore.read(kCursorKey);
    final prevJson = prev?['payload_json'];
    if (prevJson is String && prevJson.isNotEmpty) {
      try {
        final d = jsonDecode(prevJson);
        if (d is Map) {
          if (d['done'] == true) return 0; // whole history already walked
          final c = d['cursor'];
          if (c is String && c.isNotEmpty) cursorDay = c;
          final v = d['cursor_version'];
          if (v is int) cursorVersion = v;
        }
      } catch (_) {
        /* unreadable bookkeeping ⇒ start over; the walk is idempotent */
      }
    }

    // The cursor is the COMPOSITE key, not just the day. `day_result` is keyed
    // (day_id, algo_version) and one day can hold several generations, so a
    // day-only cursor stepped straight past a day's older rows and left them
    // legacy forever.
    //
    // Spelled out rather than as the row-value form `(day_id, algo_version) <
    // (?, ?)`: row values need SQLite 3.15, which this file does not assume.
    final String? where;
    final List<Object?>? whereArgs;
    if (cursorDay == null) {
      where = null;
      whereArgs = null;
    } else if (cursorVersion == null) {
      where = 'day_id < ?';
      whereArgs = [cursorDay];
    } else {
      where = 'day_id < ? OR (day_id = ? AND algo_version < ?)';
      whereArgs = [cursorDay, cursorDay, cursorVersion];
    }

    final rows = await db.query(
      'day_result',
      columns: ['day_id', 'algo_version', 'payload_json'],
      where: where,
      whereArgs: whereArgs,
      orderBy: 'day_id DESC, algo_version DESC',
      limit: limit,
    );
    if (rows.isEmpty) {
      await ComputeFreshnessStore.put(kCursorKey, jsonEncode({'done': true}));
      return 0;
    }

    // PREPARE ON A WORKER ISOLATE, outside the transaction.
    //
    // Outside the transaction because each eligible bundle costs several JSON
    // parse/serialize passes (needsReencode, then verifyLossless, which encodes
    // and decodes to prove the round trip, then the real encode), and doing
    // that inside db.transaction held the write lock open across ~40 x ~88 KB
    // of pure CPU while the rest of the app waited to write.
    //
    // Off THIS isolate because that CPU is otherwise synchronous on whichever
    // isolate called the derive, and the derive is called from the UI one:
    // measured at 0.1-0.4 s per batch on a desktop, which is several times that
    // on a mid-tier phone, with no await in the loop for the frame scheduler to
    // get a word in. This app has shipped a derive-correlated main-isolate
    // freeze before. `SeriesCodec` is pure — no I/O, no plugins, no Flutter —
    // so it is safe anywhere, and the batch is bounded by `limit`.
    final payloads = [
      for (final row in rows)
        (row['payload_json'] is String) ? row['payload_json'] as String : '',
    ];
    final prepared = await Isolate.run(() => _reencodeBatch(payloads));
    // The window the compare-and-set below exists to close: the rows were read,
    // the encode took real time, and nothing has been locked yet. A test drives
    // a competing write through here rather than racing a sleep against it —
    // the interleave is the whole property, so it has to be placed rather than
    // hoped for.
    final afterPrepare = debugAfterPrepare;
    if (afterPrepare != null) await afterPrepare();

    final updates =
        <
          ({
            int rowIndex,
            String dayId,
            int algoVersion,
            String from,
            String to,
          })
        >[];
    for (var i = 0; i < rows.length; i++) {
      final encoded = prepared[i];
      if (encoded == null) continue;
      updates.add((
        rowIndex: i,
        dayId: rows[i]['day_id'] as String,
        algoVersion: (rows[i]['algo_version'] as num).toInt(),
        from: payloads[i],
        to: encoded,
      ));
    }

    var rewritten = 0;
    // Index of the OLDEST-ranked row (first in this newest-first batch) whose
    // compare-and-set found something other than what we read.
    int? missedIndex;
    if (updates.isNotEmpty) {
      await db.transaction((txn) async {
        for (final u in updates) {
          // COMPARE-AND-SET on the payload we actually read.
          //
          // The prepare above deliberately runs outside any transaction and
          // takes hundreds of milliseconds, and derivation runs in more than
          // one isolate (see updateBaseline's exclusive transaction for the
          // same hazard). A blind `WHERE day_id = ? AND algo_version = ?` will
          // happily write a stale bundle over a row that a concurrent derive
          // rewrote in the meantime — and because this walk starts at the
          // NEWEST day with kAlgoVersion unbumped, its first targets are
          // exactly the rows a light derive is rewriting. The row would end up
          // holding the new scalar columns beside the old payload.
          //
          // A row that has moved is left alone. It is not lost: the cursor is
          // held back below so a later pass looks at it again.
          final n = await txn.update(
            'day_result',
            {'payload_json': u.to},
            where: 'day_id = ? AND algo_version = ? AND payload_json = ?',
            whereArgs: [u.dayId, u.algoVersion, u.from],
          );
          if (n > 0) {
            rewritten++;
          } else {
            missedIndex ??= u.rowIndex;
          }
        }
      });
    }

    // The cursor advances past every row we LOOKED at, not just the ones we
    // rewrote — a row we skipped (already encoded, or not provably lossless)
    // would otherwise be re-examined on every future pass and the walk would
    // never terminate.
    //
    // A row that lost the compare-and-set is the one exception: it is parked
    // just BEHIND the cursor so the next pass reads it again, and `done` is
    // withheld so the walk cannot latch shut over it. A missed FIRST row leaves
    // the cursor exactly where it was, which costs one repeated batch and
    // converges — the second look either re-encodes the row or finds it already
    // encoded and steps past.
    final Map<String, Object?> mark;
    final missed = missedIndex;
    if (missed == null) {
      mark = {
        'cursor': rows.last['day_id'],
        'cursor_version': rows.last['algo_version'],
        'done': rows.length < limit,
      };
    } else if (missed > 0) {
      mark = {
        'cursor': rows[missed - 1]['day_id'],
        'cursor_version': rows[missed - 1]['algo_version'],
        'done': false,
      };
    } else if (cursorDay == null) {
      mark = const {};
    } else {
      mark = {
        'cursor': cursorDay,
        'cursor_version': cursorVersion,
        'done': false,
      };
    }
    await ComputeFreshnessStore.put(
      kCursorKey,
      jsonEncode({...mark, 'rewritten_last': rewritten}),
    );
    return rewritten;
  }
}
