// Build 89 (Akshat, item 6): one Markdown file of diet, weight, body, lifting,
// activity and recovery data, made on demand for pasting into an AI chat
// (Claude, Codex) to analyse outside the app. Nothing is stored: the file is
// written to a temporary folder for the share sheet.
//
// Shape (Akshat's choice): a header that explains every column, one row per
// day, weekly averages, lift sessions and tape measurements, and the
// individual food items only for ranges up to three months — they are most of
// the size and add little beyond that.

import 'dart:io';

import '../compute/profile.dart';
import 'body_log.dart';
import 'day_label.dart';
import 'db.dart';
import 'goal_plan.dart';
import 'lift_log.dart';
import 'local_repository.dart';
import 'nutrition_store.dart';

enum AnalysisRange {
  twoWeeks('2 weeks', 14),
  month('1 month', 30),
  threeMonths('3 months', 91),
  sixMonths('6 months', 182),
  lifetime('Lifetime', null);

  const AnalysisRange(this.label, this.days);
  final String label;
  final int? days;

  /// Food items are listed only up to three months (Akshat's choice).
  bool get listsFoods => days != null && days! <= 91;
}

/// One day's row. Every field is null when not measured — never zero.
class AnalysisDay {
  AnalysisDay(this.date);
  final String date;
  double? weightKg, waistIn;
  double? kcal, protein, carbs, fat, fibre;
  bool kcalFloor = false;

  /// Whether the day counts toward food averages; null with no food logged.
  bool? counted;
  double? steps, sleepMin, recovery, hrv, rhr, strain;
  final List<String> workouts = [];

  bool get empty =>
      weightKg == null &&
      waistIn == null &&
      kcal == null &&
      protein == null &&
      steps == null &&
      sleepMin == null &&
      recovery == null &&
      hrv == null &&
      rhr == null &&
      strain == null &&
      workouts.isEmpty;
}

String _n(double? v, [int dp = 0]) => v == null
    ? '—'
    : dp == 0
    ? v.round().toString()
    : v.toStringAsFixed(dp);

double? _mean(Iterable<double?> xs) {
  final v = [for (final x in xs) ?x];
  return v.isEmpty ? null : v.reduce((a, b) => a + b) / v.length;
}

String _hm(double? min) {
  if (min == null) return '—';
  final m = min.round();
  return '${m ~/ 60}h ${(m % 60).toString().padLeft(2, '0')}m';
}

/// Epley estimate, labelled as an estimate wherever it is printed.
double _e1rm(double load, int reps) => reps <= 1 ? load : load * (1 + reps / 30);

