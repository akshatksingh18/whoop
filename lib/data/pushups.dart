// Pushups inside WHOOP (build 86): AkshatOS Pushup Reminder's movement-break
// day, ported with its contract (`../akshatos/features.md`). Start my day,
// a reminder every interval (45 min by default) with ten-minute nudges when
// one is ignored, Done (+1 completed set) or Pause from the notification or
// the screen, an optional Home auto-pause, a daily set goal with its own
// streak, and a recap when the day ends.
//
// What it is not: a workout. A Done tap is one completed set, never a rep
// count, a duration, heart rate or calories, and nothing here feeds strain,
// maintenance or the activity streak. Notifications iOS showed are never
// counted; only explicit Done actions are.
//
// Storage: one `pushup_session` row per session, the session as JSON (the
// AkshatOS shape, so its backup imports and exports without translation),
// and the interval/goal as calculation anchors so database backups carry
// them. The Home coordinate is NOT here: it stays in this phone's
// preferences only (`home_region.dart`), outside every backup.

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import 'calculation_store.dart';
import 'day_label.dart';
import 'db.dart';

/// Minutes between ordinary reminders, unless the user picks another.
const int kPushupDefaultInterval = 45;

/// Completed sets a day needs for the streak; zero turns the streak off.
const int kPushupDefaultGoal = 8;

/// Ten minutes between automatic nudges after an ignored reminder.
const int kPushupNudgeMinutes = 10;

/// Pause reason used only by the Home boundary. Only a pause carrying it may
/// be resumed by arriving home.
const String kHomeAwayReason = 'homeAwayAutomation';

/// Apple's reference date (2001-01-01 UTC) in Unix seconds: Swift's default
/// JSON date encoding, which AkshatOS backups use.
const int _appleEpochOffsetSec = 978307200;

double _apple(DateTime d) =>
    d.millisecondsSinceEpoch / 1000 - _appleEpochOffsetSec;
DateTime _fromApple(Object? v) => DateTime.fromMillisecondsSinceEpoch(
  (((v as num).toDouble() + _appleEpochOffsetSec) * 1000).round(),
);

String _uuid() {
  final r = math.Random.secure();
  String hex(int n) =>
      List.generate(n, (_) => r.nextInt(16).toRadixString(16)).join();
  return '${hex(8)}-${hex(4)}-4${hex(3)}-${(8 + r.nextInt(4)).toRadixString(16)}'
          '${hex(3)}-${hex(12)}'
      .toUpperCase();
}

enum PushupEventKind {
  done,
  pause,
  resume,
  // Read for old AkshatOS history only; nothing new writes it.
  snooze,
}

class PushupEvent {
  PushupEvent({String? id, required this.at, required this.kind, this.source})
    : id = id ?? _uuid();

  final String id;
  final DateTime at;
  final PushupEventKind kind;
  final String? source;

  Map<String, Object?> toJson() => {
    'id': id,
    'date': _apple(at),
    'kind': kind.name,
    'source': ?source,
  };

  static PushupEvent fromJson(Map m) => PushupEvent(
    id: m['id'] as String,
    at: _fromApple(m['date']),
    kind: PushupEventKind.values.byName(m['kind'] as String),
    source: m['source'] as String?,
  );
}

enum PushupState { running, paused, ended }

class PushupSession {
  PushupSession({
    String? id,
    required this.day,
    required this.started,
    this.ended,
    required this.interval,
    this.goal,
    this.state = PushupState.paused,
    List<PushupEvent>? events,
    List<String>? receipts,
    this.pauseReason,
    this.anchor,
  }) : id = id ?? _uuid(),
       events = events ?? [],
       receipts = receipts ?? [];

  final String id;
  final String day;
  final DateTime started;
  DateTime? ended;
  final int interval;

  /// The daily goal captured when the day started; null when the streak was
  /// off. A later goal change never rewrites this.
  final int? goal;
  PushupState state;
  final List<PushupEvent> events;

  /// Ids of notification actions already applied, so a replayed callback is
  /// a no-op.
  final List<String> receipts;
  String? pauseReason;

  /// The first deadline of the current regular cadence. Later nudge times
  /// are derived from it, so leaving and reopening never restarts the clock.
  DateTime? anchor;

