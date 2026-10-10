// Lift Log inside the WHOOP workout (build 86). A port of AkshatOS Lift Log's
// domain rules (`akshatos/lift-log.md` is the parity contract) onto WHOOP's
// own session: one Start, one clock, one Finish, one history entry.
//
// Storage is one JSON document per workout in `lift_log`, written whole on
// every mutation before the UI claims success — the same shape as Lift Log's
// SwiftData store, so a set/edit/delete/Undo is one atomic statement and an
// unfinished workout survives relaunch. A row is linked to the WHOOP session
// it was logged in (`session_id`); an imported AkshatOS workout without a
// reviewed link has no session and never enters strain or calories.
//
// Loads keep their meaning: plates per side, per hand, stack, added weight,
// weight loaded or known total, in pounds as entered. Nothing here sums them
// into a "total lifted", estimates a 1RM, or prices calories.

import 'dart:convert';
import 'dart:math' as math;

import 'package:sqflite/sqflite.dart';

import 'calculation_store.dart';
import 'db.dart';

enum LiftLoadMode {
  platesPerSide,
  perHand,
  stack,
  addedWeight,
  weightLoaded,
  total;

  String get title => switch (this) {
    platesPerSide => 'Plates per side',
    perHand => 'Weight per hand',
    stack => 'Stack setting',
    addedWeight => 'Added weight',
    weightLoaded => 'Weight loaded',
    total => 'Total weight',
  };

  String get shortUnit => switch (this) {
    platesPerSide => 'lb/side',
    perHand => 'lb/hand',
    stack => 'lb stack',
    addedWeight => 'lb added',
    weightLoaded => 'lb loaded',
    total => 'lb total',
  };

  String get guidance => switch (this) {
    platesPerSide =>
      'Enter the plates loaded on one side; the bar, sled, or machine base stays excluded.',
    perHand =>
      'Enter the weight held in one hand; do not add both dumbbells or handles together.',
    stack =>
      "Enter the number selected on the machine's weight stack; do not guess pulley-adjusted resistance.",
    addedWeight =>
      'Enter only the external weight added to a bodyweight exercise; your bodyweight stays excluded.',
    weightLoaded =>
      "Enter all the plates on the machine added together, as one number; the machine's own resistance stays excluded.",
    total =>
      'Enter the complete known load, including the bar or machine base only when you actually know it.',
  };

  /// The raw value AkshatOS writes, so imports and exports round-trip.
  static LiftLoadMode? parse(Object? raw) {
    for (final m in values) {
      if (m.name == raw) return m;
    }
    return null;
  }
}

class LiftLogError implements Exception {
  const LiftLogError(this.message);
  final String message;
  @override
  String toString() => message;

  static const emptyExerciseName = LiftLogError('Enter an exercise name.');
  static const invalidReps = LiftLogError(
    'Repetitions must be greater than zero.',
  );
  static const invalidLoad = LiftLogError('Weight must be zero or greater.');
  static const exerciseNotFound = LiftLogError(
    'That exercise is no longer in this workout.',
  );
  static const setNotFound = LiftLogError('There is no set to remove.');
  static const finished = LiftLogError('This workout is already finished.');
  static const emptySplitName = LiftLogError('Give the split a name.');
  static const duplicateSplitName = LiftLogError(
    'Another split already has that name.',
  );
  static const splitTooLarge = LiftLogError(
    'Keep a split name under 40 characters, at most 40 exercises a split and 20 splits.',
  );
  static const duplicate = LiftLogError(
    'The workout contains duplicate records.',
  );
}

String _id() {
  final r = math.Random.secure();
  String h(int n) => [
    for (var i = 0; i < n; i++) r.nextInt(16).toRadixString(16),
  ].join();
  return '${h(8)}-${h(4)}-4${h(3)}-${'89ab'[r.nextInt(4)]}${h(3)}-${h(12)}'
      .toUpperCase();
}

String newLiftId() => _id();

/// Names compare ignoring case and surrounding space ("Hammer curl" is one
/// exercise), as in Lift Log.
String liftNameKey(String name) => name.trim().toLowerCase();

