// This week on one card: the calorie deficit at the maintenance floor, average
// protein against the target, km run, the run-or-walk streak, and average
// sleep. On Mondays (build 81), when "this week" is a single unfinished day,
// it shows LAST week instead, against the week before: recovery, sleep,
// strain and steps averages with their change, the deficit, km and weight.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../compute/profile.dart' show Profile;
import '../../compute/streak.dart';
import '../../data/db.dart';
import '../../data/day_label.dart';
import '../../data/local_repository.dart';
import '../../data/nutrition_store.dart';
import '../../gps/run_history.dart';
import '../../state/app_state.dart';
import '../ui2.dart';
import 'home_screen.dart' show hm, pointsOf, repoOf, thousands;
import 'nutrition_screen.dart' show DayUpkeep;

/// Everything the card shows; any part can be missing.
class WeekNumbers {
  const WeekNumbers({
    this.deficit,
    this.acsmDeficit,
    this.daysLogged = 0,
    this.daysExcluded = 0,
    this.proteinDays = 0,
    this.avgProtein,
    this.proteinTarget,
    this.km = 0,
    this.streak,
    this.avgSleepMin,
    this.avgRecovery,
    this.avgStrain,
    this.avgSteps,
    this.weightChangeKg,
  });

  /// Maintenance − eaten summed over the days with food logged; negative is a
  /// surplus.
  final double? deficit, acsmDeficit;
  final int daysLogged, daysExcluded, proteinDays;
  final double? avgProtein, proteinTarget;
  final double km;
  final int? streak;
  final double? avgSleepMin;

  /// Daily averages over the week's measured days, and the change from the
  /// first to the last weigh-in of the week (null under two weigh-ins).
  final double? avgRecovery, avgStrain, avgSteps, weightChangeKg;

  /// [weeksBack] 0 is Monday to today, 1 last week (Monday to Sunday), 2 the
  /// week before. [withFood] false skips the per-day maintenance reads, for a
  /// comparison week that only needs its averages.
  static Future<WeekNumbers> load(
    LocalRepository repo,
    Profile pr,
    Map<String, dynamic> user, {
    DateTime? at,
    int weeksBack = 0,
    bool withFood = true,
  }) async {
    final now = at ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = DateTime(
      today.year,
      today.month,
      today.day - (today.weekday - 1) - 7 * weeksBack,
    );
    final last = weeksBack == 0
        ? today
        : DateTime(monday.year, monday.month, monday.day + 6);
    final mondayLabel = dayLabelOf(monday);
    final lastLabel = dayLabelOf(last);
    bool inWeek(String d) =>
        d.compareTo(mondayLabel) >= 0 && d.compareTo(lastLabel) <= 0;
    final db = await LocalDb.instance;
    // Read up to TODAY, then keep the week: `window` judges "today" (still in
    // progress) by its end date, so ending it on a past Sunday would wrongly
    // drop that Sunday as unfinished.
    final win = await NutritionDb.window(
      db,
      days: today.difference(monday).inDays + 1,
      now: now,
    );

    final runs = await loadRuns(repo);

    double? deficit, acsmDeficit;
    var logged = 0, acsmLogged = 0;
    final proteins = <double>[];
    for (final d in win.days) {
      if (!withFood || !inWeek(d.date)) continue;
      final eaten = d.kcal.value;
      if (!d.countsTowardAverages || eaten == null) continue;
      // Protein has its own denominator: a complete protein total counts
      // whether or not that day's maintenance is known, and a partial floor
      // never passes as a complete day (B86-11).
      if (d.protein.complete) proteins.add(d.protein.value!);
      final upkeep = await DayUpkeep.read(
        repo,
        d.date,
        pr,
        eaten: eaten,
        runs: runs,
      );
      final m = upkeep.parts?.total;
      if (m == null) continue;
      deficit = (deficit ?? 0) + m - eaten;
      final a = upkeep.acsmParts?.total;
      if (a != null) {
        acsmDeficit = (acsmDeficit ?? 0) + a - eaten;
        acsmLogged++;
      }
      logged++;
    }

    var km = 0.0;
    for (
      var d = monday;
      !d.isAfter(last);
      d = DateTime(d.year, d.month, d.day + 1)
    ) {
      km += (await DayUpkeep.read(
        repo,
        dayLabelOf(d),
        pr,
        eaten: 0,
        runs: runs,
      )).runs.km;
    }

    Future<double?> avg(String chart) async {
      try {
        final vs = [
          for (final p in pointsOf(await repo.getChart(chart)))
            if (inWeek(
              dayLabelOf(DateTime.fromMillisecondsSinceEpoch(p.t * 1000)),
            ))
              p.v,
        ];
        return vs.isEmpty ? null : vs.reduce((a, b) => a + b) / vs.length;
      } catch (_) {
        return null;
      }
    }

    final sleep = await avg('sleep');
    double? weightChange;
    final weights = [
      for (final w in await BodyWeight.since(db, mondayLabel))
        if (inWeek(w.date)) w,
    ];
    if (weights.length >= 2) {
      weightChange = weights.last.kg - weights.first.kg;
    }

    return WeekNumbers(
      deficit: deficit,
      acsmDeficit: logged > 0 && acsmLogged == logged ? acsmDeficit : null,
      daysLogged: logged,
      // Only the displayed week's exclusions, not the whole read window's.
      daysExcluded: withFood
          ? win.days
                .where(
                  (d) => inWeek(d.date) && d.logged && !d.countsTowardAverages,
                )
                .length
          : 0,
      proteinDays: proteins.length,
      avgProtein: proteins.isEmpty
          ? null
          : proteins.reduce((a, b) => a + b) / proteins.length,
      proteinTarget: (user['protein_target'] as num?)?.toDouble(),
      km: km,
      streak: weeksBack == 0 ? (await loadMoveStreak())?.current : null,
      avgSleepMin: sleep,
      avgRecovery: await avg('recovery'),
      avgStrain: await avg('strain'),
      avgSteps: await avg('steps'),
      weightChangeKg: weightChange,
    );
  }
}