/// The file's text. Pure, so it is tested without a device.
String buildAnalysisMarkdown({
  required AnalysisRange range,
  required String from,
  required String today,
  required Profile profile,
  required Map<String, dynamic> targets,
  required String? goal,
  required List<AnalysisDay> days,
  required List<LiftWorkout> lifts,
  required List<BodyMeasure> measures,
  Map<String, List<FoodEntry>> foods = const {},
}) {
  final b = StringBuffer();
  String? t(String k) {
    final v = targets[k];
    return v is num ? v.round().toString() : null;
  }

  b.writeln('# WHOOP app data export — ${range.label}');
  b.writeln();
  b.writeln('Period: $from to $today. Made on $today by the WHOOP app on my '
      'iPhone (local data, WHOOP 4.0 band plus phone steps and my own food, '
      'weight and lifting logs).');
  b.writeln();
  b.writeln('## About me');
  b.writeln();
  b.writeln([
    if (profile.ageYears != null) '- Age: ${profile.ageYears}',
    if (profile.sex != null) '- Sex: ${profile.sex == 'f' ? 'female' : 'male'}',
    if (profile.heightCm != null)
      '- Height: ${profile.heightCm!.toStringAsFixed(0)} cm',
    if (goal != null) '- Goal: $goal',
    '- Daily targets: calories ${t('kcal_target') ?? '—'} kcal, protein '
        '${t('protein_target') ?? '—'} g, carbs ${t('carbs_target') ?? '—'} g, '
        'fat ${t('fat_target') ?? '—'} g, fibre ${t('fibre_target') ?? '—'} g',
  ].join('\n'));
  b.writeln();
  b.writeln('## How to read this');
  b.writeln();
  b.writeln('- "—" means not measured or not logged. It is never zero.');
  b.writeln('- Weight is the last weigh-in of the day (kg). Waist is at the '
      'navel (inches), on measurement days only.');
  b.writeln('- Food is what I logged. "≥" means at least one item had no '
      'calories, so the total is a floor. "Counted" days are the ones the app '
      'trusts as complete (marked complete, or at least half the calorie goal '
      'with calories on every item); averages use counted days only.');
  b.writeln('- Sleep is time asleep. Recovery is 0–100. HRV is the nightly '
      'RMSSD in ms and resting HR is overnight, both from a wrist band (pulse '
      'timing, not ECG). Strain is the app\'s 0–21 estimate from heart rate. '
      'Steps are from the phone only.');
  b.writeln('- Estimated 1RM uses the Epley formula and is only an estimate.');
  b.writeln();
  b.writeln('Suggested prompt: "Here is my fitness, diet and recovery data. '
      'Look at the trends in weight, waist, calories, protein, training and '
      'recovery against my goal, tell me what is working, what is not, and '
      'what to change in the next two weeks. Say when the data is too thin to '
      'conclude anything."');
  b.writeln();

  final shown = [for (final d in days) if (!d.empty) d];
  b.writeln('## Daily');
  b.writeln();
  if (shown.isEmpty) {
    b.writeln('No recorded days in this period.');
  } else {
    b.writeln('| Date | Weight kg | Waist in | kcal | Protein g | Carbs g | '
        'Fat g | Fibre g | Counted | Steps | Sleep | Recovery | HRV ms | '
        'Resting HR | Strain | Workouts |');
    b.writeln('|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|');
    for (final d in shown) {
      b.writeln('| ${d.date} | ${_n(d.weightKg, 1)} | ${_n(d.waistIn, 1)} | '
          '${d.kcal == null ? '—' : '${d.kcalFloor ? '≥' : ''}${_n(d.kcal)}'} | '
          '${_n(d.protein)} | ${_n(d.carbs)} | ${_n(d.fat)} | ${_n(d.fibre)} | '
          '${d.counted == null ? '—' : d.counted! ? 'yes' : 'no'} | '
          '${_n(d.steps)} | ${_hm(d.sleepMin)} | ${_n(d.recovery)} | '
          '${_n(d.hrv)} | ${_n(d.rhr)} | ${_n(d.strain, 1)} | '
          '${d.workouts.isEmpty ? '—' : d.workouts.join('; ')} |');
    }
  }
  b.writeln();

  // Monday weeks, oldest first.
  final weeks = <String, List<AnalysisDay>>{};
  for (final d in shown) {
    final day = DateTime.parse(d.date);
    final mon = dayLabelOf(DateTime(day.year, day.month, day.day - (day.weekday - 1)));
    (weeks[mon] ??= []).add(d);
  }
  if (weeks.length > 1) {
    b.writeln('## Weekly averages (Monday weeks)');
    b.writeln();
    b.writeln('| Week of | Weight kg | kcal (counted days) | Protein g | '
        'Counted days | Steps | Sleep | Recovery | HRV ms | Resting HR | '
        'Strain | Workouts |');
    b.writeln('|---|---|---|---|---|---|---|---|---|---|---|---|');
    for (final e in weeks.entries) {
      final w = e.value;
      final counted = [for (final d in w) if (d.counted == true) d];
      b.writeln('| ${e.key} | ${_n(_mean(w.map((d) => d.weightKg)), 1)} | '
          '${_n(_mean(counted.map((d) => d.kcal)))} | '
          '${_n(_mean(counted.map((d) => d.protein)))} | ${counted.length} | '
          '${_n(_mean(w.map((d) => d.steps)))} | '
          '${_hm(_mean(w.map((d) => d.sleepMin)))} | '
          '${_n(_mean(w.map((d) => d.recovery)))} | '
          '${_n(_mean(w.map((d) => d.hrv)))} | '
          '${_n(_mean(w.map((d) => d.rhr)))} | '
          '${_n(_mean(w.map((d) => d.strain)), 1)} | '
          '${w.fold<int>(0, (a, d) => a + d.workouts.length)} |');
    }
    b.writeln();
  }

  b.writeln('## Lifting');
  b.writeln();
  if (lifts.isEmpty) {
    b.writeln('No lifting sessions logged in this period.');
  } else {
    for (final w in lifts) {
      b.writeln('### ${dayLabelOf(w.startedAt)}${w.splitName == null ? '' : ' — ${w.splitName}'}');
      for (final ex in w.exercises) {
        if (ex.sets.isEmpty) continue;
        final top = ex.sets.reduce(
          (a, s) => _e1rm(s.load, s.reps) > _e1rm(a.load, a.reps) ? s : a,
        );
        b.writeln('- ${ex.name}: ${[for (final s in ex.sets) ex.setText(s)].join(', ')} '
            '(best set ${ex.setText(top)}, estimated 1RM '
            '${_e1rm(top.load, top.reps).toStringAsFixed(1)} ${ex.loadMode.shortUnit})');
      }
      b.writeln();
    }
  }

  b.writeln('## Tape measurements (inches)');
  b.writeln();
  if (measures.isEmpty) {
    b.writeln('No tape measurements in this period.');
  } else {
    for (final m in measures) {
      final parts = [
        for (final s in BodySite.values)
          if (m.inches[s.name] case final v?) '${s.title} ${v.toStringAsFixed(1)}',
      ];
      b.writeln('- ${m.date}: ${parts.join(', ')}');
    }
  }
  b.writeln();

  if (foods.isNotEmpty) {
    b.writeln('## Food log');
    b.writeln();
    for (final date in foods.keys.toList()..sort()) {
      final items = foods[date]!;
      if (items.isEmpty) continue;
      b.writeln('### $date');
      for (final e in items) {
        b.writeln('- ${e.meal}: ${e.label} — ${_n(e.kcal)} kcal, P ${_n(e.proteinG)} '
            'C ${_n(e.carbsG)} F ${_n(e.fatG)} Fb ${_n(e.fibreG)}');
      }
      b.writeln();
    }
  }
  return b.toString();
}

