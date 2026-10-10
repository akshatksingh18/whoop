// The activity streak: how many days in a row had at least ten minutes of
// purposeful exercise (running, walking, lifting or another workout) OR
// completed that day's measured step goal (build 86 added lifting and other
// exercise, B86-10). A planned Rest day or a limited "Life happens" day keeps
// the streak going without counting as activity. [moveStreak] is pure, so the
// day rules (today still open, midnight, DST) are testable without a clock;
// [loadMoveStreak] feeds it from the sessions table.

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/db.dart';
import '../data/calculation_store.dart';
import '../data/day_label.dart';
import '../data/local_repository.dart' show kDefaultStepGoal;
import '../gps/workout_clock.dart';
import '../gps/run_history.dart' show isRunType, isWalkType;
import 'profile.dart' show isLiftType;

/// What kind of exercise a session was, for the streak's dots; later
/// values outrank earlier ones when a day has several.
enum MoveKind { other, walk, lift, run }

/// One exercise session, as the streak needs it.
typedef MoveSession = ({DateTime start, int minutes, MoveKind kind});

/// How much exercise a day needs to count.
const int kStreakMinutes = 10;

/// Session types that are not physical exercise for the streak: stillness
/// and recovery practices, and everyday chores logged as activities. Walking
/// types count even when everyday (a dog walk is a walk).
const Set<String> kNotExerciseTypes = {
  'breathwork',
  'meditation',
  'sauna',
  'cold_plunge',
  'housework',
  'gardening',
  'childcare',
  'diy',
  'shopping',
  'intimacy',
};

/// Whether a session of [type] is purposeful physical exercise.
bool isExerciseType(String? type) {
  if (type == null) return false;
  final t = type.toLowerCase().replaceAll(' ', '_');
  return isWalkType(t) || !kNotExerciseTypes.contains(t);
}

/// The streak's kind for a session [type].
MoveKind moveKindOf(String? type) => isRunType(type)
    ? MoveKind.run
    : isWalkType(type)
    ? MoveKind.walk
    : isLiftType(type)
    ? MoveKind.lift
    : MoveKind.other;

/// What one of the last seven days was.
enum MoveDay { none, walk, run, goal, lift, other, rest, life }

/// A protected day: planned Rest or an unplanned "Life happens".
enum Protection { rest, life }

typedef MoveStreak = ({
  int current,
  int longest,
  bool todayDone,
  List<MoveDay> last7, // oldest first, today last
  // Protected days inside the current streak, shown apart from activity.
  int protectedInStreak,
});

/// The protection allowance (taken from the build-86 proposal): at most
/// [kProtectWeekMax] protected days in any rolling seven, of which at most
/// [kLifeWeekMax] "Life happens", and never two protected days in a row. A
/// protected day keeps continuity; it is never an activity day.
const int kProtectWeekMax = 2;
const int kLifeWeekMax = 1;

/// Why [kind] cannot protect [date] given [ledger], or null when it can.
String? protectionRefusal(
  Map<String, Protection> ledger,
  String date,
  Protection kind,
) {
  final d = DateTime.parse(date);
  String label(int off) => dayLabelOf(DateTime(d.year, d.month, d.day + off));
  if (ledger.containsKey(label(-1)) || ledger.containsKey(label(1))) {
    return 'Two protected days in a row would not keep the streak honest.';
  }
  // Every rolling seven-day window containing [date] stays inside the limits.
  for (var start = -6; start <= 0; start++) {
    var all = 1, life = kind == Protection.life ? 1 : 0;
    for (var i = start; i < start + 7; i++) {
      if (i == 0) continue;
      final k = ledger[label(i)];
      if (k == null) continue;
      all++;
      if (k == Protection.life) life++;
    }
    if (all > kProtectWeekMax) {
      return 'Up to $kProtectWeekMax protected days in any seven.';
    }
    if (life > kLifeWeekMax) return 'One Life happens day in any seven.';
  }
  return null;
}

