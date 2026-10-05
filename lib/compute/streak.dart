// The run-or-walk streak: how many days in a row had at least ten minutes of
// running/walking OR completed that day's measured step goal. [moveStreak] is
// pure, so the day rules (today still open, midnight, DST) are testable
// without a clock; [loadMoveStreak] feeds it from the sessions table.

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/db.dart';
import '../data/calculation_store.dart';
import '../data/day_label.dart';
import '../data/local_repository.dart' show kDefaultStepGoal;
import '../gps/workout_clock.dart';
import '../gps/run_history.dart' show isRunType, isWalkType;

/// One run or walk session, as the streak needs it.
typedef MoveSession = ({DateTime start, int minutes, bool run});

/// How much running or walking a day needs to count.
const int kStreakMinutes = 10;

/// What one of the last seven days was: nothing, a walk day, or a run day.
enum MoveDay { none, walk, run, goal }

typedef MoveStreak = ({
  int current,
  int longest,
  bool todayDone,
  List<MoveDay> last7, // oldest first, today last
});

/// Days are local calendar days; a session belongs to the day it started.
/// A day counts once its sessions add up to [minMinutes]. Today does not
/// break the streak until it is over: with nothing yet, the streak is
/// counted up to yesterday.
MoveStreak moveStreak(
  List<MoveSession> sessions,
  DateTime now, {
  int minMinutes = kStreakMinutes,
  Set<String> stepDays = const {},
}) {
  final minutes = <int, int>{};
  final ran = <int>{};
  int key(DateTime d) => d.year * 10000 + d.month * 100 + d.day;
  for (final s in sessions) {
    if (s.minutes <= 0) continue;
    final k = key(s.start);
    minutes[k] = (minutes[k] ?? 0) + s.minutes;
    if (s.run) ran.add(k);
  }
  final goals = {for (final d in stepDays) key(DateTime.parse(d))};
  for (final k in goals) {
    minutes.putIfAbsent(k, () => 0);
  }
  bool counts(int k) => (minutes[k] ?? 0) >= minMinutes || goals.contains(k);
  DateTime day(int back) => DateTime(now.year, now.month, now.day - back);

  final todayDone = counts(key(day(0)));
  var current = 0;
  for (var back = todayDone ? 0 : 1; ; back++) {
    if (!counts(key(day(back)))) break;
    current++;
  }

  var longest = 0;
  if (minutes.isNotEmpty) {
    final days = [
      for (final k in minutes.keys)
        if (counts(k)) DateTime(k ~/ 10000, k ~/ 100 % 100, k % 100),
    ]..sort();
    var run = 0;
    DateTime? prev;
    for (final d in days) {
      final next = prev == null
          ? null
          : DateTime(prev.year, prev.month, prev.day + 1);
      run = next != null && next == d ? run + 1 : 1;
      if (run > longest) longest = run;
      prev = d;
    }
  }

  return (
    current: current,
    longest: longest < current ? current : longest,
    todayDone: todayDone,
    last7: [
      for (var back = 6; back >= 0; back--)
        () {
          final k = key(day(back));
          if (!counts(k)) return MoveDay.none;
          if ((minutes[k] ?? 0) < minMinutes) return MoveDay.goal;
          return ran.contains(k) ? MoveDay.run : MoveDay.walk;
        }(),
    ],
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
    final ran = <String, bool>{};
    for (final r in rows) {
      if (r['status'] == 'live') continue;
      final type = r['type'] as String?;
      final run = isRunType(type);
      if (!run && !isWalkType(type)) continue;
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
          ran[date] = (ran[date] ?? false) || run;
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
          ran[date] = (ran[date] ?? false) || run;
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
          run: ran[d] ?? false,
        ),
    ];
    return moveStreak(moves, now, stepDays: steps);
  } catch (_) {
    return null;
  }
}
