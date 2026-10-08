// Nutrition — the log, the dictionary, and the day rollup.
//
// The personal diary logs foods into meals. Older numberless eating occasions
// remain readable, but cannot count toward energy averages. Nutrient columns
// stay nullable: optional macros are intentionally untracked when left blank.
//
// NULL IS NOT ZERO. A barcode that returns protein but no fibre writes
// `fibre_g = NULL`, and any total that summed a NULL reports itself partial.
// This is the app's founding rule made physical — see db.dart:2258.
//
// Pure rollup logic lives at the bottom as top-level functions so it is
// testable without a database.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import 'day_label.dart';

// ══════════════════ SCHEMA ══════════════════

/// schemaVersion 35. Two tables: a per-entry log, and a dictionary so a
/// repeat entry costs one row instead of re-typing the macros.
Future<void> createNutritionTables(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS food_entry (
      id            TEXT PRIMARY KEY,
      date          TEXT NOT NULL,
      at_ts         INTEGER,
      meal          TEXT NOT NULL,
      food_key      TEXT,
      label         TEXT NOT NULL,
      quantity      REAL,
      unit          TEXT NOT NULL DEFAULT 'g',
      kcal          REAL,
      protein_g     REAL,
      carbs_g       REAL,
      fat_g         REAL,
      fibre_g       REAL,
      sugar_g       REAL,
      sat_fat_g     REAL,
      sodium_mg     REAL,
      iron_mg       REAL,
      calcium_mg    REAL,
      source        TEXT NOT NULL DEFAULT 'manual',
      confirmed     INTEGER NOT NULL DEFAULT 0,
      note          TEXT NOT NULL DEFAULT '',
      created_at    INTEGER NOT NULL,
      updated_at    INTEGER NOT NULL
    )
  ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_food_entry_date ON food_entry(date, at_ts)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_food_entry_food ON food_entry(food_key, date)',
  );
  await db.execute('''
    CREATE TABLE IF NOT EXISTS food_def (
      key            TEXT PRIMARY KEY,
      label          TEXT NOT NULL,
      brand          TEXT NOT NULL DEFAULT '',
      serving_g      REAL,
      serving_label  TEXT NOT NULL DEFAULT '',
      kcal_100       REAL,
      protein_g_100  REAL,
      carbs_g_100    REAL,
      fat_g_100      REAL,
      fibre_g_100    REAL,
      sugar_g_100    REAL,
      sat_fat_g_100  REAL,
      sodium_mg_100  REAL,
      iron_mg_100    REAL,
      calcium_mg_100 REAL,
      source         TEXT NOT NULL DEFAULT 'manual',
      created_at     INTEGER NOT NULL
    )
  ''');
  // A saved meal: a named set of the user's own foods at fixed grams, filed
  // under the occasion it is usually eaten at. Logging it writes one ordinary
  // `food_entry` per item, so nothing downstream knows templates exist.
  await db.execute('''
    CREATE TABLE IF NOT EXISTS meal_template (
      key         TEXT PRIMARY KEY,
      label       TEXT NOT NULL,
      meal        TEXT NOT NULL,
      items_json  TEXT NOT NULL,
      created_at  INTEGER NOT NULL
    )
  ''');
  // A sub-heading inside a meal ("Oatmeal", "Omelette"), Akshat's idea.
  // Added in place, guarded, no schema version: an additive column with a
  // constant default is a no-op on an install that already has it, and this
  // runs on every open (`_createUserTables` from `_repairOpenSchema`).
  final cols = {
    for (final r in await db.rawQuery('PRAGMA table_info(food_entry)'))
      r['name'],
  };
  if (!cols.contains('grp')) {
    try {
      await db.execute(
        "ALTER TABLE food_entry ADD COLUMN grp TEXT NOT NULL DEFAULT ''",
      );
    } catch (_) {
      /* another opener added it first */
    }
  }
  final foodCols = {
    for (final r in await db.rawQuery('PRAGMA table_info(food_def)')) r['name'],
  };
  // A food's category ("Fruits"), chosen in the food editor and read by every
  // food list's filter (build 85). Added in place; '' is uncategorised, so
  // every existing food and log is untouched.
  if (!foodCols.contains('category')) {
    try {
      await db.execute(
        "ALTER TABLE food_def ADD COLUMN category TEXT NOT NULL DEFAULT ''",
      );
    } catch (_) {
      /* another opener added it first */
    }
  }
  if (!foodCols.contains('unit')) {
    await db.execute(
      "ALTER TABLE food_def ADD COLUMN unit TEXT NOT NULL DEFAULT 'g'",
    );
  }
  // Akshat's own order for My foods and saved meals (drag to reorder), and
  // up to two named measures per food ("scoop = 29 g"). Added in place like
  // `grp`. The first open seeds positions from the order shown until now
  // (most recently eaten first; saved meals A–Z), so nothing jumps.
  if (!foodCols.contains('pos')) {
    try {
      await db.execute('ALTER TABLE food_def ADD COLUMN pos INTEGER');
      final rows = await db.rawQuery(
        'SELECT d.key FROM food_def d '
        'LEFT JOIN (SELECT food_key, MAX(created_at) AS last FROM food_entry '
        'GROUP BY food_key) e ON e.food_key = d.key '
        'ORDER BY e.last IS NULL, e.last DESC, d.label COLLATE NOCASE ASC',
      );
      for (var i = 0; i < rows.length; i++) {
        await db.update(
          'food_def',
          {'pos': i},
          where: 'key = ?',
          whereArgs: [rows[i]['key']],
        );
      }
    } catch (_) {
      /* another opener added it first */
    }
  }
  if (!foodCols.contains('measures_json')) {
    try {
      await db.execute(
        "ALTER TABLE food_def ADD COLUMN measures_json TEXT NOT NULL DEFAULT ''",
      );
    } catch (_) {
      /* another opener added it first */
    }
  }
  final mealCols = {
    for (final r in await db.rawQuery('PRAGMA table_info(meal_template)'))
      r['name'],
  };
  if (!mealCols.contains('pos')) {
    try {
      await db.execute('ALTER TABLE meal_template ADD COLUMN pos INTEGER');
      final rows = await db.query(
        'meal_template',
        columns: ['key'],
        orderBy: 'label COLLATE NOCASE ASC',
      );
      for (var i = 0; i < rows.length; i++) {
        await db.update(
          'meal_template',
          {'pos': i},
          where: 'key = ?',
          whereArgs: [rows[i]['key']],
        );
      }
    } catch (_) {
      /* another opener added it first */
    }
  }
  // An entry's place inside its meal/sub-heading once dragged. Null keeps
  // the time order, after any dragged entries.
  if (!cols.contains('pos')) {
    try {
      await db.execute('ALTER TABLE food_entry ADD COLUMN pos INTEGER');
    } catch (_) {
      /* another opener added it first */
    }
  }
  // Body weight, one reading per day (the latest wins). For the weight trend
  // and the maintenance measured from weight change.
  await db.execute('''
    CREATE TABLE IF NOT EXISTS body_weight (
      date   TEXT PRIMARY KEY,
      kg     REAL NOT NULL,
      at_ts  INTEGER NOT NULL
    )
  ''');
}

// ══════════════════ MODEL ══════════════════

/// Where an entry's numbers came from. Rendered on every row, because a
/// manufacturer panel and a guess are not the same claim.
enum FoodSource {
  /// Typed by the user, or logged as a bare occasion with no numbers.
  manual,

