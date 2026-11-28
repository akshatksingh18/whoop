part of 'db.dart';

/// The `sleep_override` table and sleep-window corrections, split out of
/// [LocalDb] by concern.
abstract final class SleepOverrideStore {
  // The user's word on when they slept — either typed in manually (Approach 1)
  // or a confirmation of the HR-led fallback's proposal (Approach 2). Stored
  // SEPARATELY from the derived day_result so it survives finalization AND any
  // kAlgoVersion bump: the engine re-applies it on every derive of that day.
  //   source: 'manual'    — user typed the times
  //           'confirmed' — user accepted the fallback's proposed window
  // Times are epoch SECONDS (phone clock; raw rec_ts is SET_CLOCK'd to match).
  static Future<void> _create(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sleep_override (
        day_id TEXT PRIMARY KEY,
        onset_ts INTEGER NOT NULL,
        offset_ts INTEGER NOT NULL,
        source TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
  }

  /// Upsert the user's sleep window for [dayId] (local date label). [source] is
  /// 'manual' or 'confirmed'. Replaces any prior override for that day.
  static Future<void> putOverride({
    required String dayId,
    required int onsetTs,
    required int offsetTs,
    required String source,
  }) async {
    final db = await LocalDb.instance;
    await db.insert('sleep_override', {
      'day_id': dayId,
      'onset_ts': onsetTs,
      'offset_ts': offsetTs,
      'source': source,
      'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// The user's sleep window for [dayId], or null if none.
  static Future<Map<String, dynamic>?> getOverride(String dayId) async {
    final db = await LocalDb.instance;
    final rows = await db.query(
      'sleep_override',
      where: 'day_id = ?',
      whereArgs: [dayId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  static const _correctionArtifacts = [
    'crossday',
    'rolling',
    'rolling_artifact',
  ];

  static Future<Map<String, dynamic>?> _correctionVia(
    DatabaseExecutor ex,
    String day,
  ) async {
    final rows = await ex.query(
      'baselines',
      columns: ['payload_json'],
      where: 'key = ?',
      whereArgs: ['sleep_correction:$day'],
      limit: 1,
    );
    return rows.isEmpty
        ? null
        : Map<String, dynamic>.from(
            jsonDecode(rows.first['payload_json'] as String) as Map,
          );
  }

  static Future<Map<String, dynamic>?> correction(String day) async =>
      _correctionVia(await LocalDb.instance, day);

  static Future<int?> correctionGeneration(String day) async =>
      ((await correction(day))?['generation'] as num?)?.toInt();

  static Future<int> correctionRevision() async =>
      await CursorStore.readInt('sleep_correction_revision') ?? 0;

  /// Accept intent and preserve every prior generation in one SQLite transaction.
  /// The projected row is deliberately partial/unfinalized: unknown is not a
  /// successful derivation, and cannot license raw pruning.
  static Future<void> acceptCorrection({
    required String dayId,
    required String action,
    int? onsetTs,
    int? offsetTs,
  }) async {
    if (!{'manual', 'confirmed', 'rejected', 'clear'}.contains(action) ||
        (action != 'clear' &&
            (onsetTs == null || offsetTs == null || offsetTs <= onsetTs))) {
      throw ArgumentError('Invalid sleep correction');
    }
    final db = await LocalDb.instance;
    await db.transaction((txn) async {
      final prior = await _correctionVia(txn, dayId);
      final results = await txn.query(
        'day_result',
        where: 'day_id = ?',
        whereArgs: [dayId],
        orderBy: 'algo_version DESC',
      );
      final pins = await txn.query(
        'sync_cursor',
        where: 'name = ?',
        whereArgs: [FrozenHeadlineStore.kCursorKey],
      );
      final snapshot = <String, dynamic>{
        'generation': prior?['generation'],
        'day_results': results,
        'override': await txn.query(
          'sleep_override',
          where: 'day_id = ?',
          whereArgs: [dayId],
        ),
        'candidates': await txn.query(
          'sleep_session_candidates',
          where: 'day_id = ?',
          whereArgs: [dayId],
        ),
        'series': await txn.query(
          'metric_series',
          where: 'date = ?',
          whereArgs: [dayId],
        ),
        'series_version': await txn.query(
          'metric_series_version',
          where: 'date = ?',
          whereArgs: [dayId],
        ),
        'pin': pins,
        'artifacts': await txn.query(
          'baselines',
          where:
              'key IN (${List.filled(_correctionArtifacts.length, '?').join(',')})',
          whereArgs: _correctionArtifacts,
        ),
      };
      final intent = <String, dynamic>{
        'version': 1,
        'day': dayId,
        'generation': ((prior?['generation'] as num?)?.toInt() ?? 0) + 1,
        'action': action,
        'pending': true,
        'usable': false,
        'recovery': [...?prior?['recovery'] as List?, snapshot],
      };
      final now = DateTime.now().millisecondsSinceEpoch;
      await txn.insert('baselines', {
        'key': 'sleep_correction:$dayId',
        'payload_json': jsonEncode(intent),
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      if (action == 'clear') {
        await txn.delete(
          'sleep_override',
          where: 'day_id = ?',
          whereArgs: [dayId],
        );
      } else {
        await txn.insert('sleep_override', {
          'day_id': dayId,
          'onset_ts': onsetTs,
          'offset_ts': offsetTs,
          'source': action,
          'created_at': now ~/ 1000,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      final served = results.where(
        (r) => (r['algo_version'] as int) <= kAlgoVersion,
      );
      final old = served.isEmpty
          ? <String, dynamic>{'date': dayId}
          : SeriesCodec.decodePayloadJson(served.first['payload_json']);
      if (old == null) {
        throw StateError('Cannot safely preserve malformed sleep result');
      }
      final projected = SleepCorrection.unknown(old, intent);
      await txn.insert('day_result', {
        if (served.isNotEmpty) ...served.first,
        'day_id': dayId,
        'algo_version': kAlgoVersion,
        'payload_json': SeriesCodec.encodePayloadJson(jsonEncode(projected)),
        'window_json': '{}',
        'computed_at': now,
        'finalized': 0,
        'skipped': 0,
        'partial': 1,
        'rhr': null,
        'rmssd': null,
        'readiness': null,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      for (final key in SleepCorrection.nightKeys) {
        await txn.update(
          'metric_series',
          {'value': null},
          where: 'date = ? AND key = ?',
          whereArgs: [dayId, key],
        );
      }
      if (pins.isNotEmpty) {
        Object? pin;
        try {
          pin = jsonDecode(pins.first['value'] as String);
        } on FormatException {
          // The raw pin is already in recovery. An unreadable display cache
          // must not prevent the user's durable correction from being accepted.
        }
        if (pin is Map && pin['day'] == dayId) {
          await txn.delete(
            'sync_cursor',
            where: 'name = ?',
            whereArgs: [FrozenHeadlineStore.kCursorKey],
          );
        }
      }
      await txn.delete(
        'baselines',
        where:
            'key IN (${List.filled(_correctionArtifacts.length, '?').join(',')})',
        whereArgs: _correctionArtifacts,
      );
      final revision =
          await CursorStore._readIntVia(txn, 'sleep_correction_revision') ?? 0;
      await CursorStore.write(
        'sleep_correction_revision',
        '${revision + 1}',
        txn: txn,
      );
    }, exclusive: true);
  }

  static Future<Set<String>> correctionDays({bool pendingOnly = false}) async {
    final rows = await (await LocalDb.instance).query(
      'baselines',
      columns: ['key', if (pendingOnly) 'payload_json'],
      where: 'key LIKE ?',
      whereArgs: ['sleep_correction:%'],
    );
    return {
      for (final row in rows)
        if (!pendingOnly ||
            (jsonDecode(row['payload_json'] as String) as Map)['pending'] ==
                true)
          (row['key'] as String).substring('sleep_correction:'.length),
    };
  }

  /// Every day that currently has a user override — these must be force-derived
  /// even when finalized, so an edit to a locked day actually takes effect.
  static Future<Set<String>> overrideDays() async {
    final db = await LocalDb.instance;
    final rows = await db.query('sleep_override', columns: ['day_id']);
    return {for (final r in rows) r['day_id'] as String};
  }
}
