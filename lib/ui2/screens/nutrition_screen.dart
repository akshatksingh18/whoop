// Nutrition.
//
// Three things this screen refuses to do, and they shape everything else:
//
//   1. It never shows a total it cannot stand behind. A day where any occasion
//      has no energy attached is a FLOOR, labelled "at least", and it is
//      excluded from every average on the Week tab.
//   2. Partial days are detected, not declared. There is no "I logged
//      everything" checkbox, because nobody ticks it and every average then
//      quietly rots.
//   3. Daily is the detail view. The seven-day rolling average is the hero —
//      one day of intake is noise, seven is a habit.
//
// Water is NOT re-invented here: it is the existing `water_ml` journal field
// (`lib/data/journal_fields.dart`), read and written through the repo.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../data/db.dart';
import '../../data/day_label.dart';
import '../../data/journal_fields.dart';
import '../../data/nutrition_store.dart';
import '../../models/metric.dart';
import '../../state/app_state.dart';
import '../ui2.dart';
import '../onboarding/profile_setup.dart' show formatDay;
import 'journal_compose.dart' show OsTextField;
import 'log_food.dart';

class NutritionScreen extends StatefulWidget {
  const NutritionScreen({super.key});

  @override
  State<NutritionScreen> createState() => _NutritionScreenState();
}

class _NutritionScreenState extends State<NutritionScreen> {
  int _tab = 0;
  static const _tabs = ['Today', 'Week', 'Goals'];

  final String _date = todayLabel();
  NutritionWindow? _week;
  Metric? _burned;
  double? _waterMl;
  bool _loading = true;

