// Every run, summarised once: distance, how much of it was running and how
// much walking, the climb, the steps it took, and best efforts. Feeds the PR
// badges on a run's screen, the running trends on Train and the Running row
// of maintenance. Summaries are invalidated when measurements, sessions or
// profile inputs change; retained motion answers are backed up with the ledger.

import '../compute/profile.dart' show runFloorKcal, acsmActiveKcal;
import '../data/db.dart';
import 'workout_clock.dart';
import 'session_track.dart';
import '../data/day_label.dart';
import '../data/local_repository.dart';
import 'motion_window.dart';
import 'route_math.dart' show totalDistanceMeters, movingSeconds;
import 'run_analysis.dart';

/// Activity types that count as running for pace, the distance calorie method
/// and the Running row of maintenance. Treadmill, track intervals, sprinting
/// and hurdles are running too (build 78): their steps are priced by the
/// running distance method, from phone motion distance when there is no GPS.
/// Best efforts still come only from a GPS route, so a treadmill's estimated
/// distance never sets a record.
bool isRunType(String? type) {
  final t = (type ?? '').toLowerCase();
  return t.contains('run') ||
      const {
        'cross_country',
        'treadmill',
        'track_intervals',
        'sprinting',
        'hurdles',
      }.contains(t);
}

/// Activity types that count as walking for the streak.
bool isWalkType(String? type) {
  final t = (type ?? '').toLowerCase();
  return t.contains('walk') || t.contains('hik');
}

class RunSummary {
  final String id;
  final DateTime start;
  final double meters;
  final int movingSec;
  final Map<String, double> efforts;

  /// The session's end, for matching it to a day and to the day's steps.
  final DateTime? end;

  /// Running and walking metres and the climb. [kNoMix] without a distance.
  final RunMix mix;

  /// Steps during the run from the phone, when it was carried and the
  /// window is within what it keeps (or was saved while it was).
  final int? phoneSteps;

  /// Steps the band counted during the session, the fallback for [steps].
  final int? bandSteps;

  /// True when the distance came from the phone's motion data (no GPS).
  final bool fromMotion;
  final double? weightKg;
  final List<ActiveWindow> activeWindows;
  final Map<String, ({RunMix mix, int? steps, double meters})> byDay;

  const RunSummary(
    this.id,
    this.start,
    this.meters,
    this.movingSec,
    this.efforts, {
    this.end,
    this.mix = kNoMix,
    this.phoneSteps,
    this.bandSteps,
    this.fromMotion = false,
    this.weightKg,
    this.byDay = const {},
    this.activeWindows = const [],
  });

  /// The steps to take off the day's count: the phone's for the exact window
  /// first (the same sensor the day total comes from), else the band's.
  int? get steps => phoneSteps ?? bandSteps;

  /// Method 1 calories for this run at [weightKg].
  double? floorKcal(double? weightKg) => runFloorKcal(
    runMeters: mix.runM,
    walkMeters: mix.walkM,
    climbMeters: mix.climbM,
    weightKg: this.weightKg ?? weightKg,
  );
}

final _cache = <String, RunSummary?>{};

/// The last full answer, reused for a few seconds: Today, Food and Train all
/// ask on the same refresh, and the session list read is not free.
(DateTime, List<RunSummary>)? _recent;
Future<List<RunSummary>>? _inFlight;
int _generation = 0;
LocalRepository? _cacheRepo;

/// Every run (oldest first), with its distance from GPS or the phone's motion
/// data when it has one.
Future<List<RunSummary>> loadRuns(LocalRepository repo) {
  if (!identical(_cacheRepo, repo)) {
    runsChanged();
    _cacheRepo = repo;
  }
  final r = _recent;
  if (r != null &&
      DateTime.now().difference(r.$1) < const Duration(seconds: 20)) {
    return Future.value(r.$2);
  }
  if (_inFlight != null) return _inFlight!;
  final generation = _generation;
  final job = _loadRuns(repo).then<List<RunSummary>>((v) {
    if (generation != _generation) {
      return identical(_cacheRepo, repo) ? loadRuns(repo) : v;
    }
    _recent = (DateTime.now(), v);
    return v;
  });
  _inFlight = job;
  return job.whenComplete(() {
    if (identical(_inFlight, job)) _inFlight = null;
  });
}