bool sameLiftName(String a, String b) => liftNameKey(a) == liftNameKey(b);

/// "42.5" not "42.50"; whole numbers without a point.
String liftWeightText(double v) {
  if (v == v.roundToDouble()) return v.round().toString();
  return v
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

class LiftSplitExercise {
  LiftSplitExercise({
    String? id,
    required this.name,
    required this.loadMode,
    this.equipmentNote = '',
  }) : id = id ?? _id();

  final String id;
  String name;
  LiftLoadMode loadMode;
  String equipmentNote;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'loadMode': loadMode.name,
    'equipmentNote': equipmentNote,
  };

  static LiftSplitExercise fromJson(Map m) => LiftSplitExercise(
    id: m['id'] as String,
    name: m['name'] as String,
    loadMode: LiftLoadMode.parse(m['loadMode']) ?? LiftLoadMode.platesPerSide,
    equipmentNote: (m['equipmentNote'] as String?) ?? '',
  );

  LiftSplitExercise copy() => LiftSplitExercise(
    id: id,
    name: name,
    loadMode: loadMode,
    equipmentNote: equipmentNote,
  );
}

class LiftSplit {
  LiftSplit({String? id, required this.name, List<LiftSplitExercise>? exercises})
    : id = id ?? _id(),
      exercises = exercises ?? [];

  static const maxNameLength = 40;
  static const maxExercises = 40;
  static const maxSplits = 20;

  final String id;
  String name;
  List<LiftSplitExercise> exercises;

  LiftSplit copy() => LiftSplit(
    id: id,
    name: name,
    exercises: [for (final e in exercises) e.copy()],
  );

  LiftSplit validated() {
    final c = copy()..name = name.trim();
    if (c.name.isEmpty) throw LiftLogError.emptySplitName;
    if (c.name.length > maxNameLength || c.exercises.length > maxExercises) {
      throw LiftLogError.splitTooLarge;
    }
    if (c.exercises.map((e) => e.id).toSet().length != c.exercises.length) {
      throw LiftLogError.duplicate;
    }
    for (final e in c.exercises) {
      e.name = e.name.trim();
      e.equipmentNote = e.equipmentNote.trim();
      if (e.name.isEmpty) throw LiftLogError.emptyExerciseName;
    }
    return c;
  }

  static List<LiftSplit> validatedList(List<LiftSplit> splits) {
    final checked = [for (final s in splits) s.validated()];
    if (checked.length > maxSplits) throw LiftLogError.splitTooLarge;
    if (checked.map((s) => s.id).toSet().length != checked.length) {
      throw LiftLogError.duplicate;
    }
    if (checked.map((s) => s.name.toLowerCase()).toSet().length !=
        checked.length) {
      throw LiftLogError.duplicateSplitName;
    }
    return checked;
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'exercises': [for (final e in exercises) e.toJson()],
  };

  static LiftSplit fromJson(Map m) => LiftSplit(
    id: m['id'] as String,
    name: m['name'] as String,
    exercises: [
      for (final e in (m['exercises'] as List? ?? const []))
        LiftSplitExercise.fromJson(e as Map),
    ],
  );

