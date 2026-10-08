// Profile — the on-device personal profile fed to the DerivationEngine.
//
// Sourced from AppState's local profile map (shared_preferences). Algorithms
// that NEED a field (HRmax via Tanaka, Keytel calories, TRIMP sex constant,
// fitness-age) read it from here; algorithms that don't simply ignore it.
//
// HONESTY: a missing field => the DEPENDENT metric must return null+confidence 0
// (never a fabricated default). The engine therefore passes nullable getters and
// only computes profile-gated metrics when the input is present.

import 'dart:math' as math;

class Profile {
  final int? ageYears;
  final double? weightKg;
  final double? heightCm;
  final String? sex; // 'm' | 'f' (lowercase; matches the AppState profile map)
  final int? restingHrManual; // optional user-supplied RHR

  const Profile({
    this.ageYears,
    this.weightKg,
    this.heightCm,
    this.sex,
    this.restingHrManual,
  });

  static Profile fromMap(Map<String, dynamic>? m) {
    if (m == null) return const Profile();
    return Profile(
      ageYears: (m['age'] as num?)?.round(),
      weightKg: (m['weight_kg'] as num?)?.toDouble(),
      heightCm: (m['height_cm'] as num?)?.toDouble(),
      sex: (m['sex'] as String?)?.toLowerCase(),
      restingHrManual: (m['resting_hr'] as num?)?.round(),
    );
  }

  Map<String, dynamic> toMap() => {
    if (ageYears != null) 'age': ageYears,
    if (weightKg != null) 'weight_kg': weightKg,
    if (heightCm != null) 'height_cm': heightCm,
    if (sex != null) 'sex': sex,
    if (restingHrManual != null) 'resting_hr': restingHrManual,
  };

  // NO `hrMaxTanaka` HERE. It was `208 − 0.7·age` inlined on the profile, which
  // made the HR ceiling a property of the ATHLETE alone — and the app then
  // carried four of them (this one, `220−age` twice, and `(220−age)+25`), so
  // one user's zone timeline and that same day's session zone bands were banded
  // off different ceilings with nothing on screen saying so.
  //
  // The one definition is `compute/hr_max.dart`'s `estimatedMaxHr(age, family)`
  // and it takes the STRAP as well: what a band can read at intensity is a
  // property of its sensor, so an uncalibrated or unstamped strap gets no
  // ceiling rather than gen4's. Callers resolve it at the layer that knows
  // which device measured the window and pass it down. (TS-03a)

  bool get isComplete =>
      ageYears != null && weightKg != null && heightCm != null && sex != null;

  /// The anchors Keytel (2005) needs to turn heart rate into kcal: age, body
  /// mass and sex. Height is not one of them, so it is deliberately absent
  /// here — gating calories on [isComplete] would refuse to score a profile
  /// that has everything the formula actually reads.
  ///
  /// The one definition of "can we cost this session in calories", shared by
  /// the live tick and the substrate re-score. They used to disagree: the
  /// re-score refused to guess while the live tick silently substituted a
  /// 30-year-old 70 kg male, so an unfinished profile produced a confident
  /// kcal number that was simply somebody else's.
  bool get hasCalorieAnchors =>
      ageYears != null && weightKg != null && sex != null;
}

/// Normalise every sex spelling the app can persist onto the three names the
/// analytics coefficient tables key on: 'male' | 'female' | 'nonbinary'.
///
/// Two writers disagree. Onboarding (`profile_setup_screen`) stores 'm'/'f';
/// the profile screen offers 'male'/'female'/'other'. Every scored path — day
/// calories, TRIMP, the live tick, a manually logged session — has to land on
/// the same coefficient block for the same stored value, or one field of one
/// profile scores as two different people. It happened: TRIMP tested `== 'f'`
/// while the calorie path accepted 'female' too, so a profile written by the
/// profile screen got female calories and male TRIMP.
///
/// 'other' and anything unrecognised map to `nonbinary`, which the analytics
/// tables define as the mean of the two published sex constants rather than a
/// guess at one of them.
String workoutSex(String? sex) {
  switch ((sex ?? '').toLowerCase()) {
    case 'm':
    case 'male':
      return 'male';
    case 'f':
    case 'female':
      return 'female';
    default:
      return 'nonbinary';
  }
}

/// Active calories from [steps]: 2.74 × steps × kg ÷ 8,368 (the Weyand et
/// al. 2010 walking-cost form). Energy ABOVE resting only, so it never repeats
/// the BMR. Daily accounting excludes steps already priced by running Method 1.
/// This is a conservative estimate, not a guaranteed physiological minimum.
double? stepCalories(num? steps, double? weightKg) {
  if (steps == null ||
      !steps.isFinite ||
      steps < 0 ||
      weightKg == null ||
      !weightKg.isFinite ||
      weightKg <= 0) {
    return null;
  }
  return 2.74 * steps * weightKg / 8368;
}

