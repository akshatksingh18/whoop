// Body inside WHOOP (build 86): daily weight, the eight tape sites and
// progress photos, ported from AkshatOS Body (`akshatos/body-log.md` is the
// parity contract) onto WHOOP's own data.
//
// ONE weight source. Weigh-ins live in WHOOP's existing `body_weight` table,
// the same rows Food reads, extended in place with the entered unit/value,
// a source, an origin id and a `history_only` flag. Akshat's decision: a
// backdated or imported weight is history only — it never feeds
// `ProfileHistory.on`, maintenance, workout pricing or the food/weight
// maintenance estimate, so past calorie numbers never move. Only today's
// weigh-in is a calculation input, exactly as before build 86.
//
// Tape readings are inches keyed by AkshatOS's `BodySite` raw values (an
// unknown key from a newer build is kept, never dropped). Photos are app-owned
// JPEGs re-encoded without metadata, loaded only when shown.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'calculation_store.dart';
import 'body_photo_file.dart';
import 'day_label.dart';
import 'db.dart';
import 'lift_log.dart' show newLiftId;
import 'nutrition_store.dart' show NutritionDb;

const double kLbPerKg = 2.2046226218;

/// Progress's chosen journey start ("Since start").
const String progressBaselineKey = 'progress.baseline';

enum BodySite {
  waistNavel,
  lowerBelly,
  hips,
  neck,
  chest,
  shoulders,
  upperArmRight,
  thighRight;

  String get title => switch (this) {
    waistNavel => 'Waist (navel)',
    lowerBelly => 'Lower belly',
    hips => 'Hips',
    neck => 'Neck',
    chest => 'Chest',
    shoulders => 'Shoulders',
    upperArmRight => 'Upper arm (right)',
    thighRight => 'Thigh (right)',
  };

  String get guidance => switch (this) {
    waistNavel =>
      'Level around the belly button, relaxed, after a normal breath out.',
    lowerBelly => 'Level about 2 in below the belly button, relaxed.',
    hips => 'Around the widest part of the glutes, feet together.',
    neck => "Just below the Adam's apple, sloping slightly down at the front.",
    chest => 'Around the nipple line, arms down, after a normal breath out.',
    shoulders =>
      'Around the widest part of the shoulders, arms relaxed at your sides.',
    upperArmRight => 'Right arm flexed, around the peak of the biceps.',
    thighRight =>
      'Right thigh, standing, around the widest part below the glutes.',
  };

  String get csvColumn => switch (this) {
    waistNavel => 'waist_navel_in',
    lowerBelly => 'lower_belly_in',
    hips => 'hips_in',
    neck => 'neck_in',
    chest => 'chest_in',
    shoulders => 'shoulders_in',
    upperArmRight => 'upper_arm_right_in',
    thighRight => 'thigh_right_in',
  };

  static BodySite? parse(String k) {
    for (final s in values) {
      if (s.name == k) return s;
    }
    return null;
  }
}

typedef BodyWeightRow = ({
  String date,
  double kg,
  int atTs,
  String unit,
  double? entered,
  String source,
  String? originId,
  bool historyOnly,
});

/// One weigh-in (Build 90): a day can hold several; its weight is the first.
typedef BodyWeightReading = ({
  String id,
  String date,
  double kg,
  int atTs,
  String unit,
  double? entered,
  String source,
  bool historyOnly,
});

/// The weight as the user entered it ("181.4 lb"), falling back to kg.
String bodyWeightText(BodyWeightRow w, {String unit = 'kg'}) {
  if (w.entered != null && w.unit == unit) {
    return '${_trim(w.entered!)} $unit';
  }
  final v = unit == 'lb' ? w.kg * kLbPerKg : w.kg;
  return '${_trim(v)} $unit';
}

String _trim(double v) {
  final s = v.toStringAsFixed(1);
  return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
}

class BodyMeasure {
  BodyMeasure({
    String? id,
    required this.date,
    required this.recordedAt,
    required this.inches,
    this.source = 'whoop',
  }) : id = id ?? newLiftId();

  final String id;
  String date;
  DateTime recordedAt;

  /// Inches by site key. Unknown keys are carried, not dropped.
  Map<String, double> inches;
  String source;

  double? value(BodySite s) => inches[s.name];
}

class BodyPhoto {
  BodyPhoto({
    String? id,
    required this.date,
    required this.pose,
    required this.recordedAt,
    this.source = 'whoop',
  }) : id = id ?? newLiftId();

  final String id;
  String date;

  /// 'front' or 'side'; an unknown pose stays as written.
  String pose;
  DateTime recordedAt;
  String source;

