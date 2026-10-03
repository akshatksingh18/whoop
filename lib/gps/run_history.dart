// Every recorded run, summarised once: distance, moving time, average heart
// rate and best efforts. Feeds the PR badges on a run's screen and the
// running trends on Train. Best efforts never change after a run is saved,
// so each run's summary is cached for the life of the process.

import '../data/local_repository.dart';
import 'route_math.dart' show totalDistanceMeters, movingSeconds;
import 'run_analysis.dart';

/// Activity types that count as running for best efforts and pace zones.
bool isRunType(String? type) {
  final t = (type ?? '').toLowerCase();
  return t.contains('run') || t == 'cross_country';
}

class RunSummary {
  final String id;
  final DateTime start;
  final double meters;
  final int movingSec;
  final Map<String, double> efforts;
  const RunSummary(this.id, this.start, this.meters, this.movingSec, this.efforts);
}

final _cache = <String, RunSummary?>{};

/// All runs with a recorded route, oldest first.
Future<List<RunSummary>> loadRuns(LocalRepository repo) async {
  final rows = (await repo.getWorkouts(range: 'all'))['workouts'];
  if (rows is! List) return const [];
  final out = <RunSummary>[];
  for (final r in rows) {
    if (r is! Map || !isRunType(r['type'] as String?)) continue;
    final id = r['id'] as String?;
    final ts = (r['start_ts'] as num?)?.toInt();
    if (id == null || id.isEmpty || ts == null) continue;
    if (!_cache.containsKey(id)) {
      try {
        final route = await repo.getWorkoutRoute(id);
        _cache[id] = route == null || !route.hasPath
            ? null
            : RunSummary(
                id,
                DateTime.fromMillisecondsSinceEpoch(ts * 1000),
                totalDistanceMeters(route.points),
                movingSeconds(route.points),
                bestEfforts(route.points),
              );
      } catch (_) {
        continue; // unreadable now; try again next time
      }
    }
    final s = _cache[id];
    if (s != null) out.add(s);
  }
  out.sort((a, b) => a.start.compareTo(b.start));
  return out;
}

/// Forget a run's summary — after it is deleted or retimed.
void forgetRun(String id) => _cache.remove(id);

/// The best predicted 5K time, in seconds, from efforts of a mile or more in
/// [runs] within the last [days] days. Null without one.
double? predicted5k(List<RunSummary> runs, {int days = 90}) {
  final since = DateTime.now().subtract(Duration(days: days));
  double? best;
  for (final r in runs) {
    if (r.start.isBefore(since)) continue;
    for (final (label, m) in kBestEffortDistances) {
      if (m < 1600) continue;
      final s = r.efforts[label];
      if (s == null) continue;
      final p = riegel(s, m, 5000);
      if (best == null || p < best) best = p;
    }
  }
  return best;
}
