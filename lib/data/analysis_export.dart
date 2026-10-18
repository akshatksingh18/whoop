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
import 'dart:isolate';

import '../compute/profile.dart';
import 'body_log.dart';
import 'day_label.dart';
import 'db.dart';
import 'goal_plan.dart';
import 'lift_log.dart';
import 'lift_progress.dart' show bestSet, setScore;
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
  final Map<String, NutrientTotal> nutrients = {};
  String? countingBasis;
  double? countingGoal;

  /// Whether the day counts toward food averages; null with no food logged.
  bool? counted;
  double? steps, sleepMin, recovery, hrv, rhr, strain;
  final List<String> workouts = [];

  bool get empty =>
      weightKg == null &&
      waistIn == null &&
      kcal == null &&
      protein == null &&
      carbs == null &&
      fat == null &&
      fibre == null &&
      counted == null &&
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

double? _nutrientValue(AnalysisDay d, String key) => switch (key) {
  'kcal' => d.kcal,
  'protein' => d.protein,
  'carbs' => d.carbs,
  'fat' => d.fat,
  'fibre' => d.fibre,
  _ => null,
};
String _foodCell(AnalysisDay d, String key) {
  final n = d.nutrients[key];
  final floor = n?.isFloor ?? (key == 'kcal' && d.kcalFloor);
  return '${floor ? '≥' : ''}${_n(_nutrientValue(d, key))}'
      '${n == null ? '' : ' (${n.known}/${n.known + n.unknown} items)'}';
}

String _foodMean(List<AnalysisDay> days, String key) {
  final counted = days.where((d) => d.counted == true).toList();
  final complete = counted
      .where(
        (d) => d.nutrients[key]?.complete ?? (_nutrientValue(d, key) != null),
      )
      .toList();
  return '${_n(_mean(complete.map((d) => _nutrientValue(d, key))))} '
      '(${complete.length}/${counted.length} days)';
}

