import 'dart:convert';
import '../compute/nap_edits.dart';
import 'db.dart';

/// Durable corrections projected onto retained detector proposals. No sensor
/// inference or main-sleep restaging is needed to add/remove a reported nap.
class NapLedger {
  static Future<Map<String, dynamic>> read(
    String date,
    Map<String, dynamic>? block,
  ) async {
    final rows = await LocalDb.napEdits(date);
    final key = 'nap_proposals:$date';
    final cached = await LocalDb.baseline(key);
    final old = cached == null
        ? const []
        : jsonDecode(cached['payload_json'] as String);
    final value = block?['value'];
    final raw = block?['detected'];
    // Older bundles did not keep unedited proposals. Save surviving detections
    // before the first removal, so restore works after rebuilding or relaunch.
    final candidates = raw is List
        ? raw
        : block?.containsKey('detected') == true
        ? const [] // A newer unjudged assessment must not revive old proposals.
        : [
            if (old is List) ...old,
            if (value is List)
              ...value.where((n) => n is Map && n['source'] != 'manual'),
          ];
    final byStart = <int, NapMap>{};
    for (final n in candidates) {
      if (n is Map && n['start'] is num && n['end'] is num) {
        byStart[(n['start'] as num).toInt()] = n.cast<String, dynamic>();
      }
    }
    final proposals = byStart.values.toList();
    if (raw is List || proposals.isNotEmpty) {
      final encoded = jsonEncode(proposals);
      if (cached?['payload_json'] != encoded)
        await LocalDb.putBaseline(key, encoded);
    }
    final edits = [
      for (final row in rows)
        NapEdit(
          kind: row['source'] == 'rejected'
              ? NapEditKind.rejected
              : NapEditKind.added,
          startSec: row['start_ts'] as int,
          endSec: row['end_ts'] as int,
        ),
    ];
    final merged = applyNapEdits(proposals, edits);
    final judged =
        (block?.containsKey('detected') == true
            ? raw is List
            : value is List) ||
        merged.isNotEmpty;
    return {
      'proposals': proposals,
      if (judged) 'naps': merged,
      'nap_min': judged ? napMinutes(merged) : null,
      'note': block?['note']?.toString(),
      'rejected': [
        for (final row in rows)
          if (row['source'] == 'rejected') row,
      ],
    };
  }
}
