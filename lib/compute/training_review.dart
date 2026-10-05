import 'dart:convert';
import 'package:openstrap_analytics/onehz.dart' as ana;
import '../data/calculation_store.dart';
import '../data/db.dart';
import '../data/day_label.dart';
import '../data/local_repository.dart';
import '../gps/run_history.dart';
import '../gps/workout_context.dart';
import '../gps/heart_rate_drift.dart' show activeRouteCoverage;
import '../gps/run_analysis.dart' show bestEfforts;
import '../gps/motion_window.dart';
import '../gps/workout_measurements.dart';
import 'profile.dart';

class TrainingReviewData {
  const TrainingReviewData(
    this.start,
    this.split,
    this.end,
    this.observations, {
    this.examined = 0,
  });
  final String start, split, end;
  final int examined;
  final List<ana.TrainingObservation> observations;
  List<ana.TrainingComparison> get comparisons => ana.compareTraining(
    observations,
    firstDay: start,
    splitDay: split,
    endDay: end,
  );
  List<ana.TrainingComparison> get findings =>
      comparisons.where((c) => c.hasFinding).toList();
  String get message => comparisons.isEmpty
      ? ''
      : findings.isEmpty
      ? 'Your recorded run/walk comparison is ready. ${comparisons.first.recent.length} matched session pairs; open the evidence and consistency review.'
      : findings
            .map(
              (c) => c.atSimilarPace
                  ? '${c.type}: recorded HR ${c.hrChange.abs().toStringAsFixed(1)} bpm lower at similar pace'
                  : '${c.type}: recorded pace ${c.paceChange.abs().toStringAsFixed(1)}% faster at similar HR',
            )
            .join('. ');
  Map<String, Object?> toJson() => {
    'start': start,
    'split': split,
    'end': end,
    'examined': examined,
    'observations': [
      for (final s in observations)
        {
          'id': s.id,
          'day': s.day,
          'type': s.type,
          'seconds': s.seconds,
          'meters': s.meters,
          'hr': s.hr,
          'coverage': s.coverage,
          'cadence': s.cadence,
          'context': s.context,
          'bestEfforts': s.bestEfforts,
        },
    ],
  };
  static TrainingReviewData fromJson(Map m) =>
      TrainingReviewData(m['start'], m['split'], m['end'], [
        for (final s in m['observations'] as List)
          ana.TrainingObservation(
            id: s['id'],
            day: s['day'],
            type: s['type'],
            seconds: (s['seconds'] as num).toDouble(),
            meters: (s['meters'] as num).toDouble(),
            hr: (s['hr'] as num).toDouble(),
            coverage: (s['coverage'] as num).toDouble(),
            cadence: (s['cadence'] as num?)?.toDouble(),
            context: workoutContext(s['context']),
            bestEfforts: (s['bestEfforts'] as Map? ?? {}).map(
              (k, v) => MapEntry(k.toString(), (v as num).toDouble()),
            ),
          ),
      ], examined: (m['examined'] as num).toInt());
  static Future<TrainingReviewData?> retained(String day) async {
    final raw = await CalculationStore.read('training.review.$day');
    return raw == null ? null : fromJson(jsonDecode(raw) as Map);
  }

  Future<void> retain() async {
    // Notification evidence stays fixed for the period it describes.
    final db = await LocalDb.instance;
    final keys = await db.query(
      'baselines',
      columns: ['key'],
      where: 'key LIKE ?',
      whereArgs: ['calculation:training.review.%'],
      orderBy: 'key DESC',
    );
    // Eight notification snapshots cover roughly four months. Older links
    // show an explicit unavailable state rather than newly computed evidence.
    for (final row in keys.skip(7)) {
      await CalculationStore.remove(
        (row['key'] as String).substring(CalculationStore.prefix.length),
      );
    }
    if (await retained(end) == null)
      await CalculationStore.write(
        'training.review.$end',
        jsonEncode(toJson()),
      );
  }

