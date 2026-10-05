import 'dart:math' as math;
import 'profile.dart';
import '../data/day_label.dart';
import '../data/db.dart';
import '../data/local_repository.dart';
import '../data/nutrition_store.dart';
import '../data/profile_history.dart';
import '../gps/run_history.dart';
import '../gps/workout_clock.dart';

/// Full-day resting budget plus movement and logged food to date.
class DayUpkeep {
  const DayUpkeep(
    this.profile, {
    required this.steps,
    this.runs = kNoRunDay,
    this.eaten = 0,
    this.date,
    this.overlapUnknown = false,
  });
  final Profile profile;
  final num? steps;
  final RunDay runs;
  final double eaten;
  final String? date;
  final bool overlapUnknown;

  ({double bmr, double steps, double run, double food, double total})?
  get parts {
    final m = maintenance(
      profile,
      steps: steps,
      eatenKcal: eaten,
      runKcal: runs.kcal,
      runSteps: runs.steps,
    );
    if (m == null || !overlapUnknown) return m;
    // Without evidence of run-step overlap, use the larger movement estimate
    // rather than adding the full run on top of unreduced walking steps.
    final walk = stepCalories(steps, profile.weightKg) ?? 0;
    final movement = math.max(walk, runs.kcal);
    return (
      bmr: m.bmr,
      steps: math.max(0, movement - runs.kcal),
      run: runs.kcal,
      food: m.food,
      total: m.bmr + movement + m.food,
    );
  }

  num? get walkedSteps =>
      steps == null ? null : (steps! - runs.steps).clamp(0, steps!);
  static Future<DayUpkeep> read(
    LocalRepository repo,
    String date,
    Profile fallback, {
    double? eaten,
    List<RunSummary>? runs,
  }) async {
    final profile = await ProfileHistory.on(date, fallback);
    final steps = await repo.getMeasuredDaySteps(date);
    final all = [...runs ?? await loadRuns(repo)];
    final live = WorkoutClock.current;
    if (live != null) {
      final row = await LocalDb.session(live.id);
      if (isRunType(row?['type'] as String?)) {
        final current = await summariseRun(
          repo,
          live.id,
          live.start.millisecondsSinceEpoch ~/ 1000,
          (live.end ?? live.pausedAt ?? DateTime.now())
                  .millisecondsSinceEpoch ~/
              1000,
        );
        if (current != null) {
          all.removeWhere((r) => r.id == live.id);
          all.add(current);
        }
      }
    }
    // One movement interval contributes once, even if an old/imported session overlaps.
    all.sort((a, b) => a.start.compareTo(b.start));
    final owned = <RunSummary>[], occupied = <ActiveWindow>[];
    for (final r in all) {
      final overlaps = r.activeWindows.any(
        (w) => occupied.any(
          (p) => w.start.isBefore(p.end) && w.end.isAfter(p.start),
        ),
      );
      final part = overlaps
          ? await summariseRun(
              repo,
              r.id,
              r.start.millisecondsSinceEpoch ~/ 1000,
              r.end?.millisecondsSinceEpoch == null
                  ? null
                  : r.end!.millisecondsSinceEpoch ~/ 1000,
              excluded: occupied,
            )
          : r;
      if (part != null && (!overlaps || part.activeWindows.isNotEmpty)) {
        owned.add(part);
      }
      occupied.addAll(r.activeWindows);
    }
    final dayRuns = owned
        .where(
          (r) => r.byDay.isEmpty
              ? dayLabelOf(r.start) == date
              : r.byDay.containsKey(date),
        )
        .toList();
    final unknown = dayRuns.any(
      (r) =>
          (r.byDay.containsKey(date) ? r.byDay[date]!.steps : r.steps) ==
              null &&
          (r.floorKcal(profile.weightKg) ?? 0) > 0,
    );
    final food =
        eaten ??
        rollupDay(
          date,
          await NutritionDb.entriesForDay(await LocalDb.instance, date),
          today: todayLabel(),
        ).kcal.value ??
        0;
    return DayUpkeep(
      profile,
      date: date,
      steps: steps,
      runs: runEnergyOn(
        owned,
        date,
        weightKg: profile.weightKg,
        daySteps: steps,
      ),
      eaten: food,
      overlapUnknown: unknown,
    );
  }
}