/// Days are local calendar days; a session belongs to the day it started.
/// A day counts once its sessions add up to [minMinutes]. Today does not
/// break the streak until it is over: with nothing yet, the streak is
/// counted up to yesterday.
MoveStreak moveStreak(
  List<MoveSession> sessions,
  DateTime now, {
  int minMinutes = kStreakMinutes,
  Set<String> stepDays = const {},
  Map<String, Protection> protectedDays = const {},
}) {
  final minutes = <int, int>{};
  final kinds = <int, Set<MoveKind>>{};
  int key(DateTime d) => d.year * 10000 + d.month * 100 + d.day;
  for (final s in sessions) {
    if (s.minutes <= 0) continue;
    final k = key(s.start);
    minutes[k] = (minutes[k] ?? 0) + s.minutes;
    (kinds[k] ??= {}).add(s.kind);
  }
  final goals = {for (final d in stepDays) key(DateTime.parse(d))};
  for (final k in goals) {
    minutes.putIfAbsent(k, () => 0);
  }
  final shield = {
    for (final e in protectedDays.entries) key(DateTime.parse(e.key)): e.value,
  };
  bool counts(int k) => (minutes[k] ?? 0) >= minMinutes || goals.contains(k);
  bool keeps(int k) => counts(k) || shield.containsKey(k);
  DateTime day(int back) => DateTime(now.year, now.month, now.day - back);

  final todayDone = counts(key(day(0)));
  var current = 0, kept = 0;
  // Today still open and neither earned nor protected: count to yesterday.
  for (var back = keeps(key(day(0))) ? 0 : 1; ; back++) {
    final k = key(day(back));
    if (!keeps(k)) break;
    if (counts(k)) {
      current++;
    } else {
      kept++;
    }
  }

  // Longest run of activity days, bridged (never counted) by protected days.
  var longest = 0;
  final all = {...minutes.keys, ...shield.keys}.toList()..sort();
  var run = 0;
  DateTime? prev;
  for (final k in all) {
    if (!keeps(k)) continue;
    final d = DateTime(k ~/ 10000, k ~/ 100 % 100, k % 100);
    final next = prev == null
        ? null
        : DateTime(prev.year, prev.month, prev.day + 1);
    if (next != d) run = 0;
    if (counts(k)) run++;
    if (run > longest) longest = run;
    prev = d;
  }

  return (
    current: current,
    longest: longest < current ? current : longest,
    todayDone: todayDone,
    last7: [
      for (var back = 6; back >= 0; back--)
        () {
          final k = key(day(back));
          if (!counts(k)) {
            return switch (shield[k]) {
              Protection.rest => MoveDay.rest,
              Protection.life => MoveDay.life,
              null => MoveDay.none,
            };
          }
          if ((minutes[k] ?? 0) < minMinutes) return MoveDay.goal;
          final ks = kinds[k] ?? const {};
          if (ks.contains(MoveKind.run)) return MoveDay.run;
          if (ks.contains(MoveKind.lift)) return MoveDay.lift;
          if (ks.contains(MoveKind.walk)) return MoveDay.walk;
          return MoveDay.other;
        }(),
    ],
    protectedInStreak: kept,
  );
}

/// The protection ledger: planned Rest and "Life happens" days, by date.
/// Kept with the other dated calculation anchors so encrypted backups,
/// salvage and reset carry it; computing the streak only reads it.
class StreakProtection {
  static const key = 'streak.protection';

  static Future<Map<String, Protection>> read() async {
    try {
      final m = jsonDecode(await CalculationStore.read(key) ?? '{}');
      if (m is! Map) return {};
      return {
        for (final e in m.entries)
          if (e.value == 'rest' || e.value == 'life')
            e.key as String: e.value == 'rest'
                ? Protection.rest
                : Protection.life,
      };
    } catch (_) {
      return {};
    }
  }

