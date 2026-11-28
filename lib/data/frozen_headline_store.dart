part of 'db.dart';

/// The frozen morning readiness headline pinned in the sync-cursor KV, and the
/// explanation that travels with it, split out of [LocalDb] by concern.
abstract final class FrozenHeadlineStore {
  /// Cursor holding the FROZEN morning readiness headline (see #128): the
  /// day-tagged value pinned once today's overnight first settles on a genuinely
  /// complete night, so the Today hero + recovery story stop drifting through
  /// the day. Day-tagged so it survives restarts and is ignored on a new day.
  static const String kCursorKey = 'frozen_headline';

  /// The pinned morning readiness headline (day + value), or null if unset /
  /// unparseable. The `day` must be compared to today's label by the caller — a
  /// pin left over from a previous day must NOT be surfaced.
  static Future<({String day, int value})?> read() async {
    final raw = await CursorStore.read(kCursorKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final d = jsonDecode(raw);
      if (d is Map && d['day'] is String && d['value'] is num) {
        return (day: d['day'] as String, value: (d['value'] as num).round());
      }
    } catch (_) {
      /* malformed → treat as unset */
    }
    return null;
  }

  /// Pin [value] as the frozen readiness headline for [day] (overwrites any
  /// prior pin — first-complete-settle-per-day is enforced by the caller).
  static Future<void> put(
    String day,
    int value, {
    Map<String, dynamic>? explanation,
    int? sleepIntentGeneration,
    int? sleepRevision,
  }) async {
    final db = await LocalDb.instance;
    await db.transaction((txn) async {
      final intent = await SleepOverrideStore._correctionVia(txn, day);
      if (intent != null && intent['usable'] != true) return;
      if ((intent?['generation'] as num?)?.toInt() != sleepIntentGeneration ||
          (sleepRevision != null &&
              (await CursorStore._readIntVia(
                        txn,
                        'sleep_correction_revision',
                      ) ??
                      0) !=
                  sleepRevision)) {
        return;
      }
      await CursorStore.write(
        kCursorKey,
        jsonEncode({'day': day, 'value': value, 'explanation': ?explanation}),
        txn: txn,
      );
    });
  }

  /// Optional original evidence, committed in the same cursor as the score.
  /// Older pins have none; they must not borrow a later calculation's inputs.
  static Future<Map<String, dynamic>?> explanation(
    String day,
    int value,
  ) async {
    try {
      final raw = await CursorStore.read(kCursorKey);
      final pin = raw == null ? null : jsonDecode(raw);
      if (pin is! Map ||
          pin['day'] != day ||
          (pin['value'] as num?)?.round() != value) {
        return null;
      }
      final e = pin['explanation'];
      if (e is! Map ||
          e['format'] != 1 ||
          e['composite'] is! Map ||
          e['values'] is! Map ||
          e['baselines'] is! Map) {
        return null;
      }
      return e.cast<String, dynamic>();
    } catch (_) {
      return null;
    }
  }
}