  /// The local profile map, read once per load. Targets live here rather than
  /// in a new table: they are two numbers the user typed, the same shape as
  /// `step_goal` next to them.
  Map<String, dynamic> _profile = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    final db = await LocalDb.instance;
    final week = await NutritionDb.window(db, days: 7);
    Metric? burned;
    double? water;
    final repo = app.repo;
    if (repo != null) {
      final today = await repo.getToday();
      final daily = today['daily'];
      if (daily is Map) burned = Metric.parse(daily['calories_total']);
      water = (await repo.getJournalMetrics(_date))['water_ml']?.value;
    }
    if (!mounted) return;
    setState(() {
      _week = week;
      _burned = burned;
      _waterMl = water;
      _profile = {...?app.user};
      _loading = false;
    });
  }

  NutritionDay? get _today {
    final w = _week;
    if (w == null) return null;
    for (final d in w.days) {
      if (d.date == _date) return d;
    }
    return null;
  }

  Future<void> _logFood({String meal = 'snack'}) async {
    final ok = await LogFoodSheet.show(context, date: _date, meal: meal);
    if (ok == true) await _load();
  }

  /// One tap's worth of water, from the field spec that performs the tap.
  static double get _waterStep => kJournalFieldsByKey['water_ml']!.step;

  Future<void> _addWater() async {
    final repo = context.read<AppState>().repo;
    if (repo == null) return;
    final spec = kJournalFieldsByKey['water_ml']!;
    final next = ((_waterMl ?? 0) + spec.step).clamp(0, spec.max).toDouble();
    final all = await repo.getJournalMetrics(_date);
    await repo.postJournalMetrics(_date, {
      ...all,
      'water_ml': JournalMetricValue(next),
    });
    await _load();
  }

  /// Removing a log is destructive and there is no undo, so the entry is named
  /// back before it goes. On-system rather than an `AlertDialog`: this package
  /// bans `fontSize:` and `Colors.white` in its own tests and a Material dialog
  /// smuggles both in.
  Future<void> _confirmDelete(FoodEntry e) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      sheetAnimationStyle: sheetMotion(context),
      backgroundColor: P.of(context).card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(R.xxl)),
      ),
      builder: (s) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(S.x5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Remove ${e.label}?',
                  style: F.head.copyWith(color: P.of(s).ink)),
              const SizedBox(height: S.x2),
              Text(
                'It leaves the day and every average that counted it. There is '
                'no undo.',
                style: F.cap.copyWith(color: P.of(s).ink2, height: 1.5),
              ),
              const SizedBox(height: S.x5),
              BigButton('Remove',
                  icon: LucideIcons.trash2,
                  color: C.red,
                  onTap: () => Navigator.of(s).pop(true)),
              const SizedBox(height: S.x3),
              BigButton('Keep it',
                  soft: true, onTap: () => Navigator.of(s).pop(false)),
            ],
          ),
        ),
      ),
    );
    if (ok != true) return;
    await NutritionDb.delete(await LocalDb.instance, e.id);
    await _load();
  }

  @override
  Widget build(BuildContext c) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(S.x4, S.x4, S.x4, S.x16),
      children: [
        ScreenTitle(
          'Nutrition',
          trailing: Pressable(
            semanticLabel: 'Log food',
            onTap: _logFood,
            child: Icon(
              LucideIcons.circlePlus,
              size: 22,
              color: P.of(c).on(C.domFood),
            ),
          ),
        ),
        SubTabs(_tabs, _tab, (i) => setState(() => _tab = i), color: C.domFood),
        const SizedBox(height: S.x5),
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else
          [_todayTab, _weekTab, _goalsTab][_tab](c),
      ],
    );
  }

  // ── TODAY ────────────────────────────────────────────────────────────────

  Widget _todayTab(BuildContext c) {
    final day = _today;
    final w = _week;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (day == null || !day.logged)
          StatusCard(
            'Nothing logged today',
            'One tap is a complete log.',
            fix: 'Log an eating occasion',
            icon: LucideIcons.utensils,
            onFix: _logFood,
          )
        else
          DayEnergyCard(day: day, burned: _burned),
        Section(
          'Occasions',
          Surface(
            pad: const EdgeInsets.symmetric(horizontal: S.x4),
            child: Column(
              children: [
                for (final m in kMeals) ...[
                  MealRow(
                    meal: m,
                    entries: day?.mealEntries(m) ?? const [],
                    onTap: () => _logFood(meal: m),
                  ),
                  // The individual entries, indented under the occasion they
                  // belong to, each one removable. A mistyped 2,000 kcal used
                  // to be permanent and it silently poisoned every seven-day
                  // mean it fell into.
                  for (final e in day?.mealEntries(m) ?? const <FoodEntry>[])
                    Padding(
                      padding: const EdgeInsets.only(left: S.x8),
                      child: FoodRow(
                        entry: e,
                        trailing: LucideIcons.trash2,
                        onTap: () => _confirmDelete(e),
                      ),
                    ),
                ],
              ],
            ),
          ),
          action: 'Add',
          onAction: _logFood,
        ),
        const SizedBox(height: S.x4),
        MetricRow(
          LucideIcons.glassWater,
          C.blue,
          'Water',
          _waterMl == null ? 'Not logged' : (_waterMl! / 1000).toStringAsFixed(1),
          unit: _waterMl == null ? '' : 'L',
          // The step is the spec's, and `_addWater` already reads it from
          // there. Two copies of one constant is one copy too many.
          sub: 'TAP TO ADD ${_waterStep.round()} ML',
          onTap: _addWater,
        ),
        if (day != null && day.logged && day.kcal.isFloor) ...[
          const SizedBox(height: S.x4),
          StatusCard(
            'Today\'s energy is a floor, not a total',
            '${day.kcal.unknown} of ${day.entries.length} occasions were '
                'logged without an energy figure, so the number above is the '
                'least you ate rather than what you ate.',
            fix: 'Add the numbers to an occasion',
            icon: LucideIcons.circleDashed,
            onFix: _logFood,
          ),
        ],
        if (w != null && w.daysExcluded > 0) ...[
          const SizedBox(height: S.x4),
          Observation(
            '${w.daysExcluded} of the last ${w.span} days could not be counted',
            'A day counts once every occasion carries an energy figure.',
          ),
        ],
      ],
    );
  }

  // ── WEEK ─────────────────────────────────────────────────────────────────

  Widget _weekTab(BuildContext c) {
    final w = _week;
    if (w == null) return const SizedBox.shrink();
    final counted = w.counted.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Surface(
          child: Consistency(
            w.daysLogged,
            w.span,
            w.daysExcluded == 0
                ? 'Days with something logged'
                : '${w.daysExcluded} logged but partial, so excluded from '
                      'every average below',
            C.domFood,
          ),
        ),
        Section('Energy, day by day', _weekChart(c, w)),
        Section(
          'Seven-day average',
          counted == 0
              ? const StatusCard(
                  'No complete day to average yet',
                  'You have none.',
                  icon: LucideIcons.chartNoAxesColumn,
                )
              : Surface(
                  child: Column(
                    children: [
                      _Mean('Energy', w.meanKcal, 'kcal', C.domFood),
                      _Mean('Protein', w.meanProtein, 'g', C.red),
                      _Mean('Carbs', w.meanCarbs, 'g', C.orange),
                      _Mean('Fat', w.meanFat, 'g', C.yellow),
                      _Mean('Fibre', w.meanFibre, 'g', C.green),
                    ],
                  ),
                ),
        ),
        if (counted > 0 && w.meanKcal.value != null && _burned?.value != null)
          Section(
            'Energy balance',
            Surface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InlineMetrics([
                    ('EATEN', '${w.meanKcal.value!.round()} kcal', C.domFood),
                    ('BURNED', '${_burned!.value!.round()} kcal', C.purple),
                    (
                      'BALANCE',
                      '${(w.meanKcal.value! - _burned!.value!).round()} kcal',
                      C.teal,
                    ),
                  ]),
                  const SizedBox(height: S.x3),
                  Text(
                    'Eaten is the mean of ${w.meanKcal.days} complete days. '
                    'Burned is today only.',
                    style: F.cap.copyWith(color: P.of(c).ink3, height: 1.45),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// Seven bars of logged energy, today highlighted. A day with nothing logged
  /// draws no bar rather than a zero — zero kcal is a claim, and an unlogged
  /// day is an absence. A PARTIAL day still draws, because its total is a real
  /// floor; the footnote says it is one and that the mean below excluded it.
  Widget _weekChart(BuildContext c, NutritionWindow w) {
    // `?? 0.0` here was the whole absence-versus-zero bug in one operator: an
    // unlogged day became a real zero, and `Bars`' 2 pt visibility floor drew
    // it as a measured day with almost nothing in it. Null is a hole.
    final vals = [for (final d in w.days) d.kcal.value?.toDouble()];
    final real = vals.whereType<double>().where((v) => v > 0).toList();
    final drawn = real.length;
    final axis = drawn == 0 ? null : AxisSpec.of(real, floor: 0);
    final p = P.of(c);
    return Surface(
      child: ChartFrame(
        title: 'Energy logged',
        unit: 'kcal',
        height: 120,
        yAxis: axis,
        // The window is built oldest-first ending today, so these labels are
        // the range actually drawn rather than a hardcoded guess.
        xLabels: drawn == 0
            ? const []
            : [_dayShort(w.days.first.date), 'Today'],
        footnote: w.daysExcluded == 0
            ? null
            : '${w.daysExcluded} partial, left out of the averages below.',
        empty: axis == null ? const NoData(message: 'Nothing logged yet') : null,
        series: vals,
        child: axis == null
            ? const SizedBox.shrink()
            : CustomPaint(
                size: Size.infinite,
                painter: Bars(vals, C.domFood, p.track,
                    highlight: vals.length - 1, t: animate(c, 1), axis: axis),
              ),
      ),
    );
  }

  // ── GOALS ────────────────────────────────────────────────────────────────

  /// A target the user TYPES. Adaptive targets need weight history and ~21
  /// complete days and stay deferred; a typed one needs no science at all, and
  /// the tab is named Goals.
  static const _goalSpecs = <(String, String, String, Color)>[
    ('kcal_target', 'Daily energy', 'kcal', C.domFood),
    ('protein_target', 'Daily protein', 'g', C.red),
  ];

  double? _target(String key) => (_profile[key] as num?)?.toDouble();

  /// The same gated mean the Week tab prints, so goal progress and the average
  /// can never disagree — including about how many days went into it.
  NutrientMean? _meanFor(String key) =>
      key == 'kcal_target' ? _week?.meanKcal : _week?.meanProtein;

  Future<void> _editTargets() async {
    final ctrls = {
      for (final g in _goalSpecs)
        g.$1: TextEditingController(text: _target(g.$1)?.round().toString() ?? ''),
    };
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      sheetAnimationStyle: sheetMotion(context),
      backgroundColor: P.of(context).card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(R.xxl)),
      ),
      builder: (s) => Padding(
        padding: EdgeInsets.only(
            left: S.x5,
            right: S.x5,
            top: S.x5,
            bottom: MediaQuery.of(s).viewInsets.bottom + S.x5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Your targets', style: F.head.copyWith(color: P.of(s).ink)),
            const SizedBox(height: S.x4),
            for (final g in _goalSpecs) ...[
              OsTextField(
                controller: ctrls[g.$1]!,
                label: '${g.$2} (${g.$3})',
                hint: 'none',
                keyboard: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: S.x3),
            ],
            const SizedBox(height: S.x2),
            BigButton('Save',
                color: C.domFood, onTap: () => Navigator.of(s).pop(true)),
          ],
        ),
      ),
    );
    final fields = {
      for (final g in _goalSpecs)
        g.$1: double.tryParse(ctrls[g.$1]!.text.trim()),
    };
    for (final ctrl in ctrls.values) {
      ctrl.dispose();
    }
    if (saved != true || !mounted) return;
    await context.read<AppState>().updateProfile(fields);
    await _load();
  }

  Widget _goalsTab(BuildContext c) {
    final p = P.of(c);
    final set = [for (final g in _goalSpecs) if (_target(g.$1) != null) g];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (set.isEmpty)
          StatusCard(
            'No targets set',
            'A target here is one you type.',
            fix: 'Set a target',
            icon: LucideIcons.target,
            onFix: _editTargets,
          )
        else
          Section(
            'Your targets',
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final g in set) ...[
                  _goalCard(g),
                  const SizedBox(height: S.x3),
                ],
              ],
            ),
            action: 'Edit',
            onAction: _editTargets,
          ),
        const SizedBox(height: S.x4),
        Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(LucideIcons.cpu, size: 16, color: p.on(C.purple)),
                  const SizedBox(width: S.x2),
                  Expanded(
                    child: Text(
                      'What your body spent today',
                      style: F.body.copyWith(
                        color: p.ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: S.x4),
              MetricRow(
                LucideIcons.flame,
                C.purple,
                'Estimated expenditure',
                _burned?.value == null ? 'Not measured' : '${_burned!.value!.round()}',
                unit: _burned?.value == null ? '' : 'kcal',
                sub: 'TODAY, FROM HEART RATE AND YOUR PROFILE',
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Current → target → the rate between them. The "current" is the mean of
  /// COMPLETE days only, the same denominator the Week tab uses, so the goal
  /// and the average can never disagree about what was counted.
  Widget _goalCard((String, String, String, Color) g) {
    final target = _target(g.$1)!;
    final m = _meanFor(g.$1);
    final mean = m?.value;
    if (mean == null || target <= 0) {
      return StatusCard(
        'Nothing to measure ${g.$2.toLowerCase()} against yet',
        // Two different absences, and the difference matters: the day never
        // qualified, or it qualified on energy while this nutrient was only a
        // floor. Progress against a floor would read low every single day.
        (m?.floorDays ?? 0) > 0
            ? 'Every complete day had an occasion logged without a '
                  '${g.$2.split(' ').last.toLowerCase()} figure, so the average '
                  'would only be a lower bound.'
            : 'A day counts once every occasion carries a figure and the log '
                  'reaches the evening. None of the last ${_week?.span ?? 7} '
                  'days has.',
        fix: 'Log an eating occasion',
        icon: LucideIcons.target,
        onFix: _logFood,
      );
    }
    // The nutrient's OWN denominator, not the window's count of complete days:
    // protein can be measured on fewer days than energy was.
    final days = m!.days;
    final diff = mean - target;
    return GoalTrajectory(
      g.$2,
      '${mean.round()} ${g.$3}',
      '${target.round()} ${g.$3}',
      '${diff.abs() < 1 ? 'On target' : '${diff.abs().round()} ${g.$3}/day '
          '${diff > 0 ? 'above' : 'below'}'} · mean of $days complete '
          'day${days == 1 ? '' : 's'}',
      (mean / target).clamp(0, 1).toDouble(),
      g.$4,
      rateDown: diff > 0,
    );
  }
}

/// "Thu 4 Sep" from a `YYYY-MM-DD` day label, for an axis end-label.
String _dayShort(String ymd) {
  final d = DateTime.tryParse(ymd);
  return d == null ? ymd : formatDay(d);
}

// ── components ─────────────────────────────────────────────────────────────

/// Today's energy, with its honesty state on the face of it. `at least` is not
/// a hedge — it is arithmetic: a total that summed past unknown values is a
/// lower bound and nothing more.
class DayEnergyCard extends StatelessWidget {
  const DayEnergyCard({super.key, required this.day, this.burned});

  final NutritionDay day;
  final Metric? burned;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final k = day.kcal;
    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  k.value == null ? 'LOGGED TODAY' : 'EATEN TODAY',
                  style: F.over.copyWith(color: p.ink3),
                ),
              ),
              if (k.isFloor) const Flexible(child: Pill('At least', C.yellow)),
            ],
          ),
          const SizedBox(height: S.x2),
          // With no energy anywhere in the day, the occasion count IS the
          // measurement. A dash here would read as a failure to record when
          // the day was in fact recorded exactly as designed.
          // A Wrap rather than a Row with a Spacer: `2,310 kcal` beside the
          // occasion count overflowed by 168 px at 3.1x, which is a day's
          // energy pushed off the card for the people who chose that size.
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: S.x1,
            runSpacing: S.x1,
            children: [
              Text(
                k.value == null
                    ? day.entries.length.toString()
                    : k.value!.round().toString(),
                style: F.n34.copyWith(color: p.ink),
              ),
              Text(
                k.value == null
                    ? 'occasion${day.entries.length == 1 ? '' : 's'}'
                    : 'kcal',
                style: F.cap.copyWith(color: p.ink3),
              ),
              if (k.value != null)
                Text(
                  '· ${day.entries.length} occasion'
                  '${day.entries.length == 1 ? '' : 's'}',
                  style: F.cap.copyWith(color: p.ink2),
                ),
            ],
          ),
          if (burned?.value != null) ...[
            const SizedBox(height: S.x4),
            InlineMetrics([
              ('BURNED', '${burned!.value!.round()} kcal', C.purple),
              if (k.value != null)
                (
                  // Eaten is a FLOOR when occasions were logged without an
                  // energy figure, so eaten minus burned is a floor too: the
                  // balance is AT LEAST this, never at most. The pill on this
                  // same card says "At least".
                  k.isFloor ? 'BALANCE AT LEAST' : 'BALANCE',
                  '${(k.value! - burned!.value!).round()} kcal',
                  C.teal,
                ),
            ]),
          ],
        ],
      ),
    );
  }
}

