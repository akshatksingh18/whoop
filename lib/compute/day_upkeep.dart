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
    this.walkingMeters,
    this.distanceSource = 'Distance unavailable',
    this.acsmRuns = kNoRunDay,
    this.runWindows = const [],
    this.digestion,
    this.lifting,
  });
  final Profile profile;
  final num? steps;
  final RunDay runs;
  final double eaten;
  final String? date;
  final bool overlapUnknown;
  final double? walkingMeters;
  final String distanceSource;
  final RunDay acsmRuns;
  final List<ActiveWindow> runWindows;

  /// The day's summed per-entry [digestionKcal]; null prices [eaten] as food
  /// of unknown composition.
  final double? digestion;

  /// Net strength-training energy for the day, shown as a separate line and
  /// never added to [parts]' total (Akshat's decision, build 84). Null with no
  /// lifting session; `approximate` when a session's steps were unknown.
  final ({double kcal, int sessions, bool approximate})? lifting;

  ({double bmr, double steps, double run, double food, double total})?
  get acsmParts {
    final m = parts;
    if (m == null || walkingMeters == null) return null;
    final walk = acsmActiveKcal(
      runMeters: 0,
      walkMeters: walkingMeters!,
      weightKg: profile.weightKg,
    );
    if (walk == null) return null;
    final movement = overlapUnknown
        ? math.max(walk, acsmRuns.kcal)
        : walk + acsmRuns.kcal;
    return (
      bmr: m.bmr,
      steps: math.max(0, movement - acsmRuns.kcal),
      run: acsmRuns.kcal,
      food: m.food,
      total: m.bmr + movement + m.food,
    );
  }

  ({double bmr, double steps, double run, double food, double total})?
  get parts {
    final m = maintenance(
      profile,
      steps: steps,
      eatenKcal: eaten,
      digestionKcal: digestion,
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

  /// [distanceSource] as a short chip ("Distance: GPS route"). The long
  /// sentence stays for the explanation; the chip is what a card shows.
  String get distanceTag => distanceTagOf(distanceSource);

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
    // `eaten: 0` is a caller asking for maintenance without food.
    final entries = eaten == 0
        ? const <FoodEntry>[]
        : await NutritionDb.entriesForDay(await LocalDb.instance, date);
    final food =
        eaten ?? rollupDay(date, entries, today: todayLabel()).kcal.value ?? 0;
    var digestion = 0.0;
    for (final e in entries) {
      digestion += digestionKcal(
        kcal: e.kcal,
        proteinG: e.proteinG,
        carbsG: e.carbsG,
        fatG: e.fatG,
      );
    }
    final dayEnergy = runEnergyOn(
      owned,
      date,
      weightKg: profile.weightKg,
      daySteps: steps,
    );
    final walked = steps == null ? null : math.max(0, steps - dayEnergy.steps);
    final distance = await _walkingDistance(repo, date, walked, profile, [
      for (final r in dayRuns)
        if ((r.floorKcal(profile.weightKg) ?? 0) > 0) ...r.activeWindows,
    ]);
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
      digestion: food > 0 ? digestion : 0,
      lifting: await liftingOn(date, profile),
      overlapUnknown: unknown,
      walkingMeters: distance.meters,
      distanceSource: distance.source,
      acsmRuns: runEnergyOn(
        owned,
        date,
        weightKg: profile.weightKg,
        daySteps: steps,
        acsm: true,
      ),
      runWindows: [
        for (final r in dayRuns)
          if ((r.floorKcal(profile.weightKg) ?? 0) > 0) ...r.activeWindows,
      ],
    );
  }
}

/// The profile a session is priced with: the one recorded with it, else the
/// dated profile for the day it started — so a past session keeps the weight
/// it was done at on every screen.
Future<Profile> sessionProfile(
  String id,
  DateTime start,
  Profile fallback, {
  DateTime? end,
}) async =>
    WorkoutClock.read(id, start, end: end).profile ??
    await ProfileHistory.on(dayLabelOf(start), fallback);

/// Net energy of the day's strength sessions ([kLiftTypeKeys]), each priced by
/// [sessionActiveKcal] ((MET − 1) × kg × active hours; heart rate not used),
/// less the step calories of steps taken inside the session's active windows,
/// which the Steps row already counts. A session is filed under the day it
/// started. Null when the day has no lifting session or no weight.
Future<({double kcal, int sessions, bool approximate})?> liftingOn(
  String date,
  Profile profile,
) async {
  final day = DateTime.tryParse(date);
  final kg = profile.weightKg;
  if (day == null || kg == null) return null;
  final from = DateTime(day.year, day.month, day.day);
  final to = DateTime(day.year, day.month, day.day + 1);
  final lo = from.millisecondsSinceEpoch ~/ 1000;
  final hi = to.millisecondsSinceEpoch ~/ 1000 - 1;
  final rows = [
    for (final r in await LocalDb.sessionsInRange(lo, hi))
      if (isLiftType(r['type'] as String?)) r,
  ];
  if (rows.isEmpty) return null;
  var kcal = 0.0;
  var counted = 0;
  var approximate = false;
  for (final r in rows) {
    final id = r['id'] as String?;
    final startTs = (r['start_ts'] as num?)?.toInt();
    if (id == null || startTs == null) continue;
    final start = DateTime.fromMillisecondsSinceEpoch(startTs * 1000);
    final endTs = (r['end_ts'] as num?)?.toInt();
    final end = endTs == null
        ? DateTime.now()
        : DateTime.fromMillisecondsSinceEpoch(endTs * 1000);
    if (!end.isAfter(start)) continue;
    final clock = WorkoutClock.read(id, start, end: end);
    final minutes = clock.activeDuration(end).inSeconds / 60;
    final at = await sessionProfile(id, start, profile, end: end);
    final net = sessionActiveKcal(
      p: at,
      type: r['type'] as String,
      minutes: minutes,
    );
    if (net == null) continue;
    var steps = 0;
    var known = false;
    for (final w in clock.windows()) {
      final s = await LocalDb.resolvedStepsForWindow(w.start, w.end);
      if (s.hasPhoneCoverage || s.total > 0) {
        known = true;
        steps += s.total;
      }
    }
    if (!known) approximate = true;
    kcal += math.max(0.0, net - (stepCalories(steps, at.weightKg) ?? 0));
    counted++;
  }
  if (counted == 0) return null;
  return (kcal: kcal, sessions: counted, approximate: approximate);
}

