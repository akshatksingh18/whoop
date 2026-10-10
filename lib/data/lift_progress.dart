// Is this exercise actually getting stronger? (build 86, Akshat's request.)
// Answered inside the live workout, from earlier sessions of the SAME
// exercise, load meaning and equipment note only — a dumbbell press is
// never compared with a machine press, and plates-per-side never with
// a total.
//
// The per-set measure is an estimated one-rep load on this setup (Epley:
// load × (1 + reps / 30)). It ranks a heavier set and a longer set on one
// scale, and is only ever compared with itself: plates per side exclude the
// bar and added weight excludes your bodyweight, so it is not your true
// one-rep max and is never shown as one. Sets above 12 reps are compared by
// reps at load instead, where the estimate is weakest; bodyweight-only sets
// (no added load) compare reps.

import 'dart:math' as math;

import 'lift_log.dart';

/// Above this many reps the estimate is unreliable; compare reps at load.
const int kEstimateMaxReps = 12;

/// The estimated one-rep load of [s] on its own setup; null when it has no
/// load or too many reps to estimate.
double? setScore(LiftSet s) {
  if (s.reps <= 0 || s.load <= 0 || s.reps > kEstimateMaxReps) return null;
  return s.load * (1 + s.reps / 30);
}

/// One earlier session of an exercise.
typedef ExerciseSession = ({
  DateTime date,
  LiftExercise exercise,
  LiftSet best,
  double? score,
  int reps,
});

bool _comparable(LiftExercise a, LiftExercise b) =>
    sameLiftName(a.name, b.name) &&
    a.loadMode == b.loadMode &&
    liftNameKey(a.equipmentNote) == liftNameKey(b.equipmentNote);

/// The best set of [sets]: the highest estimate, else the most reps at the
/// heaviest load.
LiftSet bestSet(List<LiftSet> sets) {
  LiftSet? best;
  for (final s in sets) {
    if (best == null) {
      best = s;
      continue;
    }
    final a = setScore(s), b = setScore(best);
    if (a != null && b != null) {
      if (a > b) best = s;
    } else if (s.load > best.load ||
        (s.load == best.load && s.reps > best.reps)) {
      best = s;
    }
  }
  return best!;
}

/// Comparable finished sessions of [e], newest first.
List<ExerciseSession> exerciseHistory(
  LiftExercise e,
  List<LiftWorkout> finished, {
  String? excludingId,
}) {
  final out = <ExerciseSession>[];
  for (final w in finished) {
    if (w.id == excludingId || w.isActive) continue;
    for (final x in w.exercises) {
      if (!_comparable(x, e) || x.sets.isEmpty) continue;
      final b = bestSet(x.sets);
      out.add((
        date: w.startedAt,
        exercise: x,
        best: b,
        score: setScore(b),
        reps: x.sets.fold(0, (n, s) => n + s.reps),
      ));
    }
  }
  out.sort((a, b) => b.date.compareTo(a.date));
  return out;
}

enum LiftTrend { tooFew, up, flat, down }

/// The trend over the last [window] comparable sessions (newest first), in
/// one plain line. Needs two sessions; "flat" means no new best in the last
/// three.
({LiftTrend trend, String text}) liftTrend(
  List<ExerciseSession> h, {
  int window = 6,
}) {
  if (h.length < 2) {
    return (
      trend: LiftTrend.tooFew,
      text: h.isEmpty
          ? 'First time on this exercise here.'
          : 'One earlier session. Two or more show a trend.',
    );
  }
  final w = h.take(window).toList();
  final newest = w.first, oldest = w.last;
  final useScore = w.every((s) => s.score != null);
  double m(ExerciseSession s) => useScore ? s.score! : s.best.reps.toDouble();
  final change = m(newest) - m(oldest);
  final pct = m(oldest) == 0 ? 0.0 : change / m(oldest) * 100;
  // No new best in the most recent three sessions.
  final recent = w.take(3).toList();
  final before = h.skip(3);
  final comparableBefore = [
    for (final s in before)
      if (!useScore || s.score != null) s,
  ];
  final bestBefore = comparableBefore.isEmpty
      ? null
      : comparableBefore.map(m).reduce(math.max);
  final stalled =
      recent.length == 3 &&
      bestBefore != null &&
      recent.map(m).reduce(math.max) <= bestBefore;
  final unit = useScore ? '' : ' reps';
  if (stalled) {
    return (
      trend: LiftTrend.flat,
      text:
          'No new best in your last 3 sessions. One more rep, or a small step '
          'up in weight, would show progress.',
    );
  }
  final span = '${w.length} sessions';
  if (pct >= 1) {
    return (
      trend: LiftTrend.up,
      text: useScore
          ? 'Best set up ${pct.round()}% over $span.'
          : 'Best set up ${change.round()}$unit over $span.',
    );
  }
  if (pct <= -1) {
    return (
      trend: LiftTrend.down,
      text: useScore
          ? 'Best set down ${pct.abs().round()}% over $span. Sleep, food and '
                'rest between sessions are worth a look.'
          : 'Best set down ${change.abs().round()}$unit over $span.',
    );
  }
  return (trend: LiftTrend.flat, text: 'About level over $span.');
}