/// Read the period from the local stores and write the file. Returns its path.
Future<String> writeAnalysisExport({
  required AnalysisRange range,
  required LocalRepository repo,
  required Map<String, dynamic> user,
}) async {
  final today = todayLabel();
  final db = await LocalDb.instance;
  final weights = await BodyLogDb.weights();
  final measures = await BodyLogDb.measures();
  final lifts = await LiftLogDb.finished();

  Future<Map<String, double>> chart(String key) async {
    final out = <String, double>{};
    final pts = (await repo.getChart(key))['points'];
    if (pts is List) {
      for (final e in pts) {
        if (e is Map && e['v'] is num && e['t'] is num) {
          out[dayLabelOf(DateTime.fromMillisecondsSinceEpoch(
            (e['t'] as num).round() * 1000,
          ))] = (e['v'] as num).toDouble();
        }
      }
    }
    return out;
  }

  final series = {
    for (final k in const ['steps', 'sleep', 'recovery', 'hrv', 'resting_hr', 'strain'])
      k: await chart(k),
  };
  final foodsAll = await NutritionDb.entriesSince(db, '0000-00-00');

  // Lifetime starts at the earliest record of any kind.
  final from = range.days == null
      ? [
          ...weights.map((w) => w.date),
          ...measures.map((m) => m.date),
          ...lifts.map((l) => dayLabelOf(l.startedAt)),
          ...foodsAll.keys,
          for (final s in series.values) ...s.keys,
        ].fold<String>(today, (a, d) => d.compareTo(a) < 0 ? d : a)
      : shiftLabel(today, -(range.days! - 1));
  final marks = await NutritionDb.dayMarks(db, from);
  final sessions = await LocalDb.sessionsInRange(
    DateTime.parse(from).millisecondsSinceEpoch ~/ 1000,
    DateTime.now().millisecondsSinceEpoch ~/ 1000,
  );

  final days = <AnalysisDay>[];
  for (var d = from; d.compareTo(today) <= 0; d = shiftLabel(d, 1)) {
    final row = AnalysisDay(d);
    final w = [for (final x in weights) if (x.date == d && !x.historyOnly) x];
    if (w.isNotEmpty) {
      w.sort((a, b) => a.atTs.compareTo(b.atTs));
      row.weightKg = w.last.kg;
    }
    for (final m in measures) {
      if (m.date == d && m.inches[BodySite.waistNavel.name] != null) {
        row.waistIn = m.inches[BodySite.waistNavel.name];
      }
    }
    final es = foodsAll[d] ?? const <FoodEntry>[];
    if (es.isNotEmpty) {
      final r = rollupDay(d, es, today: today, mark: marks[d]);
      row
        ..kcal = r.kcal.value
        ..kcalFloor = r.kcal.isFloor
        ..protein = r.protein.value
        ..carbs = r.carbs.value
        ..fat = r.fat.value
        ..fibre = r.fibre.value
        ..counted = r.countsTowardAverages;
    }
    row
      ..steps = series['steps']![d]
      ..sleepMin = series['sleep']![d]
      ..recovery = series['recovery']![d]
      ..hrv = series['hrv']![d]
      ..rhr = series['resting_hr']![d]
      ..strain = series['strain']![d];
    for (final s in sessions) {
      final st = (s['start_ts'] as num?)?.toInt();
      if (st == null || s['status'] == 'live') continue;
      if (dayLabelOf(DateTime.fromMillisecondsSinceEpoch(st * 1000)) != d) continue;
      final en = (s['end_ts'] as num?)?.toInt();
      final min = en == null ? null : ((en - st) / 60).round();
      final strain = (s['strain'] as num?)?.toDouble();
      row.workouts.add([
        (s['type'] as String?) ?? 'workout',
        if (min != null) '$min min',
        if (strain != null) 'strain ${strain.toStringAsFixed(1)}',
      ].join(' '));
    }
    days.add(row);
  }

  final goal = await GoalPlan.read();
  final text = buildAnalysisMarkdown(
    range: range,
    from: from,
    today: today,
    profile: Profile.fromMap(user),
    targets: user,
    goal: goal.phase.title,
    days: days,
    lifts: [
      for (final l in lifts)
        if (dayLabelOf(l.startedAt).compareTo(from) >= 0) l,
    ],
    measures: [for (final m in measures) if (m.date.compareTo(from) >= 0) m],
    foods: range.listsFoods
        ? {
            for (final e in foodsAll.entries)
              if (e.key.compareTo(from) >= 0) e.key: e.value,
          }
        : const {},
  );
  final dir = await Directory.systemTemp.createTemp('whoop_analysis');
  final file = File(
    '${dir.path}/whoop_analysis_${range.name}_$today.md',
  )..writeAsStringSync(text);
  return file.path;
}

String shiftLabel(String day, int by) {
  final d = DateTime.parse(day);
  return dayLabelOf(DateTime(d.year, d.month, d.day + by));
}