/// Resting energy for a whole day, Mifflin–St Jeor:
/// 10 × kg + 6.25 × cm − 5 × age, + 5 for men, − 161 for women, and the
/// midpoint of the two otherwise. Null without weight, height and age.
double? bmrMifflin(Profile p) {
  final w = p.weightKg, h = p.heightCm, a = p.ageYears;
  if (w == null ||
      h == null ||
      a == null ||
      !w.isFinite ||
      !h.isFinite ||
      w <= 0 ||
      h <= 0 ||
      a <= 0) {
    return null;
  }
  final base = 10 * w + 6.25 * h - 5 * a;
  return base +
      switch (p.sex) {
        'm' || 'male' => 5,
        'f' || 'female' => -161,
        _ => -78,
      };
}

/// Net oxygen cost of running, ml/kg per metre (Akshat's Method 1, the
/// chosen budgeting coefficient; ACSM's own running coefficient is 0.2).
const double kRunO2PerMeter = 0.143;

/// Net oxygen cost of walking, ml/kg per metre (ACSM walking equation). Used
/// for walk breaks inside a run so the budget never prices walking as running.
const double kWalkO2PerMeter = 0.1;

/// Oxygen cost of climbing, ml/kg per vertical metre (ACSM running grade
/// term, 0.9 × speed × grade, summed over time = 0.9 × metres climbed).
const double kClimbO2PerMeter = 0.9;

/// Budget estimate: active kcal for moving [weightKg] over
/// [runMeters] at running speed, [walkMeters] at walking speed and up
/// [climbMeters] of ascent.
///
/// Akshat's four steps (speed = d/t; O₂ = 0.143·speed + 0.9·speed·incline;
/// kcal/h = O₂ × kg × 0.3; kcal = kcal/h ÷ 60 × t) collapse to
/// 0.005 × kg × (0.143 × metres + 0.9 × metres climbed), because speed × time
/// is distance and speed × incline × time is height gained. 0.005 is
/// 0.3 ÷ 60: five kcal per litre of oxygen. Null without a weight.
double? runFloorKcal({
  required double runMeters,
  double walkMeters = 0,
  double climbMeters = 0,
  double? weightKg,
}) {
  if (weightKg == null ||
      !weightKg.isFinite ||
      weightKg <= 0 ||
      !runMeters.isFinite ||
      !walkMeters.isFinite ||
      !climbMeters.isFinite) {
    return null;
  }
  final o2 =
      kRunO2PerMeter * math.max(0, runMeters) +
      kWalkO2PerMeter * math.max(0, walkMeters) +
      kClimbO2PerMeter * math.max(0, climbMeters);
  return 0.005 * weightKg * o2;
}

/// Method 2, Keytel et al. (2005) heart-rate calories, ACTIVE only:
/// gross kcal/min from heart rate minus resting (Mifflin–St Jeor ÷ 1,440),
/// summed over the session's per-minute heart rate.
///
/// [hrPerSlot] has dense minute indices, null where the band recorded nothing.
/// Only the remaining fraction of the final minute is included. A slot whose
/// active energy comes out below zero (an easy walk break at a low heart
/// rate, below what the equation was fitted on) counts as zero rather than
/// subtracting. Null without age, weight, sex-independent BMR inputs, or a
/// single measured slot.
({double kcal, int measured, int slots})? keytelActiveKcal(
  List<double?> hrPerSlot,
  double durationMin,
  Profile p,
) {
  final w = p.weightKg, a = p.ageYears;
  final bmr = bmrMifflin(p);
  if (w == null || a == null || bmr == null || hrPerSlot.isEmpty) return null;
  if (!durationMin.isFinite || durationMin <= 0) return null;
  final sex = workoutSex(p.sex);
  double gross(double hr) => switch (sex) {
    'male' => (-55.0969 + 0.6309 * hr + 0.1988 * w + 0.2017 * a) / 4.184,
    'female' => (-20.4022 + 0.4472 * hr - 0.1263 * w + 0.074 * a) / 4.184,
    _ =>
      ((-55.0969 + 0.6309 * hr + 0.1988 * w + 0.2017 * a) +
              (-20.4022 + 0.4472 * hr - 0.1263 * w + 0.074 * a)) /
          2 /
          4.184,
  };
  final rest = bmr / 1440;
  // Dense minute indices preserve missing minutes and the actual last fraction.
  final slots = math.min(hrPerSlot.length, durationMin.ceil());
  var kcal = 0.0;
  var measured = 0;
  for (var i = 0; i < slots; i++) {
    final hr = hrPerSlot[i];
    final perSlot = math.min(1.0, durationMin - i);
    if (hr == null || !hr.isFinite || hr <= 0) continue;
    measured++;
    kcal += math.max(0, gross(hr) - rest) * perSlot;
  }
  if (measured == 0) return null;
  return (kcal: kcal, measured: measured, slots: slots);
}