enum SetVerdict { better, same, worse }

/// Today's sets against last time's set by set, by position.
SetVerdict compareSet(LiftSet now, LiftSet last) {
  if (now.load == last.load && now.reps == last.reps) return SetVerdict.same;
  final heavier = now.load >= last.load, longer = now.reps >= last.reps;
  if (heavier && longer) return SetVerdict.better;
  if (now.load <= last.load && now.reps <= last.reps) return SetVerdict.worse;
  // Heavier for fewer, or lighter for more: the estimate decides, when it
  // can; otherwise it is not a clear step either way.
  final a = setScore(now), b = setScore(last);
  if (a == null || b == null || (a - b).abs() < 0.5) return SetVerdict.same;
  return a > b ? SetVerdict.better : SetVerdict.worse;
}

/// One line for the exercise as it stands: ahead, level or behind last time
/// so far, and by how much on the sets that differ. Null before a set.
({SetVerdict verdict, String text})? versusLast(
  LiftExercise today,
  LiftExercise last,
) {
  if (today.sets.isEmpty || last.sets.isEmpty) return null;
  final n = math.min(today.sets.length, last.sets.length);
  var better = 0, worse = 0;
  for (var i = 0; i < n; i++) {
    switch (compareSet(today.sets[i], last.sets[i])) {
      case SetVerdict.better:
        better++;
      case SetVerdict.worse:
        worse++;
      case SetVerdict.same:
        break;
    }
  }
  final repsNow = today.sets.take(n).fold(0, (a, s) => a + s.reps);
  final repsThen = last.sets.take(n).fold(0, (a, s) => a + s.reps);
  final extra = today.sets.length > last.sets.length
      ? ' · ${today.sets.length - last.sets.length} more '
            '${today.sets.length - last.sets.length == 1 ? 'set' : 'sets'} than last time'
      : '';
  final reps = repsNow == repsThen
      ? ''
      : ' (${repsNow > repsThen ? '+' : '−'}${(repsNow - repsThen).abs()} reps)';
  if (better > 0 && worse == 0) {
    return (
      verdict: SetVerdict.better,
      text:
          'Ahead of last time on $better of $n ${n == 1 ? 'set' : 'sets'}$reps$extra',
    );
  }
  if (worse > 0 && better == 0) {
    return (
      verdict: SetVerdict.worse,
      text:
          'Behind last time on $worse of $n ${n == 1 ? 'set' : 'sets'}$reps$extra',
    );
  }
  if (better == 0 && worse == 0) {
    return (verdict: SetVerdict.same, text: 'Matching last time so far$extra');
  }
  return (
    verdict: SetVerdict.same,
    text: 'Mixed: $better ahead, $worse behind$reps$extra',
  );
}

/// What the next set has to do to beat the same set last time; null when
/// last time had no set at that position.
String? nextToBeat(LiftExercise today, LiftExercise last) {
  final i = today.sets.length;
  if (i >= last.sets.length) return null;
  final l = last.sets[i];
  final w = liftWeightText(l.load);
  return 'Set ${i + 1} to beat: $w × ${l.reps}. '
      '$w × ${l.reps + 1}, or more weight for ${l.reps}, beats it.';
}

/// The best set ever at each rep count on this setup, heaviest first: the
/// records today's sets are measured against.
List<({int reps, double load, DateTime date})> repRecords(
  List<ExerciseSession> h,
) {
  final best = <int, ({double load, DateTime date})>{};
  for (final s in h) {
    for (final x in s.exercise.sets) {
      final cur = best[x.reps];
      if (cur == null || x.load > cur.load) {
        best[x.reps] = (load: x.load, date: s.date);
      }
    }
  }
  final out = [
    for (final e in best.entries)
      (reps: e.key, load: e.value.load, date: e.value.date),
  ]..sort((a, b) => a.reps.compareTo(b.reps));
  return out;
}
