// Medication and supplements — definitions, a schedule, and per-dose state.
//
// This needs its own table where habits do not (see db.dart's journal_metric
// note and UI_WIRING §5.6): a habit is one number per day, a medication is a
// SCHEDULE plus one taken/skipped record per slot. Multiple rows per (day,
// thing) is the whole reason for a table.
//
// `taken_ts IS NULL AND skipped = 0` on a PAST slot is the only thing that
// counts as a miss. A slot still ahead of you today is neither taken nor
// missed, and adherence that counts it is adherence that lies to you every
// morning. That is why taken_ts is nullable rather than a boolean.
//
// THERE IS NO INTERACTION CHECKING, and there will not be one bolted on
// quietly: no free authoritative source exists, and being wrong here is
// dangerous. The UI says so in a StatusCard.

import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'day_label.dart';

// ══════════════════ SCHEMA ══════════════════

/// schemaVersion 36.
Future<void> createMedTables(Database db) async {
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

// ══════════════════ MODEL ══════════════════

/// One scheduled time. [days] are `DateTime.weekday` values, 1 = Monday.
class MedSchedule {
  const MedSchedule(this.minuteOfDay, this.days);
  final int minuteOfDay;
  final List<int> days;

  bool onDay(DateTime d) => days.isEmpty || days.contains(d.weekday);

  Map<String, Object?> toJson() => {'minute_of_day': minuteOfDay, 'days': days};

  static MedSchedule fromJson(Map<String, Object?> j) => MedSchedule(
    (j['minute_of_day'] as num?)?.toInt() ?? 0,
    [for (final d in (j['days'] as List?) ?? const []) (d as num).toInt()],
  );
}

class MedDef {
  const MedDef({
    required this.key,
    required this.label,
    this.doseValue,
    this.doseUnit = '',
    this.kind = 'medication',
    this.schedule = const [],
    this.active = true,
    this.note = '',
  });

  final String key;
  final String label;

  /// Null means "as directed" — a real answer, not a missing one.
  final double? doseValue;
  final String doseUnit;

  /// 'medication' | 'supplement'.
  final String kind;
  final List<MedSchedule> schedule;
  final bool active;
  final String note;

  String get doseLabel {
    final v = doseValue;
    if (v == null) return doseUnit.isEmpty ? 'As directed' : doseUnit;
    final n = v == v.roundToDouble() ? v.round().toString() : v.toString();
    return doseUnit.isEmpty ? n : '$n $doseUnit';
  }

  Map<String, Object?> toRow(int nowMs) => {
    'key': key,
    'label': label,
    'dose_value': doseValue,
    'dose_unit': doseUnit,
    'kind': kind,
    'schedule_json': jsonEncode([for (final s in schedule) s.toJson()]),
    'active': active ? 1 : 0,
    'note': note,
    'created_at': nowMs,
  };

  static MedDef fromRow(Map<String, Object?> r) {
    final raw = jsonDecode((r['schedule_json'] as String?) ?? '[]');
    return MedDef(
      key: r['key'] as String,
      label: r['label'] as String,
      doseValue: (r['dose_value'] as num?)?.toDouble(),
      doseUnit: (r['dose_unit'] as String?) ?? '',
      kind: (r['kind'] as String?) ?? 'medication',
      schedule: raw is List
          ? [
              for (final s in raw)
                if (s is Map) MedSchedule.fromJson(s.cast<String, Object?>()),
            ]
          : const [],
      active: ((r['active'] as num?)?.toInt() ?? 1) == 1,
      note: (r['note'] as String?) ?? '',
    );
  }
}

/// What happened to one scheduled dose.
enum DoseState { taken, skipped, missed, upcoming }

/// One slot on one day, with its state resolved against the clock.
class MedSlot {
  const MedSlot({
    required this.def,
    required this.date,
    required this.slotMin,
    required this.state,
  });

  final MedDef def;
  final String date;
  final int slotMin;
  final DoseState state;

  String get timeLabel {
    final h = (slotMin ~/ 60).toString().padLeft(2, '0');
    final m = (slotMin % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// A slot that has passed and was neither taken nor deliberately skipped.
  bool get isMiss => state == DoseState.missed;

  /// Whether this slot may be counted at all. An upcoming slot is not yet an
  /// opportunity, so it belongs in no adherence denominator.
  bool get isDecided => state != DoseState.upcoming;
}

/// Resolve one day's slots for [defs]. [now] decides what "past" means, so the
/// caller owns the clock and the tests do not have to wait for one.
List<MedSlot> slotsForDay(
  List<MedDef> defs,
  String date,
  Map<String, Map<int, Map<String, Object?>>> doses, {
  required DateTime now,
}) {
  final startSec = localDayStartSec(date);
  if (startSec == null) return const [];
  final day = DateTime.fromMillisecondsSinceEpoch(startSec * 1000);
  final nowMin = dayLabelOf(now) == date
      ? now.hour * 60 + now.minute
      : (now.isAfter(day) ? 24 * 60 : -1);
  final out = <MedSlot>[];
  for (final d in defs) {
    if (!d.active) continue;
    for (final s in d.schedule) {
      if (!s.onDay(day)) continue;
      final row = doses[d.key]?[s.minuteOfDay];
      final taken = (row?['taken_ts'] as num?) != null;
      final skipped = ((row?['skipped'] as num?)?.toInt() ?? 0) == 1;
      out.add(
        MedSlot(
          def: d,
          date: date,
          slotMin: s.minuteOfDay,
          state: taken
              ? DoseState.taken
              : skipped
              ? DoseState.skipped
              : (s.minuteOfDay <= nowMin ? DoseState.missed : DoseState.upcoming),
        ),
      );
    }
  }
  out.sort((a, b) => a.slotMin.compareTo(b.slotMin));
  return out;
}

/// Adherence as a COUNT with its window stated — never a percentage on its
/// own. `(taken, of)` feeds `Consistency` directly.
({int taken, int of}) adherence(List<MedSlot> slots) {
  var taken = 0, of = 0;
  for (final s in slots) {
    if (!s.isDecided) continue;
    of++;
    if (s.state == DoseState.taken) taken++;
  }
  return (taken: taken, of: of);
}

// ══════════════════ STORE ══════════════════

class MedDb {
  MedDb._();

  static String keyFor(String label) =>
      'custom_${label.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_')}';

  static Future<List<MedDef>> defs(Database db, {bool activeOnly = true}) async {
    final rows = await db.query(
      'med_def',
      where: activeOnly ? 'active = 1' : null,
      orderBy: 'label ASC',
    );
    return [for (final r in rows) MedDef.fromRow(r)];
  }

  static Future<void> putDef(Database db, MedDef d) => db.insert(
    'med_def',
    d.toRow(DateTime.now().millisecondsSinceEpoch),
    conflictAlgorithm: ConflictAlgorithm.replace,
  );

  static Future<void> deleteDef(Database db, String key) async {
    await db.delete('med_def', where: 'key = ?', whereArgs: [key]);
    // The dose history stays: those doses were still taken. Nothing reads them
    // once the definition is gone, and a re-added key picks them back up.
  }

  /// Doses over a date range, indexed `[med_key][slot_min]`.
  static Future<Map<String, Map<int, Map<String, Object?>>>> doses(
    Database db, {
    required String from,
    required String to,
  }) async {
    final rows = await db.query(
      'med_dose',
      where: 'date >= ? AND date <= ?',
      whereArgs: [from, to],
    );
    final out = <String, Map<int, Map<String, Object?>>>{};
    for (final r in rows) {
      final key = '${r['med_key']}|${r['date']}';
      (out[key] ??= {})[(r['slot_min'] as num).toInt()] = r;
    }
    return out;
  }

  /// One day's doses, indexed `[med_key][slot_min]` — the shape
  /// [slotsForDay] wants.
  static Future<Map<String, Map<int, Map<String, Object?>>>> dosesForDay(
    Database db,
    String date,
  ) async {
    final rows = await db.query(
      'med_dose',
      where: 'date = ?',
      whereArgs: [date],
    );
    final out = <String, Map<int, Map<String, Object?>>>{};
    for (final r in rows) {
      (out[r['med_key'] as String] ??= {})[(r['slot_min'] as num).toInt()] = r;
    }
    return out;
  }

  static Future<void> mark(
    Database db, {
    required String medKey,
    required String date,
    required int slotMin,
    required bool taken,
    bool skipped = false,
  }) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await db.insert('med_dose', {
      'med_key': medKey,
      'date': date,
      'slot_min': slotMin,
      'taken_ts': taken ? nowMs ~/ 1000 : null,
      'skipped': skipped ? 1 : 0,
      'dose_value': null,
      'note': '',
      'updated_at': nowMs,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Adherence over the trailing [days] days ending today.
  static Future<({int taken, int of})> adherenceWindow(
    Database db, {
    int days = 7,
    DateTime? now,
  }) async {
    final end = now ?? DateTime.now();
    final defsList = await defs(db);
    if (defsList.isEmpty) return (taken: 0, of: 0);
    final labels = [
      for (var i = days - 1; i >= 0; i--)
        dayLabelOf(DateTime(end.year, end.month, end.day - i)),
    ];
    final all = await doses(db, from: labels.first, to: labels.last);
    var taken = 0, of = 0;
    for (final l in labels) {
      final byMed = <String, Map<int, Map<String, Object?>>>{
        for (final d in defsList)
          if (all['${d.key}|$l'] != null) d.key: all['${d.key}|$l']!,
      };
      final a = adherence(slotsForDay(defsList, l, byMed, now: end));
      taken += a.taken;
      of += a.of;
    }
    return (taken: taken, of: of);
  }
}
