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
import 'day_label.dart';
import 'db.dart';
import 'lift_log.dart' show newLiftId;
import 'nutrition_store.dart' show NutritionDb;

const double kLbPerKg = 2.2046226218;

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

  String get fileName => '$id.jpg';
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

  /// Save a weigh-in for [date] as entered. Today's is a calculation input;
  /// any other day is history only (Akshat's decision: past calorie numbers
  /// never move). A same-day reading replaces the earlier one — the caller
  /// asks first.
  static Future<void> putWeight(
    String date,
    double value,
    String unit, {
    String source = 'whoop',
    String? originId,
    bool? historyOnly,
    DateTime? at,
  }) async {
    if (!value.isFinite || value <= 0)
      throw const BodyLogError('Enter a weight.');
    final kg = unit == 'lb' ? value / kLbPerKg : value;
    if (kg < 30 || kg > 300) {
      throw const BodyLogError(
        'Enter a weight from 30 to 300 kg (66 to 660 lb).',
      );
    }
    final db = await LocalDb.instance;
    await db.insert('body_weight', {
      'date': date,
      'kg': kg,
      'at_ts': (at ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000,
      'unit': unit,
      'entered': value,
      'source': source,
      'origin_id': originId,
      'history_only': (historyOnly ?? date != todayLabel()) ? 1 : 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    NutritionDb.changed();
  }

  static Future<void> deleteWeight(String date) async {
    final db = await LocalDb.instance;
    await db.delete('body_weight', where: 'date = ?', whereArgs: [date]);
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
        orderBy: 'date DESC, recorded_at DESC',
      ))
        _m(r),
    ];
  }

  /// Checked like Body: 5–80 in, rounded to 0.01 in, at least one site.
  static Future<void> putMeasure(BodyMeasure m) async {
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
    final db = await LocalDb.instance;
    await db.insert('body_measure', {
      'id': m.id,
      'date': m.date,
      'recorded_at': m.recordedAt.millisecondsSinceEpoch,
      'inches_json': jsonEncode(clean),
      'source': m.source,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    NutritionDb.changed();
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
  }) async {
    final ph = BodyPhoto(
      id: id,
      date: date,
      pose: pose,
      recordedAt: DateTime.now(),
      source: source,
    );
    final f = await photoFile(ph);
    await f.writeAsBytes(jpeg, flush: true);
    try {
      final db = await LocalDb.instance;
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
    NutritionDb.changed();
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

  /// Photo rows whose file is missing — shown, never silently dropped.
  static Future<List<BodyPhoto>> missingPhotos() async {
    final out = <BodyPhoto>[];
    for (final ph in await photos()) {
      if (!await (await photoFile(ph)).exists()) out.add(ph);
    }
    return out;
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

bool _validDay(Object? d) =>
    d is String &&
    RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(d) &&
    DateTime.tryParse(d) != null;

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
  });

  final String source;

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
  for (final raw in (m['weights'] as List? ?? const [])) {
    final w = raw as Map;
    final day = generated ? w['date'] : w['day'];
    if (!_validDay(day)) throw FormatException('Bad date $day');
    if (!seenDays.add(day as String))
      throw FormatException('Two weights on $day');
    final unit = generated ? (w['unit'] as String? ?? 'lb') : 'lb';
    final value = ((generated ? w['value'] : w['pounds']) as num).toDouble();
    final kg = unit == 'lb' ? value / kLbPerKg : value;
    if (!value.isFinite || kg < 30 || kg > 300)
      throw FormatException('Weight out of range on $day');
    final origin = (w['id'] as String?) ?? '$source:$day';
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
  for (final raw in (m['measurements'] as List? ?? const [])) {
    final x = raw as Map;
    if (!_validDay(x['day'])) throw FormatException('Bad date ${x['day']}');
    final id = x['id'] as String;
    if (existingMeasures.contains(id)) {
      already++;
      continue;
    }
    final inches = {
      for (final e in (x['inches'] as Map).entries)
        e.key as String: (e.value as num).toDouble(),
    };
    for (final v in inches.values) {
      if (!v.isFinite || v < 5 || v > 80)
        throw FormatException('Measurement out of range on ${x['day']}');
    }
    measures.add(
      BodyMeasure(
        id: id,
        date: x['day'] as String,
        recordedAt: _appleDate(x['recordedAt']),
        inches: inches,
        source: source,
      ),
    );
  }
  final existingPhotos = {for (final x in await BodyLogDb.photos()) x.id};
  final photos = <({BodyPhoto photo, String path})>[];
  final missing = <BodyPhoto>[];
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
  for (final w in plan.weights) {
    await BodyLogDb.putWeight(
      w.date,
      w.value,
      w.unit,
      source: plan.source,
      originId: w.originId,
      historyOnly: true,
      at: DateTime.parse(w.date),
    );
    n++;
  }
  for (final m in plan.measures) {
    await BodyLogDb.putMeasure(m);
    n++;
  }
  for (final ph in plan.photos) {
    await BodyLogDb.addPhoto(
      await encode(ph.path),
      date: ph.photo.date,
      pose: ph.photo.pose,
      source: plan.source,
      id: ph.photo.id,
    );
    n++;
  }
  if (applyWeekday && plan.measureWeekday != null) {
    await BodyLogDb.setMeasureWeekday(plan.measureWeekday!);
  }
  return n;
}