  /// What a new log starts with: Lift Log's own starting splits (names,
  /// order and modes only — no performance).
  static List<LiftSplit> get starting => [
    LiftSplit(
      name: 'Lower day',
      exercises: [
        LiftSplitExercise(
          name: 'Smith-machine squat',
          loadMode: LiftLoadMode.platesPerSide,
          equipmentNote: 'Smith bar resistance excluded',
        ),
        LiftSplitExercise(
          name: 'Barbell Romanian deadlift',
          loadMode: LiftLoadMode.platesPerSide,
          equipmentNote: 'Bar weight excluded',
        ),
        LiftSplitExercise(
          name: 'Leg press',
          loadMode: LiftLoadMode.platesPerSide,
          equipmentNote: 'Sled/base resistance excluded',
        ),
        LiftSplitExercise(
          name: 'Seated machine leg curl',
          loadMode: LiftLoadMode.stack,
        ),
        LiftSplitExercise(
          name: 'Seated calf raise',
          loadMode: LiftLoadMode.weightLoaded,
          equipmentNote: "Machine's own resistance excluded",
        ),
      ],
    ),
    LiftSplit(
      name: 'Back and biceps day',
      exercises: [
        LiftSplitExercise(
          name: 'Weighted pull-ups',
          loadMode: LiftLoadMode.addedWeight,
        ),
        LiftSplitExercise(
          name: 'Seated cable row',
          loadMode: LiftLoadMode.stack,
        ),
        LiftSplitExercise(
          name: 'Dumbbell biceps curl',
          loadMode: LiftLoadMode.perHand,
        ),
      ],
    ),
    LiftSplit(
      name: 'Chest day',
      exercises: [
        LiftSplitExercise(
          name: 'Dumbbell bench press',
          loadMode: LiftLoadMode.perHand,
        ),
        LiftSplitExercise(
          name: 'Shoulder press',
          loadMode: LiftLoadMode.perHand,
          equipmentNote: 'Default: dumbbells',
        ),
        LiftSplitExercise(name: 'Pec-deck fly', loadMode: LiftLoadMode.stack),
        LiftSplitExercise(
          name: 'Triceps pushdown',
          loadMode: LiftLoadMode.stack,
        ),
      ],
    ),
  ];
}

class LiftSet {
  LiftSet({
    String? id,
    required this.reps,
    required this.load,
    required this.completedAt,
  }) : id = id ?? _id();

  final String id;
  int reps;

  /// Read with the owning exercise's [LiftLoadMode], in pounds as entered.
  double load;

  /// When the set was logged — not a measured start or duration.
  DateTime completedAt;

  LiftSet copy() =>
      LiftSet(id: id, reps: reps, load: load, completedAt: completedAt);

  Map<String, Object?> toJson() => {
    'id': id,
    'reps': reps,
    'load': load,
    'completedAt': completedAt.millisecondsSinceEpoch,
  };

  static LiftSet fromJson(Map m) => LiftSet(
    id: m['id'] as String,
    reps: (m['reps'] as num).toInt(),
    load: (m['load'] as num).toDouble(),
    completedAt: DateTime.fromMillisecondsSinceEpoch(
      (m['completedAt'] as num).toInt(),
    ),
  );
}

class LiftExercise {
  LiftExercise({
    String? id,
    required String name,
    this.loadMode = LiftLoadMode.platesPerSide,
    String equipmentNote = '',
    List<LiftSet>? sets,
    this.splitExerciseId,
  }) : id = id ?? _id(),
       name = name.trim(),
       equipmentNote = equipmentNote.trim(),
       sets = sets ?? [];

  final String id;
  String name;
  LiftLoadMode loadMode;
  String equipmentNote;
  List<LiftSet> sets;
  String? splitExerciseId;

  LiftExercise copy() => LiftExercise(
    id: id,
    name: name,
    loadMode: loadMode,
    equipmentNote: equipmentNote,
    sets: [for (final s in sets) s.copy()],
    splitExerciseId: splitExerciseId,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'loadMode': loadMode.name,
    'equipmentNote': equipmentNote,
    'sets': [for (final s in sets) s.toJson()],
    if (splitExerciseId != null) 'splitExerciseID': splitExerciseId,
  };

  static LiftExercise fromJson(Map m) => LiftExercise(
    id: m['id'] as String,
    name: m['name'] as String,
    loadMode: LiftLoadMode.parse(m['loadMode']) ?? LiftLoadMode.platesPerSide,
    equipmentNote: (m['equipmentNote'] as String?) ?? '',
    sets: [
      for (final s in (m['sets'] as List? ?? const [])) LiftSet.fromJson(s as Map),
    ],
    splitExerciseId: m['splitExerciseID'] as String?,
  );

  String setText(LiftSet s) =>
      '${liftWeightText(s.load)} ${loadMode.shortUnit} × ${s.reps}';
}