  /// Protect [date]; returns why not when the allowance refuses it.
  static Future<String?> protect(String date, Protection kind) async {
    final ledger = await read();
    final why = protectionRefusal(ledger, date, kind);
    if (why != null) return why;
    ledger[date] = kind;
    await _write(ledger);
    return null;
  }

  static Future<void> clear(String date) async {
    final ledger = await read()
      ..remove(date);
    await _write(ledger);
  }

  static Future<void> _write(Map<String, Protection> l) =>
      CalculationStore.write(
        key,
        jsonEncode({for (final e in l.entries) e.key: e.value.name}),
      );
}

/// Every run and walk this phone holds, as a streak. Read straight from the
/// sessions table, because a streak can reach further back than a month.
/// Null when the table cannot be read.
/// Dated step targets and earned threshold. Targets before migration are unknown.
class StepGoals {
  static const key = 'steps.goal_history';
  static Future<dynamic>? _tail;
  static Future<void> flush() async {
    await _tail;
  }

  static int _pending = 0;
  static bool get busy => _pending > 0;
  static Future<T> _serial<T>(Future<T> Function() action) {
    _pending++;
    final prior = _tail;
    late Future<T> job;
    job =
        (prior == null
                ? action()
                : prior.then<T>(
                    (_) => action(),
                    onError: (Object e, StackTrace s) => action(),
                  ))
            .whenComplete(() {
              _pending--;
              if (identical(_tail, job)) _tail = null;
            });
    _tail = job;
    return job;
  }

  static Map<String, dynamic> _decode(String? raw) {
    try {
      final m = jsonDecode(raw ?? '');
      if (m is Map) return Map<String, dynamic>.from(m);
    } catch (_) {
      /* No ledger before migration. */
    }
    return {};
  }

  static Future<Map<String, dynamic>> read({int? initial, DateTime? at}) =>
      _serial(() => _read(initial: initial, at: at));
  static Future<Map<String, dynamic>> _read({
    int? initial,
    DateTime? at,
  }) async {
    final h = _decode(await CalculationStore.read(key));
    if (h.isEmpty) {
      final date = todayLabel(at);
      h.addAll({
        'from': date,
        'targets': {date: initial ?? kDefaultStepGoal},
        'earned': <String, dynamic>{},
      });
      await CalculationStore.write(key, jsonEncode(h));
    }
    return h;
  }

  /// Configured target, independent of a streak award already earned today.
  static int? targetOn(Map<String, dynamic> h, String date) {
    if (date.compareTo(h['from'] as String) < 0) return null;
    final targets = h['targets'] as Map;
    final dates =
        targets.keys
            .cast<String>()
            .where((d) => d.compareTo(date) <= 0)
            .toList()
          ..sort();
    return dates.isEmpty ? null : (targets[dates.last] as num).toInt();
  }

  /// Qualification threshold: raising a target must not revoke an earned day.
  static int? goalOn(Map<String, dynamic> h, String date) {
    if (date.compareTo(h['from'] as String) < 0) return null;
    final earned = h['earned'] as Map;
    return earned[date] is num
        ? (earned[date] as num).toInt()
        : targetOn(h, date);
  }

  static Future<Set<String>> qualifying({int? initial, DateTime? at}) =>
      _serial(() => _qualifying(initial: initial, at: at));
  static Future<Set<String>> _qualifying({int? initial, DateTime? at}) async {
    final now = at ?? DateTime.now();
    final h = await _read(initial: initial, at: now);
    final earned = Map<String, dynamic>.from(h['earned'] as Map);
    final out = <String>{};
    var d = DateTime.parse(h['from'] as String);
    final last = DateTime(now.year, now.month, now.day);
    while (!d.isAfter(last)) {
      final date = dayLabelOf(d);
      final resolved = await LocalDb.resolvedStepsForDay(date);
      final goal = goalOn(h, date);
      if (goal != null && goal > 0 && resolved.total >= goal) {
        out.add(date);
        earned[date] = goal;
      } else if (resolved.hasPhoneCoverage || resolved.total > 0) {
        earned.remove(
          date,
        ); // A measured correction can revoke unsupported evidence.
      } else if (earned[date] is num) {
        out.add(
          date,
        ); // Retained award survives unavailable historical coverage.
      }
      d = DateTime(d.year, d.month, d.day + 1);
    }
    final changed = jsonEncode(h['earned']) != jsonEncode(earned);
    h['earned'] = earned;
    if (changed) await CalculationStore.write(key, jsonEncode(h));
    return out;
  }