  /// Read off a manufacturer or USDA panel. The only VERIFIED tier.
  verified,

  /// Filled from a barcode scanned against Open Food Facts, then edited by
  /// the user if they chose to.
  ///
  /// NOT [verified], and the difference is load-bearing. OFF is crowd-sourced:
  /// about 6% of its products carrying nutrition data hold a physically
  /// impossible value, ~20% among the most-scanned. [isVerified] gates search
  /// ranking, so calling this verified would promote exactly that data above
  /// numbers the user read off the pack themselves. It is input, never a
  /// measurement — their own terms say the data is not for medical use.
  barcode,

  /// Copied from an earlier entry of the same food.
  repeat,

  /// Identified from a photo. NEVER carries an energy total — see
  /// [FoodEntry.sanitised].
  photo,
}

FoodSource _sourceOf(String s) => switch (s) {
  'verified' => FoodSource.verified,
  'barcode' => FoodSource.barcode,
  'repeat' => FoodSource.repeat,
  'photo' => FoodSource.photo,
  _ => FoodSource.manual,
};

/// Whether a source counts as manufacturer/USDA-backed. Search ranks on this,
/// never on how often something was picked — popularity ranking quietly
/// promotes whichever wrong entry got tapped first.
bool isVerified(FoodSource s) => s == FoodSource.verified;

const kMeals = <String>['breakfast', 'lunch', 'dinner', 'snack'];

/// A chosen diary day keeps its own local date. Historical entries default to
/// the meal's clock time; the amount/edit forms let the user adjust it.
DateTime foodEntryTime(String date, String meal, {DateTime? now}) {
  final clock = now ?? DateTime.now();
  final d = DateTime.parse(date);
  final usual = DateTime(d.year, d.month, d.day, switch (meal) {
    'breakfast' => 8,
    'lunch' => 13,
    'dinner' => 19,
    _ => 16,
  });
  if (date != dayLabelOf(clock)) return usual;
  // Today: the clock while it is that meal's time (snacks any time), and
  // otherwise the meal's usual hour, so dinner logged at 10 AM is not
  // stamped 10 AM. The time stays editable on the portion screen.
  final (from, to) = switch (meal) {
    'breakfast' => (4, 11),
    'lunch' => (11, 16),
    'dinner' => (16, 24),
    _ => (0, 24),
  };
  return clock.hour >= from && clock.hour < to ? clock : usual;
}

class FoodEntry {
  const FoodEntry({
    required this.id,
    required this.date,
    required this.meal,
    required this.label,
    this.atTs,
    this.foodKey,
    this.quantity,
    this.unit = 'g',
    this.kcal,
    this.proteinG,
    this.carbsG,
    this.fatG,
    this.fibreG,
    this.sugarG,
    this.satFatG,
    this.sodiumMg,
    this.ironMg,
    this.calciumMg,
    this.source = FoodSource.manual,
    this.confirmed = false,
    this.note = '',
    this.group = '',
  });

  final String id;

  /// The sub-heading inside its meal ('' for none), e.g. "Omelette".
  final String group;

  /// Local day label, 'YYYY-MM-DD'.
  final String date;
  final String meal;
  final String label;

  /// Epoch SECONDS. Null means the time was not recorded, which costs the day
  /// its span check — see [dayLogState].
  final int? atTs;
  final String? foodKey;

  /// Null means the portion was never confirmed.
  final double? quantity;
  final String unit;

  final double? kcal,
      proteinG,
      carbsG,
      fatG,
      fibreG,
      sugarG,
      satFatG,
      sodiumMg,
      ironMg,
      calciumMg;

  final FoodSource source;
  final bool confirmed;
  final String note;

  /// A bare eating occasion: logged, but with no energy attached. Complete and
  /// valid as a log; it just cannot contribute to an energy average.
  bool get isBareOccasion => kcal == null;

  /// The write-time guard. A photo cannot produce a calorie total: AI photo
  /// estimation misses roughly a third of calories in controlled testing, and
  /// a number that wrong is worse than an honest absence. Until the user
  /// confirms a portion, a photo entry keeps its identified label and nothing
  /// else.
  FoodEntry get sanitised => (source == FoodSource.photo && !confirmed)
      ? FoodEntry(
          id: id,
          date: date,
          meal: meal,
          label: label,
          atTs: atTs,
          foodKey: foodKey,
          unit: unit,
          source: source,
          note: note,
          group: group,
        )
      : this;

  /// The same food, somewhere else: another day, meal or group. A fresh id;
  /// the time keeps its clock time on the new day.
  FoodEntry copyTo(
    String newDate,
    String newMeal, {
    required String newId,
    String? newGroup,
  }) {
    int? ts = atTs;
    if (ts != null) {
      final t = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
      final d = DateTime.tryParse(newDate);
      if (d != null) {
        ts =
            DateTime(
              d.year,
              d.month,
              d.day,
              t.hour,
              t.minute,
            ).millisecondsSinceEpoch ~/
            1000;
      }
    }
    return FoodEntry(
      id: newId,
      date: newDate,
      meal: newMeal,
      label: label,
      atTs: ts,
      foodKey: foodKey,
      quantity: quantity,
      unit: unit,
      kcal: kcal,
      proteinG: proteinG,
      carbsG: carbsG,
      fatG: fatG,
      fibreG: fibreG,
      sugarG: sugarG,
      satFatG: satFatG,
      sodiumMg: sodiumMg,
      ironMg: ironMg,
      calciumMg: calciumMg,
      // A copy is a repeat of what was logged; moving an entry between groups
      // (same id) is still the original entry.
      source: newId == id || source == FoodSource.photo
          ? source
          : FoodSource.repeat,
      confirmed: confirmed,
      note: note,
      group: newGroup ?? group,
    );
  }

  FoodEntry atQuantity(double amount) {
    if (!amount.isFinite || amount <= 0 || quantity == null || quantity! <= 0) {
      throw ArgumentError('Invalid portion');
    }
    final factor = amount / quantity!;
    double? scale(double? v) => v == null ? null : v * factor;
    return FoodEntry(
      id: id,
      date: date,
      meal: meal,
      label: label,
      atTs: atTs,
      foodKey: foodKey,
      quantity: amount,
      unit: unit,
      kcal: scale(kcal),
      proteinG: scale(proteinG),
      carbsG: scale(carbsG),
      fatG: scale(fatG),
      fibreG: scale(fibreG),
      sugarG: scale(sugarG),
      satFatG: scale(satFatG),
      sodiumMg: scale(sodiumMg),
      ironMg: scale(ironMg),
      calciumMg: scale(calciumMg),
      source: source,
      confirmed: confirmed,
      note: note,
      group: group,
    );
  }

  /// This entry in another group ('' = none).
  FoodEntry inGroup(String g) => copyTo(date, meal, newId: id, newGroup: g);

  Map<String, Object?> toRow(int nowMs) => {
    'id': id,
    'date': date,
    'at_ts': atTs,
    'meal': meal,
    'food_key': foodKey,
    'label': label,
    'quantity': quantity,
    'unit': unit,
    'kcal': kcal,
    'protein_g': proteinG,
    'carbs_g': carbsG,
    'fat_g': fatG,
    'fibre_g': fibreG,
    'sugar_g': sugarG,
    'sat_fat_g': satFatG,
    'sodium_mg': sodiumMg,
    'iron_mg': ironMg,
    'calcium_mg': calciumMg,
    'source': source.name,
    'confirmed': confirmed ? 1 : 0,
    'note': note,
    'grp': group,
    'created_at': nowMs,
    'updated_at': nowMs,
  };

