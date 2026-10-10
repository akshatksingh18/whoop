// Dated calculation anchors; older days retain the upgrade baseline.
import 'dart:convert';
import 'calculation_store.dart';
import '../compute/profile.dart';
import 'day_label.dart';
import 'db.dart';

class ProfileHistory {
  static const key = 'profile.calculation_history';
  static Map<String, dynamic> decode(String? raw) {
    try {
      final m = jsonDecode(raw ?? '');
      if (m is Map) return Map<String, dynamic>.from(m);
    } catch (_) {
      /* No history before build 73. */
    }
    return {};
  }

  static Future<void> record(
    Map<String, dynamic>? before,
    Map<String, dynamic> after, {
    DateTime? now,
  }) async {
    final h = decode(await CalculationStore.read(key));
    h.putIfAbsent('baseline', () => Profile.fromMap(before ?? after).toMap());
    final day = dayLabelOf(now ?? DateTime.now());
    h[day] = Profile.fromMap(after).toMap();
    if (before?['weight_kg'] != after['weight_kg']) {
      final weights = Map<String, dynamic>.from(
        h['weight_edits'] as Map? ?? {},
      );
      weights[day] = {
        'kg': after['weight_kg'],
        'at_ts': (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000,
      };
      h['weight_edits'] = weights;
    }
    await CalculationStore.write(key, jsonEncode(h));
  }

  static Future<Profile> on(String day, Profile fallback) async {
    final h = decode(await CalculationStore.read(key));
    final dates =
        h.keys
            .where(
              (k) =>
                  RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(k) &&
                  k.compareTo(day) <= 0,
            )
            .toList()
          ..sort();
    final m = h[dates.isEmpty ? 'baseline' : dates.last];
    final profile = m is Map
        ? Profile.fromMap(Map<String, dynamic>.from(m))
        : fallback;
    final db = await LocalDb.instance;
    final weights = await db.query(
      'body_weight',
      // History-only rows (backdated or imported, build 86) never price a
      // past day: Akshat's decision that past calorie numbers do not move.
      where: 'date <= ? AND history_only = 0',
      whereArgs: [day],
      orderBy: 'date DESC',
      limit: 1,
    );
    if (weights.isEmpty) return profile;
    final kg = (weights.first['kg'] as num?)?.toDouble();
    final date = weights.first['date'] as String;
    final edits = (h['weight_edits'] as Map?) ?? {};
    final newer = edits.keys.cast<String>().any(
      (d) =>
          d.compareTo(day) <= 0 &&
          (d.compareTo(date) > 0 ||
              (d == date &&
                  edits[d] is Map &&
                  ((edits[d]['at_ts'] as num?)?.toInt() ?? 0) >
                      ((weights.first['at_ts'] as num?)?.toInt() ?? 0))),
    );
    if (kg == null || !kg.isFinite || kg <= 0 || newer) return profile;
    return Profile.fromMap({...profile.toMap(), 'weight_kg': kg});
  }
}