  static Future<void> change(int before, int after) => _serial(() async {
    await _qualifying(initial: before);
    final h = await _read(initial: before);
    (h['targets'] as Map)[todayLabel()] = after;
    await CalculationStore.write(key, jsonEncode(h));
    await _qualifying(initial: after);
  });
}

Future<MoveStreak?> loadMoveStreak() async {
  try {
    final now = DateTime.now();
    final rows = await LocalDb.sessionsInRange(
      0,
      now.millisecondsSinceEpoch ~/ 1000,
    );
    final seconds = <String, int>{};
    final occupied = <ActiveWindow>[];
    final kinds = <String, MoveKind>{};
    for (final r in rows) {
      if (r['status'] == 'live') continue;
      final type = r['type'] as String?;
      if (!isExerciseType(type)) continue;
      final kind = moveKindOf(type);
      // A run outranks a lift, a lift a walk, a walk other exercise.
      void mark(String date) {
        final was = kinds[date];
        if (was == null || kind.index > was.index) kinds[date] = kind;
      }
      final ts = (r['start_ts'] as num?)?.toInt();
      final te = (r['end_ts'] as num?)?.toInt();
      if (ts == null) continue;
      final legacyMinutes = (r['duration_min'] as num?)?.toInt();
      if (te == null || te <= ts || r['end_ts_fabricated'] == 1) {
        if (legacyMinutes != null && legacyMinutes > 0) {
          final date = dayLabelOf(
            DateTime.fromMillisecondsSinceEpoch(ts * 1000),
          );
          seconds[date] = (seconds[date] ?? 0) + legacyMinutes * 60;
          mark(date);
        }
        continue;
      }
      final start = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
      final end = DateTime.fromMillisecondsSinceEpoch(te * 1000);
      final clock = WorkoutClock.read(r['id'] as String, start, end: end);
      final unique = WorkoutClock(
        clock.id,
        clock.start,
        end: end,
        profile: clock.profile,
        pauses: [...clock.pauses, ...occupied],
      );
      for (final w in unique.windows()) {
        var cursor = w.start;
        while (cursor.isBefore(w.end)) {
          final midnight = DateTime(cursor.year, cursor.month, cursor.day + 1);
          final stop = midnight.isBefore(w.end) ? midnight : w.end;
          final date = dayLabelOf(cursor);
          seconds[date] =
              (seconds[date] ?? 0) + stop.difference(cursor).inSeconds;
          mark(date);
          cursor = stop;
        }
      }
      occupied.addAll(clock.windows());
    }
    final p = await SharedPreferences.getInstance();
    Map? profile;
    try {
      profile = jsonDecode(p.getString('local_profile_json') ?? '{}') as Map;
    } catch (_) {}
    final steps = await StepGoals.qualifying(
      initial: (profile?['step_goal'] as num?)?.toInt(),
    );
    final moves = [
      for (final d in seconds.keys)
        (
          start: DateTime.parse(d),
          minutes: seconds[d]! ~/ 60,
          kind: kinds[d] ?? MoveKind.walk,
        ),
    ];
    return moveStreak(
      moves,
      now,
      stepDays: steps,
      protectedDays: await StreakProtection.read(),
    );
  } catch (_) {
    return null;
  }
}