  static FoodEntry fromRow(Map<String, Object?> r) {
    double? d(String k) => (r[k] as num?)?.toDouble();
    return FoodEntry(
      id: r['id'] as String,
      date: r['date'] as String,
      meal: r['meal'] as String,
      label: r['label'] as String,
      atTs: (r['at_ts'] as num?)?.toInt(),
      foodKey: r['food_key'] as String?,
      quantity: d('quantity'),
      unit: (r['unit'] as String?) ?? 'g',
      kcal: d('kcal'),
      proteinG: d('protein_g'),
      carbsG: d('carbs_g'),
      fatG: d('fat_g'),
      fibreG: d('fibre_g'),
      sugarG: d('sugar_g'),
      satFatG: d('sat_fat_g'),
      sodiumMg: d('sodium_mg'),
      ironMg: d('iron_mg'),
      calciumMg: d('calcium_mg'),
      source: _sourceOf((r['source'] as String?) ?? 'manual'),
      confirmed: ((r['confirmed'] as num?)?.toInt() ?? 0) == 1,
      note: (r['note'] as String?) ?? '',
      group: (r['grp'] as String?) ?? '',
    );
  }
}

/// One nutrient summed across a day, carrying how much of the day it could
/// not see. [value] null means nothing in the day reported this nutrient at
/// all — categorically different from "the day totalled zero grams".
class NutrientTotal {
  const NutrientTotal(this.value, this.known, this.unknown);
  final double? value;
  final int known, unknown;

  /// Every entry reported it. Only a complete total may feed an average.
  bool get complete => known > 0 && unknown == 0;

  /// Some entries reported it and some did not, so the total is a FLOOR.
  bool get isFloor => known > 0 && unknown > 0;
}

NutrientTotal _sum(List<FoodEntry> es, double? Function(FoodEntry) pick) {
  var total = 0.0;
  var known = 0, unknown = 0;
  for (final e in es) {
    final v = pick(e);
    if (v == null) {
      unknown++;
    } else {
      total += v;
      known++;
    }
  }
  return NutrientTotal(known == 0 ? null : total, known, unknown);
}

/// How much of a day's eating we can honestly claim to have seen.
enum DayLogState {
  /// Nothing logged.
  none,

  /// Today, still in progress. Neither complete nor partial — a day cannot be
  /// judged incomplete while it is still happening.
  inProgress,

  /// Logged, but with a gap we can detect: an unknown energy value, or no
  /// occasion in the evening. EXCLUDED from every derived average, and the UI
  /// says so.
  partial,

  /// Every occasion carries energy and the day's span reaches the evening.
  complete,
}

/// The hour after which a finished day is taken to have been logged through to
/// the end. A calibration knob, not a physiological claim: shift-workers and
/// early eaters will trip it, which is exactly why the UI states the rule
/// rather than hiding it.
const int kEveningLogHour = 17;

/// One day, rolled up. Built by [rollupDay] — never by the UI.
class NutritionDay {
  const NutritionDay({
    required this.date,
    required this.entries,
    required this.state,
    required this.kcal,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.fibre,
  });

  final String date;
  final List<FoodEntry> entries;
  final DayLogState state;
  final NutrientTotal kcal, protein, carbs, fat, fibre;

  bool get logged => entries.isNotEmpty;

  /// Only a complete day may move an average. A partial day left in would
  /// drag every mean down by exactly the meals we failed to see.
  bool get countsTowardAverages => state == DayLogState.complete;

  List<FoodEntry> mealEntries(String meal) => [
    for (final e in entries)
      if (e.meal == meal) e,
  ];
}

/// Roll a day up. [today] is the local day label of the current day, so
/// "in progress" is decided by the caller's clock and never by a hidden one.
NutritionDay rollupDay(
  String date,
  List<FoodEntry> entries, {
  required String today,
}) {
  final kcal = _sum(entries, (e) => e.kcal);
  final state = dayLogState(date, entries, today: today, kcal: kcal);
  return NutritionDay(
    date: date,
    entries: entries,
    state: state,
    kcal: kcal,
    protein: _sum(entries, (e) => e.proteinG),
    carbs: _sum(entries, (e) => e.carbsG),
    fat: _sum(entries, (e) => e.fatG),
    fibre: _sum(entries, (e) => e.fibreG),
  );
}

/// Partial-day detection. Automatic and never a checkbox — a user who has to
/// tick "I didn't log everything" will not, and every average silently rots.
DayLogState dayLogState(
  String date,
  List<FoodEntry> entries, {
  required String today,
  NutrientTotal? kcal,
}) {
  if (entries.isEmpty) return DayLogState.none;
  if (date == today) return DayLogState.inProgress;
  final energy = kcal ?? _sum(entries, (e) => e.kcal);
  if (!energy.complete) return DayLogState.partial;
  final spanned = entries.any((e) {
    final ts = e.atTs;
    if (ts == null) return false;
    final at = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    return dayLabelOf(at) == date && at.hour >= kEveningLogHour;
  });
  return spanned ? DayLogState.complete : DayLogState.partial;
}

/// One nutrient averaged across a window, with what was left out of it.
/// [value] null is an absence with a reason attached, never a zero: either no
/// counted day reported the nutrient at all ([floorDays] 0), or every one that
/// did reported only a floor.
class NutrientMean {
  const NutrientMean(this.value, this.days, this.floorDays);

  /// The mean of [days] COMPLETE totals, or null when there were none.
  final double? value;

  /// How many counted days reported this nutrient on every occasion. This is
  /// the denominator the screen must name — it can be smaller than the number
  /// of counted days, which is the whole point.
  final int days;

  /// Counted days whose total was a floor, so excluded. Averaging a floor
  /// understates the mean by exactly the occasions we failed to see.
  final int floorDays;
}

/// A rolling window. Daily is the detail view; THIS is the hero — one day of
/// intake is noise, seven is a habit.
class NutritionWindow {
  const NutritionWindow(this.days);
  final List<NutritionDay> days;

  int get span => days.length;
  int get daysLogged => days.where((d) => d.logged).length;
  List<NutritionDay> get counted => [
    for (final d in days)
      if (d.countsTowardAverages) d,
  ];

  /// Days that were logged but had to be excluded. Named on screen, because
  /// an average quietly computed over four of seven days is a lie of omission.
  int get daysExcluded =>
      days.where((d) => d.logged && !d.countsTowardAverages).length;

  /// One nutrient's mean over the counted days, gated PER NUTRIENT.
  ///
  /// [NutritionDay.countsTowardAverages] is an ENERGY rule: a day qualifies on
  /// complete kcal and an evening occasion, and says nothing about protein. So
  /// this used to admit any non-null total — including one that summed past
  /// occasions carrying no macro figure, i.e. a FLOOR — and print it as a mean
  /// with no marker. Only [NutrientTotal.complete] totals go in; the floors are
  /// counted so the screen can say why the number is missing or built on fewer
  /// days than the energy mean.
  NutrientMean _mean(NutrientTotal Function(NutritionDay) pick) {
    final vs = <double>[];
    var floorDays = 0;
    for (final d in counted) {
      final t = pick(d);
      if (t.complete) {
        vs.add(t.value!);
      } else if (t.isFloor) {
        floorDays++;
      }
    }
    return NutrientMean(
      vs.isEmpty ? null : vs.reduce((a, b) => a + b) / vs.length,
      vs.length,
      floorDays,
    );
  }