  int get count => events.where((e) => e.kind == PushupEventKind.done).length;
  bool get isActive => state != PushupState.ended;
  List<DateTime> get completions => [
    for (final e in events)
      if (e.kind == PushupEventKind.done) e.at,
  ]..sort();

  /// Log [e] once; an ended day or a repeated id changes nothing.
  bool log(PushupEvent e) {
    if (!isActive || events.any((x) => x.id == e.id)) return false;
    events.add(e);
    return true;
  }

  /// Remove the most recent completed set (Undo).
  bool undo() {
    if (!isActive) return false;
    final i = events.lastIndexWhere((e) => e.kind == PushupEventKind.done);
    if (i < 0) return false;
    events.removeAt(i);
    return true;
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'day': day,
    'started': _apple(started),
    if (ended != null) 'ended': _apple(ended!),
    'interval': interval,
    'goal': ?goal,
    'state': state.name,
    'events': [for (final e in events) e.toJson()],
    'actionReceipts': receipts,
    'pauseReason': ?pauseReason,
    if (anchor != null) 'reminderCadenceAnchor': _apple(anchor!),
  };

  static PushupSession fromJson(Map m) => PushupSession(
    id: m['id'] as String,
    day: m['day'] as String,
    started: _fromApple(m['started']),
    ended: m['ended'] == null ? null : _fromApple(m['ended']),
    interval: (m['interval'] as num).toInt(),
    goal: (m['goal'] as num?)?.toInt(),
    state: PushupState.values.byName(m['state'] as String? ?? 'paused'),
    events: [
      for (final e in (m['events'] as List? ?? const []))
        PushupEvent.fromJson(e as Map),
    ],
    receipts: [
      for (final r in (m['actionReceipts'] as List? ?? const [])) r as String,
    ],
    pauseReason: m['pauseReason'] as String?,
    anchor: m['reminderCadenceAnchor'] == null
        ? null
        : _fromApple(m['reminderCadenceAnchor']),
  );
}

/// The next reminder deadline a running day's single clock shows: the
/// ordinary reminder until it is due, then each ten-minute nudge in turn.
DateTime? pushupNextDue(PushupSession s, DateTime now) {
  final a = s.anchor;
  if (s.state != PushupState.running || a == null) return null;
  if (a.isAfter(now)) return a;
  final over = now.difference(a).inSeconds;
  final steps = over ~/ (kPushupNudgeMinutes * 60) + 1;
  return a.add(Duration(minutes: kPushupNudgeMinutes * steps));
}

/// Current and best streak over local days whose completed sets reached the
/// goal captured that day. Today below goal does not break it until the day
/// is over; a future-dated day never counts.
({int current, int best}) pushupStreaks(
  List<PushupSession> sessions,
  DateTime now,
) {
  final today = dayLabelOf(now);
  final byDay = <String, List<PushupSession>>{};
  for (final s in sessions) {
    (byDay[s.day] ??= []).add(s);
  }
  final qualified = <String>{};
  byDay.forEach((day, v) {
    if (day.compareTo(today) > 0) return;
    v.sort((a, b) => a.started.compareTo(b.started));
    final goal = v.first.goal;
    if (goal == null || goal <= 0) return;
    if (v.fold<int>(0, (n, s) => n + s.count) >= goal) qualified.add(day);
  });
  var best = 0, run = 0;
  DateTime? prev;
  for (final d in qualified.toList()..sort()) {
    final t = DateTime.parse(d);
    final next = prev == null
        ? null
        : DateTime(prev.year, prev.month, prev.day + 1);
    run = next == t ? run + 1 : 1;
    best = math.max(best, run);
    prev = t;
  }
  var cursor = DateTime(now.year, now.month, now.day);
  if (!qualified.contains(today)) {
    cursor = DateTime(cursor.year, cursor.month, cursor.day - 1);
  }
  var current = 0;
  while (qualified.contains(dayLabelOf(cursor))) {
    current++;
    cursor = DateTime(cursor.year, cursor.month, cursor.day - 1);
  }
  return (current: current, best: best);
}

enum PushupGoalStatus { notSet, reached, atRisk, missed }

/// One local day of Pushups, every session that day together.
class PushupDay {
  PushupDay({
    required this.day,
    required this.sessions,
    required this.sets,
    required this.goal,
    required this.status,
    required this.active,
    required this.paused,
    required this.pauses,
    required this.completions,
    required this.intervals,
  });