  String get fileName => bodyPhotoFileName(id);
}

class BodyLogError implements Exception {
  const BodyLogError(this.message);
  final String message;
  @override
  String toString() => message;
}

class BodyLogDb {
  BodyLogDb._();

  static const weekdayKey = 'body.measure_weekday';

  /// Called on every open, like the other user tables: additive and guarded.
  static Future<void> createTables(Database db) async {
    final cols = {
      for (final r in await db.rawQuery('PRAGMA table_info(body_weight)'))
        r['name'],
    };
    for (final (name, ddl) in const [
      ('unit', "TEXT NOT NULL DEFAULT 'kg'"),
      ('entered', 'REAL'),
      ('source', "TEXT NOT NULL DEFAULT 'whoop'"),
      ('origin_id', 'TEXT'),
      ('history_only', 'INTEGER NOT NULL DEFAULT 0'),
    ]) {
      if (cols.isEmpty || cols.contains(name)) continue;
      try {
        await db.execute('ALTER TABLE body_weight ADD COLUMN $name $ddl');
      } catch (_) {
        /* another opener added it first */
      }
    }
    await db.execute('''
      CREATE TABLE IF NOT EXISTS body_measure (
        id           TEXT PRIMARY KEY,
        date         TEXT NOT NULL,
        recorded_at  INTEGER NOT NULL,
        inches_json  TEXT NOT NULL,
        source       TEXT NOT NULL DEFAULT 'whoop',
        created_at   INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS body_photo (
        id           TEXT PRIMARY KEY,
        date         TEXT NOT NULL,
        pose         TEXT NOT NULL,
        recorded_at  INTEGER NOT NULL,
        source       TEXT NOT NULL DEFAULT 'whoop',
        created_at   INTEGER NOT NULL
      )
    ''');
  }

  // ── weight ──

  static BodyWeightRow _w(Map<String, Object?> r) => (
    date: r['date'] as String,
    kg: (r['kg'] as num).toDouble(),
    atTs: (r['at_ts'] as num?)?.toInt() ?? 0,
    unit: (r['unit'] as String?) ?? 'kg',
    entered: (r['entered'] as num?)?.toDouble(),
    source: (r['source'] as String?) ?? 'whoop',
    originId: r['origin_id'] as String?,
    historyOnly: ((r['history_only'] as num?) ?? 0) != 0,
  );

  /// Every weigh-in, oldest first, history-only ones included.
  static Future<List<BodyWeightRow>> weights() async {
    final db = await LocalDb.instance;
    return [
      for (final r in await db.query('body_weight', orderBy: 'date ASC')) _w(r),
    ];
  }

  static Future<BodyWeightRow?> weightOn(String date) async {
    final db = await LocalDb.instance;
    final rows = await db.query(
      'body_weight',
      where: 'date = ?',
      whereArgs: [date],
    );
    return rows.isEmpty ? null : _w(rows.first);
  }

  /// The kilograms [value] in [unit] stands for, or a [BodyLogError] when it
  /// is not a plausible weight. Callers validate with it before any write.
  static double checkWeight(double value, String unit) {
    if (unit != 'kg' && unit != 'lb') {
      throw const BodyLogError('Choose kg or lb for weight.');
    }
    if (!value.isFinite || value <= 0) {
      throw const BodyLogError('Enter a weight.');
    }
    final kg = unit == 'lb' ? value / kLbPerKg : value;
    if (kg < 30 || kg > 300) {
      throw const BodyLogError(
        'Enter a weight from 30 to 300 kg (66 to 660 lb).',
      );
    }
    return kg;
  }

  /// One weigh-in of the day, as entered.
  static BodyWeightReading _reading(Map<String, Object?> r) => (
    id: r['id'] as String,
    date: r['date'] as String,
    kg: (r['kg'] as num).toDouble(),
    atTs: (r['at_ts'] as num).toInt(),
    unit: (r['unit'] as String?) ?? 'kg',
    entered: (r['entered'] as num?)?.toDouble(),
    source: (r['source'] as String?) ?? 'whoop',
    historyOnly: ((r['history_only'] as num?) ?? 0) != 0,
  );

  /// Every reading of [date], earliest first.
  static Future<List<BodyWeightReading>> readingsOn(String date) async {
    final db = await LocalDb.instance;
    return [
      for (final r in await db.query(
        'body_weight_reading',
        where: 'date = ?',
        whereArgs: [date],
        orderBy: 'at_ts ASC, id ASC',
      ))
        _reading(r),
    ];
  }

