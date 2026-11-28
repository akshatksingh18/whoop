part of 'db.dart';

/// The `compute_freshness` key/value ledger: per-surface freshness stamps and
/// one-time job markers, split out of [LocalDb] by concern.
abstract final class ComputeFreshnessStore {
  static Future<Map<String, dynamic>?> read(String key) async {
    final db = await LocalDb.instance;
    final rows = await db.query(
      'compute_freshness',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  static Future<void> put(String key, String payloadJson) async {
    final db = await LocalDb.instance;
    await db.insert('compute_freshness', {
      'key': key,
      'payload_json': payloadJson,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> refresh() async {
    final raw = await DiagnosticsStore.rawStats();
    final recent = await LocalDb.recentDayResults(30);
    final rolling = await MetricSeriesStore.baseline('rolling');
    final cross = await MetricSeriesStore.baseline('crossday');
    final today = LocalDb.localDayLabelNow();
    final latestRawTs = (raw['max_rec_ts'] as num?)?.toInt();
    final todayWake = await SleepIntermediateStore.wakeFeatures(today);
    String? latestOvernightDay;
    int? latestOvernightComputedAt;
    String? latestRecoveryDay;
    int? latestRecoveryComputedAt;
    Map<String, dynamic>? todayRow;
    // B88-05: today's row flagged NO_SLEEP_DETECTED is a decided night with no
    // sleep, not a scored overnight. It must not mark the overnight "ready"
    // while the bundle served is an EARLIER night with sleep — that printed a
    // prior night's readiness/HRV/RHR as today's with no held-over note.
    var todayNoSleep = false;
    for (final row in recent) {
      final dayId = row['day_id']?.toString();
      if (dayId == null || dayId.isEmpty) continue;
      if (dayId == today && todayRow == null) todayRow = row;
      final decoded =
          SeriesCodec.decodePayloadJson(row['payload_json']) ??
          const <String, dynamic>{};
      if (decoded['skipped'] == true) continue;
      // Persisted/imported JSON may have an older or damaged block shape.
      final storedScalars = decoded['scalars'];
      final scalars = storedScalars is Map ? storedScalars : const {};
      if (latestOvernightDay == null) {
        final storedSleep = decoded['sleep'];
        final accounting = storedSleep is Map
            ? storedSleep['accounting']
            : null;
        final sleep = accounting is Map ? accounting['value'] : null;
        final flags = decoded['flags'];
        final hasSleep = sleep is Map && sleep['tst_sec'] != null;
        final noSleep = flags is List && flags.contains('NO_SLEEP_DETECTED');
        if (noSleep && !hasSleep && dayId == today) todayNoSleep = true;
        if (hasSleep) {
          latestOvernightDay = dayId;
          latestOvernightComputedAt = (row['computed_at'] as num?)?.toInt();
        }
      }
      if (latestRecoveryDay == null &&
          ((row['readiness'] as num?) != null || scalars['readiness'] is num)) {
        latestRecoveryDay = dayId;
        latestRecoveryComputedAt = (row['computed_at'] as num?)?.toInt();
      }
      if (latestOvernightDay != null &&
          latestRecoveryDay != null &&
          todayRow != null) {
        break;
      }
    }
    final todayComputedAt = (todayRow?['computed_at'] as num?)?.toInt();
    final wakeComputedAt = (todayWake?['computed_at'] as num?)?.toInt();
    final activityReady = todayRow != null || todayWake != null;
    final overnightReady = latestOvernightDay == today;
    final rawReachedToday =
        latestRawTs != null &&
        LocalDb._localDayLabelFromEpoch(latestRawTs) == today;
    final activityState = activityReady
        ? 'ready'
        : (rawReachedToday ? 'building' : 'missing');
    final overnightState = overnightReady
        ? 'ready'
        : (rawReachedToday ? 'building' : 'missing');
    await put(
      'capture',
      jsonEncode({
        'latest_raw_rec_ts': latestRawTs,
        'latest_raw_day': latestRawTs == null
            ? null
            : LocalDb._localDayLabelFromEpoch(latestRawTs),
        'decoded_onehz': raw['decoded_onehz'],
        'decoded_rr': raw['decoded_rr'],
      }),
    );
    await put(
      'today',
      jsonEncode({
        'today_day': today,
        'activity_day': activityReady ? today : null,
        'activity_state': activityState,
        'activity_computed_at': todayComputedAt ?? wakeComputedAt,
        'overnight_day': latestOvernightDay,
        'overnight_state': overnightState,
        'overnight_computed_at': latestOvernightComputedAt,
        'recovery_day': latestRecoveryDay,
        'recovery_computed_at': latestRecoveryComputedAt,
        'showing_prior_overnight':
            latestOvernightDay != null && latestOvernightDay != today,
        'overnight_no_sleep_today': todayNoSleep,
      }),
    );
    await put(
      'crossday',
      jsonEncode({
        'present': cross != null,
        'updated_at': rolling?['updated_at'],
      }),
    );
  }
}