  /// Energy is unchanged by the per-nutrient gate — a counted day already has
  /// `kcal.complete` by definition of [DayLogState.complete] — but it goes
  /// through the same path so there is one mean, not two.
  NutrientMean get meanKcal => _mean((d) => d.kcal);
  NutrientMean get meanProtein => _mean((d) => d.protein);
  NutrientMean get meanCarbs => _mean((d) => d.carbs);
  NutrientMean get meanFat => _mean((d) => d.fat);
  NutrientMean get meanFibre => _mean((d) => d.fibre);
}

// ══════════════════ STORE ══════════════════

class NutritionDb {
  NutritionDb._();

  /// Committed food changes, independent of the live heart-rate notifier.
  static final revision = ValueNotifier<int>(0);
  static void changed() => revision.value++;

  static String newId() => 'f${DateTime.now().microsecondsSinceEpoch}';

  /// Write one entry. [FoodEntry.sanitised] runs HERE rather than in the UI:
  /// a photo estimate must not be able to reach the table with a calorie
  /// total no matter which screen wrote it.
  static Future<void> put(
    DatabaseExecutor db,
    FoodEntry e, {
    bool notify = true,
  }) async {
    // A replace would drop the entry's dragged position; carry it over.
    final kept = await db.query(
      'food_entry',
      columns: ['pos'],
      where: 'id = ?',
      whereArgs: [e.id],
      limit: 1,
    );
    await db.insert('food_entry', {
      ...e.sanitised.toRow(DateTime.now().millisecondsSinceEpoch),
      if (kept.isNotEmpty) 'pos': kept.first['pos'],
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    if (notify) changed();
  }

  /// Save the order of entries the user dragged inside one meal/sub-heading.
  static Future<void> reorderEntries(Database db, List<String> ids) async {
    await db.transaction((tx) async {
      for (var i = 0; i < ids.length; i++) {
        await tx.update(
          'food_entry',
          {'pos': i},
          where: 'id = ?',
          whereArgs: [ids[i]],
        );
      }
    });
    changed();
  }

  static Future<void> delete(Database db, String id) async {
    await db.delete('food_entry', where: 'id = ?', whereArgs: [id]);
    changed();
  }

  static Future<List<FoodEntry>> entriesForDay(Database db, String date) async {
    final rows = await db.query(
      'food_entry',
      where: 'date = ?',
      whereArgs: [date],
      orderBy: 'pos IS NULL, pos ASC, at_ts ASC, created_at ASC',
    );
    return [for (final r in rows) FoodEntry.fromRow(r)];
  }

  /// Every entry on or after [sinceDate], grouped by day label. Lexicographic
  /// range, matching every other day-keyed table.
  static Future<Map<String, List<FoodEntry>>> entriesSince(
    Database db,
    String sinceDate,
  ) async {
    final rows = await db.query(
      'food_entry',
      where: 'date >= ?',
      whereArgs: [sinceDate],
      orderBy: 'date ASC, at_ts ASC',
    );
    final out = <String, List<FoodEntry>>{};
    for (final r in rows) {
      final e = FoodEntry.fromRow(r);
      (out[e.date] ??= []).add(e);
    }
    return out;
  }

  /// The last distinct things eaten, newest first. This is what makes a repeat
  /// entry a two-second job, and it is why there is no need for a "favourites"
  /// concept on top.
  static Future<List<FoodEntry>> recent(Database db, {int limit = 12}) async {
    final rows = await db.rawQuery(
      'SELECT * FROM food_entry WHERE id IN '
      '(SELECT MAX(id) FROM food_entry GROUP BY label) '
      'ORDER BY created_at DESC LIMIT ?',
      [limit],
    );
    return [for (final r in rows) FoodEntry.fromRow(r)];
  }

  /// Search the dictionary, VERIFIED entries first. Ranking is provenance then
  /// alphabetical — never popularity.
  static Future<List<Map<String, Object?>>> searchFoods(
    Database db,
    String query, {
    int limit = 25,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    return db.rawQuery(
      "SELECT * FROM food_def WHERE label LIKE ? OR brand LIKE ? "
      "ORDER BY (source = 'verified') DESC, label ASC LIMIT ?",
      ['%$q%', '%$q%', limit],
    );
  }

  /// One dictionary entry by key. The key for a scanned product is its
  /// barcode, which makes this table the barcode cache — a second scan of the
  /// same packet is a local read and no network request at all.
  static Future<Map<String, Object?>?> foodDef(
    DatabaseExecutor db,
    String key,
  ) async {
    final rows = await db.query(
      'food_def',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  static Future<void> putFoodDef(Database db, Map<String, Object?> def) async {
    // A replace rewrites the whole row: keep the saved position and measures
    // unless this write sets them. A new food goes to the top of the list.
    final old = await db.query(
      'food_def',
      columns: ['pos', 'measures_json', 'category'],
      where: 'key = ?',
      whereArgs: [def['key']],
      limit: 1,
    );
    int? pos;
    if (old.isNotEmpty) {
      pos = (old.first['pos'] as num?)?.toInt();
    } else {
      final top = await db.rawQuery('SELECT MIN(pos) AS p FROM food_def');
      pos = ((top.first['p'] as num?)?.toInt() ?? 0) - 1;
    }
    await db.insert('food_def', {
      ...def,
      'pos': def['pos'] ?? pos,
      'measures_json':
          def['measures_json'] ??
          (old.isEmpty ? '' : old.first['measures_json'] ?? ''),
      'category':
          def['category'] ??
          (old.isEmpty ? '' : old.first['category'] ?? ''),
      'created_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    changed();
  }

  /// Only months with retained entries, plus this month even when empty.
  static Future<List<String>> historyMonths(
    Database db, {
    DateTime? now,
  }) async {
    final current = dayLabelOf(now ?? DateTime.now()).substring(0, 7);
    final rows = await db.rawQuery(
      'SELECT DISTINCT substr(date, 1, 7) AS month FROM food_entry '
      'WHERE date <= ? ORDER BY month DESC',
      [dayLabelOf(now ?? DateTime.now())],
    );
    return {current, for (final r in rows) r['month'] as String}.toList()
      ..sort((a, b) => b.compareTo(a));
  }

  /// A calendar month, bounded by today, without reading all older history.
  static Future<NutritionWindow> month(
    Database db,
    String month, {
    DateTime? now,
  }) async {
    final start = DateTime.parse('$month-01');
    final next = DateTime(start.year, start.month + 1);
    final today = dayLabelOf(now ?? DateTime.now());
    final rows = await db.query(
      'food_entry',
      where: 'date >= ? AND date < ?',
      whereArgs: [dayLabelOf(start), dayLabelOf(next)],
      orderBy: 'date ASC, at_ts ASC',
    );
    final byDay = <String, List<FoodEntry>>{};
    for (final row in rows) {
      final e = FoodEntry.fromRow(row);
      (byDay[e.date] ??= []).add(e);
    }
    return NutritionWindow([
      for (
        var d = start;
        d.isBefore(next) && dayLabelOf(d).compareTo(today) <= 0;
        d = DateTime(d.year, d.month, d.day + 1)
      )
        rollupDay(
          dayLabelOf(d),
          byDay[dayLabelOf(d)] ?? const [],
          today: today,
        ),
    ]);
  }

  /// Copy every entry of [fromMeal] on [fromDate] into [toMeal] on [toDate]
  /// (MyFitnessPal's "copy from" / "copy to"). Returns how many were copied.
  static Future<int> copyMeal(
    Database db, {
    required String fromDate,
    required String fromMeal,
    required String toDate,
    required String toMeal,
  }) async {
    final src = [
      for (final e in await entriesForDay(db, fromDate))
        if (e.meal == fromMeal) e,
    ];
    await db.transaction((tx) async {
      var i = 0;
      for (final e in src) {
        await put(
          tx,
          e.copyTo(toDate, toMeal, newId: '${newId()}_${i++}'),
          notify: false,
        );
      }
    });
    if (src.isNotEmpty) changed();
    return src.length;
  }

  /// Foods most often logged in the same day and meal as [foodKey], most
  /// frequent first (the "often eaten with" row). Only the user's own foods,
  /// never [foodKey] itself.
  static Future<List<Map<String, Object?>>> eatenWith(
    Database db,
    String foodKey, {
    int limit = 5,
  }) async {
    // Portions may be in any of a food's units now; average them in label
    // units, skipping any whose unit the food no longer converts.
    final rows = await db.rawQuery(
      'SELECT d.*, o.quantity AS q, o.unit AS u FROM food_entry a '
      'JOIN food_entry o ON o.date = a.date AND o.meal = a.meal '
      'AND o.food_key IS NOT NULL AND o.food_key != a.food_key '
      'JOIN food_def d ON d.key = o.food_key WHERE a.food_key = ?',
      [foodKey],
    );
    final by = <String, ({Map<String, Object?> def, int n, List<double> base})>{};
    for (final r in rows) {
      final key = r['key'] as String;
      final def = {...r}..remove('q')..remove('u');
      final q = (r['q'] as num?)?.toDouble();
      final b = q == null ? null : toBase(def, q, (r['u'] as String?) ?? 'g');
      final prev = by[key];
      by[key] = (
        def: prev?.def ?? def,
        n: (prev?.n ?? 0) + 1,
        base: [...?prev?.base, ?b],
      );
    }
    final out = by.values.toList()
      ..sort((a, b) {
        final c = b.n.compareTo(a.n);
        return c != 0
            ? c
            : '${a.def['label']}'.compareTo('${b.def['label']}');
      });
    return [
      for (final e in out.take(limit))
        {
          ...e.def,
          'n': e.n,
          'usual_g': e.base.isEmpty
              ? null
              : e.base.reduce((a, b) => a + b) / e.base.length,
        },
    ];
  }

  /// How much of [foodKey] was logged last time, in label units, for a
  /// one-tap re-log. Any unit the food still converts counts.
  static Future<double?> lastGrams(Database db, String foodKey) async {
    final last = await lastPortion(db, foodKey);
    return last?.base;
  }

  /// The last portion of [foodKey] as it was entered ("3 links"), with its
  /// label-unit amount; null when never logged in a unit it still converts.
  static Future<({double amount, String unit, double base})?> lastPortion(
    Database db,
    String foodKey,
  ) async {
    final def = await foodDef(db, foodKey);
    if (def == null) return null;
    final rows = await db.rawQuery(
      'SELECT quantity, unit FROM food_entry WHERE food_key = ? '
      'AND quantity IS NOT NULL ORDER BY created_at DESC LIMIT 5',
      [foodKey],
    );
    for (final r in rows) {
      final q = (r['quantity'] as num?)?.toDouble();
      final u = (r['unit'] as String?) ?? 'g';
      if (q == null) continue;
      final base = toBase(def, q, u);
      if (base != null) return (amount: q, unit: u, base: base);
    }
    return null;
  }

  /// The trailing [days] days ending today, oldest first, already rolled up.
  static Future<NutritionWindow> window(
    Database db, {
    int days = 7,
    DateTime? now,
  }) async {
    final end = now ?? DateTime.now();
    final today = dayLabelOf(end);
    final labels = [
      for (var i = days - 1; i >= 0; i--)
        dayLabelOf(DateTime(end.year, end.month, end.day - i)),
    ];
    final byDay = await entriesSince(db, labels.first);
    return NutritionWindow([
      for (final l in labels) rollupDay(l, byDay[l] ?? const [], today: today),
    ]);
  }
}

// ══════════════════ MY FOODS & SAVED MEALS ══════════════════

/// Nutrients for [grams] of a `food_def` row (stored per 100 g). A field the
/// food never had stays null — scaling cannot invent one.
({double? kcal, double? protein, double? carbs, double? fat, double? fibre})
nutrientsFor(Map<String, Object?> def, double grams) {
  double? at(String k) {
    final v = (def[k] as num?)?.toDouble();
    if (v == null || !v.isFinite || v < 0 || !grams.isFinite || grams < 0) {
      return null;
    }
    final total = v * grams / 100;
    return total.isFinite ? total : null;
  }

  return (
    kcal: at('kcal_100'),
    protein: at('protein_g_100'),
    carbs: at('carbs_g_100'),
    fat: at('fat_g_100'),
    fibre: at('fibre_g_100'),
  );
}

/// A `food_def` row from label numbers as the user reads them: "50 g of oats
/// is 200 kcal, 6.5 g protein, 33 g carbs". Stored per 100 g so any later
/// portion scales from it.
Map<String, Object?> myFoodDef({
  required String key,
  required String label,
  required double refGrams,
  String unit = 'g',
  double? kcal,
  double? protein,
  double? carbs,
  double? fat,
  double? fibre,
  List<FoodMeasure>? measures,
  Map<String, double> measureCounts = const {},
  String? category,
}) {
  if (!refGrams.isFinite || refGrams <= 0) {
    throw ArgumentError('Serving amount must be positive.');
  }
  double? per100(double? v) {
    if (v == null) return null;
    if (!v.isFinite || v < 0) {
      throw ArgumentError('Nutrition must be a non-negative number.');
    }
    return v * 100 / refGrams;
  }

  return {
    'key': key,
    'label': label,
    'serving_g': refGrams,
    'unit': unit.trim().isEmpty ? 'g' : unit.trim(),
    'kcal_100': per100(kcal),
    'protein_g_100': per100(protein),
    'carbs_g_100': per100(carbs),
    'fat_g_100': per100(fat),
    'fibre_g_100': per100(fibre),
    'source': 'manual',
    if (measures != null)
      'measures_json': encodeMeasures(measures, counts: measureCounts),
    if (category != null) 'category': category.trim(),
  };
}

/// The categories a food can be filed under (build 85). Plain names, one per
/// food; a food with none is "Uncategorised".
const List<String> kFoodCategories = [
  'Fruits',
  'Vegetables',
  'Protein',
  'Dairy & eggs',
  'Grains & bread',
  'Snacks & sweets',
  'Drinks',
  'Supplements',
  'Meals & dishes',
];

/// The filter name for foods with no category.
const String kUncategorised = 'Uncategorised';

/// A food's category, or [kUncategorised].
String foodCategory(Map<String, Object?> def) {
  final c = (def['category'] ?? '').toString().trim();
  return c.isEmpty ? kUncategorised : c;
}

/// The categories present among [defs], in [kFoodCategories] order, with
/// uncategorised last. The filter shows only these.
List<String> foodCategoriesIn(Iterable<Map<String, Object?>> defs) {
  final present = {for (final d in defs) foodCategory(d)};
  return [
    for (final c in kFoodCategories)
      if (present.contains(c)) c,
    for (final c in present)
      if (!kFoodCategories.contains(c) && c != kUncategorised) c,
    if (present.contains(kUncategorised)) kUncategorised,
  ];
}

/// A named household measure of a food and what it weighs: "scoop = 29 g".
/// For understanding only — portions are still entered and scaled in the
/// food's own unit (grams for a weighed food).
typedef FoodMeasure = ({String label, double amount});

/// At most two, as stored; a damaged value reads as none. A name typed with
/// its count ("1 scoop", "2 scoops") reads as the single measure, so a chip
/// never says "1 1 scoop".
List<FoodMeasure> foodMeasures(Map<String, Object?> def) {
  final raw = def['measures_json'];
  if (raw is! String || raw.isEmpty) return const [];
  FoodMeasure single(String label, double amount) {
    final m = RegExp(r'^(\d+(?:\.\d+)?)\s+(.+)$').firstMatch(label);
    final n = m == null ? 0.0 : double.parse(m.group(1)!);
    if (m == null || n <= 0) return (label: label, amount: amount);
    final name = m.group(2)!;
    return (
      label: n != 1 && name.length > 1 && name.endsWith('s')
          ? name.substring(0, name.length - 1)
          : name,
      amount: amount / n,
    );
  }

  try {
    return [
      for (final m in jsonDecode(raw) as List)
        if (m is Map &&
            m['l'] is String &&
            (m['l'] as String).trim().isNotEmpty &&
            m['a'] is num &&
            (m['a'] as num) > 0)
          single((m['l'] as String).trim(), (m['a'] as num).toDouble()),
    ].take(2).toList();
  } catch (_) {
    return const [];
  }
}

/// Every unit [def] can be logged in: its label unit first, then its other
/// units (a measure's name), without duplicates. "link" and "Link" are one.
List<String> foodUnitNames(Map<String, Object?> def) {
  final out = [foodUnit(def)];
  for (final m in foodMeasures(def)) {
    if (!out.any((u) => u.toLowerCase() == m.label.toLowerCase())) {
      out.add(m.label);
    }
  }
  return out;
}

/// How many label units one [unit] is, or null when [def] has no conversion
/// for it. A food labelled per link with "1 link = 71 g" stores grams as a
/// measure of 1/71 link, so both directions resolve here.
double? unitInBase(Map<String, Object?> def, String unit) {
  final u = unit.trim().toLowerCase();
  if (u == foodUnit(def).toLowerCase()) return 1;
  for (final m in foodMeasures(def)) {
    if (m.label.toLowerCase() == u) return m.amount;
  }
  return null;
}

/// [amount] of [unit] in label units, or null without a conversion.
double? toBase(Map<String, Object?> def, double amount, String unit) {
  final f = unitInBase(def, unit);
  return f == null ? null : amount * f;
}

/// "3 links · 213 g": the logged portion with its weight when the food knows
/// one and the portion was not already logged by weight.
String portionWithWeight(
  num amount,
  String unit,
  Map<String, Object?>? def,
) {
  final shown = portionText(amount, unit);
  final u = unit.toLowerCase();
  if (def == null || u == 'g' || u == 'ml') return shown;
  final base = toBase(def, amount.toDouble(), unit);
  if (base == null) return shown;
  for (final w in const ['g', 'ml']) {
    final per = unitInBase(def, w);
    if (per != null && per > 0) {
      return '$shown · ${portionText((base / per).roundToDouble(), w)}';
    }
  }
  return shown;
}

/// [counts] keeps how a unit was typed off the label ("6 pieces = 85 g" is
/// stored as one piece of 85/6 g plus n: 6), so the editor shows it back as
/// typed. Conversions never read it.
String encodeMeasures(
  List<FoodMeasure> ms, {
  Map<String, double> counts = const {},
}) => ms.isEmpty
    ? ''
    : jsonEncode([
        for (final m in ms.take(2))
          {
            'l': m.label,
            'a': m.amount,
            if ((counts[m.label] ?? 1) != 1) 'n': counts[m.label],
          },
      ]);

/// The count each unit was typed with ("6" of "6 pieces = 85 g"), by name;
/// a unit typed as one is absent.
Map<String, double> measureCounts(Map<String, Object?> def) {
  final raw = def['measures_json'];
  if (raw is! String || raw.isEmpty) return const {};
  try {
    return {
      for (final m in jsonDecode(raw) as List)
        if (m is Map &&
            m['l'] is String &&
            m['n'] is num &&
            (m['n'] as num) > 0)
          (m['l'] as String).trim(): (m['n'] as num).toDouble(),
    };
  } catch (_) {
    return const {};
  }
}

/// "6 pieces (85 g)" as a pack prints its serving: the count, the unit named
/// once ("piece") and the weight. Null for anything else ("85 g", "1 cup").
({double count, String name, double grams})? servingCountOf(String label) {
  final m = RegExp(
    r'^\s*(\d+(?:\.\d+)?)\s+([A-Za-z][A-Za-z ]*?)\s*\(\s*(\d+(?:\.\d+)?)\s*g\s*\)\s*$',
  ).firstMatch(label);
  if (m == null) return null;
  final count = double.parse(m.group(1)!);
  final grams = double.parse(m.group(3)!);
  var name = m.group(2)!.trim().toLowerCase();
  if (count <= 0 ||
      grams <= 0 ||
      const {'g', 'gram', 'grams', 'ml'}.contains(name)) {
    return null;
  }
  if (count != 1 && name.length > 1 && name.endsWith('s')) {
    name = name.substring(0, name.length - 1);
  }
  return (count: count, name: name, grams: grams);
}

/// A food logged at [grams] into [meal] on [date].
/// [grams] is the amount in the food's label unit; nutrients scale from it.
/// [amount]/[unit], when given, are what the diary shows ("3 links") — the
/// portion as it was entered, in any of the food's units.
FoodEntry entryFromFood(
  Map<String, Object?> def,
  double grams, {
  required String id,
  required String date,
  required String meal,
  int? atTs,
  double? amount,
  String? unit,
}) {
  final n = nutrientsFor(def, grams);
  return FoodEntry(
    id: id,
    date: date,
    meal: meal,
    label: (def['label'] ?? '').toString(),
    atTs: atTs,
    foodKey: def['key']?.toString(),
    quantity: amount ?? grams,
    unit: unit ?? foodUnit(def),
    kcal: n.kcal,
    proteinG: n.protein,
    carbsG: n.carbs,
    fatG: n.fat,
    fibreG: n.fibre,
    source: FoodSource.repeat,
    confirmed: true,
  );
}

class MealTemplate {
  const MealTemplate({
    required this.key,
    required this.label,
    required this.meal,
    required this.items,
    this.units = const {},
    this.groups = const [],
  });

  final String key, label, meal;
  final Map<String, String> units;

  /// (food_def key, grams), in the user's order.
  final List<(String, double)> items;

  /// The sub-heading of each item ("Oatmeal", "Eggs and Sausage"), aligned
  /// with [items]; '' for none. Templates saved before sub-headings were kept
  /// have none.
  final List<String> groups;

  String groupAt(int i) => i < groups.length ? groups[i] : '';
  bool get hasGroups => groups.any((g) => g.isNotEmpty);

  Map<String, Object?> toRow(int nowMs) => {
    'key': key,
    'label': label,
    'meal': meal,
    'items_json': jsonEncode([
      for (final (i, (f, g)) in items.indexed)
        {
          'food': f,
          'g': g,
          'unit': units[f] ?? 'g',
          if (groupAt(i).isNotEmpty) 'grp': groupAt(i),
        },
    ]),
    'created_at': nowMs,
  };

  static MealTemplate fromRow(Map<String, Object?> r) {
    final items = <(String, double)>[];
    final units = <String, String>{};
    final groups = <String>[];
    try {
      for (final e in (jsonDecode(r['items_json'] as String) as List)) {
        if (e is Map && e['food'] is String && e['g'] is num) {
          items.add((e['food'] as String, (e['g'] as num).toDouble()));
          units[e['food'] as String] = e['unit'] is String
              ? e['unit'] as String
              : 'g';
          groups.add(e['grp'] is String ? e['grp'] as String : '');
        }
      }
    } catch (_) {
      /* a damaged row logs nothing rather than crashing */
    }
    return MealTemplate(
      key: r['key'] as String,
      label: (r['label'] ?? '').toString(),
      meal: (r['meal'] ?? 'snack').toString(),
      items: items,
      units: units,
      groups: groups,
    );
  }
}

class MyFoods {
  MyFoods._();

  /// Every food the user can pick, in the order Akshat dragged them into
  /// (shared by Food → Foods and every log screen). Foods without a position
  /// yet follow, most recently eaten first.
  static Future<List<Map<String, Object?>>> all(Database db) => db.rawQuery(
    'SELECT d.* FROM food_def d '
    'LEFT JOIN (SELECT food_key, MAX(created_at) AS last FROM food_entry '
    'GROUP BY food_key) e ON e.food_key = d.key '
    'ORDER BY d.pos IS NULL, d.pos ASC, e.last IS NULL, e.last DESC, '
    'd.label COLLATE NOCASE ASC',
  );

  /// Save a dragged order of foods: position = index.
  static Future<void> reorderFoods(Database db, List<String> keys) =>
      _reorder(db, 'food_def', keys);

  /// Save a dragged order of saved meals.
  static Future<void> reorderMeals(Database db, List<String> keys) =>
      _reorder(db, 'meal_template', keys);

  static Future<void> _reorder(
    Database db,
    String table,
    List<String> keys,
  ) async {
    await db.transaction((tx) async {
      for (var i = 0; i < keys.length; i++) {
        await tx.update(
          table,
          {'pos': i},
          where: 'key = ?',
          whereArgs: [keys[i]],
        );
      }
    });
    NutritionDb.changed();
  }

  static Future<void> deleteFood(Database db, String key) async {
    await db.delete('food_def', where: 'key = ?', whereArgs: [key]);
    NutritionDb.changed();
  }

  static Future<List<MealTemplate>> meals(Database db) async {
    final rows = await db.query(
      'meal_template',
      orderBy: 'pos IS NULL, pos ASC, label COLLATE NOCASE ASC',
    );
    return [for (final r in rows) MealTemplate.fromRow(r)];
  }

  static Future<void> putMeal(Database db, MealTemplate m) async {
    // Keep an edited meal's place; a new one goes to the top.
    final old = await db.query(
      'meal_template',
      columns: ['pos'],
      where: 'key = ?',
      whereArgs: [m.key],
      limit: 1,
    );
    final int pos;
    if (old.isNotEmpty) {
      pos = (old.first['pos'] as num?)?.toInt() ?? 0;
    } else {
      final top = await db.rawQuery('SELECT MIN(pos) AS p FROM meal_template');
      pos = ((top.first['p'] as num?)?.toInt() ?? 0) - 1;
    }
    await db.insert('meal_template', {
      ...m.toRow(DateTime.now().millisecondsSinceEpoch),
      'pos': pos,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    NutritionDb.changed();
  }

  static Future<void> deleteMeal(Database db, String key) async {
    await db.delete('meal_template', where: 'key = ?', whereArgs: [key]);
    NutritionDb.changed();
  }

  /// A saved meal from the entries of one meal. Only the user's own foods
  /// (entries with a food key and grams) can go into a saved meal; the rest
  /// are counted so the screen can say they were left out.
  static Future<({int saved, int skipped})> saveMeal(
    Database db, {
    required String label,
    required String meal,
    required List<FoodEntry> entries,
  }) async {
    final kept = [
      for (final e in entries)
        if (e.foodKey != null && e.quantity != null) e,
    ];
    // A saved meal keeps ONE unit per food. The first entry of a food sets
    // it; a later entry of the same food logged in another unit ("50 g" after
    // "2 eggs") is converted into it, not stored as 50 eggs.
    final units = <String, String>{};
    final items = <(String, double)>[];
    for (final e in kept) {
      final key = e.foodKey!;
      final unit = units.putIfAbsent(key, () => e.unit);
      var amount = e.quantity!;
      if (unit.toLowerCase() != e.unit.toLowerCase()) {
        final def = await NutritionDb.foodDef(db, key);
        final base = def == null ? null : toBase(def, amount, e.unit);
        final per = def == null ? null : unitInBase(def, unit);
        if (base != null && per != null && per > 0) amount = base / per;
      }
      items.add((key, amount));
    }
    if (items.isNotEmpty) {
      await putMeal(
        db,
        MealTemplate(
          key: 'meal:${DateTime.now().microsecondsSinceEpoch}',
          label: label,
          meal: meal,
          items: items,
          units: units,
          // Sub-headings travel with the saved meal.
          groups: [for (final e in kept) e.group],
        ),
      );
    }
    return (saved: items.length, skipped: entries.length - items.length);
  }

  /// Log every item of [m] into [meal] on [date]. Each item keeps its saved
  /// sub-heading; an item without one goes under [group] when given, or, for
  /// an old template with no sub-headings at all, under the meal's name.
  /// [amounts], aligned with the items, replaces each saved amount after the
  /// review screen; a null there leaves that item out. Items whose food was
  /// since deleted are skipped. Returns how many entries were written.
  static Future<int> logMeal(
    Database db,
    MealTemplate m,
    String date,
    String meal, {
    DateTime? now,
    String? group,
    List<double?>? amounts,
    List<String>? units,
  }) async {
    var n = 0;
    final at = foodEntryTime(date, meal, now: now);
    await db.transaction((tx) async {
      for (final (i, (key, saved)) in m.items.indexed) {
        final grams = amounts == null
            ? saved
            : (i < amounts.length ? amounts[i] : saved);
        if (grams == null || !grams.isFinite || grams <= 0) continue;
        final def = await NutritionDb.foodDef(tx, key);
        if (def == null) continue;
        // A saved amount may be in any of the food's units ("2 links"); it is
        // converted, and only a unit the food no longer knows is refused.
        final unit = units != null && i < units.length
            ? units[i]
            : (m.units[key] ?? 'g');
        final base = toBase(def, grams, unit);
        if (base == null) {
          throw StateError(
            'The unit of ${def['label']} changed. Edit this saved meal before logging it.',
          );
        }
        await NutritionDb.put(
          tx,
          entryFromFood(
            def,
            base,
            id: '${NutritionDb.newId()}_$n',
            date: date,
            meal: meal,
            atTs: at.millisecondsSinceEpoch ~/ 1000,
            amount: grams,
            unit: unit,
          ).inGroup(
            m.groupAt(i).isNotEmpty
                ? m.groupAt(i)
                : (group ?? (m.hasGroups ? '' : m.label)),
          ),
          notify: false,
        );
        n++;
      }
    });
    if (n > 0) NutritionDb.changed();
    return n;
  }
}

// ══════════════════ BODY WEIGHT ══════════════════

class BodyWeight {
  BodyWeight._();

  /// Record today's (or [date]'s) weight; a second reading the same day
  /// replaces the first.
  static Future<void> put(Database db, String date, double kg) async {
    if (!kg.isFinite || kg <= 0 || kg > 500) {
      throw ArgumentError.value(kg, 'kg', 'Enter a valid weight');
    }
    await db.insert('body_weight', {
      'date': date,
      'kg': kg,
      'at_ts': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    NutritionDb.changed();
  }

  static Future<void> delete(Database db, String date) async {
    await db.delete('body_weight', where: 'date = ?', whereArgs: [date]);
    NutritionDb.changed();
  }

  /// Every reading on or after [sinceDate], oldest first.
  static Future<List<({String date, double kg})>> since(
    Database db,
    String sinceDate,
  ) async {
    final rows = await db.query(
      'body_weight',
      where: 'date >= ?',
      whereArgs: [sinceDate],
      orderBy: 'date ASC',
    );
    return [
      for (final r in rows)
        (date: r['date'] as String, kg: (r['kg'] as num).toDouble()),
    ];
  }
}

/// Dated, completed food coverage between morning weigh-ins [first,last).
({int complete, int days}) maintenanceFoodCoverage(
  List<({String date, double kg})> weights,
  List<NutritionDay> days,
) {
  if (weights.length < 2) return (complete: 0, days: 0);
  final ordered = [...weights]..sort((a, b) => a.date.compareTo(b.date));
  final from = DateTime.parse(ordered.first.date),
      to = DateTime.parse(ordered.last.date);
  final n = DateTime.utc(
    to.year,
    to.month,
    to.day,
  ).difference(DateTime.utc(from.year, from.month, from.day)).inDays;
  final complete = days
      .where(
        (d) =>
            d.date.compareTo(ordered.first.date) >= 0 &&
            d.date.compareTo(ordered.last.date) < 0 &&
            d.countsTowardAverages,
      )
      .map((d) => d.date)
      .toSet()
      .length;
  return (complete: complete, days: n);
}

/// Food and weight estimate, withheld if ANY aligned food day is incomplete.
/// The fixed tissue-energy conversion remains an approximation, not a measure.
({double kcal, double kgPerWeek, int days, int weighIns, int loggedDays})?
estimatedMaintenance(
  List<({String date, double kg})> weights,
  List<NutritionDay> days,
) {
  final ordered = [...weights]..sort((a, b) => a.date.compareTo(b.date));
  final coverage = maintenanceFoodCoverage(ordered, days);
  if (coverage.days < 14 || coverage.complete != coverage.days) return null;
  final byDay = {for (final d in days) d.date: d};
  final kcal = <double>[];
  for (
    var d = DateTime.parse(ordered.first.date);
    dayLabelOf(d).compareTo(ordered.last.date) < 0;
    d = DateTime(d.year, d.month, d.day + 1)
  ) {
    final food = byDay[dayLabelOf(d)];
    if (food == null || !food.countsTowardAverages || food.kcal.value == null) {
      return null;
    }
    kcal.add(food.kcal.value!);
  }
  return measuredMaintenance(
    ordered,
    kcal,
    minDays: 15,
    minLoggedDays: coverage.days,
  );
}

/// Kilocalories in a kilogram of body-weight change. The common 7,700
/// (3,500 kcal per pound) is a fat-tissue figure; early changes include water,
/// which is why the measured maintenance needs weeks, not days.
const double kKcalPerKg = 7700;

/// The 7-day trailing mean of [weights] (by date), one value per reading:
/// the trend line that smooths out water swings.
List<({String date, double kg})> weightTrend(
  List<({String date, double kg})> weights,
) {
  final out = <({String date, double kg})>[];
  for (var i = 0; i < weights.length; i++) {
    final end = DateTime.parse(weights[i].date);
    final from = DateTime(end.year, end.month, end.day - 6);
    final win = [
      for (var j = 0; j <= i; j++)
        if (!DateTime.parse(weights[j].date).isBefore(from)) weights[j].kg,
    ];
    out.add((
      date: weights[i].date,
      kg: win.reduce((a, b) => a + b) / win.length,
    ));
  }
  return out;
}

/// Maintenance MEASURED from the scale: average food eaten minus the energy
/// the trend weight change accounts for, over a window of at least
/// [minDays] days with at least [minWeighIns] weigh-ins and [minLoggedDays]
/// days of food. The weight change is the least-squares slope of all
/// readings in the window (kg a day), which no single water swing moves much.
///
/// [eaten] is kcal per COMPLETE logged day in the same window. Null when
/// there is not enough of either.
({double kcal, double kgPerWeek, int days, int weighIns, int loggedDays})?
measuredMaintenance(
  List<({String date, double kg})> weights,
  List<double> eaten, {
  int minDays = 14,
  int minWeighIns = 8,
  int minLoggedDays = 10,
}) {
  if (weights.length < minWeighIns ||
      eaten.length < minLoggedDays ||
      weights.any((w) => !w.kg.isFinite || w.kg <= 0) ||
      eaten.any((k) => !k.isFinite || k < 0)) {
    return null;
  }
  final t0 = DateTime.parse(weights.first.date);
  final xs = [
    for (final w in weights)
      DateTime.utc(
        DateTime.parse(w.date).year,
        DateTime.parse(w.date).month,
        DateTime.parse(w.date).day,
      ).difference(DateTime.utc(t0.year, t0.month, t0.day)).inDays.toDouble(),
  ];
  final span = xs.last - xs.first;
  if (span < minDays - 1) return null;
  final ys = [for (final w in weights) w.kg];
  final mx = xs.reduce((a, b) => a + b) / xs.length;
  final my = ys.reduce((a, b) => a + b) / ys.length;
  var num = 0.0, den = 0.0;
  for (var i = 0; i < xs.length; i++) {
    num += (xs[i] - mx) * (ys[i] - my);
    den += (xs[i] - mx) * (xs[i] - mx);
  }
  if (den <= 0) return null;
  final slope = num / den; // kg per day
  final avgEaten = eaten.reduce((a, b) => a + b) / eaten.length;
  final estimate = avgEaten - slope * kKcalPerKg;
  if (!estimate.isFinite || estimate <= 0) return null;
  return (
    kcal: estimate,
    kgPerWeek: slope * 7,
    days: span.round() + 1,
    weighIns: weights.length,
    loggedDays: eaten.length,
  );
}

String foodUnit(Map<String, Object?> def) =>
    (def['unit'] as String?)?.trim().isNotEmpty == true
    ? (def['unit'] as String).trim()
    : 'g';
/// A stored number as an edit field shows it: at most three decimals, no
/// trailing zeros. Nutrition is kept per 100 units, so converting back to a
/// 29 g serving gives 20.000000000000004 for 20 g; the field shows 20.
String editableNumber(double? v) => v == null ? '' : portionText(v, '');

String portionText(num amount, String unit) {
  final value = amount == amount.roundToDouble()
      ? amount.round().toString()
      : amount
            .toStringAsFixed(3)
            .replaceFirst(RegExp(r'0+$'), '')
            .replaceFirst(RegExp(r'\.$'), '');
  final label =
      unit.isEmpty ||
          unit == 'g' ||
          unit == 'ml' ||
          amount == 1 ||
          unit.endsWith('s')
      ? unit
      : '${unit}s';
  return '$value $label'.trim();
}