/// One workout's set log. [sessionId] is the WHOOP session it belongs to;
/// null only for imported history without a reviewed link.
class LiftWorkout {
  LiftWorkout({
    String? id,
    required this.startedAt,
    this.endedAt,
    List<LiftExercise>? exercises,
    this.notes = '',
    this.splitName,
    this.splitId,
    List<String>? skipped,
    this.sessionId,
    this.origin = 'whoop',
  }) : id = id ?? _id(),
       exercises = exercises ?? [],
       skipped = skipped ?? [];

  final String id;
  DateTime startedAt;
  DateTime? endedAt;
  List<LiftExercise> exercises;
  String notes;
  String? splitName;
  String? splitId;

  /// Split exercises taken off today only, so syncing does not bring them back.
  List<String> skipped;
  String? sessionId;

  /// 'whoop' for a log made here, 'akshatos' for an imported one.
  String origin;

  bool get isActive => endedAt == null;
  int get setCount => exercises.fold(0, (n, e) => n + e.sets.length);

  /// How long a workout can sit with nothing logged before it asks whether it
  /// is finished (Lift Log's one-hour rule).
  static const inactivityDelay = Duration(hours: 1);

  /// When the latest set was logged, or when the workout started.
  DateTime get lastActivity {
    var t = startedAt;
    for (final e in exercises) {
      for (final s in e.sets) {
        if (s.completedAt.isAfter(t)) t = s.completedAt;
      }
    }
    return t;
  }

  LiftWorkout copy() => LiftWorkout(
    id: id,
    startedAt: startedAt,
    endedAt: endedAt,
    exercises: [for (final e in exercises) e.copy()],
    notes: notes,
    splitName: splitName,
    splitId: splitId,
    skipped: [...skipped],
    sessionId: sessionId,
    origin: origin,
  );

  void _active() {
    if (!isActive) throw LiftLogError.finished;
  }

  int _indexOf(String exerciseId) {
    final i = exercises.indexWhere((e) => e.id == exerciseId);
    if (i < 0) throw LiftLogError.exerciseNotFound;
    return i;
  }

  String addExercise({
    required String name,
    required LiftLoadMode loadMode,
    String equipmentNote = '',
    String? splitExerciseId,
  }) {
    _active();
    final e = LiftExercise(
      name: name,
      loadMode: loadMode,
      equipmentNote: equipmentNote,
      splitExerciseId: splitExerciseId,
    );
    if (e.name.isEmpty) throw LiftLogError.emptyExerciseName;
    exercises.add(e);
    return e.id;
  }

  /// Log a set. An exercise's first set moves it up to sit after the ones
  /// already done, so the third exercise done sits third.
  LiftSet addSet(
    String exerciseId, {
    required int reps,
    required double load,
    required DateTime at,
  }) {
    _active();
    if (reps <= 0) throw LiftLogError.invalidReps;
    if (!load.isFinite || load < 0) throw LiftLogError.invalidLoad;
    var i = _indexOf(exerciseId);
    if (exercises[i].sets.isEmpty) {
      final done = exercises.where((e) => e.sets.isNotEmpty).length;
      final e = exercises.removeAt(i);
      i = math.min(done, exercises.length);
      exercises.insert(i, e);
    }
    final set = LiftSet(reps: reps, load: load, completedAt: at);
    exercises[i].sets.add(set);
    return set;
  }

  void updateSet(
    String exerciseId,
    String setId, {
    required int reps,
    required double load,
  }) {
    _active();
    if (reps <= 0) throw LiftLogError.invalidReps;
    if (!load.isFinite || load < 0) throw LiftLogError.invalidLoad;
    final e = exercises[_indexOf(exerciseId)];
    final s = e.sets.where((x) => x.id == setId).firstOrNull;
    if (s == null) throw LiftLogError.setNotFound;
    s
      ..reps = reps
      ..load = load;
  }

  void removeSet(String exerciseId, String setId) {
    _active();
    final e = exercises[_indexOf(exerciseId)];
    final before = e.sets.length;
    e.sets.removeWhere((s) => s.id == setId);
    if (e.sets.length == before) throw LiftLogError.setNotFound;
  }

  LiftSet removeLastSet(String exerciseId) {
    _active();
    final e = exercises[_indexOf(exerciseId)];
    if (e.sets.isEmpty) throw LiftLogError.setNotFound;
    return e.sets.removeLast();
  }