  final String day;
  final List<PushupSession> sessions;
  final int sets;
  final int? goal;
  final PushupGoalStatus status;
  final Duration active, paused;
  final List<({DateTime from, DateTime to})> pauses;
  final List<DateTime> completions;
  final List<int> intervals;
  DateTime get started => sessions.first.started;
  DateTime? get ended => sessions.every((s) => s.ended != null)
      ? sessions.map((s) => s.ended!).reduce((a, b) => a.isAfter(b) ? a : b)
      : null;

  static PushupDay? of(String day, List<PushupSession> all, DateTime now) {
    final v = [
      for (final s in all)
        if (s.day == day) s,
    ]..sort((a, b) => a.started.compareTo(b.started));
    if (v.isEmpty) return null;
    final sets = v.fold<int>(0, (n, s) => n + s.count);
    final goal = v.first.goal;
    final status = goal == null || goal <= 0
        ? PushupGoalStatus.notSet
        : sets >= goal
        ? PushupGoalStatus.reached
        : day == dayLabelOf(now)
        ? PushupGoalStatus.atRisk
        : PushupGoalStatus.missed;
    final pauses = <({DateTime from, DateTime to})>[];
    var active = Duration.zero;
    for (final s in v) {
      final end = s.ended ?? now;
      final first = pauses.length;
      DateTime? from;
      for (final e in [...s.events]..sort((a, b) => a.at.compareTo(b.at))) {
        final at = e.at.isBefore(s.started)
            ? s.started
            : e.at.isAfter(end)
            ? end
            : e.at;
        if (e.kind == PushupEventKind.pause && from == null) from = at;
        if (e.kind == PushupEventKind.resume && from != null) {
          pauses.add((from: from, to: at));
          from = null;
        }
      }
      if (from != null) pauses.add((from: from, to: end));
      final pausedHere = pauses
          .sublist(first)
          .fold(Duration.zero, (a, p) => a + p.to.difference(p.from));
      final whole = end.difference(s.started);
      if (whole > pausedHere) active += whole - pausedHere;
    }
    return PushupDay(
      day: day,
      sessions: v,
      sets: sets,
      goal: goal,
      status: status,
      active: active,
      paused: pauses.fold(Duration.zero, (a, p) => a + p.to.difference(p.from)),
      pauses: pauses,
      completions: [for (final s in v) ...s.completions]..sort(),
      intervals: {for (final s in v) s.interval}.toList()..sort(),
    );
  }

  /// Every day kept, newest first.
  static List<PushupDay> all(List<PushupSession> sessions, DateTime now) {
    final days = {for (final s in sessions) s.day}.toList()
      ..sort((a, b) => b.compareTo(a));
    return [for (final d in days) ?PushupDay.of(d, sessions, now)];
  }
}

/// A notification action or screen command waiting to be applied.
class PushupAction {
  PushupAction({
    required this.id,
    required this.kind,
    required this.sessionId,
    required this.at,
    this.source = 'notification',
    String? eventId,
  }) : eventId = eventId ?? _uuid();

  final String id;
  final String kind; // 'done' | 'pause'
  final String sessionId;
  final DateTime at;
  final String source;
  final String eventId;

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind,
    'session': sessionId,
    'at': at.millisecondsSinceEpoch,
    'source': source,
    'event': eventId,
  };

  static PushupAction fromJson(Map m) => PushupAction(
    id: m['id'] as String,
    kind: m['kind'] as String,
    sessionId: m['session'] as String,
    at: DateTime.fromMillisecondsSinceEpoch((m['at'] as num).toInt()),
    source: (m['source'] as String?) ?? 'notification',
    eventId: m['event'] as String?,
  );

  /// Apply to [s] once. Done counts only on its own day; Pause always
  /// applies. Returns whether anything changed.
  bool applyTo(PushupSession s) {
    if (s.id != sessionId || !s.isActive || s.receipts.contains(id)) {
      return false;
    }
    if (at.isBefore(s.started)) return false;
    switch (kind) {
      case 'done':
        if (dayLabelOf(at) != s.day) return false;
        s.log(
          PushupEvent(
            id: eventId,
            at: at,
            kind: PushupEventKind.done,
            source: source,
          ),
        );
        if (s.state == PushupState.running) {
          s.anchor = at.add(Duration(minutes: s.interval));
        }
      case 'pause':
        if (s.state == PushupState.running || s.pauseReason != source) {
          s.log(
            PushupEvent(
              id: eventId,
              at: at,
              kind: PushupEventKind.pause,
              source: source,
            ),
          );
        }
        s.state = PushupState.paused;
        s.pauseReason = source;
        s.anchor = null;
      default:
        return false;
    }
    s.receipts.add(id);
    return true;
  }
}

