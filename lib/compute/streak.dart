// The run-or-walk streak: how many days in a row had at least ten minutes of
// running or walking. Lifts and other workouts never count. [moveStreak] is
// pure, so the day rules (today still open, midnight, DST) are testable
// without a clock; [loadMoveStreak] feeds it from the sessions table.

import '../data/db.dart';
import '../gps/run_history.dart' show isRunType, isWalkType;

/// One run or walk session, as the streak needs it.
typedef MoveSession = ({DateTime start, int minutes, bool run});

/// How much running or walking a day needs to count.
const int kStreakMinutes = 10;

/// What one of the last seven days was: nothing, a walk day, or a run day.
enum MoveDay { none, walk, run }

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
MoveStreak moveStreak(List<MoveSession> sessions, DateTime now,
    {int minMinutes = kStreakMinutes}) {
  final minutes = <int, int>{};
  final ran = <int>{};
  int key(DateTime d) => d.year * 10000 + d.month * 100 + d.day;
  for (final s in sessions) {
    if (s.minutes <= 0) continue;
    final k = key(s.start);
    minutes[k] = (minutes[k] ?? 0) + s.minutes;
    if (s.run) ran.add(k);
  }
  bool counts(int k) => (minutes[k] ?? 0) >= minMinutes;
  DateTime day(int back) => DateTime(now.year, now.month, now.day - back);

  final todayDone = counts(key(day(0)));
  var current = 0;
  for (var back = todayDone ? 0 : 1;; back++) {
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
          return ran.contains(k) ? MoveDay.run : MoveDay.walk;
        }(),
    ],
  );
}

/// Every run and walk this phone holds, as a streak. Read straight from the
/// sessions table, because a streak can reach further back than a month.
/// Null when the table cannot be read.
Future<MoveStreak?> loadMoveStreak() async {
  try {
    final now = DateTime.now();
    final rows =
        await LocalDb.sessionsInRange(0, now.millisecondsSinceEpoch ~/ 1000);
    final moves = <MoveSession>[];
    for (final r in rows) {
      final type = r['type'] as String?;
      final run = isRunType(type);
      if (!run && !isWalkType(type)) continue;
      final ts = (r['start_ts'] as num?)?.toInt();
      if (ts == null) continue;
      final te = (r['end_ts'] as num?)?.toInt();
      final mins = (r['duration_min'] as num?)?.toInt() ??
          (te == null ? 0 : (te - ts) ~/ 60);
      moves.add((
        start: DateTime.fromMillisecondsSinceEpoch(ts * 1000),
        minutes: mins,
        run: run,
      ));
    }
    return moveStreak(moves, now);
  } catch (_) {
    return null;
  }
}
