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

  @override
  Widget build(BuildContext c) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(S.x4, S.x4, S.x4, S.x16),
      children: [
        ScreenTitle(
          'Nutrition',
          trailing: Pressable(
            expand: false,
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
            'One tap records that you ate, with no numbers at all. That is a '
                'complete entry — the detail is optional and always has been.',
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
                for (final m in kMeals)
                  MealRow(
                    meal: m,
                    entries: day?.mealEntries(m) ?? const [],
                    onTap: () => _logFood(meal: m),
                  ),
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
          conf: _waterMl == null ? Conf.none : Conf.high,
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
            'A day is counted only when every occasion carries an energy '
                'figure and the log reaches the evening. Partial days are '
                'left out of the averages instead of dragging them down.',
            'Nothing to fix if that is genuinely how you ate.',
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
        Section(
          'Seven-day average',
          counted == 0
              ? const StatusCard(
                  'No complete day to average yet',
                  'An average over partial days is an average of the meals we '
                      'happened to see. A day counts once every occasion has '
                      'an energy figure and the log reaches the evening.',
                  icon: LucideIcons.chartNoAxesColumn,
                )
              : Surface(
                  child: Column(
                    children: [
                      _Mean('Energy', w.meanKcal, 'kcal', C.domFood, counted),
                      _Mean('Protein', w.meanProtein, 'g', C.red, counted),
                      _Mean('Carbs', w.meanCarbs, 'g', C.orange, counted),
                      _Mean('Fat', w.meanFat, 'g', C.yellow, counted),
                      _Mean('Fibre', w.meanFibre, 'g', C.green, counted),
                    ],
                  ),
                ),
        ),
        if (counted > 0 && w.meanKcal != null && _burned?.value != null)
          Section(
            'Energy balance',
            Surface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InlineMetrics([
                    ('EATEN', '${w.meanKcal!.round()} kcal', C.domFood),
                    ('BURNED', '${_burned!.value!.round()} kcal', C.purple),
                    (
                      'BALANCE',
                      '${(w.meanKcal! - _burned!.value!).round()} kcal',
                      C.teal,
                    ),
                  ]),
                  const SizedBox(height: S.x3),
                  Text(
                    'Eaten is the mean of $counted complete days. Burned is '
                        'today\'s estimated expenditure, not a weekly mean — '
                        'there is no expenditure history to average yet.',
                    style: F.cap.copyWith(color: P.of(c).ink3, height: 1.45),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // ── GOALS ────────────────────────────────────────────────────────────────

  Widget _goalsTab(BuildContext c) {
    final p = P.of(c);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
              const SizedBox(height: S.x3),
              Text(
                'A basal rate from your height, weight, age and sex, plus what '
                'your heart rate says you spent on top of it. It is an '
                'estimate, and it is sensitive to every one of those.',
                style: F.cap.copyWith(color: p.ink2, height: 1.55),
              ),
              const SizedBox(height: S.x4),
              MetricRow(
                LucideIcons.flame,
                C.purple,
                'Estimated expenditure',
                _burned?.value == null ? 'Not measured' : '${_burned!.value!.round()}',
                unit: _burned?.value == null ? '' : 'kcal',
                sub: 'TODAY, FROM HEART RATE AND YOUR PROFILE',
                conf: ConfX.of(_burned),
              ),
            ],
          ),
        ),
      ],
    );
  }
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
              Text(
                k.value == null ? 'LOGGED TODAY' : 'EATEN TODAY',
                style: F.over.copyWith(color: p.ink3),
              ),
              const Spacer(),
              if (k.isFloor) const Pill('At least', C.yellow),
            ],
          ),
          const SizedBox(height: S.x2),
          // With no energy anywhere in the day, the occasion count IS the
          // measurement. A dash here would read as a failure to record when
          // the day was in fact recorded exactly as designed.
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                k.value == null
                    ? day.entries.length.toString()
                    : k.value!.round().toString(),
                style: F.n34.copyWith(color: p.ink),
              ),
              const SizedBox(width: S.x1),
              Text(
                k.value == null
                    ? 'occasion${day.entries.length == 1 ? '' : 's'}'
                    : 'kcal',
                style: F.cap.copyWith(color: p.ink3),
              ),
              const Spacer(),
              if (k.value != null)
                Text(
                  '${day.entries.length} occasion'
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

class _Mean extends StatelessWidget {
  const _Mean(this.label, this.value, this.unit, this.color, this.days);
  final String label;
  final double? value;
  final String unit;
  final Color color;
  final int days;

  @override
  Widget build(BuildContext c) => MetricRow(
    LucideIcons.chartNoAxesColumn,
    color,
    label,
    value == null ? 'Not recorded' : value!.round().toString(),
    unit: value == null ? '' : unit,
    sub: 'MEAN OF $days COMPLETE DAY${days == 1 ? '' : 'S'}',
    conf: value == null ? Conf.none : Conf.high,
  );
}