Future<List<RunSummary>> _loadRuns(LocalRepository repo) async {
  final rows = (await repo.getWorkouts(range: 'all'))['workouts'];
  if (rows is! List) return const [];
  final out = <RunSummary>[];
  for (final r in rows) {
    if (r is! Map || !isRunType(r['type'] as String?)) continue;
    if (r['status'] == 'live' ||
        r['end_ts_fabricated'] == true ||
        r['end_ts_fabricated'] == 1) {
      continue;
    }
    final id = r['id'] as String?;
    final ts = (r['start_ts'] as num?)?.toInt();
    final te = (r['end_ts'] as num?)?.toInt();
    if (id == null || id.isEmpty || ts == null) continue;
    final key = '$id@$ts-$te';
    if (!_cache.containsKey(key)) {
      _cache[key] = await summariseRun(
        repo,
        id,
        ts,
        te,
        bandSteps: (r['steps'] as num?)?.toInt(),
      );
    }
    final s = _cache[key];
    if (s != null) out.add(s);
  }
  out.sort((a, b) => a.start.compareTo(b.start));
  return out;
}

Future<RunSummary?> summariseRun(
  LocalRepository repo,
  String id,
  int ts,
  int? te, {
  int? bandSteps,
  List<ActiveWindow> excluded = const [],
}) async {
  final start = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
  final end = te == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(te * 1000);
  if (end == null || !end.isAfter(start)) return null;
  final clock = WorkoutClock.read(id, start, end: end);
  final dailyClock = WorkoutClock(
    id,
    clock.start,
    end: end,
    profile: clock.profile,
    pauses: [...clock.pauses, ...excluded],
    pausedAt: clock.pausedAt,
  );
  final route = await repo.getWorkoutRoute(id);
  final points = activeTrack(route?.points ?? [], clock);
  final motion = points.length > 1
      ? null
      : await sessionMotionWindow(id, start, end);
  final mix = points.length > 1
      ? runMix(points)
      : motion == null
      ? kNoMix
      : motionMix(
          steps: motion.steps,
          meters: motion.meters,
          chunkSec: motion.chunkSec,
          seconds: motion.seconds,
        );
  final byDay = <String, ({RunMix mix, int? steps, double meters})>{};
  var day = DateTime(start.year, start.month, start.day);
  var totalSteps = 0;
  var measured = false;
  while (day.isBefore(end)) {
    final label = dayLabelOf(day);
    var steps = 0;
    var known = false;
    var complete = true;
    final windows = dailyClock.onDay(label);
    for (final w in windows) {
      final r = await LocalDb.resolvedStepsForWindow(w.start, w.end);
      if (r.coveredSeconds < w.end.difference(w.start).inSeconds) {
        complete = false;
      }
      if (r.hasPhoneCoverage || r.total > 0) {
        known = true;
        steps += r.total;
      }
    }
    // A retained phone motion result preserves exact session steps after native
    // retention expires. Never subtract more than the daily resolver accepted.
    var phone = 0;
    if (motion != null) {
      for (var i = 0; i < motion.steps.length; i++) {
        if (dayLabelOf(DateTime.fromMillisecondsSinceEpoch(motion.timeAt(i))) ==
            label) {
          phone += motion.steps[i];
        }
      }
      if (!known && excluded.isEmpty && phone > 0) {
        steps = phone;
        known = true;
        complete = true;
      }
    }
    if (!known &&
        excluded.isEmpty &&
        bandSteps != null &&
        bandSteps > 0 &&
        dayLabelOf(start) == label &&
        dayLabelOf(end.subtract(const Duration(milliseconds: 1))) == label) {
      steps = bandSteps;
      known = true;
      complete = true;
    }
    final dayClock = WorkoutClock(
      id,
      day,
      end: DateTime(day.year, day.month, day.day + 1),
    );
    final dayPts = activeTrack(activeTrack(points, dailyClock), dayClock);
    final dayMotion = motion?.within(windows);
    final mm = <double?>[], st = <int>[], sec = <double>[];
    if (dayMotion != null) {
      st.addAll(dayMotion.steps);
      mm.addAll(dayMotion.meters);
      sec.addAll([
        for (var i = 0; i < dayMotion.steps.length; i++) dayMotion.secondsAt(i),
      ]);
    }
    final dayMix = dayPts.length > 1
        ? runMix(dayPts)
        : motionMix(
            steps: st,
            meters: mm,
            chunkSec: motion?.chunkSec ?? 60,
            seconds: sec,
          );
    final meters = dayPts.length > 1
        ? totalDistanceMeters(dayPts)
        : mm.fold<double>(0, (a, b) => a + (b ?? 0));
    if (windows.isNotEmpty) {
      byDay[label] = (
        mix: dayMix,
        steps: known && complete ? steps : null,
        meters: meters,
      );
    }
    totalSteps += steps;
    measured |= known;
    day = DateTime(day.year, day.month, day.day + 1);
  }
  return RunSummary(
    id,
    start,
    points.length > 1 ? totalDistanceMeters(points) : motion?.totalMeters ?? 0,
    points.length > 1 ? movingSeconds(points) : clock.activeSeconds(),
    points.length > 1 ? bestEfforts(points) : const {},
    end: end,
    mix: mix,
    phoneSteps: measured ? totalSteps : null,
    bandSteps: bandSteps,
    fromMotion: points.length < 2 && motion != null,
    weightKg: clock.profile?.weightKg,
    byDay: byDay,
    activeWindows: dailyClock.windows(),
  );
}