  LiftExercise removeExercise(String exerciseId) {
    _active();
    return exercises.removeAt(_indexOf(exerciseId));
  }

  /// Today's order only, as a list drag reports it.
  void moveExercise(int from, int to) {
    _active();
    if (from < 0 || from >= exercises.length) return;
    final e = exercises.removeAt(from);
    exercises.insert(to.clamp(0, exercises.length), e);
  }

  /// Bring the open workout in step with its edited split — Lift Log's rule:
  /// new split exercises join, removed ones go unless sets were logged (those
  /// stay, unlinked), unlogged ones take renames/mode changes, unstarted ones
  /// follow the split's order, and today's skips stay skipped.
  void syncWith(LiftSplit split) {
    if (!isActive) return;
    splitId = split.id;
    splitName = split.name;
    final skip = skipped.toSet();
    for (final e in exercises.where((e) => e.splitExerciseId == null)) {
      final taken = exercises.map((x) => x.splitExerciseId).toSet();
      final match = split.exercises
          .where((s) => !taken.contains(s.id) && sameLiftName(s.name, e.name))
          .firstOrNull;
      if (match != null) e.splitExerciseId = match.id;
    }
    exercises = [
      for (final e in exercises)
        if (e.splitExerciseId == null)
          e
        else if (split.exercises.where((s) => s.id == e.splitExerciseId).firstOrNull
            case final src?)
          (e.sets.isEmpty
              ? (e
                  ..name = src.name
                  ..loadMode = src.loadMode
                  ..equipmentNote = src.equipmentNote)
              : e)
        else if (e.sets.isNotEmpty)
          (e..splitExerciseId = null),
    ];
    final linked = exercises.map((e) => e.splitExerciseId).toSet();
    for (final src in split.exercises) {
      if (linked.contains(src.id) || skip.contains(src.id)) continue;
      exercises.add(
        LiftExercise(
          name: src.name,
          loadMode: src.loadMode,
          equipmentNote: src.equipmentNote,
          splitExerciseId: src.id,
        ),
      );
    }
    final order = {
      for (var i = 0; i < split.exercises.length; i++) split.exercises[i].id: i,
    };
    final slots = [
      for (var i = 0; i < exercises.length; i++)
        if (exercises[i].sets.isEmpty &&
            order.containsKey(exercises[i].splitExerciseId))
          i,
    ];
    final arranged = [for (final i in slots) exercises[i]]
      ..sort(
        (a, b) => order[a.splitExerciseId]!.compareTo(order[b.splitExerciseId]!),
      );
    for (var k = 0; k < slots.length; k++) {
      exercises[slots[k]] = arranged[k];
    }
    skipped = [
      for (final s in skip)
        if (order.containsKey(s)) s,
    ];
  }

  /// End the log at [at]. Exercises left empty drop off; every performed set
  /// stays. A zero-set log is allowed to end (tracking without sets is a
  /// valid WHOOP workout); the caller removes an empty log instead of keeping
  /// it.
  void finish(DateTime at) {
    _active();
    exercises.removeWhere((e) => e.sets.isEmpty);
    endedAt = at.isBefore(startedAt) ? startedAt : at;
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'startedAt': startedAt.millisecondsSinceEpoch,
    if (endedAt != null) 'endedAt': endedAt!.millisecondsSinceEpoch,
    'exercises': [for (final e in exercises) e.toJson()],
    'notes': notes,
    if (splitName != null) 'splitName': splitName,
    if (splitId != null) 'splitID': splitId,
    if (skipped.isNotEmpty) 'skippedSplitExercises': skipped,
  };