// ── Home boundary decisions (pure) ───────────────────────────────────────────

enum HomePresence { unknown, inside, outside }

/// What one Home boundary event should do to the day. Leaving pauses only a
/// running day; arriving resumes only the same day paused BY leaving; a
/// manual resume while outside suppresses repeat exit pauses until the next
/// arrival. Duplicate events within two minutes are ignored.
class HomeAutomation {
  HomeAutomation({
    this.presence = HomePresence.unknown,
    this.suppressExit = false,
    this.lastEvent,
  });

  HomePresence presence;
  bool suppressExit;
  DateTime? lastEvent;

  static const debounce = Duration(minutes: 2);

  /// 'pause', 'resume' or null.
  String? accept(
    HomePresence now,
    DateTime at, {
    required PushupSession? active,
    required String today,
  }) {
    if (now == HomePresence.unknown) return null;
    final last = lastEvent;
    if (now == presence &&
        last != null &&
        at.difference(last).abs() < debounce) {
      return null;
    }
    presence = now;
    lastEvent = at;
    if (now == HomePresence.inside) {
      suppressExit = false;
      return active != null &&
              active.day == today &&
              active.state == PushupState.paused &&
              active.pauseReason == kHomeAwayReason
          ? 'resume'
          : null;
    }
    return active?.state == PushupState.running && !suppressExit
        ? 'pause'
        : null;
  }

  Map<String, Object?> toJson() => {
    'presence': presence.name,
    'suppressExit': suppressExit,
    'last': lastEvent?.millisecondsSinceEpoch,
  };

  static HomeAutomation fromJson(Map m) => HomeAutomation(
    presence: HomePresence.values.byName(m['presence'] as String? ?? 'unknown'),
    suppressExit: m['suppressExit'] == true,
    lastEvent: m['last'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch((m['last'] as num).toInt()),
  );
}

// ── store ────────────────────────────────────────────────────────────────────

class PushupDb {
  PushupDb._();

  static const intervalKey = 'pushups.interval';
  static const goalKey = 'pushups.goal';

  /// Bumped on every write so open screens re-read.
  static final changes = ValueNotifier<int>(0);

  static Future<void> createTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pushup_session (
        id          TEXT PRIMARY KEY,
        day         TEXT NOT NULL,
        state       TEXT NOT NULL,
        origin      TEXT NOT NULL DEFAULT 'whoop',
        json        TEXT NOT NULL,
        updated_at  INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_pushup_session_day ON pushup_session(day)',
    );
  }