/// Active (net) kcal for any non-walking, non-running session, the ONE number
/// every screen shows for it (build 85).
///
/// Strength ([isLiftType]) is priced by MET alone: (MET − 1) × kg × active
/// hours, with [conservativeMet] (3.5 for weight training, the lowest
/// resistance-training value in the 2024 Compendium). Heart rate is not used:
/// at a given heart rate lifting burns less than steady exercise, so it would
/// overstate, and Keytel was built on 57-90% of max heart rate, so below that
/// it understates. Sets and rests are priced together, as the Compendium's
/// whole-session averages are; the band cannot isolate a 15-second set.
/// Other sessions keep [otherWorkoutActiveKcal] (the lower of heart rate and
/// MET). Null without the inputs.
double? sessionActiveKcal({
  required Profile p,
  required String? type,
  required double minutes,
  double? meanHr,
  double? catalogueMet,
}) {
  if (isLiftType(type)) {
    final key = type!.toLowerCase().replaceAll(' ', '_');
    final w = p.weightKg;
    if (w == null || !minutes.isFinite || minutes <= 0) return null;
    return math.max(0.0, conservativeMet(key, 0) - 1) * w * minutes / 60;
  }
  return otherWorkoutActiveKcal(
    p: p,
    minutes: minutes,
    meanHr: meanHr,
    met: catalogueMet == null || type == null
        ? null
        : conservativeMet(type.toLowerCase().replaceAll(' ', '_'), catalogueMet),
  );
}

/// The strength workouts the maintenance sheet's separate Lifting line counts:
/// exactly the types [conservativeMet] prices as strength work.
const Set<String> kLiftTypeKeys = {
  'weight_training',
  'bodyweight',
  'functional',
  'calisthenics',
  'powerlifting',
};

bool isLiftType(String? type) =>
    type != null &&
    kLiftTypeKeys.contains(type.toLowerCase().replaceAll(' ', '_'));

/// The MET a non-walking, non-running workout is priced at: the catalogue
/// value, except strength work, which the 2024 Adult Compendium puts at 3.5
/// for a typical multi-exercise session (5.0 for heavy squats/deadlifts) —
/// the catalogue's 6.0 is its vigorous bodybuilding figure.
double conservativeMet(String type, double catalogueMet) =>
    switch (type.toLowerCase()) {
      'weight_training' || 'bodyweight' || 'functional' => 3.5,
      'calisthenics' => 3.8,
      'powerlifting' => 5.0,
      _ => catalogueMet,
    };

/// Active (net) kcal for a workout that is neither walking nor running — the
/// counterpart of the step and distance methods: energy above resting only,
/// and the LOWER of two estimates.
///
/// - Heart rate: Keytel minus resting (BMR ÷ 1,440) at the session's mean HR
///   for its active minutes. Keytel is linear in HR, so the mean gives the same
///   total; it is known to overestimate, worst in resistance and interval work.
/// - Activity: (MET − 1) × kg × hours, from [met] (see [conservativeMet]).
///
/// Either alone when the other is unavailable; null with neither. Non-step
/// workouts stay out of maintenance (Akshat's decision); this is the number a
/// session shows.
double? otherWorkoutActiveKcal({
  required Profile p,
  required double minutes,
  double? meanHr,
  double? met,
}) {
  if (!minutes.isFinite || minutes <= 0) return null;
  final w = p.weightKg;
  final byMet = met == null || w == null || !met.isFinite
      ? null
      : math.max(0.0, met - 1) * w * minutes / 60;
  final byHr = meanHr == null || !meanHr.isFinite || meanHr <= 0
      ? null
      : keytelActiveKcal(
          List<double?>.filled(minutes.ceil(), meanHr),
          minutes,
          p,
        )?.kcal;
  if (byMet == null) return byHr;
  if (byHr == null) return byMet;
  return math.min(byMet, byHr);
}

/// Digestion cost rates, the LOW end of each published range (build 84,
/// Akshat's conservative choice; `todo.md` holds the audit): protein 20%,
/// carbohydrate 5%, fat 0%, and 5% for kcal of unknown composition (the low
/// end of the 5-15% measured for mixed diets, Westerterp 2004). No entry
/// costs more than pure protein would.
const double kDigestProtein = 0.20;
const double kDigestCarbs = 0.05;
const double kDigestFat = 0.0;
const double kDigestUnknown = 0.05;
const double kDigestCap = 0.20;