  static LiftWorkout fromJson(
    Map m, {
    String? sessionId,
    String origin = 'whoop',
  }) => LiftWorkout(
    id: m['id'] as String,
    startedAt: DateTime.fromMillisecondsSinceEpoch(
      (m['startedAt'] as num).toInt(),
    ),
    endedAt: m['endedAt'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch((m['endedAt'] as num).toInt()),
    exercises: [
      for (final e in (m['exercises'] as List? ?? const []))
        LiftExercise.fromJson(e as Map),
    ],
    notes: (m['notes'] as String?) ?? '',
    splitName: m['splitName'] as String?,
    splitId: m['splitID'] as String?,
    skipped: [
      for (final s in (m['skippedSplitExercises'] as List? ?? const []))
        s as String,
    ],
    sessionId: sessionId,
    origin: origin,
  );
}

/// The last finished performance of an exercise with the same name and load
/// meaning — every set of it, as Lift Log shows.
typedef LiftPerformance = ({DateTime date, LiftExercise exercise});

/// A context-qualified record set by one set in a workout: more reps at a
/// load already lifted, or more load at a rep count already done, for the
/// same exercise, load meaning and equipment note. Quiet, never a ranking.
typedef LiftRecord = ({String exercise, String text});

List<LiftRecord> liftRecords(LiftWorkout w, List<LiftWorkout> earlier) {
  final out = <LiftRecord>[];
  for (final e in w.exercises) {
    final past = [
      for (final p in earlier)
        if (p.id != w.id && !p.isActive && p.startedAt.isBefore(w.startedAt))
          for (final x in p.exercises)
            if (sameLiftName(x.name, e.name) &&
                x.loadMode == e.loadMode &&
                liftNameKey(x.equipmentNote) == liftNameKey(e.equipmentNote))
              ...x.sets,
    ];
    if (past.isEmpty) continue; // nothing comparable: no record claimed
    LiftSet? bestReps, bestLoad;
    for (final s in e.sets) {
      final atLoad = past.where((p) => p.load == s.load);
      if (atLoad.isNotEmpty &&
          s.reps > atLoad.map((p) => p.reps).reduce(math.max) &&
          (bestReps == null || s.reps > bestReps.reps)) {
        bestReps = s;
      }
      final atReps = past.where((p) => p.reps >= s.reps);
      if (atReps.isNotEmpty &&
          s.load > atReps.map((p) => p.load).reduce(math.max) &&
          (bestLoad == null || s.load > bestLoad.load)) {
        bestLoad = s;
      }
    }
    if (bestReps != null) {
      out.add((
        exercise: e.name,
        text:
            '${bestReps.reps} reps at ${liftWeightText(bestReps.load)} ${e.loadMode.shortUnit}',
      ));
    }
    if (bestLoad != null && bestLoad != bestReps) {
      out.add((
        exercise: e.name,
        text:
            '${liftWeightText(bestLoad.load)} ${e.loadMode.shortUnit} for ${bestLoad.reps}',
      ));
    }
  }
  return out;
}

/// The durable store: the `lift_log` table and the user's splits.
class LiftLogDb {
  LiftLogDb._();

  static const splitsKey = 'lift.splits';

  static Future<void> createTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS lift_log (
        id          TEXT PRIMARY KEY,
        session_id  TEXT,
        started_at  INTEGER NOT NULL,
        ended_at    INTEGER,
        origin      TEXT NOT NULL DEFAULT 'whoop',
        json        TEXT NOT NULL,
        updated_at  INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_lift_log_session ON lift_log(session_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_lift_log_started ON lift_log(started_at)',
    );
  }

  static LiftWorkout _of(Map<String, Object?> r) => LiftWorkout.fromJson(
    jsonDecode(r['json'] as String) as Map,
    sessionId: r['session_id'] as String?,
    origin: (r['origin'] as String?) ?? 'whoop',
  );

