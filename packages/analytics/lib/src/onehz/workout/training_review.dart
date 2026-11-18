// Descriptive comparisons of measured sessions; not a fitness or calorie model.
class TrainingObservation {
  const TrainingObservation(
      {required this.id,
      required this.day,
      required this.type,
      required this.seconds,
      required this.meters,
      required this.hr,
      required this.coverage,
      this.cadence,
      this.context = const [],
      this.bestEfforts = const {}});
  final String id, day, type;
  final double seconds, meters, hr, coverage;
  final double? cadence;
  final List<String> context;
  final Map<String, double> bestEfforts;
  double get pace => seconds * 1000 / meters;
  bool get usable =>
      seconds.isFinite &&
      seconds >= 600 &&
      meters.isFinite &&
      meters >= 500 &&
      hr.isFinite &&
      hr > 0 &&
      coverage.isFinite &&
      coverage >= .8;
}

class TrainingComparison {
  const TrainingComparison(this.type, this.older, this.recent, this.hrChange,
      this.paceChange, this.cadenceChange,
      {required this.atSimilarPace});
  final String type;
  final bool atSimilarPace;
  final List<TrainingObservation> older, recent;
  final double hrChange, paceChange;
  final double? cadenceChange;
  bool get hasFinding => hrChange <= -3 || paceChange <= -3;
}

/// Pair without replacement, at similar pace (within 5%) or HR (within 5 bpm).
/// Three distinct sessions in each period are required; the thresholds are
/// engineering quality gates, not statistical significance or causal evidence.
List<TrainingComparison> compareTraining(List<TrainingObservation> observations,
    {required String firstDay,
    required String splitDay,
    required String endDay}) {
  final out = <TrainingComparison>[];
  final distinct = <String, TrainingObservation>{};
  for (final s in observations) {
    distinct.putIfAbsent(s.id, () => s);
  }
  for (final type in ['Running', 'Walking']) {
    final old = distinct.values
        .where((s) =>
            s.usable &&
            s.type == type &&
            s.day.compareTo(firstDay) >= 0 &&
            s.day.compareTo(splitDay) < 0)
        .toList();
    final recent = distinct.values
        .where((s) =>
            s.usable &&
            s.type == type &&
            s.day.compareTo(splitDay) >= 0 &&
            s.day.compareTo(endDay) < 0)
        .toList();
    for (final byPace in [true, false]) {
      final remaining = [...old];
      final left = <TrainingObservation>[], right = <TrainingObservation>[];
      for (final s in recent) {
        final candidates = remaining
            .where((o) =>
                (o.context.toList()..sort()).join(",") ==
                (s.context.toList()..sort()).join(","))
            .toList();
        candidates.sort((a, b) => (byPace
                ? (a.pace - s.pace).abs()
                : (a.hr - s.hr).abs())
            .compareTo(byPace ? (b.pace - s.pace).abs() : (b.hr - s.hr).abs()));
        if (candidates.isEmpty) continue;
        final match = candidates.first;
        final similar = byPace
            ? (match.pace / s.pace - 1).abs() <= .05
            : (match.hr - s.hr).abs() <= 5;
        if (!similar) continue;
        left.add(match);
        right.add(s);
        remaining.remove(match);
      }
      if (left.length < 3) continue;
      double average(List<TrainingObservation> rows,
              double Function(TrainingObservation) value) =>
          rows.fold<double>(0, (n, s) => n + value(s)) / rows.length;
      final oldCadence =
          left.map((s) => s.cadence).whereType<double>().toList();
      final newCadence =
          right.map((s) => s.cadence).whereType<double>().toList();
      final cad =
          oldCadence.length == left.length && newCadence.length == right.length
              ? newCadence.reduce((a, b) => a + b) / newCadence.length -
                  oldCadence.reduce((a, b) => a + b) / oldCadence.length
              : null;
      out.add(TrainingComparison(
          type,
          left,
          right,
          byPace ? average(right, (s) => s.hr) - average(left, (s) => s.hr) : 0,
          byPace
              ? 0
              : (average(right, (s) => s.pace) / average(left, (s) => s.pace) -
                      1) *
                  100,
          cad,
          atSimilarPace: byPace));
    }
  }
  return out;
}