class WeekCard extends StatefulWidget {
  const WeekCard({super.key, this.data});
  @visibleForTesting
  static int debugLoads = 0;

  /// Preloaded for tests; null reads the app.
  final WeekNumbers? data;

  @override
  State<WeekCard> createState() => _WeekCardState();
}

class _WeekCardState extends State<WeekCard> with RevisionReload {
  WeekNumbers? _w;

  /// On Mondays, the week before the one [_w] shows — for the changes.
  WeekNumbers? _before;
  bool _failed = false;

  /// Monday shows last week: this week is one unfinished day.
  static bool get _monday => DateTime.now().weekday == DateTime.monday;

  @override
  bool get revisionReloads => widget.data == null;

  @override
  void reload() => _load();

  @override
  void initState() {
    super.initState();
    _w = widget.data;
    if (_w == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  Future<void> _load() async {
    final t = beginRead(#week);
    final repo = repoOf(context);
    if (repo == null) return;
    Map<String, dynamic> user;
    try {
      user = context.read<AppState>().user ?? const {};
    } catch (_) {
      return;
    }
    try {
      final pr = Profile.fromMap(user);
      final w = await WeekNumbers.load(
        repo,
        pr,
        user,
        weeksBack: _monday ? 1 : 0,
      );
      final before = _monday
          ? await WeekNumbers.load(repo, pr, user, weeksBack: 2, withFood: false)
          : null;
      if (stillNewest(#week, t)) {
        setState(() {
          _w = w;
          _before = before;
          _failed = false;
        });
        WeekCard.debugLoads++;
      }
    } catch (_) {
      if (stillNewest(#week, t)) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext c) {
    final w = _w;
    if (_failed) {
      return StatusCard(
        'Week summary unavailable',
        'Your saved data is intact. Try reading it again.',
        fix: 'Retry',
        onFix: _load,
      );
    }
    if (w == null) return const SizedBox.shrink();
    final p = P.of(c);
    final d = w.deficit;
    final top = <(String, String, Color)>[
      if (d != null)
        (
          d >= 0 ? 'BUDGET DEFICIT' : 'BUDGET SURPLUS',
          '${thousands(d.abs())} kcal',
          d >= 0 ? C.green : C.red,
        ),
      if (d != null)
        (
          w.acsmDeficit == null
              ? 'ACSM ESTIMATE'
              : w.acsmDeficit! >= 0
              ? 'ACSM DEFICIT'
              : 'ACSM SURPLUS',
          w.acsmDeficit == null
              ? 'Unavailable'
              : '${thousands(w.acsmDeficit!.abs())} kcal',
          C.teal,
        ),
      if (w.avgProtein != null)
        (
          'LOGGED PROTEIN',
          w.proteinTarget == null
              ? '${w.avgProtein!.round()} g'
              : '${w.avgProtein!.round()}/${w.proteinTarget!.round()} g',
          C.red,
        ),
    ];
    final b = _before;
    final lastWeek = b != null;
    final weight = w.weightChangeKg;
    final bottom = <(String, String, Color)>[
      ('RUN', '${w.km.toStringAsFixed(1)} km', C.run),
      if (w.streak != null) ('STREAK', '${w.streak} d', C.steps),
      if (w.avgSleepMin != null && !lastWeek)
        ('SLEEP', hm(w.avgSleepMin), C.sleep),
      if (lastWeek && weight != null)
        (
          'WEIGHT',
          '${weight >= 0 ? '+' : '\u2212'}${weight.abs().toStringAsFixed(1)} kg',
          C.domFood,
        ),
    ];
    final body = <(String, String, Color)>[
      if (b != null) ...[
        if (w.avgRecovery != null)
          (
            'RECOVERY',
            weekChange(w.avgRecovery!, b.avgRecovery, (v) => '${v.round()}'),
            C.green,
          ),
        if (w.avgSleepMin != null)
          ('SLEEP', weekChange(w.avgSleepMin!, b.avgSleepMin, hm), C.sleep),
        if (w.avgStrain != null)
          (
            'STRAIN',
            weekChange(w.avgStrain!, b.avgStrain, (v) => v.toStringAsFixed(1)),
            C.blue,
          ),
        if (w.avgSteps != null)
          ('STEPS', weekChange(w.avgSteps!, b.avgSteps, thousands), C.steps),
      ],
    ];
    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            lastWeek ? 'Last week \u00b7 change from the week before' : 'This week',
            style: F.over.copyWith(color: p.ink3),
          ),
          const SizedBox(height: S.x2),
          if (body.isNotEmpty) ...[
            InlineMetrics(body.take(2).toList()),
            if (body.length > 2) ...[
              const SizedBox(height: S.x3),
              InlineMetrics(body.skip(2).toList()),
            ],
            const SizedBox(height: S.x3),
          ],
          if (top.isNotEmpty) ...[
            InlineMetrics(top),
            const SizedBox(height: S.x3),
          ],
          InlineMetrics(bottom),
          if (d != null) ...[
            const SizedBox(height: S.x2),
            Text(
              '${w.daysLogged} completed day${w.daysLogged == 1 ? '' : 's'} · '
              'maintenance estimate${w.daysExcluded > 0 ? ' · ${w.daysExcluded} unfinished excluded' : ''}'
              '${w.avgProtein != null ? ' · protein on ${w.proteinDays} days' : ''}',
              style: F.over.copyWith(color: p.ink3),
            ),
          ],
          if (d == null && w.daysExcluded > 0) ...[
            const SizedBox(height: S.x2),
            Text(
              'Food summary awaits a completed day. Today and incomplete logs are excluded.',
              style: F.over.copyWith(color: p.ink3),
            ),
          ],
        ],
      ),
    );
  }
}

/// "64 · +5": a week's average with its change from the week before, the
/// change formatted the same way. Just the value with nothing to compare.
String weekChange(double v, double? before, String Function(double) fmt) {
  if (before == null) return fmt(v);
  final d = v - before;
  return '${fmt(v)} · ${d >= 0 ? '+' : '−'}${fmt(d.abs())}';
}
