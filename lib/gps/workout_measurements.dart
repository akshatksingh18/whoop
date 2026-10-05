import '../compute/profile.dart';
import '../data/db.dart';
import '../data/day_label.dart';
import '../data/local_repository.dart';
import '../data/profile_history.dart';
import 'motion_window.dart';
import 'route_math.dart';
import 'route_models.dart';
import 'run_analysis.dart';
import 'run_history.dart' show isRunType, isWalkType;
import 'session_track.dart';
import 'workout_clock.dart';

double? workoutMethod1(String type, Profile p, {int? steps, RunMix? mix}) {
  if (isWalkType(type)) return stepCalories(steps, p.weightKg);
  if (!isRunType(type) || mix == null) return null;
  return runFloorKcal(
    runMeters: mix.runM,
    walkMeters: mix.walkM,
    climbMeters: mix.climbM,
    weightKg: p.weightKg,
  );
}

class WorkoutMeasurements {
  const WorkoutMeasurements(
    this.clock,
    this.profile,
    this.points,
    this.motion,
    this.steps,
  );
  final WorkoutClock clock;
  final Profile profile;
  final List<RoutePoint> points;
  final MotionWindow? motion;
  final int? steps;
  RunMix? get mix => points.length > 1
      ? runMix(points)
      : motion?.totalMeters == null
      ? null
      : motionMix(
          steps: motion!.steps,
          meters: motion!.meters,
          chunkSec: motion!.chunkSec,
          seconds: motion!.seconds,
        );
  double? get meters =>
      points.length > 1 ? totalDistanceMeters(points) : motion?.totalMeters;
  int get movingSec => points.length > 1
      ? movingSeconds(points)
      : ((motion?.activeMinutes ?? 0) * 60).round();
  double? method1(String type) =>
      workoutMethod1(type, profile, steps: steps, mix: mix);
  static Future<WorkoutMeasurements> read(
    LocalRepository repo,
    String id,
    DateTime start,
    DateTime end,
    Profile fallback, {
    int? bandSteps,
  }) async {
    final clock = WorkoutClock.read(id, start, end: end);
    final profile =
        clock.profile ?? await ProfileHistory.on(dayLabelOf(start), fallback);
    final route = await repo.getWorkoutRoute(id);
    final points = activeTrack(route?.points ?? [], clock);
    final motion = points.length > 1
        ? null
        : await sessionMotionWindow(id, start, end);
    var steps = 0;
    var known = false;
    for (final w in clock.windows()) {
      final resolved = await LocalDb.resolvedStepsForWindow(w.start, w.end);
      if (resolved.hasPhoneCoverage || resolved.total > 0) {
        known = true;
        steps += resolved.total;
      }
    }
    if (!known && motion != null && motion.totalSteps > 0) {
      known = true;
      steps = motion.totalSteps;
    }
    if (!known && bandSteps != null && bandSteps > 0) {
      known = true;
      steps = bandSteps;
    }
    return WorkoutMeasurements(
      clock,
      profile,
      points,
      motion,
      known ? steps : null,
    );
  }
}
