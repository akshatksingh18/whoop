// Every run, summarised once: distance, how much of it was running and how
// much walking, the climb, the steps it took, and best efforts. Feeds the PR
// badges on a run's screen, the running trends on Train and the Running row
// of maintenance. A finished run never changes, so each summary is cached for
// the life of the process (and the phone's motion answer is saved on disk;
// see motion_window.dart).

import '../compute/profile.dart' show runFloorKcal;
import '../data/day_label.dart';
import '../data/local_repository.dart';
import 'motion_window.dart';
import 'route_math.dart' show totalDistanceMeters, movingSeconds;
import 'run_analysis.dart';

/// Activity types that count as running for best efforts, pace zones and the
/// Running row of maintenance.
bool isRunType(String? type) {
  final t = (type ?? '').toLowerCase();
  return t.contains('run') || t == 'cross_country';
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

  const RunSummary(this.id, this.start, this.meters, this.movingSec, this.efforts,
      {this.end,
      this.mix = kNoMix,
      this.phoneSteps,
      this.bandSteps,
      this.fromMotion = false});

  /// The steps to take off the day's count: the phone's for the exact window
  /// first (the same sensor the day total comes from), else the band's.
  int? get steps => phoneSteps ?? bandSteps;

  /// Method 1 calories for this run at [weightKg].
  double? floorKcal(double? weightKg) => runFloorKcal(
      runMeters: mix.runM,
      walkMeters: mix.walkM,
      climbMeters: mix.climbM,
      weightKg: weightKg);
}

final _cache = <String, RunSummary?>{};

/// The last full answer, reused for a few seconds: Today, Food and Train all
/// ask on the same refresh, and the session list read is not free.
(DateTime, List<RunSummary>)? _recent;
Future<List<RunSummary>>? _inFlight;

/// Every run (oldest first), with its distance from GPS or the phone's motion
/// data when it has one.
Future<List<RunSummary>> loadRuns(LocalRepository repo) {
  final r = _recent;
  if (r != null && DateTime.now().difference(r.$1) < const Duration(seconds: 20)) {
    return Future.value(r.$2);
  }
  return _inFlight ??= _loadRuns(repo).then((v) {
    _recent = (DateTime.now(), v);
    return v;
  }).whenComplete(() => _inFlight = null);
}

Future<List<RunSummary>> _loadRuns(LocalRepository repo) async {
  final rows = (await repo.getWorkouts(range: 'all'))['workouts'];
  if (rows is! List) return const [];
  final out = <RunSummary>[];
  for (final r in rows) {
    if (r is! Map || !isRunType(r['type'] as String?)) continue;
    if (r['status'] == 'live') continue;
    final id = r['id'] as String?;
    final ts = (r['start_ts'] as num?)?.toInt();
    final te = (r['end_ts'] as num?)?.toInt();
    if (id == null || id.isEmpty || ts == null) continue;
    final key = '$id@$ts-$te';
    if (!_cache.containsKey(key)) {
      try {
        _cache[key] = await _summarise(repo, id, ts, te,
            bandSteps: (r['steps'] as num?)?.toInt());
      } catch (_) {
        continue; // unreadable now; try again next time
      }
    }
    final s = _cache[key];
    if (s != null) out.add(s);
  }
  out.sort((a, b) => a.start.compareTo(b.start));
  return out;
}

Future<RunSummary?> _summarise(
    LocalRepository repo, String id, int ts, int? te,
    {int? bandSteps}) async {
  final start = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
  final end = te == null ? null : DateTime.fromMillisecondsSinceEpoch(te * 1000);
  final motion = end == null ? null : await motionWindow(id, start, end);
  final route = await repo.getWorkoutRoute(id);
  if (route != null && route.hasPath) {
    return RunSummary(
      id,
      start,
      totalDistanceMeters(route.points),
      movingSeconds(route.points),
      bestEfforts(route.points),
      end: end,
      mix: runMix(route.points),
      phoneSteps: motion?.totalSteps,
      bandSteps: bandSteps,
    );
  }
  // No GPS: the phone's motion data, when it was carried.
  final m = motion?.totalMeters;
  if (motion == null || m == null || m <= 0) {
    // Still a run for the steps it took, with no distance and no calories.
    return RunSummary(id, start, 0, 0, const {},
        end: end, phoneSteps: motion?.totalSteps, bandSteps: bandSteps);
  }
  return RunSummary(
    id,
    start,
    m,
    motion.activeMinutes.round() * 60,
    const {}, // no PRs from an estimate
    end: end,
    mix: motionMix(
        steps: motion.steps, meters: motion.meters, chunkSec: motion.chunkSec),
    phoneSteps: motion.totalSteps,
    bandSteps: bandSteps,
    fromMotion: true,
  );
}

/// Forget a run's summary — after it is deleted or retimed.
void forgetRun(String id) {
  _cache.removeWhere((k, _) => k.startsWith('$id@'));
  _recent = null;
}

/// Drop the reused answer so the next read sees a session that just changed.
void runsChanged() => _recent = null;

/// The runs that started on [day] (a local `yyyy-MM-dd` label).
Iterable<RunSummary> runsOnDay(List<RunSummary> runs, String day) =>
    runs.where((r) => dayLabelOf(r.start) == day);

/// One day's Running row: Method 1 calories over that day's runs, the steps
/// those runs took (never more than [daySteps]) and their distance.
typedef RunDay = ({double kcal, int steps, int count, double km});

const RunDay kNoRunDay = (kcal: 0, steps: 0, count: 0, km: 0);

RunDay runEnergyOn(List<RunSummary> runs, String day,
    {double? weightKg, num? daySteps}) {
  var kcal = 0.0, km = 0.0;
  var steps = 0;
  var count = 0;
  for (final r in runsOnDay(runs, day)) {
    final k = r.floorKcal(weightKg) ?? 0;
    if (k <= 0) continue; // no distance: its steps stay walking steps
    count++;
    kcal += k;
    km += r.meters / 1000;
    steps += r.steps ?? 0;
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