/// Distance follows credited source steps and excludes the same active run windows.
/// Partial coverage uses an explicit height-based step-length estimate, never zero.
Future<({double? meters, String source})> _walkingDistance(
  LocalRepository repo,
  String date,
  num? walked,
  Profile profile,
  List<ActiveWindow> excluded,
) async {
  if (walked == null)
    return (meters: null, source: 'Walking steps unavailable');
  if (walked == 0) return (meters: 0.0, source: 'No walking steps');
  final d = DateTime.parse(date);
  final hi =
      DateTime(d.year, d.month, d.day + 1).millisecondsSinceEpoch ~/ 1000;
  final lo = d.millisecondsSinceEpoch ~/ 1000;
  final db = await LocalDb.instance;
  final rows = await db.query(
    'live_coverage',
    where: 'source = ? AND start_ts < ? AND end_ts > ?',
    whereArgs: [LocalDb.kStepSourcePhone, hi, lo],
  );
  final resolved = await LocalDb.resolvedStepsForDay(date);
  var nativeSteps = 0.0, meters = 0.0;
  final blocked = [...excluded];
  var workoutSteps = 0.0, workoutMeters = 0.0;
  final walks = await db.query(
    'sessions',
    where: 'start_ts < ? AND COALESCE(end_ts, ?) > ?',
    whereArgs: [hi, DateTime.now().millisecondsSinceEpoch ~/ 1000, lo],
    orderBy: 'start_ts ASC, id ASC',
  );
  for (final row in walks) {
    if (!isWalkType(row['type'] as String?) || row['end_ts_fabricated'] == 1)
      continue;
    final ts = (row['start_ts'] as num).toInt();
    final te =
        (row['end_ts'] as num?)?.toInt() ??
        DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final walk = await summariseRun(
      repo,
      row['id'] as String,
      ts,
      te,
      bandSteps: (row['steps'] as num?)?.toInt(),
      excluded: blocked,
    );
    final slice = walk?.byDay[date];
    if (walk == null ||
        walk.fromMotion ||
        slice?.steps == null ||
        slice!.steps! <= 0 ||
        slice.meters <= 0)
      continue;
    // A recorded walk replaces its own motion-distance estimate, never adds
    // a second walking contribution. Paused windows remain ordinary movement.
    workoutSteps += slice.steps!;
    workoutMeters += slice.meters;
    blocked.addAll(walk.activeWindows);
  }
  blocked.sort((a, b) => a.start.compareTo(b.start));
  for (final span in resolved.spans.where((s) => !s.fromBand)) {
    var remaining = (span.endTs - span.startTs).toDouble();
    var until = span.startTs;
    for (final w in blocked) {
      final a = math.max(until, w.start.millisecondsSinceEpoch ~/ 1000);
      final b = math.min(span.endTs, w.end.millisecondsSinceEpoch ~/ 1000);
      if (b > a) {
        remaining -= b - a;
        until = b;
      }
    }
    if (remaining <= 0) continue;
    for (final row in rows) {
      final start = (row['start_ts'] as num).toInt(),
          end = (row['end_ts'] as num).toInt();
      final m = (row['distance_m'] as num?)?.toDouble(),
          n = (row['steps'] as num).toDouble();
      if (start > span.startTs ||
          end < span.endTs ||
          n <= 0 ||
          m == null ||
          !m.isFinite ||
          m <= 0)
        continue;
      final count = span.steps * remaining / (span.endTs - span.startTs);
      nativeSteps += count;
      meters += count * m / n;
      break;
    }
  }
  nativeSteps += workoutSteps;
  meters += workoutMeters;
  final credited = math.min(walked.toDouble(), nativeSteps);
  if (nativeSteps > credited) meters *= credited / nativeSteps;
  final remainder = math.max(0.0, walked - credited);
  final fallback = remainder < .5 ? 0.0 : walkingEnergy(remainder, profile)?.km;
  if (fallback == null)
    return (
      meters: null,
      source: 'Distance incomplete; add height for step-length estimate',
    );
  meters += fallback * 1000;
  return (
    meters: meters,
    source: workoutSteps > 0
        ? (walked - workoutSteps < .5
              ? 'Recorded walking route'
              : 'Walking route + phone motion / estimated step length')
        : credited <= 0
        ? 'Estimated from step length'
        : remainder < .5
        ? 'Phone motion-distance estimate'
        : 'Phone motion + estimated step length',
  );
}

/// A distance source sentence as a short chip ("Distance: GPS route"). The
/// sentence stays for explanations; the chip is what a card shows.
String distanceTagOf(String source) => switch (source) {
  'Recorded walking route' => 'Distance: GPS route',
  'Walking route + phone motion / estimated step length' =>
    'Distance: route + phone',
  'Estimated from step length' => 'Distance: step length',
  'Phone motion-distance estimate' => 'Distance: phone motion',
  'Phone motion + estimated step length' => 'Distance: phone + step length',
  'Distance unavailable' => 'Distance unavailable',
  _ => 'Distance incomplete',
};
