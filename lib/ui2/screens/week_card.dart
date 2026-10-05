// This week on one card, for Monday mornings and every glance after: the
// calorie deficit at the maintenance floor, average protein against the
// target, km run, the run-or-walk streak, and average sleep.

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
  });

  /// Maintenance − eaten summed over the days with food logged; negative is a
  /// surplus.
  final double? deficit, acsmDeficit;
  final int daysLogged, daysExcluded, proteinDays;
  final double? avgProtein, proteinTarget;
  final double km;
  final int? streak;
  final double? avgSleepMin;

  static Future<WeekNumbers> load(
    LocalRepository repo,
    Profile pr,
    Map<String, dynamic> user, {
    DateTime? at,
  }) async {
    final now = at ?? DateTime.now();
    final monday = DateTime(now.year, now.month, now.day - (now.weekday - 1));
    final mondayLabel = dayLabelOf(monday);
    final db = await LocalDb.instance;
    final win = await NutritionDb.window(db, days: now.weekday, now: now);

    final runs = await loadRuns(repo);

    double? deficit, acsmDeficit;
    var logged = 0, acsmLogged = 0;
    final proteins = <double>[];
    for (final d in win.days) {
      final eaten = d.kcal.value;
      if (!d.countsTowardAverages || eaten == null) continue;
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
      if (d.protein.value != null) proteins.add(d.protein.value!);
    }

    var km = 0.0;
    for (
      var d = monday;
      !d.isAfter(DateTime(now.year, now.month, now.day));
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

    double? sleep;
    try {
      final mins = [
        for (final p in pointsOf(await repo.getChart('sleep')))
          if (dayLabelOf(
                DateTime.fromMillisecondsSinceEpoch(p.t * 1000),
              ).compareTo(mondayLabel) >=
              0)
            p.v,
      ];
      if (mins.isNotEmpty) sleep = mins.reduce((a, b) => a + b) / mins.length;
    } catch (_) {}

    return WeekNumbers(
      deficit: deficit,
      acsmDeficit: logged > 0 && acsmLogged == logged ? acsmDeficit : null,
      daysLogged: logged,
      daysExcluded: win.daysExcluded,
      proteinDays: proteins.length,
      avgProtein: proteins.isEmpty
          ? null
          : proteins.reduce((a, b) => a + b) / proteins.length,
      proteinTarget: (user['protein_target'] as num?)?.toDouble(),
      km: km,
      streak: (await loadMoveStreak())?.current,
      avgSleepMin: sleep,
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
  bool _failed = false;

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
      final w = await WeekNumbers.load(repo, Profile.fromMap(user), user);
      if (stillNewest(#week, t)) {
        setState(() {
          _w = w;
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
    final bottom = <(String, String, Color)>[
      ('RUN', '${w.km.toStringAsFixed(1)} km', C.run),
      if (w.streak != null) ('STREAK', '${w.streak} d', C.steps),
      if (w.avgSleepMin != null) ('SLEEP', hm(w.avgSleepMin), C.sleep),
    ];
    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('This week', style: F.over.copyWith(color: p.ink3)),
          const SizedBox(height: S.x2),
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