  /// Actual latest timed reading, separate from the first-reading daily view.
  static Future<BodyWeightReading?> latestReading({DateTime? through}) async {
    final now = through ?? DateTime.now();
    final db = await LocalDb.instance;
    final rows = await db.query(
      'body_weight_reading',
      where: 'date <= ? AND (at_ts <= ? OR at_ts IS NULL)',
      whereArgs: [todayLabel(now), now.millisecondsSinceEpoch ~/ 1000],
      orderBy: 'date DESC, at_ts DESC, id DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : _reading(rows.single);
  }

  /// Build 90 (C3, Akshat): THE DAY'S WEIGHT IS ITS FIRST READING — taken on
  /// waking, before food or water. Every weigh-in is kept in
  /// `body_weight_reading`; `body_weight` stays the one-row-per-day value every
  /// reader already uses, rebuilt here from the earliest reading (or removed
  /// when the day has none).
  static Future<void> _refreshDay(DatabaseExecutor db, String date) async {
    final first = await db.query(
      'body_weight_reading',
      where: 'date = ?',
      whereArgs: [date],
      orderBy: 'at_ts ASC, id ASC',
      limit: 1,
    );
    if (first.isEmpty) {
      await db.delete('body_weight', where: 'date = ?', whereArgs: [date]);
      return;
    }
    final r = first.single;
    await db.insert('body_weight', {
      'date': date,
      'kg': r['kg'],
      'at_ts': r['at_ts'],
      'unit': r['unit'],
      'entered': r['entered'],
      'source': r['source'],
      'origin_id': r['origin_id'],
      'history_only': r['history_only'],
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Rebuild the projection after a database merge using the same first-reading
  /// order as individual writes. The indexed anti-join stays inside SQLite.
  static Future<void> rebuildDailyWeights(DatabaseExecutor db) async {
    await db.delete(
      'body_weight',
      where:
          'NOT EXISTS (SELECT 1 FROM body_weight_reading r WHERE r.date=body_weight.date)',
    );
    await db.rawInsert('''INSERT OR REPLACE INTO body_weight
      (date,kg,at_ts,unit,entered,source,origin_id,history_only)
      SELECT r.date,r.kg,r.at_ts,r.unit,r.entered,r.source,r.origin_id,r.history_only
      FROM body_weight_reading r WHERE NOT EXISTS
      (SELECT 1 FROM body_weight_reading f WHERE f.date=r.date
       AND (f.at_ts<r.at_ts OR (f.at_ts=r.at_ts AND f.id<r.id)))''');
  }

  /// Save a weigh-in for [date] as entered. Today's is a calculation input;
  /// any other day is history only (Akshat's decision: past calorie numbers
  /// never move). Every reading is kept; the day's weight is its first.
  /// [correctFirst] fixes the day's first reading in place instead of adding
  /// one (a mistyped morning weight). A reading for a past day without a
  /// time takes that day at the current clock time, never today's timestamp.
  static Future<void> putWeight(
    String date,
    double value,
    String unit, {
    String source = 'whoop',
    String? originId,
    bool? historyOnly,
    DateTime? at,
    bool correctFirst = false,
    DatabaseExecutor? database,
    bool notify = true,
  }) async {
    _checkDay(date);
    final kg = checkWeight(value, unit);
    final now = DateTime.now();
    final when =
        at ??
        (date == todayLabel()
            ? now
            : DayClock.onDate(date, now.hour, now.minute));
    final db = database ?? await LocalDb.instance;
    Future<void> write(DatabaseExecutor tx) async {
      final row = {
        'date': date,
        'kg': kg,
        'unit': unit,
        'entered': value,
        'source': source,
        'origin_id': originId,
        'history_only': (historyOnly ?? date != todayLabel()) ? 1 : 0,
      };
      // The reading to update in place: the day's first when correcting it,
      // or the same imported record (origin ID) so a re-import never doubles.
      final first = correctFirst
          ? await tx.query(
              'body_weight_reading',
              where: 'date = ?',
              whereArgs: [date],
              orderBy: 'at_ts ASC, id ASC',
              limit: 1,
            )
          : originId != null
          ? await tx.query(
              'body_weight_reading',
              where: 'origin_id = ?',
              whereArgs: [originId],
              limit: 1,
            )
          : const <Map<String, Object?>>[];
      if (first.isNotEmpty) {
        await tx.update(
          'body_weight_reading',
          {
            ...row,
            if (!correctFirst && at != null)
              'at_ts': when.millisecondsSinceEpoch ~/ 1000,
          },
          where: 'id = ?',
          whereArgs: [first.single['id']],
        );
        final previousDate = first.single['date'] as String;
        if (previousDate != date) await _refreshDay(tx, previousDate);
      } else {
        await tx.insert('body_weight_reading', {
          'id': newLiftId(),
          ...row,
          'at_ts': when.millisecondsSinceEpoch ~/ 1000,
          'created_at': now.millisecondsSinceEpoch ~/ 1000,
        });
      }
      await _refreshDay(tx, date);
    }

    if (db is Database) {
      await db.transaction(write);
    } else {
      await write(db);
    }
    if (notify) NutritionDb.changed();
  }

  /// Delete every reading of [date] (the day's weight goes with them).
  static Future<void> deleteWeight(String date) async {
    final db = await LocalDb.instance;
    await db.transaction((tx) async {
      await tx.delete(
        'body_weight_reading',
        where: 'date = ?',
        whereArgs: [date],
      );
      await tx.delete('body_weight', where: 'date = ?', whereArgs: [date]);
    });
    NutritionDb.changed();
  }

  /// Delete one reading; the day's weight becomes its next earliest.
  static Future<void> deleteReading(String id) async {
    final db = await LocalDb.instance;
    await db.transaction((tx) async {
      final r = await tx.query(
        'body_weight_reading',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (r.isEmpty) return;
      await tx.delete('body_weight_reading', where: 'id = ?', whereArgs: [id]);
      await _refreshDay(tx, r.single['date'] as String);
    });
    NutritionDb.changed();
  }

  /// The mean of the readings in the seven calendar days ending [date], with
  /// how many there were; null with none. No day is forward-filled.
  static ({double kg, int count})? sevenDayMean(
    List<BodyWeightRow> all,
    String date,
  ) {
    final end = DateTime.parse(date);
    final from = dayLabelOf(DateTime(end.year, end.month, end.day - 6));
    final vs = [
      for (final w in all)
        if (w.date.compareTo(from) >= 0 && w.date.compareTo(date) <= 0) w.kg,
    ];
    if (vs.isEmpty) return null;
    return (kg: vs.reduce((a, b) => a + b) / vs.length, count: vs.length);
  }

  /// The first day of the weekly block holding [date]: blocks start on the
  /// measurement [weekday] (DateTime.monday…sunday), so a week's average and
  /// its tape session line up, as in AkshatOS Body.
  static String blockStart(String date, int weekday) {
    final d = DateTime.parse(date);
    final back = (d.weekday - weekday) % 7;
    return dayLabelOf(DateTime(d.year, d.month, d.day - back));
  }

  /// Weekly weight blocks, newest first: each block's mean over the readings
  /// actually in it (never forward-filled), how many there were, and the
  /// change from the previous block that had readings. A block with no
  /// reading is absent, not zero.
  static List<({String from, String to, double kg, int count, double? change})>
  weekBlocks(List<BodyWeightRow> all, int weekday) {
    final byBlock = <String, List<double>>{};
    for (final w in all) {
      (byBlock[blockStart(w.date, weekday)] ??= []).add(w.kg);
    }
    final starts = byBlock.keys.toList()..sort();
    final out =
        <({String from, String to, double kg, int count, double? change})>[];
    double? prev;
    for (final s in starts) {
      final vs = byBlock[s]!;
      final mean = vs.reduce((a, b) => a + b) / vs.length;
      final d = DateTime.parse(s);
      out.add((
        from: s,
        to: dayLabelOf(DateTime(d.year, d.month, d.day + 6)),
        kg: mean,
        count: vs.length,
        change: prev == null ? null : mean - prev,
      ));
      prev = mean;
    }
    return out.reversed.toList();
  }

  // ── tape ──

  static BodyMeasure _m(Map<String, Object?> r) {
    final raw = jsonDecode(r['inches_json'] as String) as Map;
    return BodyMeasure(
      id: r['id'] as String,
      date: r['date'] as String,
      recordedAt: DateTime.fromMillisecondsSinceEpoch(
        (r['recorded_at'] as num).toInt(),
      ),
      inches: {
        for (final e in raw.entries)
          e.key as String: (e.value as num).toDouble(),
      },
      source: (r['source'] as String?) ?? 'whoop',
    );
  }

  /// Newest first.
  static Future<List<BodyMeasure>> measures() async {
    final db = await LocalDb.instance;
    return [
      for (final r in await db.query(
        'body_measure',
        orderBy: 'date DESC, recorded_at DESC, id DESC',
      ))
        _m(r),
    ];
  }

  /// Checked like Body: 5–80 in, rounded to 0.01 in, at least one site.
  static Map<String, double> checkedMeasurements(BodyMeasure m) {
    _checkDay(m.date);
    final clean = <String, double>{};
    for (final e in m.inches.entries) {
      final v = e.value;
      if (!v.isFinite || v < 5 || v > 80) {
        final site = BodySite.parse(e.key)?.title ?? e.key;
        throw BodyLogError('$site must be between 5 and 80 in.');
      }
      clean[e.key] = (v * 100).round() / 100;
    }
    if (clean.isEmpty)
      throw const BodyLogError('Enter at least one measurement.');
    return clean;
  }

  static Future<void> putMeasure(
    BodyMeasure m, {
    DatabaseExecutor? database,
    bool notify = true,
  }) async {
    final clean = checkedMeasurements(m);
    final db = database ?? await LocalDb.instance;
    await db.insert('body_measure', {
      'id': m.id,
      'date': m.date,
      'recorded_at': m.recordedAt.millisecondsSinceEpoch,
      'inches_json': jsonEncode(clean),
      'source': m.source,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    if (notify) NutritionDb.changed();
  }

  static Future<void> deleteMeasure(String id) async {
    final db = await LocalDb.instance;
    await db.delete('body_measure', where: 'id = ?', whereArgs: [id]);
    NutritionDb.changed();
  }

  /// A site's change since the most recent earlier session that measured it.
  static double? changeSince(
    List<BodyMeasure> newestFirst,
    BodyMeasure m,
    BodySite s,
  ) {
    final v = m.value(s);
    if (v == null) return null;
    for (final x in newestFirst) {
      if (x.id == m.id) continue;
      final earlier =
          x.date.compareTo(m.date) < 0 ||
          (x.date == m.date && x.recordedAt.isBefore(m.recordedAt));
      if (!earlier) continue;
      final prev = x.value(s);
      if (prev != null) return v - prev;
    }
    return null;
  }

  /// US Navy circumference estimate (male form, inches), from the latest
  /// session that has both waist and neck. Labelled an estimate; absent
  /// without height or the two sites.
  static double? navyBodyFat(double? waist, double? neck, double? heightIn) {
    if (waist == null || neck == null || heightIn == null) return null;
    if (waist - neck <= 0 || heightIn <= 0) return null;
    return 86.010 * math.log(waist - neck) / math.ln10 -
        70.041 * math.log(heightIn) / math.ln10 +
        36.76;
  }

  /// Body's measurement weekday, DateTime.weekday numbering (Saturday 6 by
  /// default, as in AkshatOS). WHOOP's Monday review weeks are separate.
  static Future<int> measureWeekday() async {
    final raw = await CalculationStore.read(weekdayKey);
    final v = int.tryParse(raw ?? '');
    return v != null && v >= 1 && v <= 7 ? v : DateTime.saturday;
  }

  static Future<void> setMeasureWeekday(int weekday) =>
      CalculationStore.write(weekdayKey, '$weekday');

  // ── photos ──

  static Future<Directory> photoDir() async {
    final root = await getApplicationSupportDirectory();
    final d = Directory(p.join(root.path, 'body_photos'));
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static Future<File> photoFile(BodyPhoto ph) async =>
      File(p.join((await photoDir()).path, ph.fileName));

  static BodyPhoto _ph(Map<String, Object?> r) => BodyPhoto(
    id: r['id'] as String,
    date: r['date'] as String,
    pose: r['pose'] as String,
    recordedAt: DateTime.fromMillisecondsSinceEpoch(
      (r['recorded_at'] as num).toInt(),
    ),
    source: (r['source'] as String?) ?? 'whoop',
  );

  /// Oldest first, so a filmstrip reads left to right in time.
  static Future<List<BodyPhoto>> photos() async {
    final db = await LocalDb.instance;
    return [
      for (final r in await db.query(
        'body_photo',
        orderBy: 'date ASC, recorded_at ASC',
      ))
        _ph(r),
    ];
  }

  /// Write the (already re-encoded) JPEG, then the row; a failed row write
  /// removes the file so no orphan is left.
  static Future<BodyPhoto> addPhoto(
    List<int> jpeg, {
    required String date,
    required String pose,
    String source = 'whoop',
    String? id,
    DatabaseExecutor? database,
    bool notify = true,
  }) async {
    _checkDay(date);
    final ph = BodyPhoto(
      id: id,
      date: date,
      pose: pose,
      recordedAt: DateTime.now(),
      source: source,
    );
    final f = await photoFile(ph);
    final db = database ?? await LocalDb.instance;
    if ((await db.query(
      'body_photo',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [ph.id],
    )).isNotEmpty) {
      throw const BodyLogError('This photo is already here.');
    }
    // Exclusive creation owns this file or fails without touching it. A stale
    // import preview or concurrent call must never overwrite an existing photo.
    await f.create(exclusive: true);
    try {
      await f.writeAsBytes(jpeg, flush: true);
      await db.insert('body_photo', {
        'id': ph.id,
        'date': ph.date,
        'pose': ph.pose,
        'recorded_at': ph.recordedAt.millisecondsSinceEpoch,
        'source': ph.source,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.abort);
    } catch (e) {
      try {
        await f.delete();
      } catch (_) {}
      rethrow;
    }
    if (notify) NutritionDb.changed();
    return ph;
  }

  /// Delete a photo record and its file. Its day's weight is untouched.
  static Future<void> deletePhoto(BodyPhoto ph) async {
    final db = await LocalDb.instance;
    await db.delete('body_photo', where: 'id = ?', whereArgs: [ph.id]);
    try {
      final f = await photoFile(ph);
      if (await f.exists()) await f.delete();
    } catch (_) {}
    NutritionDb.changed();
  }

  /// One row per day, oldest first: date, weight in lb, then one inch column
  /// per site — AkshatOS Body's CSV.
  static Future<String> csv() async {
    final ws = {for (final w in await weights()) w.date: w};
    final ms = await measures();
    final byDay = <String, BodyMeasure>{};
    for (final m in ms.reversed) {
      byDay[m.date] = m;
    }
    final days = {...ws.keys, ...byDay.keys}.toList()..sort();
    final lines = [
      [
        'date',
        'weight_lb',
        for (final s in BodySite.values) s.csvColumn,
      ].join(','),
    ];
    for (final d in days) {
      final w = ws[d];
      final m = byDay[d];
      lines.add(
        [
          d,
          w == null
              ? ''
              : _trim2(
                  w.unit == 'lb' && w.entered != null
                      ? w.entered!
                      : w.kg * kLbPerKg,
                ),
          for (final s in BodySite.values)
            m?.value(s) == null ? '' : _trim2(m!.value(s)!),
        ].join(','),
      );
    }
    return '${lines.join('\n')}\n';
  }

  static String _trim2(double v) => v
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

// ── imports: AkshatOS Body and generated body-history files ────────────────

const int _appleEpochOffsetSec = 978307200;

DateTime _appleDate(Object? v) {
  if (v is num) {
    return DateTime.fromMillisecondsSinceEpoch(
      ((v + _appleEpochOffsetSec) * 1000).round(),
    );
  }
  if (v is String) return DateTime.parse(v);
  throw const FormatException('Unreadable date');
}

bool _validDay(Object? d) {
  if (d is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(d)) return false;
  final parsed = DateTime.tryParse(d);
  return parsed != null && dayLabelOf(parsed) == d;
}

void _checkDay(String date) {
  if (!_validDay(date))
    throw const BodyLogError('Choose a valid calendar date.');
}

/// A validated, not-yet-applied body import, for the preview.
class BodyImportPlan {
  BodyImportPlan({
    required this.source,
    required this.weights,
    required this.measures,
    required this.photos,
    required this.missingPhotoFiles,
    required this.sameDayConflicts,
    required this.alreadyHere,
    this.heightInches,
    this.measureWeekday,
    this.baselineDate,
  });

  final String source;

  /// The journey start a generated file declares; set as Progress's "Since
  /// start" only when none is chosen yet.
  final String? baselineDate;

  /// New weigh-ins (no reading on that day yet). All history only.
  final List<({String date, double value, String unit, String originId})>
  weights;
  final List<BodyMeasure> measures;

  /// Photos with their file found among the picked files.
  final List<({BodyPhoto photo, String path})> photos;

  /// Photo records whose JPEG was not among the picked files.
  final List<BodyPhoto> missingPhotoFiles;

  /// Days that already hold a different weight here: never overwritten.
  final List<({String date, String here, String there})> sameDayConflicts;

  /// Records already imported (same origin id or same value that day).
  final int alreadyHere;
  final double? heightInches;
  final int? measureWeekday;

  bool get isEmpty => weights.isEmpty && measures.isEmpty && photos.isEmpty;
}

/// Read [manifest] — AkshatOS `body-log.json`, or a generated
/// `whoop-body-history` file — with [files] the other picked files (photo
/// JPEGs by name). Validates everything before anything changes.
Future<BodyImportPlan> planBodyImport(
  String manifest, {
  Map<String, String> files = const {},
}) async {
  final m = jsonDecode(manifest);
  if (m is! Map) throw const FormatException('This is not a body backup.');
  final generated = m['format'] == 'whoop-body-history';
  if (!generated && (m['version'] != 1 || m['weights'] is! List)) {
    throw const FormatException('This is not an AkshatOS Body backup.');
  }
  if (generated && m['version'] != 1) {
    throw const FormatException('This body-history file needs a newer app.');
  }
  final source = generated ? (m['source'] as String? ?? 'import') : 'akshatos';
  final here = {for (final w in await BodyLogDb.weights()) w.date: w};
  final weights =
      <({String date, double value, String unit, String originId})>[];
  final conflicts = <({String date, String here, String there})>[];
  var already = 0;
  final seenDays = <String>{};
  final seenOrigins = <String>{};
  final db = await LocalDb.instance;
  final originsHere = {
    for (final r in await db.query(
      'body_weight_reading',
      columns: ['origin_id', 'date'],
      where: 'origin_id IS NOT NULL',
    ))
      r['origin_id'] as String: r['date'] as String,
  };
  for (final raw in (m['weights'] as List? ?? const [])) {
    final w = raw as Map;
    final day = generated ? w['date'] : w['day'];
    if (!_validDay(day)) throw FormatException('Bad date $day');
    if (!seenDays.add(day as String))
      throw FormatException('Two weights on $day');
    final unit = generated ? (w['unit'] as String? ?? 'lb') : 'lb';
    final value = ((generated ? w['value'] : w['pounds']) as num).toDouble();
    final kg = BodyLogDb.checkWeight(value, unit);
    final origin = (w['id'] as String?) ?? '$source:$day';
    if (origin.trim().isEmpty || !seenOrigins.add(origin)) {
      throw const FormatException(
        'Weight record IDs must be nonempty and unique. Nothing was imported.',
      );
    }
    if (originsHere[origin] != null && originsHere[origin] != day) {
      throw const FormatException(
        'A weight ID already belongs to another date. Nothing was imported.',
      );
    }
    final existing = here[day];
    if (existing == null) {
      weights.add((date: day, value: value, unit: unit, originId: origin));
    } else if (existing.originId == origin || (existing.kg - kg).abs() < 0.05) {
      already++;
    } else {
      conflicts.add((
        date: day,
        here: bodyWeightText(existing, unit: unit),
        there: '${_trimOne(value)} $unit',
      ));
    }
  }
  final existingMeasures = {for (final x in await BodyLogDb.measures()) x.id};
  final measures = <BodyMeasure>[];
  final incomingMeasures = <String>{};
  for (final raw in (m['measurements'] as List? ?? const [])) {
    final x = raw as Map;
    if (!_validDay(x['day'])) throw FormatException('Bad date ${x['day']}');
    final id = x['id'] as String;
    if (id.trim().isEmpty || !incomingMeasures.add(id)) {
      throw const FormatException(
        'Measurement record IDs must be nonempty and unique. Nothing was imported.',
      );
    }
    final inches = {
      for (final e in (x['inches'] as Map).entries)
        e.key as String: (e.value as num).toDouble(),
    };
    for (final v in inches.values) {
      if (!v.isFinite || v < 5 || v > 80)
        throw FormatException('Measurement out of range on ${x['day']}');
    }
    final measure = BodyMeasure(
      id: id,
      date: x['day'] as String,
      recordedAt: _appleDate(x['recordedAt']),
      inches: inches,
      source: source,
    );
    BodyLogDb.checkedMeasurements(measure);
    if (existingMeasures.contains(id)) {
      already++;
    } else {
      measures.add(measure);
    }
  }
  final existingPhotos = {for (final x in await BodyLogDb.photos()) x.id};
  final photos = <({BodyPhoto photo, String path})>[];
  final missing = <BodyPhoto>[];
  final incomingPhotos = <String>{};
  for (final raw in (m['photos'] as List? ?? const [])) {
    final x = raw as Map;
    if (!_validDay(x['day'])) throw FormatException('Bad date ${x['day']}');
    final ph = BodyPhoto(
      id: x['id'] as String,
      date: x['day'] as String,
      pose: (x['pose'] as String?) ?? 'front',
      recordedAt: _appleDate(x['recordedAt']),
      source: source,
    );
    bodyPhotoFileName(ph.id);
    if (!incomingPhotos.add(ph.id)) {
      throw const FormatException(
        'Two photos have the same ID. Nothing was imported.',
      );
    }
    if (existingPhotos.contains(ph.id)) {
      already++;
      continue;
    }
    final path = files[ph.fileName] ?? files[ph.fileName.toLowerCase()];
    if (path == null) {
      missing.add(ph);
    } else {
      photos.add((photo: ph, path: path));
    }
  }
  final h = (m['heightInches'] as num?)?.toDouble();
  final wd = (m['measurementWeekday'] as num?)?.toInt();
  final base = (m['baseline'] as Map?)?['date'];
  if (base != null && !_validDay(base)) {
    throw const FormatException('Choose a valid baseline date.');
  }
  return BodyImportPlan(
    source: source,
    weights: weights,
    measures: measures,
    photos: photos,
    missingPhotoFiles: missing,
    sameDayConflicts: conflicts,
    alreadyHere: already,
    heightInches: h != null && h >= 36 && h <= 96 ? h : null,
    // Swift Calendar numbering: 1 = Sunday … 7 = Saturday.
    measureWeekday: wd == null || wd < 1 || wd > 7
        ? null
        : (wd == 1 ? 7 : wd - 1),
    baselineDate: _validDay(base) ? base as String : null,
  );
}

String _trimOne(double v) {
  final s = v.toStringAsFixed(1);
  return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
}

/// Apply a previewed plan. Weights land as history only; photos are
/// re-encoded by [encode] (metadata stripped) before they are kept.
/// Returns how many records were added.
Future<int> applyBodyImport(
  BodyImportPlan plan, {
  required Future<List<int>> Function(String path) encode,
  bool applyWeekday = false,
}) async {
  var n = 0;
  final db = await LocalDb.instance;
  // Decode before publishing any row. Files created in the transaction are
  // owned by this attempt and removed if the database rolls it back.
  final staging = await (await getTemporaryDirectory()).createTemp(
    'body_import_',
  );
  final encoded = <({BodyPhoto photo, File file})>[];
  final created = <BodyPhoto>[];
  try {
    for (final (i, ph) in plan.photos.indexed) {
      final file = File(p.join(staging.path, '$i.jpg'));
      await file.writeAsBytes(await encode(ph.path), flush: true);
      encoded.add((photo: ph.photo, file: file));
    }
    await db.transaction((tx) async {
      for (final w in plan.weights) {
        final present = await tx.query(
          'body_weight_reading',
          columns: ['id'],
          where: 'date=? OR origin_id=?',
          whereArgs: [w.date, w.originId],
          limit: 1,
        );
        if (present.isNotEmpty) continue;
        await BodyLogDb.putWeight(
          w.date,
          w.value,
          w.unit,
          source: plan.source,
          originId: w.originId,
          historyOnly: true,
          at: DayClock.onDate(w.date, 0, 0),
          database: tx,
          notify: false,
        );
        n++;
      }
      for (final m in plan.measures) {
        if ((await tx.query(
          'body_measure',
          columns: ['id'],
          where: 'id=?',
          whereArgs: [m.id],
          limit: 1,
        )).isNotEmpty)
          continue;
        await BodyLogDb.putMeasure(m, database: tx, notify: false);
        n++;
      }
      for (final ph in encoded) {
        if ((await tx.query(
          'body_photo',
          columns: ['id'],
          where: 'id=?',
          whereArgs: [ph.photo.id],
          limit: 1,
        )).isNotEmpty)
          continue;
        final added = await BodyLogDb.addPhoto(
          await ph.file.readAsBytes(),
          date: ph.photo.date,
          pose: ph.photo.pose,
          source: plan.source,
          id: ph.photo.id,
          database: tx,
          notify: false,
        );
        created.add(added);
        n++;
      }
      if (applyWeekday && plan.measureWeekday != null) {
        await CalculationStore.writeIn(
          tx,
          BodyLogDb.weekdayKey,
          '${plan.measureWeekday!}',
        );
      }
      final base = plan.baselineDate;
      if (base != null &&
          (await tx.query(
            'baselines',
            columns: ['key'],
            where: 'key=?',
            whereArgs: ['${CalculationStore.prefix}$progressBaselineKey'],
          )).isEmpty) {
        await CalculationStore.writeIn(tx, progressBaselineKey, base);
      }
    });
  } catch (_) {
    for (final ph in created) {
      try {
        await (await BodyLogDb.photoFile(ph)).delete();
      } catch (_) {}
    }
    rethrow;
  } finally {
    try {
      await staging.delete(recursive: true);
    } catch (_) {}
  }
  await CalculationStore.hydrate();
  if (n > 0) NutritionDb.changed();
  return n;
}
