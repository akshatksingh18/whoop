part of 'db.dart';

/// The atomic sync-batch commit (raw records, decoded seconds, archive and
/// continuation cursor in one transaction), split out of [LocalDb] by concern.
abstract final class SyncLedgerStore {
  /// Persist a sync batch atomically: the raw records, their samples, AND the
  /// continuation cursor in ONE transaction. This is the durable half of the
  /// safe-trim invariant — it MUST return before the engine writes the ACK frame.
  /// Advances counter_hw / rec_ts_hw to the batch max so a restart resumes cleanly.
  ///
  /// [onCheckpoint], if given, is called synchronously at each of the three
  /// phases (decoded+archive queued, decoded+archive committed, cursor
  /// advanced) — field diagnosability without giving up the single-txn
  /// atomicity: the checkpoint calls are pure logging, wrapped so a
  /// misbehaving callback can never abort a real commit. db.dart itself stays
  /// logging-framework-free (no Flutter dependency); callers pass their own
  /// logger (e.g. ble_engine.dart's `_log`, background_sync.dart's `debugPrint`).
  /// Times the ACK-gating commit ran at a weaker durability level than
  /// intended, because `PRAGMA synchronous=FULL` was refused or did not stick.
  /// Not fatal (see the pragma block below) but never silent.
  static int _syncFullDowngrades = 0;