/// Forget a run's summary — after it is deleted or retimed.
void forgetRun(String id) {
  _cache.removeWhere((k, _) => k.startsWith('$id@'));
  _recent = null;
}

/// Drop the reused answer so the next read sees a session that just changed.
void runsChanged() {
  _generation++;
  _recent = null;
  _cache.clear();
  _inFlight = null;
}

/// The runs that started on [day] (a local `yyyy-MM-dd` label).
Iterable<RunSummary> runsOnDay(List<RunSummary> runs, String day) =>
    runs.where((r) => dayLabelOf(r.start) == day);

/// One day's Running row: Method 1 calories over that day's runs, the steps
/// those runs took (never more than [daySteps]) and their distance.
typedef RunDay = ({double kcal, int steps, int count, double km});

const RunDay kNoRunDay = (kcal: 0, steps: 0, count: 0, km: 0);

RunDay runEnergyOn(
  List<RunSummary> runs,
  String day, {
  double? weightKg,
  num? daySteps,
  bool acsm = false,
}) {
  var kcal = 0.0, km = 0.0;
  var steps = 0;
  var count = 0;
  for (final r in runs.where(
    (r) =>
        r.byDay.isEmpty ? dayLabelOf(r.start) == day : r.byDay.containsKey(day),
  )) {
    final slice = r.byDay[day];
    final mix = slice?.mix ?? r.mix;
    final k =
        (acsm
            ? acsmActiveKcal(
                runMeters: mix.runM,
                walkMeters: mix.walkM,
                runClimbMeters: mix.climbM,
                weightKg: r.weightKg ?? weightKg,
              )
            : runFloorKcal(
                runMeters: mix.runM,
                walkMeters: mix.walkM,
                climbMeters: mix.climbM,
                weightKg: r.weightKg ?? weightKg,
              )) ??
        0;
    if (k <= 0) continue; // no distance: its steps stay walking steps
    count++;
    kcal += k;
    km += (slice?.meters ?? r.meters) / 1000;
    steps += (slice == null ? r.steps : slice.steps) ?? 0;
  }
  if (daySteps != null && steps > daySteps) steps = daySteps.toInt();
  return (kcal: kcal, steps: steps, count: count, km: km);
}

/// The best predicted 5K time, in seconds, from efforts of 3 km or more in
/// [runs] within the last [days] days. Null without one.
double? predicted5k(List<RunSummary> runs, {int days = 90}) {
  final since = DateTime.now().subtract(Duration(days: days));
  double? best;
  for (final r in runs) {
    if (r.start.isBefore(since)) continue;
    for (final (label, m) in kAllEfforts) {
      if (m < 3000) continue;
      final s = r.efforts[label];
      if (s == null) continue;
      final p = riegel(s, m, 5000);
      if (best == null || p < best) best = p;
    }
  }
  return best;
}
