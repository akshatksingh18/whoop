// Automatic rest days for every streak (Build 91, Akshat: "it should
// automatically account for that ... one day is fine, or max 2, but not more").
//
// A missed day inside a running streak is a rest day by itself, without being
// marked, as long as it leaves no more than [kAutoRestPerWeek] rest days in any
// seven. Two in a row are fine; a third missed day in seven ends the streak.
// Rest keeps a streak alive but never adds to its count, and today is never a
// rest day while it is still open. Pure, so the movement and Pushups streaks
// share one rule and tests need no clock.

import 'day_label.dart';

/// Rest days a streak forgives in any rolling seven.
const int kAutoRestPerWeek = 2;

/// [current] and [best] count active days only; [rest] holds every missed day
/// a streak bridged, and [restInCurrent] those inside the current streak.
typedef RestRun = ({
  int current,
  int best,
  Set<String> rest,
  int restInCurrent,
});

/// The streak over [active] day labels up to [today], walking forward from the
/// earliest active day.
RestRun restAwareRun(Set<String> active, String today) {
  final days = active.where((d) => d.compareTo(today) <= 0).toList()..sort();
  if (days.isEmpty) return (current: 0, best: 0, rest: {}, restInCurrent: 0);
  final end = DateTime.parse(today);
  var d = DateTime.parse(days.first);
  var run = 0, best = 0;
  final runRest = <DateTime>[];
  final rest = <String>{};
  while (!d.isAfter(end)) {
    final label = dayLabelOf(d);
    if (active.contains(label)) {
      run++;
      if (run > best) best = run;
    } else if (label != today && run > 0) {
      final weekStart = DateTime(d.year, d.month, d.day - 6);
      final inWeek = runRest.where((r) => !r.isBefore(weekStart)).length + 1;
      if (inWeek <= kAutoRestPerWeek) {
        runRest.add(d);
        rest.add(label);
      } else {
        // The streak ended here: the missed days of this last week were
        // not rest after all (earlier ones did carry the streak).
        rest.removeAll(
          runRest.where((r) => !r.isBefore(weekStart)).map(dayLabelOf),
        );
        run = 0;
        runRest.clear();
      }
    }
    d = DateTime(d.year, d.month, d.day + 1);
  }
  return (current: run, best: best, rest: rest, restInCurrent: runRest.length);
}

/// Whether ending [today] with nothing would still keep a running streak, as
/// an automatic rest day (Build 92, Codex audit 7: Pushups said "at risk"
/// while a rest day was still available). False with no streak running or
/// when today is already active.
bool restWouldCover(Set<String> active, String today) {
  if (active.contains(today)) return false;
  final t = DateTime.parse(today);
  final tomorrow = dayLabelOf(DateTime(t.year, t.month, t.day + 1));
  final now = restAwareRun(active, today);
  if (now.current == 0) return false;
  return restAwareRun(active, tomorrow).rest.contains(today);
}