/// The digestion cost of one logged entry. Grams become energy by label
/// factors (protein 4, carbohydrate 4, fat 9 kcal/g). With all three macros
/// logged, kcal they do not explain (fibre, alcohol, label rounding) adds
/// nothing; with any missing, the kcal the logged macros do not explain is
/// priced at [kDigestUnknown]. Capped at [kDigestCap] of the entry's kcal.
/// An entry without kcal costs nothing, as it adds nothing to the day.
double digestionKcal({
  double? kcal,
  double? proteinG,
  double? carbsG,
  double? fatG,
}) {
  if (kcal == null || !kcal.isFinite || kcal <= 0) return 0;
  double g(double? v) => v == null || !v.isFinite || v < 0 ? 0 : v;
  final p = 4 * g(proteinG), c = 4 * g(carbsG), f = 9 * g(fatG);
  var cost = kDigestProtein * p + kDigestCarbs * c + kDigestFat * f;
  final complete = proteinG != null && carbsG != null && fatG != null;
  if (!complete) cost += kDigestUnknown * math.max(0.0, kcal - (p + c + f));
  return math.min(cost, kDigestCap * kcal);
}

/// A day's conservative maintenance budget:
/// BMR + step calories + running (Method 1) + the digestion cost of the food
/// logged that day.
///
/// [digestionKcal] is the day's summed per-entry [digestionKcal]; without it
/// [eatenKcal] is priced as food of unknown composition ([kDigestUnknown]).
/// [runSteps] are the steps taken during the day's runs. They are taken off
/// [steps] before the step formula, because those metres are already in
/// [runKcal]; walks are never in [runKcal], so their steps stay in [steps].
/// With nothing logged the food part is 0. Null without a BMR.
({double bmr, double steps, double run, double food, double total})?
maintenance(
  Profile p, {
  num? steps,
  double eatenKcal = 0,
  double? digestionKcal,
  double runKcal = 0,
  num runSteps = 0,
}) {
  final bmr = bmrMifflin(p);
  if (bmr == null ||
      !eatenKcal.isFinite ||
      !runKcal.isFinite ||
      !runSteps.isFinite ||
      (digestionKcal != null && !digestionKcal.isFinite) ||
      (steps != null && !steps.isFinite)) {
    return null;
  }
  final walked = steps == null ? null : math.max(0, steps - runSteps);
  final st = stepCalories(walked, p.weightKg) ?? 0;
  final run = math.max(0.0, runKcal);
  final tef =
      digestionKcal ?? (eatenKcal > 0 ? eatenKcal * kDigestUnknown : 0.0);
  return (
    bmr: bmr,
    steps: st,
    run: run,
    food: tef,
    total: bmr + st + run + tef,
  );
}

/// Distance and active calories for [steps], for the steps breakdown. The
/// distance is a height-based step length (0.415 × height for men, 0.413 for women,
/// their mean otherwise); the calories are [stepCalories]. Null without a
/// weight or steps; missing height only withholds distance.
({double kcal, double? km})? walkingEnergy(num? steps, Profile p) {
  final h = p.heightCm, w = p.weightKg;
  if (steps == null ||
      !steps.isFinite ||
      steps <= 0 ||
      w == null ||
      !w.isFinite ||
      w <= 0) {
    return null;
  }
  final factor = switch (p.sex) {
    'm' || 'male' => 0.415,
    'f' || 'female' => 0.413,
    _ => 0.414,
  };
  final km = h == null || !h.isFinite || h <= 0
      ? null
      : steps * factor * h / 100 / 1000;
  return (kcal: stepCalories(steps, w)!, km: km);
}

/// ACSM net movement estimate, approximately 5 kcal per litre of oxygen.
/// Resting VO2 is excluded here; daily BMR must not be subtracted again.
double? acsmActiveKcal({
  required double runMeters,
  double walkMeters = 0,
  double runClimbMeters = 0,
  double walkClimbMeters = 0,
  double? weightKg,
}) {
  final inputs = [runMeters, walkMeters, runClimbMeters, walkClimbMeters];
  if (weightKg == null ||
      !weightKg.isFinite ||
      weightKg <= 0 ||
      inputs.any((v) => !v.isFinite || v < 0))
    return null;
  return .005 *
      weightKg *
      (.2 * runMeters +
          .1 * walkMeters +
          .9 * runClimbMeters +
          1.8 * walkClimbMeters);
}