/// One meal slot. An empty slot is an invitation, not a gap — the row never
/// implies you failed to log something you may simply not have eaten.
class MealRow extends StatelessWidget {
  const MealRow({
    super.key,
    required this.meal,
    required this.entries,
    this.onTap,
  });

  final String meal;
  final List<FoodEntry> entries;
  final VoidCallback? onTap;

  static const _icons = {
    'breakfast': LucideIcons.eggFried,
    'lunch': LucideIcons.salad,
    'dinner': LucideIcons.beef,
    'snack': LucideIcons.apple,
  };

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final known = [
      for (final e in entries)
        if (e.kcal != null) e.kcal!,
    ];
    final total = known.isEmpty ? null : known.reduce((a, b) => a + b);
    final anyUnknown = entries.any((e) => e.kcal == null);
    return Pressable(
      onTap: onTap,
      semanticLabel: _mealLabel(meal),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: S.x3),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: p.card2, borderRadius: R.rSm),
              child: Icon(
                _icons[meal] ?? LucideIcons.utensils,
                size: 17,
                color: p.ink2,
              ),
            ),
            const SizedBox(width: S.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _mealLabel(meal),
                    style: F.body.copyWith(color: p.ink),
                  ),
                  Text(
                    entries.isEmpty
                        ? 'Not logged'
                        : total == null
                        ? '${entries.length} logged · energy not recorded'
                        : '${anyUnknown ? 'at least ' : ''}'
                              '${total.round()} kcal',
                    style: F.over.copyWith(color: p.ink3),
                  ),
                ],
              ),
            ),
            Icon(
              entries.isEmpty
                  ? LucideIcons.circlePlus
                  : LucideIcons.circleCheck,
              size: 20,
              color: entries.isEmpty ? p.ink3 : p.on(C.green),
            ),
          ],
        ),
      ),
    );
  }
}