String _cell(String value) =>
    value.replaceAll('|', r'\|').replaceAll(RegExp(r'[\r\n]+'), ' ');

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
  List<Map<String, Object?>> weightReadings = const [],
}) {
  final b = StringBuffer();
  String? t(String k) {
    final v = targets[k];
    return v is num ? v.round().toString() : null;
  }

  b.writeln('# WHOOP app data export — ${range.label}');
  b.writeln();
  b.writeln(
    'Period: $from to $today. Made on $today by the WHOOP app on my '
    'iPhone (local data, WHOOP 4.0 band plus phone steps and my own food, '
    'weight and lifting logs).',
  );
  b.writeln();
  b.writeln('## About me');
  b.writeln();
  b.writeln(
    [
      if (profile.ageYears != null) '- Age: ${profile.ageYears}',
      if (profile.sex != null)
        '- Sex: ${profile.sex == 'f' ? 'female' : 'male'}',
      if (profile.heightCm != null)
        '- Height: ${profile.heightCm!.toStringAsFixed(0)} cm',
      if (goal != null) '- Goal: $goal',
      '- Daily targets: calories ${t('kcal_target') ?? '—'} kcal, protein '
          '${t('protein_target') ?? '—'} g, carbs ${t('carbs_target') ?? '—'} g, '
          'fat ${t('fat_target') ?? '—'} g, fibre ${t('fibre_target') ?? '—'} g',
    ].join('\n'),
  );
  b.writeln();
  b.writeln('## How to read this');
  b.writeln();
  b.writeln('- "—" means not measured or not logged. It is never zero.');
  b.writeln(
    '- Weight is the first weigh-in of the day (kg). Waist is at the '
    'navel (inches), on measurement days only.',
  );
  b.writeln(
    '- Food is what I logged. "≥" means at least one item had no '
    'calories, so the total is a floor. "Counted" days are the ones the app '
    'counts for averages (marked complete, or at least half its frozen calorie goal '
    'with calories on every item); averages use counted days only.',
  );
  b.writeln(
    '- Sleep is time asleep. Recovery is 0–100. HRV is the nightly '
    'RMSSD in ms and resting HR is overnight, both from a wrist band (pulse '
    'timing, not ECG). Strain is the app\'s 0–21 estimate from heart rate. '
    'Steps are from the phone only.',
  );
  b.writeln(
    '- Nutrients keep their own coverage: ≥ is a partial total; (n/N items) '
    'names known entries. Weekly nutrient means use only counted days with complete '
    'coverage for that nutrient; (n/N days) names that denominator. Automatic '
    'counting does not mean every meal was recorded.',
  );
  b.writeln(
    '- Lift best sets use the app’s shared bestSet/setScore rules. Estimated '
    'one-rep load applies only to loaded sets of 1–12 reps and to that setup, '
    'not a true 1RM; other sets compare reps at load. Equipment/load meanings '
    'are kept separate.',
  );
  b.writeln();
  b.writeln(
    'Suggested prompt: "Here is my fitness, diet and recovery data. '
    'Look at the trends in weight, waist, calories, protein, training and '
    'recovery against my goal, tell me what is working, what is not, and '
    'what to change in the next two weeks. Say when the data is too thin to '
    'conclude anything."',
  );
  b.writeln();

  final shown = [
    for (final d in days)
      if (!d.empty) d,
  ];
  b.writeln('## Daily');
  b.writeln();
  if (shown.isEmpty) {
    b.writeln('No recorded days in this period.');
  } else {
    b.writeln(
      '| Date | Weight kg | Waist in | kcal | Protein g | Carbs g | '
      'Fat g | Fibre g | Counting provenance | Steps | Sleep | Recovery | HRV ms | '
      'Resting HR | Strain | Workouts |',
    );
    b.writeln(
      '|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|',
    );
    for (final d in shown) {
      b.writeln(
        '| ${d.date} | ${_n(d.weightKg, 1)} | ${_n(d.waistIn, 1)} | '
        '${_foodCell(d, 'kcal')} | ${_foodCell(d, 'protein')} | '
        '${_foodCell(d, 'carbs')} | ${_foodCell(d, 'fat')} | ${_foodCell(d, 'fibre')} | '
        '${d.counted == null
            ? '—'
            : d.counted!
            ? (d.countingBasis == 'marked_complete'
                  ? 'Marked complete'
                  : d.countingBasis == 'automatic'
                  ? 'Counted automatically'
                  : 'Counted (basis unavailable)')
            : 'Not counted'}'
        '${d.countingGoal == null ? '' : ' (goal ${_n(d.countingGoal)} kcal)'} | '
        '${_n(d.steps)} | ${_hm(d.sleepMin)} | ${_n(d.recovery)} | '
        '${_n(d.hrv)} | ${_n(d.rhr)} | ${_n(d.strain, 1)} | '
        '${d.workouts.isEmpty ? '—' : _cell(d.workouts.join('; '))} |',
      );
    }
  }
  b.writeln();

  // Monday weeks, oldest first.
  final weeks = <String, List<AnalysisDay>>{};
  for (final d in shown) {
    final day = DateTime.parse(d.date);
    final mon = dayLabelOf(
      DateTime(day.year, day.month, day.day - (day.weekday - 1)),
    );
    (weeks[mon] ??= []).add(d);
  }
  if (weeks.length > 1) {
    b.writeln('## Weekly averages (Monday weeks)');
    b.writeln();
    b.writeln(
      '| Week of | Weight kg | kcal (counted days) | Protein g | '
      'Carbs g | Fat g | Fibre g | Counted days | Steps | Sleep | Recovery | HRV ms | Resting HR | '
      'Strain | Workouts |',
    );
    b.writeln('|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|');
    for (final e in weeks.entries) {
      final w = e.value;
      final counted = [
        for (final d in w)
          if (d.counted == true) d,
      ];
      b.writeln(
        '| ${e.key} | ${_n(_mean(w.map((d) => d.weightKg)), 1)} | '
        '${_foodMean(w, 'kcal')} | ${_foodMean(w, 'protein')} | '
        '${_foodMean(w, 'carbs')} | ${_foodMean(w, 'fat')} | ${_foodMean(w, 'fibre')} | ${counted.length} | '
        '${_n(_mean(w.map((d) => d.steps)))} | '
        '${_hm(_mean(w.map((d) => d.sleepMin)))} | '
        '${_n(_mean(w.map((d) => d.recovery)))} | '
        '${_n(_mean(w.map((d) => d.hrv)))} | '
        '${_n(_mean(w.map((d) => d.rhr)))} | '
        '${_n(_mean(w.map((d) => d.strain)), 1)} | '
        '${w.fold<int>(0, (a, d) => a + d.workouts.length)} |',
      );
    }
    b.writeln();
  }

  b.writeln('## Lifting');
  b.writeln();
  if (lifts.isEmpty) {
    b.writeln('No lifting sessions logged in this period.');
  } else {
    for (final w in lifts) {
      b.writeln(
        '### ${dayLabelOf(w.startedAt)}${w.splitName == null ? '' : ' — ${w.splitName}'}',
      );
      for (final ex in w.exercises) {
        if (ex.sets.isEmpty) continue;
        final top = bestSet(ex.sets);
        final score = setScore(top);
        b.writeln(
          '- ${_cell(ex.name)}: ${[for (final s in ex.sets) ex.setText(s)].join(', ')} '
          '(best set ${ex.setText(top)}; ${ex.loadMode.title}; '
          '${_cell(ex.equipmentNote.isEmpty ? 'equipment not specified' : ex.equipmentNote)}; '
          '${score == null ? 'comparison: reps at load' : 'estimated one-rep load ${score.toStringAsFixed(1)} ${ex.loadMode.shortUnit} on this setup'})',
        );
        b.writeln('  ${ex.loadMode.guidance}');
      }
      b.writeln();
    }
  }

  b.writeln('## Weigh-in readings and provenance');
  b.writeln();
  if (weightReadings.isEmpty) {
    b.writeln('No individual weigh-in readings in this period.');
  } else {
    b.writeln(
      '| Date | Time (epoch seconds) | kg | Source | Calculation eligibility | Entered |',
    );
    b.writeln('|---|---|---|---|---|---|');
    final firstDays = <String>{};
    for (final r in weightReadings) {
      final firstOfDay = firstDays.add(r['date'] as String);
      final at = (r['at_ts'] as num?)?.toInt();
      b.writeln(
        '| ${r['date']} | ${at == null || at <= 0 ? 'unknown' : at} | '
        '${_n((r['kg'] as num?)?.toDouble(), 2)} | ${_cell(r['source']?.toString() ?? 'unknown')} | '
        '${r['history_only'] == 1
            ? 'history only'
            : firstOfDay
            ? 'eligible daily input (first reading)'
            : 'additional reading (history)'} | '
        '${r['entered'] ?? '—'} ${_cell(r['unit']?.toString() ?? 'unknown')} |',
      );
    }
  }
  b.writeln();

  b.writeln('## Tape measurements (inches)');
  b.writeln();
  if (measures.isEmpty) {
    b.writeln('No tape measurements in this period.');
  } else {
    for (final m in measures) {
      final parts = [
        for (final s in BodySite.values)
          if (m.inches[s.name] case final v?)
            '${s.title} ${v.toStringAsFixed(1)}',
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
        b.writeln(
          '- ${e.meal}: ${_cell(e.label)} — ${_n(e.kcal)} kcal, P ${_n(e.proteinG)} '
          'C ${_n(e.carbsG)} F ${_n(e.fatG)} Fb ${_n(e.fibreG)}',
        );
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
  var lifts = await LiftLogDb.finished();

  Future<Map<String, double>> chart(String key) async {
    final out = <String, double>{};
    final pts = (await repo.getChart(key))['points'];
    if (pts is List) {
      for (final e in pts) {
        if (e is Map && e['v'] is num && e['t'] is num) {
          out[dayLabelAtSec((e['t'] as num).round())] = (e['v'] as num)
              .toDouble();
        }
      }
    }
    return out;
  }

  final series = {
    for (final k in const [
      'steps',
      'sleep',
      'recovery',
      'hrv',
      'resting_hr',
      'strain',
    ])
      k: await chart(k),
  };
  final foodsAll = await NutritionDb.entriesSince(db, '0000-00-00');

  // Build 93 (Codex full-flow audit F03/F05): a workout marked private
  // ("Hidden from summaries and exports") is left out of this shareable file,
  // with its Lift Log; and Lifetime starts at the earliest record of any kind,
  // workouts included.
  final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final allSessions = [
    for (final s in await LocalDb.sessionsInRange(0, nowSec))
      if ((s['private'] as num?)?.toInt() != 1) s,
  ];
  final privateIds = {
    for (final s in await LocalDb.sessionsInRange(0, nowSec))
      if ((s['private'] as num?)?.toInt() == 1) s['id'] as String,
  };
  lifts = [
    for (final l in lifts)
      if (l.sessionId == null || !privateIds.contains(l.sessionId)) l,
  ];
  final from = range.days == null
      ? [
          ...weights.map((w) => w.date),
          ...measures.map((m) => m.date),
          ...lifts.map((l) => dayLabelOf(l.startedAt)),
          ...foodsAll.keys,
          for (final s in series.values) ...s.keys,
          for (final s in allSessions)
            if (s['start_ts'] is num)
              dayLabelOf(
                DateTime.fromMillisecondsSinceEpoch(
                  (s['start_ts'] as num).toInt() * 1000,
                ),
              ),
        ].fold<String>(today, (a, d) => d.compareTo(a) < 0 ? d : a)
      : shiftLabel(today, -(range.days! - 1));
  final marks = await NutritionDb.dayMarks(db, from);
  final fromSec = localDayStartSec(from)!;
  final sessions = [
    for (final s in allSessions)
      if (((s['start_ts'] as num?)?.toInt() ?? 0) >= fromSec) s,
  ];

  final days = <AnalysisDay>[];
  for (var d = from; d.compareTo(today) <= 0; d = shiftLabel(d, 1)) {
    final row = AnalysisDay(d);
    final w = [
      for (final x in weights)
        if (x.date == d) x,
    ];
    if (w.isNotEmpty) {
      w.sort((a, b) => a.atTs.compareTo(b.atTs));
      row.weightKg = w.first.kg;
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
        ..counted = r.countsTowardAverages
        ..countingBasis = marks[d] == null ? 'automatic' : 'marked_${marks[d]}'
        ..countingGoal = r.counting?.calorieGoal;
      row.nutrients.addAll({
        'kcal': r.kcal,
        'protein': r.protein,
        'carbs': r.carbs,
        'fat': r.fat,
        'fibre': r.fibre,
      });
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
      if (dayLabelAtSec(st) != d) continue;
      final en = (s['end_ts'] as num?)?.toInt();
      final min = en == null ? null : ((en - st) / 60).round();
      final strain = (s['strain'] as num?)?.toDouble();
      row.workouts.add(
        [
          (s['type'] as String?) ?? 'workout',
          if (min != null) '$min min',
          if (strain != null) 'strain ${strain.toStringAsFixed(1)}',
        ].join(' '),
      );
    }
    days.add(row);
  }

  final goal = await GoalPlan.read();
  final readings = await db.query(
    'body_weight_reading',
    where: 'date >= ? AND date <= ?',
    whereArgs: [from, today],
    orderBy: 'date ASC, at_ts ASC, id ASC',
  );
  final text = await renderAnalysisOffThread(
    range: range,
    from: from,
    today: today,
    profile: Profile.fromMap(user),
    targets: user,
    goal: goal.phase.title,
    days: days,
    weightReadings: readings,
    lifts: [
      for (final l in lifts)
        if (dayLabelOf(l.startedAt).compareTo(from) >= 0) l,
    ],
    measures: [
      for (final m in measures)
        if (m.date.compareTo(from) >= 0) m,
    ],
    foods: range.listsFoods
        ? {
            for (final e in foodsAll.entries)
              if (e.key.compareTo(from) >= 0) e.key: e.value,
          }
        : const {},
  );
  final dir = await Directory.systemTemp.createTemp('whoop_analysis');
  final file = File('${dir.path}/whoop_analysis_${range.name}_$today.md');
  try {
    await file.writeAsString(text);
    return file.path;
  } catch (_) {
    await dir.delete(recursive: true);
    rethrow;
  }
}

/// Isolate boundary contains only serializable export inputs, never a DB/repo.
Future<String> renderAnalysisOffThread({
  required AnalysisRange range,
  required String from,
  required String today,
  required Profile profile,
  required Map<String, dynamic> targets,
  required String? goal,
  required List<AnalysisDay> days,
  required List<LiftWorkout> lifts,
  required List<BodyMeasure> measures,
  required Map<String, List<FoodEntry>> foods,
  required List<Map<String, Object?>> weightReadings,
}) => Isolate.run(
  () => buildAnalysisMarkdown(
    range: range,
    from: from,
    today: today,
    profile: profile,
    targets: targets,
    goal: goal,
    days: days,
    lifts: lifts,
    measures: measures,
    foods: foods,
    weightReadings: weightReadings,
  ),
);

String shiftLabel(String day, int by) {
  final d = DateTime.parse(day);
  return dayLabelOf(DateTime(d.year, d.month, d.day + by));
}