  static Future<TrainingReviewData> load(
    LocalRepository repo,
    Profile profile, {
    DateTime? at,
  }) async {
    final now = at ?? DateTime.now();
    final stop = DateTime(now.year, now.month, now.day);
    final start = DateTime(now.year, now.month, now.day - 28);
    final split = DateTime(now.year, now.month, now.day - 14);
    final rows =
        (await repo.getWorkouts(range: 'month'))['workouts'] as List? ??
        const [];
    final out = <ana.TrainingObservation>[];
    var examined = 0;
    for (final row in rows.whereType<Map>()) {
      final type = row['type']?.toString(), id = row['id']?.toString();
      final ts = row['start_ts'] as num?, te = row['end_ts'] as num?;
      if (!(isRunType(type) || isWalkType(type)) ||
          id == null ||
          ts == null ||
          te == null ||
          row['status'] == 'live' ||
          row['private'] == 1 ||
          row['private'] == true ||
          row['end_ts_fabricated'] == true ||
          row['end_ts_fabricated'] == 1)
        continue;
      final begin = DateTime.fromMillisecondsSinceEpoch(ts.toInt() * 1000);
      final end = DateTime.fromMillisecondsSinceEpoch(te.toInt() * 1000);
      if (begin.isBefore(start) || !begin.isBefore(stop) || end.isAfter(stop))
        continue;
      examined++;
      final measured = await WorkoutMeasurements.read(
        repo,
        id,
        begin,
        end,
        profile,
        bandSteps: (row['steps'] as num?)?.toInt(),
      );
      // Motion distance is useful for calories but too uncertain for a pace/HR
      // finding; require a measured route and a usable HR trace for this review.
      if (measured.points.length < 2) continue;
      if (activeRouteCoverage(measured.points, measured.clock, end) < .8)
        continue;
      final b = await repo.getWorkout(id);
      final samples = (b['hr'] as List? ?? const [])
          .whereType<Map>()
          .where((v) => v['t'] is num && v['v'] is num)
          .toList();
      final byMinute = <int, double>{};
      for (final sample in samples) {
        final t = DateTime.fromMillisecondsSinceEpoch(
          (sample['t'] as num).toInt() * 1000,
        );
        if (!measured.clock.includes(t)) continue;
        final hr = (sample['v'] as num).toDouble();
        if (hr.isFinite && hr > 0)
          byMinute[measured.clock.activeSeconds(t) ~/ 60] = hr;
      }
      final minutes = measured.clock.activeSeconds() / 60;
      if (byMinute.isEmpty || minutes <= 0) continue;
      // A legacy coverage scalar cannot make a sparse retained curve complete.
      // Count actual active-minute evidence too; pauses and missing minutes stay out.
      final measuredCoverage = (byMinute.length / minutes.ceil()).clamp(
        0.0,
        1.0,
      );
      final declaredCoverage =
          ((b['trace_coverage_pct'] as num?)?.toDouble() ?? 0) / 100;
      final mix = measured.mix;
      if (mix == null) continue;
      final meters = mix.runM + mix.walkM;
      final motion =
          measured.motion ?? await sessionMotionWindow(id, begin, end);
      final motionSeconds = motion == null
          ? 0.0
          : [
              for (var i = 0; i < motion.steps.length; i++) motion.secondsAt(i),
            ].fold<double>(0, (a, b) => a + b);
      final cadence = motionSeconds >= measured.clock.activeSeconds() * .8
          ? motion?.cadence
          : null;
      out.add(
        ana.TrainingObservation(
          id: id,
          day: dayLabelOf(begin),
          type: isRunType(type) ? 'Running' : 'Walking',
          seconds: measured.clock.activeSeconds().toDouble(),
          context: workoutContext(measured.clock.results['context']),
          bestEfforts: isRunType(type)
              ? bestEfforts(measured.points)
              : const {},
          meters: meters,
          cadence: cadence != null && cadence.isFinite && cadence > 0
              ? cadence
              : null,
          hr: byMinute.values.reduce((a, b) => a + b) / byMinute.length,
          coverage: declaredCoverage < measuredCoverage
              ? declaredCoverage
              : measuredCoverage,
        ),
      );
    }
    return TrainingReviewData(
      dayLabelOf(start),
      dayLabelOf(split),
      dayLabelOf(stop),
      out,
      examined: examined,
    );
  }
}