  static Future<void> commitBatch(
    List<RawRecord> raws,
    List<Sample?> samples, {
    String? trimToken,
    Map<String, String>? extraCursors,
    List<ArchiveRecord>? archives,
    void Function(String)? onCheckpoint,
    // Which strap this batch came off, from the LIVE LINK (the engine pins it at
    // service discovery). Null = the caller could not name it, which lands as
    // NULL = unknown provenance. Never defaulted to gen4.
    String? deviceFamily,
    // WHICH PHYSICAL DEVICE these rows belong to (see [kPrimaryDeviceId]).
    String deviceId = LocalDb.kPrimaryDeviceId,
  }) async {
    // B4: `sync_cursor` is a SINGLE GLOBAL `name TEXT PRIMARY KEY` namespace
    // shared with everything else that keeps a scalar (`frozen_headline`, …),
    // and `band_backlog` carries `device_family` but no device id. So the trim
    // token, `counter_hw`, `rec_ts_hw` and the data range of a SECOND
    // offloading band would land on the first band's cursor and mis-trim its
    // flash. Namespacing that key space is a phase-4 job (it needs the device
    // table and a decision about which keys are per-device at all); refusing is
    // the honest thing until then, and it refuses in the SAFE direction —
    // nothing commits, so nothing is ACKed and the band keeps its data.
    //
    // ponytail: global cursor namespace, one offloading device. Per-device
    // namespacing when a second adapter can actually offload.
    if (deviceId != LocalDb.kPrimaryDeviceId) {
      throw StateError(
        'commitBatch: sync_cursor is a single global namespace and cannot '
        'hold a second offloading device (deviceId="$deviceId"). Namespace it '
        'before enabling a non-primary offload path.',
      );
    }
    void checkpoint(String msg) {
      try {
        onCheckpoint?.call(msg);
      } catch (_) {
        /* a logging callback must never affect the commit */
      }
    }

    final db = await LocalDb.instance;
    // POWER-LOSS DURABILITY WINDOW. This is the ACK-gating commit: once it
    // returns, the caller writes the BLE batch-ACK and the band trims its flash.
    // Under WAL + synchronous=NORMAL (the default this connection opens with) a
    // commit is durable only at the next checkpoint — so a kernel panic /
    // battery-yank AFTER the ACK but BEFORE the -wal is checkpointed loses these
    // just-committed rows from the phone while they are already gone from the
    // band. Raise durability to FULL (fsync AT commit) for THIS commit only,
    // leaving every other path at NORMAL — they are all recomputable and FULL
    // everywhere is brutally slow. `synchronous` is per-connection and CANNOT be
    // changed mid-transaction, so it is set on the connection BEFORE
    // db.transaction opens and reset AFTER it commits. The reset lives in a
    // finally: a leaked FULL from a throwing commit would fsync every subsequent
    // write on this connection forever. `PRAGMA synchronous=FULL/NORMAL` returns
    // NO rows → execute() (not rawQuery), kept non-fatal like the open-time
    // PRAGMAs so a PRAGMA throw can never fail a durable commit. Every ACK-gating
    // commit — the foreground drain AND the headless iOS-restore recovery drain
    // (background_sync.dart) — funnels through here, so this one choke point
    // covers them all. `synchronous` is per-connection, so the bracket is only
    // safe because these drains never OVERLAP on a shared connection: the offload
    // processor is single-flight (ble_engine.dart) and BandOwnership makes the
    // headless drain yield when the foreground owns the band. Do not add a second
    // concurrent caller of commitBatch on the main-isolate connection without
    // reinstating that serialization — a mid-window reset would silently
    // downgrade this commit back to NORMAL.
    // Best-effort, and deliberately NOT fatal. Failing the commit when the
    // upgrade is refused would mean never committing, therefore never ACKing,
    // therefore never trimming — the strap re-floods the same backlog forever
    // and sync is dead on any platform that rejects the pragma. NORMAL under
    // WAL still commits atomically; FULL narrows the power-loss window, it is
    // not itself the safe-trim invariant.
    //
    // What it must not do is fail SILENTLY, which is what "best-effort" meant
    // before: read it back, so a downgrade shows up in the log and the counter
    // instead of being invisible for the life of the install.
    try {
      await db.execute('PRAGMA synchronous=FULL');
      final got = await db.rawQuery('PRAGMA synchronous');
      final level = got.isEmpty ? null : got.first.values.firstOrNull;
      // 2 == FULL. sqflite reports the numeric level.
      if (level is num && level.toInt() != 2) {
        _syncFullDowngrades++;
        checkpoint(
          '[DB] synchronous=FULL did not take (reads back as '
          '$level) — the ACK-gating commit is running at a weaker '
          'durability level (downgrades_total=$_syncFullDowngrades).',
        );
      }
    } catch (e) {
      _syncFullDowngrades++;
      checkpoint(
        '[DB] PRAGMA synchronous=FULL was refused ($e) — the '
        'ACK-gating commit is running at NORMAL '
        '(downgrades_total=$_syncFullDowngrades).',
      );
    }
    try {
      await db.transaction((txn) async {
        // Read the existing high-water THROUGH the txn — never via the global db
        // handle, which would deadlock against this same open transaction.
        var maxCounter = await CursorStore._readIntVia(txn, 'counter_hw') ?? 0;
        var maxRecTs = await CursorStore._readIntVia(txn, 'rec_ts_hw') ?? 0;
        // CHUNKED BATCH: sqflite serialises an ENTIRE batch's operations+args into
        // ONE platform-channel message, and the native side builds a single
        // ArrayList of every argument. A large backlog offload (raws in the
        // hundreds-of-thousands) blew the native heap in SqlCommand.getSqlArguments
        // → OutOfMemoryError (Crashlytics 0.9.13). Committing in bounded chunks
        // flushes and frees each message's args. These commits all happen INSIDE
        // the single `db.transaction` below, so the safe-trim invariant holds: the
        // whole offload (raw_archive + samples + decoded_onehz + decoded_rr +
        // cursor) is still one atomic transaction — every row is durable before the
        // caller echoes the HISTORY_END trim token, or none is.
        const chunkOps = 4000;
        var batch = txn.batch();
        var ops = 0;
        Future<void> flushChunk() async {
          if (ops == 0) return;
          await batch.commit(noResult: true);
          batch = txn.batch();
          ops = 0;
        }

        // SAFE-TRIM INVARIANT: archive the undecodable records in the SAME
        // transaction as the raw records + trim cursor, so they are durably set
        // aside BEFORE the caller writes the batch-ACK that lets the band trim.
        if (archives != null) {
          for (final a in archives) {
            batch.insert('raw_archive', {
              'counter': a.counter,
              'hex': a.hex,
              'packet_type': a.packetType,
              'rec_ts': a.recTs,
              'captured_at': a.capturedAt,
              'reason': a.reason,
            }, conflictAlgorithm: ConflictAlgorithm.ignore);
            if (++ops >= chunkOps) await flushChunk();
          }
        }
        for (var i = 0; i < raws.length; i++) {
          final raw = raws[i];
          final sample = samples[i];
          if (sample != null) {
            batch.insert('samples', {
              'device_id': deviceId,
              // From `ts`, not `recTs`: `toDbMap` writes `ts: sample.tsEpoch`
              // and the migration derives `ts_ms` from `ts`, so the key and the
              // column it is built from must not be allowed to disagree.
              'ts_ms': sample.tsEpoch * 1000,
              'counter': raw.counter,
              ...sample.toDbMap(),
            }, conflictAlgorithm: ConflictAlgorithm.ignore);
            ops++;
          }
          ops += LocalDb._queueDecodedOneHz(
            batch,
            raw,
            sample,
            deviceFamily: deviceFamily,
            deviceId: deviceId,
          );
          if (raw.counter > maxCounter) maxCounter = raw.counter;
          final frontierTs = LocalDb._frontierTsFor(raw);
          if (frontierTs != null && frontierTs > maxRecTs) {
            maxRecTs = frontierTs;
          }
          if (ops >= chunkOps) await flushChunk();
        }
        checkpoint(
          'decoded_archive_queued raws=${raws.length} '
          'archives=${archives?.length ?? 0}',
        );
        await flushChunk();
        checkpoint('decoded_archive_committed');
        await CursorStore.write('counter_hw', '$maxCounter', txn: txn);
        await CursorStore.write('rec_ts_hw', '$maxRecTs', txn: txn);
        if (trimToken != null) {
          await CursorStore.write('strap_trim', trimToken, txn: txn);
        }
        if (extraCursors != null) {
          for (final e in extraCursors.entries) {
            await CursorStore.write(e.key, e.value, txn: txn);
          }
        }
        checkpoint(
          'cursor_advanced counter_hw=$maxCounter rec_ts_hw=$maxRecTs '
          'trim=${trimToken != null}',
        );
      });
    } finally {
      // ALWAYS restore NORMAL — even if the commit threw — so a leaked FULL does
      // not fsync every subsequent write on this connection. Non-fatal.
      try {
        await db.execute('PRAGMA synchronous=NORMAL');
      } catch (_) {
        /* non-fatal — see open-time PRAGMA discipline */
      }
    }
    await LocalDb._writeCaptureFreshness(raws);
  }
}