  /// Write the whole workout in one statement; returns once it is durable.
  static Future<void> save(LiftWorkout w) async {
    final db = await LocalDb.instance;
    await db.insert('lift_log', {
      'id': w.id,
      'session_id': w.sessionId,
      'started_at': w.startedAt.millisecondsSinceEpoch,
      'ended_at': w.endedAt?.millisecondsSinceEpoch,
      'origin': w.origin,
      'json': jsonEncode(w.toJson()),
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> delete(String id) async {
    final db = await LocalDb.instance;
    await db.delete('lift_log', where: 'id = ?', whereArgs: [id]);
  }

  static Future<LiftWorkout?> forSession(String sessionId) async {
    final db = await LocalDb.instance;
    final rows = await db.query(
      'lift_log',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      limit: 1,
    );
    return rows.isEmpty ? null : _of(rows.first);
  }

  static Future<LiftWorkout?> active() async {
    final db = await LocalDb.instance;
    final rows = await db.query(
      'lift_log',
      where: 'ended_at IS NULL',
      orderBy: 'started_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : _of(rows.first);
  }

  /// Every finished log, newest first.
  static Future<List<LiftWorkout>> finished() async {
    final db = await LocalDb.instance;
    final rows = await db.query(
      'lift_log',
      where: 'ended_at IS NOT NULL',
      orderBy: 'started_at DESC',
    );
    return [for (final r in rows) _of(r)];
  }

  static Future<LiftPerformance?> lastPerformance(
    String name,
    LiftLoadMode mode, {
    String? excludingId,
  }) async {
    for (final w in await finished()) {
      if (w.id == excludingId) continue;
      for (final e in w.exercises) {
        if (sameLiftName(e.name, name) &&
            e.loadMode == mode &&
            e.sets.isNotEmpty) {
          return (date: w.startedAt, exercise: e);
        }
      }
    }
    return null;
  }

  /// Exercises logged before, one per name, most recent first — Lift Log's
  /// Add exercise suggestions.
  static Future<List<LiftExercise>> recentExercises() async {
    final seen = <String>{};
    return [
      for (final w in await finished())
        for (final e in w.exercises)
          if (seen.add(liftNameKey(e.name))) e,
    ];
  }

  static Future<List<LiftSplit>> splits() async {
    final raw = await CalculationStore.read(splitsKey);
    if (raw == null) {
      final start = LiftSplit.starting;
      await saveSplits(start);
      return start;
    }
    try {
      return [
        for (final s in jsonDecode(raw) as List) LiftSplit.fromJson(s as Map),
      ];
    } catch (_) {
      return LiftSplit.starting;
    }
  }

  static Future<void> saveSplits(List<LiftSplit> splits) async {
    final checked = LiftSplit.validatedList(splits);
    await CalculationStore.write(
      splitsKey,
      jsonEncode([for (final s in checked) s.toJson()]),
    );
  }

  /// One row per set, with its load meaning so `42.5 lb/side` is never read
  /// as a 42.5 lb total — Lift Log's CSV columns.
  static Future<String> csv() async {
    final all = [...await finished()]
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    String f(String v) =>
        v.contains(RegExp('[,"\n]')) ? '"${v.replaceAll('"', '""')}"' : v;
    final lines = ['date,exercise,load_mode,load_lbs,reps,set,equipment_notes'];
    for (final w in all) {
      for (final e in w.exercises) {
        for (var i = 0; i < e.sets.length; i++) {
          final s = e.sets[i];
          lines.add(
            [
              s.completedAt.toUtc().toIso8601String(),
              e.name,
              e.loadMode.name,
              liftWeightText(s.load),
              '${s.reps}',
              '${i + 1}',
              e.equipmentNote,
            ].map(f).join(','),
          );
        }
      }
    }
    return '${lines.join('\n')}\n';
  }
}

// ── AkshatOS import ────────────────────────────────────────────────────────

/// Swift's default JSON date: seconds since 2001-01-01 UTC.
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

/// A validated, not-yet-applied Lift Log import, for the preview.
class LiftImportPlan {
  LiftImportPlan(this.add, this.unchanged, this.conflicts, this.splits);

  /// Workouts not here yet (by their AkshatOS id).
  final List<LiftWorkout> add;

  /// Already imported and identical — repeating an import is a no-op.
  final int unchanged;

  /// Same id here with different content: reported, never overwritten.
  final List<String> conflicts;

  /// The backup's splits, if it carried any (applied only when chosen).
  final List<LiftSplit>? splits;
}

/// Read an AkshatOS `lift-log.json` (standalone or the hub backup's part),
/// validating the whole payload before anything changes. An active AkshatOS
/// workout is refused: finish it there first, so neither draft is lost.
Future<LiftImportPlan> planLiftImport(String json) async {
  final m = jsonDecode(json);
  if (m is! Map || m['version'] != 1 || m['workouts'] is! List) {
    throw const FormatException('This is not a Lift Log backup.');
  }
  final workouts = <LiftWorkout>[];
  for (final raw in m['workouts'] as List) {
    final w = raw as Map;
    if (w['endedAt'] == null) {
      throw const FormatException(
        'The backup has an unfinished workout. Finish it in AkshatOS, back up again, then import.',
      );
    }
    final exercises = <LiftExercise>[];
    for (final e in (w['exercises'] as List? ?? const [])) {
      final ex = e as Map;
      final mode = LiftLoadMode.parse(ex['loadMode']);
      if (mode == null) throw FormatException('Unknown load mode ${ex['loadMode']}');
      final sets = <LiftSet>[];
      for (final s in (ex['sets'] as List? ?? const [])) {
        final st = s as Map;
        final reps = (st['reps'] as num).toInt();
        final load = (st['load'] as num).toDouble();
        if (reps <= 0) throw LiftLogError.invalidReps;
        if (!load.isFinite || load < 0) throw LiftLogError.invalidLoad;
        sets.add(
          LiftSet(
            id: st['id'] as String,
            reps: reps,
            load: load,
            completedAt: _appleDate(st['completedAt']),
          ),
        );
      }
      final name = (ex['name'] as String).trim();
      if (name.isEmpty) throw LiftLogError.emptyExerciseName;
      exercises.add(
        LiftExercise(
          id: ex['id'] as String,
          name: name,
          loadMode: mode,
          equipmentNote: (ex['equipmentNote'] as String?) ?? '',
          sets: sets,
          splitExerciseId: ex['splitExerciseID'] as String?,
        ),
      );
    }
    final started = _appleDate(w['startedAt']);
    final ended = _appleDate(w['endedAt']);
    if (ended.isBefore(started)) throw const FormatException('A workout ends before it starts.');
    workouts.add(
      LiftWorkout(
        id: w['id'] as String,
        startedAt: started,
        endedAt: ended,
        exercises: exercises,
        notes: (w['notes'] as String?) ?? '',
        splitName: w['splitName'] as String?,
        splitId: w['splitID'] as String?,
        origin: 'akshatos',
      ),
    );
  }
  if (workouts.map((w) => w.id).toSet().length != workouts.length) {
    throw LiftLogError.duplicate;
  }
  List<LiftSplit>? splits;
  if (m['splits'] is List) {
    splits = LiftSplit.validatedList([
      for (final s in m['splits'] as List) LiftSplit.fromJson(s as Map),
    ]);
  }
  final db = await LocalDb.instance;
  final add = <LiftWorkout>[];
  final conflicts = <String>[];
  var unchanged = 0;
  for (final w in workouts) {
    final rows = await db.query(
      'lift_log',
      columns: ['json'],
      where: 'id = ?',
      whereArgs: [w.id],
    );
    if (rows.isEmpty) {
      add.add(w);
      continue;
    }
    final here = jsonDecode(rows.first['json'] as String) as Map;
    final there = w.toJson();
    if (jsonEncode(here['exercises']) == jsonEncode(there['exercises'])) {
      unchanged++;
    } else {
      conflicts.add(w.id);
    }
  }
  return LiftImportPlan(add, unchanged, conflicts, splits);
}

/// Apply a previewed plan: imported workouts land as lift history only (no
/// WHOOP session, no strain, no calories), all in one transaction.
Future<int> applyLiftImport(LiftImportPlan plan, {bool replaceSplits = false}) async {
  final db = await LocalDb.instance;
  final now = DateTime.now().millisecondsSinceEpoch;
  await db.transaction((tx) async {
    for (final w in plan.add) {
      await tx.insert('lift_log', {
        'id': w.id,
        'session_id': null,
        'started_at': w.startedAt.millisecondsSinceEpoch,
        'ended_at': w.endedAt?.millisecondsSinceEpoch,
        'origin': 'akshatos',
        'json': jsonEncode(w.toJson()),
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  });
  if (replaceSplits && plan.splits != null) {
    await LiftLogDb.saveSplits(plan.splits!);
  }
  return plan.add.length;
}