String _mealLabel(String m) => switch (m) {
  'breakfast' => 'Breakfast',
  'lunch' => 'Lunch',
  'dinner' => 'Dinner',
  _ => 'Snacks',
};

/// One nutrient's seven-day mean, with its own denominator.
///
/// The denominator is the nutrient's, not the window's: a day counts toward the
/// ENERGY average on complete kcal alone, so protein can be a floor on a day
/// that qualified. Those days are excluded and NAMED here — a mean built on
/// floors is understated, and printing it beside the energy mean as though both
/// were measured the same way is the failure this row exists to prevent. There
/// is deliberately no "at least" pill: the gated mean is not a floor, so a floor
/// marker would be as wrong as the understatement it replaced.
class _Mean extends StatelessWidget {
  const _Mean(this.label, this.mean, this.unit, this.color);
  final String label;
  final NutrientMean mean;
  final String unit;
  final Color color;

  @override
  Widget build(BuildContext c) {
    final n = mean.days;
    final floors = mean.floorDays;
    return MetricRow(
      LucideIcons.chartNoAxesColumn,
      color,
      label,
      mean.value == null
          ? (floors > 0 ? 'Not counted' : 'Not recorded')
          : mean.value!.round().toString(),
      unit: mean.value == null ? '' : unit,
      sub: mean.value == null
          ? (floors > 0
                ? 'EVERY COMPLETE DAY HAD AN OCCASION WITH NO '
                      '${label.toUpperCase()} FIGURE'
                : 'NO COMPLETE DAY RECORDED ${label.toUpperCase()}')
          : 'MEAN OF $n COMPLETE DAY${n == 1 ? '' : 'S'}'
                '${floors == 0 ? '' : ' · $floors LEFT OUT AS A FLOOR'}',
    );
  }
}