  static Future<void> save(PushupSession s, {String origin = 'whoop'}) async {
    final db = await LocalDb.instance;
    await db.insert('pushup_session', {
      'id': s.id,
      'day': s.day,
      'state': s.state.name,
      'origin': origin,
      'json': jsonEncode(s.toJson()),
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    changes.value++;
  }

  static Future<List<PushupSession>> all() async {
    final db = await LocalDb.instance;
    return [
      for (final r in await db.query('pushup_session', orderBy: 'day ASC'))
        PushupSession.fromJson(jsonDecode(r['json'] as String) as Map),
    ];
  }

  static Future<PushupSession?> active() async {
    final db = await LocalDb.instance;
    final rows = await db.query(
      'pushup_session',
      where: "state != 'ended'",
      orderBy: 'day DESC',
      limit: 1,
    );
    return rows.isEmpty
        ? null
        : PushupSession.fromJson(
            jsonDecode(rows.first['json'] as String) as Map,
          );
  }

  /// Completed history only; an open day stays.
  static Future<int> deleteHistory() async {
    final db = await LocalDb.instance;
    final n = await db.delete('pushup_session', where: "state = 'ended'");
    changes.value++;
    return n;
  }

  static Future<int> interval() async =>
      int.tryParse(await CalculationStore.read(intervalKey) ?? '') ??
      kPushupDefaultInterval;
  static Future<int> goal() async =>
      int.tryParse(await CalculationStore.read(goalKey) ?? '') ??
      kPushupDefaultGoal;

  static Future<void> setInterval(int minutes) async {
    if (minutes < 1 || minutes > 180) {
      throw RangeError('The interval is 1 to 180 minutes.');
    }
    await CalculationStore.write(intervalKey, '$minutes');
  }

  static Future<void> setGoal(int sets) async {
    if (sets < 0 || sets > 100) throw RangeError('The goal is 0 to 100 sets.');
    await CalculationStore.write(goalKey, '$sets');
  }
}

// ── AkshatOS backup (SquatsBackup version 1) ─────────────────────────────────

class PushupImportPlan {
  PushupImportPlan(
    this.add,
    this.unchanged,
    this.conflicts,
    this.interval,
    this.goal,
  );
  final List<PushupSession> add;
  final int unchanged;
  final List<String> conflicts;
  final int interval, goal;
}

/// Read an AkshatOS Pushup Reminder backup (or the hub backup's part),
/// validating the whole file first. An open AkshatOS day is refused: end it
/// there, so no reminders are restored running here.
Future<PushupImportPlan> planPushupImport(String json) async {
  final Object? m;
  try {
    m = jsonDecode(json);
  } catch (_) {
    throw const FormatException('This is not a Pushup Reminder backup.');
  }
  if (m is! Map || m['version'] != 1 || m['sessions'] is! List) {
    throw const FormatException('This is not a Pushup Reminder backup.');
  }
  final settings = m['settings'];
  final interval = (settings is Map ? settings['interval'] as num? : null)
      ?.toInt();
  final goal = (settings is Map ? settings['goal'] as num? : null)?.toInt();
  if (interval == null ||
      interval < 1 ||
      interval > 180 ||
      goal == null ||
      goal < 0 ||
      goal > 100) {
    throw const FormatException('The backup has invalid Pushup settings.');
  }
  final sessions = <PushupSession>[];
  try {
    for (final raw in m['sessions'] as List) {
      sessions.add(PushupSession.fromJson(raw as Map));
    }
  } catch (_) {
    throw const FormatException('The backup has unreadable Pushup history.');
  }
  if ({for (final s in sessions) s.id}.length != sessions.length) {
    throw const FormatException('The backup repeats a day.');
  }
  for (final s in sessions) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s.day) ||
        s.interval < 1 ||
        s.interval > 180) {
      throw const FormatException(
        'The backup has inconsistent Pushup history.',
      );
    }
    if (s.isActive) {
      throw const FormatException(
        'The backup has a day still open. End it in AkshatOS, back up again, then import.',
      );
    }
  }
  final here = {for (final s in await PushupDb.all()) s.id: s};
  final add = <PushupSession>[];
  final conflicts = <String>[];
  var unchanged = 0;
  for (final s in sessions) {
    final h = here[s.id];
    if (h == null) {
      add.add(s);
    } else if (jsonEncode(h.toJson()) == jsonEncode(s.toJson())) {
      unchanged++;
    } else {
      conflicts.add(s.day);
    }
  }
  add.sort((a, b) => b.day.compareTo(a.day));
  return PushupImportPlan(add, unchanged, conflicts, interval, goal);
}

/// Add the plan's days; existing ones are never overwritten. With
/// [useSettings], the backup's interval and goal replace this phone's.
Future<int> applyPushupImport(
  PushupImportPlan plan, {
  bool useSettings = false,
}) async {
  for (final s in plan.add) {
    await PushupDb.save(s, origin: 'akshatos');
  }
  if (useSettings) {
    await PushupDb.setInterval(plan.interval);
    await PushupDb.setGoal(plan.goal);
  }
  return plan.add.length;
}

/// Finished days and settings in AkshatOS's own backup shape (version 1).
Future<String> exportPushupBackup() async {
  final sessions = [
    for (final s in await PushupDb.all())
      if (!s.isActive) s.toJson(),
  ];
  return const JsonEncoder.withIndent('  ').convert({
    'version': 1,
    'createdAt': _apple(DateTime.now()),
    'sessions': sessions,
    'settings': {
      'interval': await PushupDb.interval(),
      'goal': await PushupDb.goal(),
    },
  });
}
