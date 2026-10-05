// Nutrition — a food log in the MyFitnessPal shape, kept simple.
//
//   · Calories left = your goal − food. Exercise is NOT added back: the goal
//     is the number you chose, and a wrist estimate of burn is not precise
//     enough to spend.
//   · Protein, carbs, fat and fibre against your own targets.
//   · Breakfast, lunch, dinner and snacks, each with its own Add — from saved
//     meals, from your foods by weight, or quick add / barcode.
//   · Maintenance: what the day cost as a floor (BMR + steps + runs + 10% of the
//     food logged), shown beside the food, never changing the goal.
//   · History: a trailing chart and calendar-month groups of retained entries.
//   · Foods: the foods and saved meals you log from.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../data/db.dart';
import '../../data/day_label.dart';
import '../../compute/profile.dart' show Profile;
import '../../compute/day_upkeep.dart';
export '../../compute/day_upkeep.dart' show DayUpkeep;
import '../../data/local_repository.dart';
import '../../data/nutrition_store.dart';
import '../../gps/run_history.dart';
import '../../state/app_state.dart';
import '../ui2.dart';
import 'food_diary.dart';
import 'food_picker.dart';
import 'home_screen.dart'
    show metricOf, prettyDay, pullToRefresh, repoOf, thousands;
import 'journal_compose.dart' show OsTextField;
import 'metric_detail.dart' show detailScaffold;

/// The five typed targets, in display order: (profile key, label, unit, colour).
const kNutritionTargets = [
  ('kcal_target', 'Calories', 'kcal', C.domFood),
  ('protein_target', 'Protein', 'g', C.red),
  ('carbs_target', 'Carbs', 'g', C.blue),
  ('fat_target', 'Fat', 'g', C.yellow),
  ('fibre_target', 'Fibre', 'g', C.green),
];

double? _targetOf(Map<String, dynamic> profile, String key) =>
    (profile[key] as num?)?.toDouble();

class NutritionScreen extends StatefulWidget {
  const NutritionScreen({super.key});

  /// How many times any Nutrition tab has finished (re)reading its data. Tests
  /// use it to tell a real re-read from a mere rebuild.
  @visibleForTesting
  static int debugLoads = 0;

  @override
  State<NutritionScreen> createState() => _NutritionScreenState();
}

class _NutritionScreenState extends State<NutritionScreen> with RevisionReload {
  int _tab = 0;
  NutritionWindow? _month;
  List<String> _historyMonths = const [];
  bool _failed = false, _calorieLoading = false, _calorieFailed = false;
  List<Map<String, Object?>> _foods = const [];
  List<MealTemplate> _meals = const [];

  /// Steps per day for the month, for each day's maintenance figure.
  Map<String, double?> _maintenance = const {}, _acsmMaintenance = const {};
  List<RunSummary> _runs = const [];
  List<({String date, double kg})> _weights = const [];
  bool _loading = true;

  /// The day the Today tab shows; null follows the calendar day.
  String? _shownDay;

  /// Read on every use, never captured once: the shell keeps this tab alive,
  /// so a field initialiser would still be yesterday after midnight.
  String get _date => todayLabel();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void reload() => _load();

  Future<void> _load() async {
    final t = beginRead(#nutrition);
    final repo = repoOf(context);
    final pr = Profile.fromMap(context.read<AppState>().user);
    try {
      final db = await LocalDb.instance;
      final month = await NutritionDb.window(db, days: 31);
      final months = await NutritionDb.historyMonths(db);
      final now = DateTime.now();
      final weights = await BodyWeight.since(
        db,
        dayLabelOf(DateTime(now.year, now.month, now.day - 60)),
      );
      final foods = await MyFoods.all(db);
      final meals = await MyFoods.meals(db);
      final maintenance = <String, double?>{},
          acsmMaintenance = <String, double?>{};
      final runs = await _allRuns(repo);
      if (!stillNewest(#nutrition, t)) return;
      setState(() {
        _month = month;
        _historyMonths = months;
        _foods = foods;
        _meals = meals;
        _maintenance = {};
        _acsmMaintenance = {};
        _runs = runs;
        _weights = weights;
        _loading = false;
        _failed = false;
        _calorieLoading = true;
        _calorieFailed = false;
      });
      // Food navigation is ready immediately; historical movement estimates
      // finish in the background. A manual refresh still awaits both paths.
      try {
        if (repo != null) {
          for (final d in month.days) {
            if (!stillNewest(#nutrition, t)) return;
            final upkeep = await DayUpkeep.read(
              repo,
              d.date,
              pr,
              eaten: d.kcal.value ?? 0,
              runs: runs,
            );
            maintenance[d.date] = upkeep.parts?.total;
            acsmMaintenance[d.date] = upkeep.acsmParts?.total;
          }
        }
        if (!stillNewest(#nutrition, t)) return;
        setState(() {
          _maintenance = maintenance;
          _acsmMaintenance = acsmMaintenance;
          _calorieLoading = false;
        });
      } catch (_) {
        if (!stillNewest(#nutrition, t)) return;
        setState(() {
          _calorieLoading = false;
          _calorieFailed = true;
        });
      }
      // Counted when the read has LANDED, so a test waiting on it also waits
      // for the database it opened.
      NutritionScreen.debugLoads++;
    } catch (error, stack) {
      debugPrint('[food] load failed: $error\n$stack');
      if (stillNewest(#nutrition, t)) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext c) {
    return RefreshIndicator(
      onRefresh: () => pullToRefresh(c, () async {
        runsChanged();
        _dayKey++;
        await _load();
      }),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(S.x4, S.x4, S.x4, S.x16),
        children: [
          ScreenTitle(
            'Food',
            trailing: Pressable(
              semanticLabel: 'Goals',
              onTap: () async {
                if (await editNutritionGoals(c)) await _load();
              },
              child: Icon(
                LucideIcons.target,
                size: 22,
                color: P.of(c).on(C.domFood),
              ),
            ),
          ),
          SubTabs(
            const ['Today', 'History', 'Foods'],
            _tab,
            (i) => setState(() => _tab = i),
            color: C.domFood,
          ),
          const SizedBox(height: S.x5),
          if (_failed)
            StatusCard(
              'Food could not load',
              'Your saved log is intact.',
              fix: 'Retry',
              onFix: _load,
            )
          else if (_loading)
            const Center(child: CircularProgressIndicator())
          else
            switch (_tab) {
              0 => _today(c),
              1 => _history(c),
              _ => _foodsTab(c),
            },
        ],
      ),
    );
  }

  /// Bumped by a pull so today's view reads its steps and runs again.
  int _dayKey = 0;

  // ── TODAY (any day) ──────────────────────────────────────────────────────

  /// The day view with ‹ Today › above it; swipe for the next or previous day.
  Widget _today(BuildContext c) {
    final day = _shownDay ?? _date;
    void go(String d) => setState(() => _shownDay = d == _date ? null : d);
    return Swipe(
      label: 'Day',
      onPrevious: () => go(shiftDay(day, -1)),
      onNext: day == _date ? null : () => go(shiftDay(day, 1)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DayHeader(day, go),
          const SizedBox(height: S.x3),
          NutritionDayView(
            key: ValueKey('$day#$_dayKey'),
            date: day,
            onChanged: _load,
          ),
        ],
      ),
    );
  }

  // ── HISTORY ──────────────────────────────────────────────────────────────

  /// Every day of the last month: maintenance, what was eaten and the
  /// difference, with a chart and this week's totals, and body weight with
  /// the maintenance it measures. Any day opens to view or add food.
  Widget _history(BuildContext c) {
    final p = P.of(c);
    final profile = context.watch<AppState>().user ?? const {};
    final pr = Profile.fromMap(profile);
    final days = [...?_month?.days]; // oldest first
    if (days.isEmpty) return const SizedBox.shrink();
    final m = [for (final d in days) _maintenance[d.date]];
    final acsm = [for (final d in days) _acsmMaintenance[d.date]];
    final eaten = [for (final d in days) d.logged ? d.kcal.value : null];

    // This week, Monday to today, over the days with food logged.
    final today = DateTime.now();
    final monday = dayLabelOf(
      DateTime(today.year, today.month, today.day - (today.weekday - 1)),
    );
    var deficit = 0.0, eatSum = 0.0, mSum = 0.0, acsmSum = 0.0;
    var acsmCount = 0;
    var counted = 0;
    for (var i = 0; i < days.length; i++) {
      if (days[i].date.compareTo(monday) < 0) continue;
      final e = eaten[i], mm = m[i];
      if (!days[i].countsTowardAverages || e == null || mm == null) continue;
      deficit += mm - e;
      eatSum += e;
      mSum += mm;
      if (acsm[i] != null) {
        acsmSum += acsm[i]!;
        acsmCount++;
      }
      counted++;
    }

    final all = [
      for (final v in [...m, ...acsm, ...eaten]) ?v,
    ];
    final axis = all.isEmpty
        ? null
        : AxisSpec.of(all, floor: 0, ticks: 3, format: (v) => thousands(v));
    String says(int i) {
      final d = days[i];
      final mm = m[i], e = eaten[i];
      return '${dayTitle(d.date)}${d.state == DayLogState.inProgress ? ' · so far' : ''}\n${[if (mm != null) 'Budget ${thousands(mm)}', if (acsm[i] != null) 'ACSM ${thousands(acsm[i])}', e == null ? 'no food logged' : 'ate ${thousands(e)}', if (mm != null && e != null) '${e > mm ? '+' : '−'}${thousands((e - mm).abs())}'].join(' · ')}';
    }

    final pick = _histPick;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _weightCard(c, p, pr, days),
        if (_calorieLoading)
          Text(
            'Updating historical calorie estimates…',
            style: F.cap.copyWith(color: p.ink3),
          ),
        if (_calorieFailed)
          StatusCard(
            'Calorie history could not load',
            'Your food entries remain available.',
            fix: 'Retry',
            onFix: _load,
          ),
        const SizedBox(height: S.x3),
        if (counted > 0)
          Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('This week', style: F.over.copyWith(color: p.ink3)),
                const SizedBox(height: S.x2),
                InlineMetrics([
                  (
                    deficit >= 0 ? 'DEFICIT' : 'SURPLUS',
                    thousands(deficit.abs()),
                    deficit >= 0 ? C.green : C.red,
                  ),
                  ('AVG EATEN', thousands(eatSum / counted), C.domFood),
                  ('AVG BUDGET', thousands(mSum / counted), C.steps),
                ]),
                const SizedBox(height: S.x2),
                CaloriePair(
                  budget: mSum / counted,
                  acsm: acsmCount == counted ? acsmSum / counted : null,
                  compact: true,
                  note: 'Average maintenance on these completed days.',
                ),
                Text(
                  '$counted completed day${counted == 1 ? '' : 's'} · estimated maintenance. '
                  'Today and detectably incomplete logs are excluded.',
                  style: F.cap.copyWith(color: p.ink3),
                ),
              ],
            ),
          ),
        if (axis != null) ...[
          const SizedBox(height: S.x3),
          Surface(
            child: ChartFrame(
              title: 'Maintenance and eaten',
              unit: 'kcal',
              footnote: 'Last 31 days · tap or drag for daily values',
              height: 130,
              yAxis: axis,
              series: eaten,
              readout: pick == null ? null : says(pick),
              legend: [
                ('Budget', p.on(C.steps)),
                ('ACSM', p.on(C.teal)),
                ('Eaten', p.on(C.domFood)),
              ],
              xLabels: const ['30 days ago', 'Today'],
              child: Scrubber(
                value: pick == null ? null : (pick + .5) / days.length,
                step: 1 / days.length,
                label: 'Maintenance and eaten by day',
                describe: (v) =>
                    says((v * days.length).floor().clamp(0, days.length - 1)),
                onChanged: (v) => setState(
                  () => _histPick = (v * days.length).floor().clamp(
                    0,
                    days.length - 1,
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: Bars(
                          m,
                          p.on(C.steps).withValues(alpha: .45),
                          axis: axis,
                          cursor: pick,
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: CustomPaint(
                        painter: LineChart(
                          acsm,
                          p.on(C.teal),
                          fill: false,
                          axis: axis,
                          cursor: pick,
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: CustomPaint(
                        painter: LineChart(
                          eaten,
                          p.on(C.domFood),
                          fill: false,
                          dots: true,
                          axis: axis,
                          dotInk: p.card,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: S.x3),
        Text(
          'By month',
          style: F.body.copyWith(color: p.ink, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: S.x2),
        for (final month in _historyMonths)
          _FoodHistoryMonth(
            key: ValueKey(month),
            month: month,
            profile: profile,
            runs: _runs,
            onChanged: _load,
          ),
        const SizedBox(height: S.x2),
        Text(
          'Completed = a past day with calories on every entry and an entry after 5 pm. '
          'Food you forget to log cannot be detected.',
          style: F.over.copyWith(color: p.ink3),
        ),
      ],
    );
  }

  /// The day under the finger on the history chart.
  int? _histPick;

  /// Body weight: the latest reading, the 7-day trend, a Log button, and
  /// maintenance measured from weight change and food once there is enough.
  Widget _weightCard(BuildContext c, P p, Profile pr, List<NutritionDay> days) {
    final w = _weights;
    final trend = weightTrend(w);
    final now = DateTime.now();
    final since = dayLabelOf(DateTime(now.year, now.month, now.day - 27));
    final recent = [
      for (final x in w)
        if (x.date.compareTo(since) >= 0) x,
    ];
    final measured = estimatedMaintenance(recent, days);
    final coverage = maintenanceFoodCoverage(recent, days);
    final series = [for (final t in trend) t.kg];
    final axis = series.length < 2
        ? null
        : AxisSpec.of(series, ticks: 2, format: axisFixed);
    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Weight', style: F.over.copyWith(color: p.ink3)),
                    Text(
                      w.isEmpty
                          ? (pr.weightKg == null
                                ? '–'
                                : '${pr.weightKg!.toStringAsFixed(1)} kg')
                          : '${w.last.kg.toStringAsFixed(1)} kg',
                      style: F.n24.copyWith(color: p.ink),
                    ),
                    if (trend.length >= 2)
                      Text(
                        '7-day trend ${trend.last.kg.toStringAsFixed(1)} kg',
                        style: F.cap.copyWith(color: p.ink3),
                      ),
                  ],
                ),
              ),
              Pressable(
                semanticLabel: 'Log weight',
                onTap: () => _logWeight(c),
                child: Pill('Log weight', C.domFood, icon: LucideIcons.plus),
              ),
            ],
          ),
          if (axis != null) ...[
            const SizedBox(height: S.x3),
            SizedBox(
              height: 48,
              child: CustomPaint(
                size: Size.infinite,
                painter: LineChart(
                  series,
                  p.on(C.domFood),
                  fill: false,
                  axis: axis,
                ),
              ),
            ),
          ],
          const SizedBox(height: S.x3),
          Text(
            measured == null
                ? (coverage.days == 0
                      ? 'Log morning weight and complete food days. At least 14 days and 8 weigh-ins are needed.'
                      : '${coverage.complete}/${coverage.days} aligned food days complete. At least 14 days and 8 weigh-ins are needed.')
                : 'Estimated maintenance from food and weight: about ${thousands(measured.kcal)} kcal · '
                      '${measured.kgPerWeek <= 0 ? 'losing' : 'gaining'} '
                      '${measured.kgPerWeek.abs().toStringAsFixed(2)} kg a week '
                      '(${measured.days} days, ${measured.weighIns} weigh-ins)',
            style: F.cap.copyWith(color: measured == null ? p.ink3 : p.ink2),
          ),
        ],
      ),
    );
  }

  Future<void> _logWeight(BuildContext c) async {
    final app = c.read<AppState>();
    final kg = await askText(
      c,
      'Log weight',
      'Weight (kg)',
      (_weights.isEmpty ? Profile.fromMap(app.user).weightKg : _weights.last.kg)
              ?.toStringAsFixed(1) ??
          '',
      validate: (s) {
        final v = Typed.of(s).value;
        return v == null || v < 30 || v > 300
            ? 'Enter a weight from 30 to 300 kg.'
            : null;
      },
      keyboard: const TextInputType.numberWithOptions(decimal: true),
    );
    final v = kg == null ? null : Typed.of(kg).value;
    if (v == null || v < 30 || v > 300) return;
    try {
      await BodyWeight.put(await LocalDb.instance, todayLabel(), v);
      // The profile weight follows the scale, so resting energy and every
      // calorie figure use the current weight.
      await app.updateProfile({'weight_kg': v});
      app.bumpInsights();
      await _load();
    } catch (_) {
      if (c.mounted) {
        ScaffoldMessenger.maybeOf(c)?.showSnackBar(
          const SnackBar(
            content: Text('Weight was not saved. Please try again.'),
          ),
        );
      }
    }
  }

  // ── FOODS ────────────────────────────────────────────────────────────────

  Widget _foodsTab(BuildContext c) {
    final p = P.of(c);
    Future<void> edit(Future<Object?> Function() f) async {
      try {
        await f();
        if (mounted) await _load();
      } catch (_) {
        if (c.mounted) {
          ScaffoldMessenger.maybeOf(c)?.showSnackBar(
            const SnackBar(
              content: Text(
                'Could not change your saved food. Please try again.',
              ),
            ),
          );
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Section(
          'Saved meals',
          Surface(
            pad: const EdgeInsets.symmetric(horizontal: S.x4),
            child: _meals.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: S.x4),
                    child: Text(
                      'A saved meal is your usual breakfast or lunch, logged in '
                      'one tap.',
                      style: F.cap.copyWith(color: p.ink3),
                    ),
                  )
                : Column(
                    children: [
                      for (final m in _meals)
                        PickRow(
                          m.label,
                          '${mealName(m.meal)} · ${m.items.length} '
                          'food${m.items.length == 1 ? '' : 's'}',
                          trailing: LucideIcons.chevronRight,
                          onTap: () => edit(() => _mealActions(c, m)),
                        ),
                    ],
                  ),
          ),
          action: 'New',
          onAction: () => edit(() => MealEditor.show(c)),
        ),
        Section(
          'My foods',
          Surface(
            pad: const EdgeInsets.symmetric(horizontal: S.x4),
            child: _foods.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: S.x4),
                    child: Text(
                      'Add a food once from its label; log any amount after.',
                      style: F.cap.copyWith(color: p.ink3),
                    ),
                  )
                : Column(
                    children: [
                      for (final f in _foods)
                        PickRow(
                          (f['label'] ?? '').toString(),
                          foodServingLine(f),
                          trailing: LucideIcons.chevronRight,
                          onTap: () => edit(() => _foodActions(c, f)),
                        ),
                    ],
                  ),
          ),
          action: 'New',
          onAction: () => edit(() => FoodEditor.show(c)),
        ),
      ],
    );
  }

  Future<void> _mealActions(BuildContext c, MealTemplate m) async {
    final choice = await _chooseAction(c, m.label);
    if (!c.mounted) return;
    if (choice == 'edit') {
      await MealEditor.show(c, existing: m);
    } else if (choice == 'delete' &&
        await confirmRemove(
          c,
          title: 'Delete ${m.label}?',
          body: 'Days you already logged keep their entries.',
        )) {
      await MyFoods.deleteMeal(await LocalDb.instance, m.key);
    }
  }

  Future<void> _foodActions(BuildContext c, Map<String, Object?> f) async {
    final label = (f['label'] ?? '').toString();
    final choice = await _chooseAction(c, label);
    if (!c.mounted) return;
    if (choice == 'edit') {
      await FoodEditor.show(c, existing: f);
    } else if (choice == 'delete' &&
        await confirmRemove(
          c,
          title: 'Delete $label?',
          body:
              'Days you already logged keep their entries; saved meals '
              'that use it skip it.',
        )) {
      await MyFoods.deleteFood(await LocalDb.instance, f['key'] as String);
    }
  }

  Future<String?> _chooseAction(BuildContext c, String title) =>
      showModalBottomSheet<String>(
        context: c,
        sheetAnimationStyle: sheetMotion(c),
        backgroundColor: P.of(c).card,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(R.xxl)),
        ),
        builder: (s) => Padding(
          padding: const EdgeInsets.all(S.x5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: F.head.copyWith(color: P.of(s).ink)),
              const SizedBox(height: S.x4),
              BigButton(
                'Edit',
                color: C.domFood,
                onTap: () => Navigator.of(s).pop('edit'),
              ),
              const SizedBox(height: S.x3),
              BigButton(
                'Delete',
                color: C.red,
                soft: true,
                onTap: () => Navigator.of(s).pop('delete'),
              ),
            ],
          ),
        ),
      );
}

// ══════════════════ ONE DAY ══════════════════

/// A day's log: calories left, macros, and the four meals. Used for today and
/// for any past day opened from History (so a missed entry can be added late).
class NutritionDayView extends StatefulWidget {
  const NutritionDayView({super.key, required this.date, this.onChanged});

  final String date;
  final VoidCallback? onChanged;

  @override
  State<NutritionDayView> createState() => _NutritionDayViewState();
}

class _NutritionDayViewState extends State<NutritionDayView>
    with RevisionReload {
  NutritionDay? _day;
  DayUpkeep? _upkeep;
  bool _failed = false;

  @override
  void reload() => _load();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(NutritionDayView old) {
    super.didUpdateWidget(old);
    if (old.date != widget.date) {
      _day = null;
      _load();
    }
  }

  Future<void> _load() async {
    final t = beginRead(#foodDay);
    final date = widget.date;
    final repo = repoOf(context);
    final pr = Profile.fromMap(context.read<AppState>().user);
    try {
      final db = await LocalDb.instance;
      final es = await NutritionDb.entriesForDay(db, date);
      final d = rollupDay(date, es, today: todayLabel());
      final upkeep = repo == null
          ? null
          : await DayUpkeep.read(repo, date, pr, eaten: d.kcal.value ?? 0);
      if (stillNewest(#foodDay, t)) {
        setState(() {
          _day = d;
          _upkeep = upkeep;
          _failed = false;
        });
      }
    } catch (_) {
      if (stillNewest(#foodDay, t)) setState(() => _failed = true);
    }
  }

  Future<void> _changed() async {
    await _load();
    widget.onChanged?.call();
  }

  /// In the evening, how much protein is still to eat against the target.
  /// Shown here only, never as a notification.
  String? _proteinLeft(NutritionDay d, Map<String, dynamic> profile) {
    final target = _targetOf(profile, 'protein_target');
    if (target == null || widget.date != todayLabel()) return null;
    if (DateTime.now().hour < 17) return null;
    final left = target - (d.protein.value ?? 0);
    if (left < 5) return null;
    return '${left.round()} g protein left today';
  }

  @override
  Widget build(BuildContext c) {
    final profile = c.watch<AppState>().user ?? const {};
    final d = _day;
    if (_failed) {
      return StatusCard(
        'Day could not load',
        'Try reading your saved food again.',
        fix: 'Retry',
        onFix: _load,
      );
    }
    if (d == null) return const Center(child: CircularProgressIndicator());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CalorieCard(
          eaten: d.kcal.value,
          goal: _targetOf(profile, 'kcal_target'),
        ),
        const SizedBox(height: S.x3),
        if (_upkeep != null)
          MaintenanceCard(_upkeep!, today: widget.date == todayLabel()),
        const SizedBox(height: S.x3),
        MacroCard(day: d, profile: profile),
        if (_proteinLeft(d, profile) case final line?) ...[
          const SizedBox(height: S.x2),
          Text(
            line,
            textAlign: TextAlign.center,
            style: F.cap.copyWith(color: P.of(c).on(C.red)),
          ),
        ],
        const SizedBox(height: S.x2),
        for (final m in kMeals)
          MealCard(
            date: widget.date,
            meal: m,
            entries: d.mealEntries(m),
            onChanged: _changed,
          ),
      ],
    );
  }
}

/// Goal, food, and what is left. Exercise never adds to the goal.
class CalorieCard extends StatelessWidget {
  const CalorieCard({super.key, required this.eaten, required this.goal});

  final double? eaten, goal;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final food = eaten ?? 0;
    final g = goal;
    final left = g == null ? null : g - food;
    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Calories',
            style: F.body.copyWith(color: p.ink, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: S.x3),
          // Wrap, not Row: at the largest text sizes the number and its label
          // stack instead of pushing off the card.
          Wrap(
            spacing: S.x2,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              Text(
                left == null ? '${food.round()}' : '${left.abs().round()}',
                style: F.n34.copyWith(
                  color: left != null && left < 0 ? p.on(C.red) : p.ink,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: S.x1),
                child: Text(
                  left == null
                      ? 'kcal eaten'
                      : (left < 0 ? 'kcal over' : 'kcal left'),
                  style: F.cap.copyWith(color: p.ink3),
                ),
              ),
            ],
          ),
          if (g != null && g > 0) ...[
            const SizedBox(height: S.x3),
            ProgressCard(
              'Food',
              '${food.round()}',
              'of ${g.round()} kcal goal',
              (food / g).clamp(0.0, 1.0).toDouble(),
              C.domFood,
            ),
          ] else ...[
            const SizedBox(height: S.x2),
            Text(
              'Set a calorie goal with the target button above.',
              style: F.cap.copyWith(color: p.ink3),
            ),
          ],
        ],
      ),
    );
  }
}

/// Protein, carbs, fat and fibre eaten against their targets.
class MacroCard extends StatelessWidget {
  const MacroCard({super.key, required this.day, required this.profile});

  final NutritionDay day;
  final Map<String, dynamic> profile;

  @override
  Widget build(BuildContext c) {
    final rows = [
      (
        'Protein',
        day.protein.value,
        _targetOf(profile, 'protein_target'),
        C.red,
      ),
      ('Carbs', day.carbs.value, _targetOf(profile, 'carbs_target'), C.blue),
      ('Fat', day.fat.value, _targetOf(profile, 'fat_target'), C.yellow),
      ('Fibre', day.fibre.value, _targetOf(profile, 'fibre_target'), C.green),
    ];
    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: S.x3),
            ProgressCard(
              rows[i].$1,
              '${(rows[i].$2 ?? 0).round()} g',
              rows[i].$3 == null ? '' : 'of ${rows[i].$3!.round()} g',
              rows[i].$3 == null || rows[i].$3! <= 0
                  ? 0
                  : ((rows[i].$2 ?? 0) / rows[i].$3!)
                        .clamp(0.0, 1.0)
                        .toDouble(),
              rows[i].$4,
            ),
          ],
          const SizedBox(height: S.x2),
          Text(
            'Logged macros only · blank values are not tracked',
            style: F.over.copyWith(color: P.of(c).ink3),
          ),
        ],
      ),
    );
  }
}

/// One meal: its total, its entries, and its own Add.
class MealSection extends StatelessWidget {
  const MealSection({
    super.key,
    required this.meal,
    required this.entries,
    required this.onAdd,
    this.onEntry,
    this.onRemove,
  });

  final String meal;
  final List<FoodEntry> entries;
  final VoidCallback onAdd;
  final ValueChanged<FoodEntry>? onEntry, onRemove;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final kcal = entries.fold<double>(0, (a, e) => a + (e.kcal ?? 0));
    return Section(
      entries.isEmpty
          ? mealName(meal)
          : '${mealName(meal)} · ${kcal.round()} kcal',
      Surface(
        pad: const EdgeInsets.symmetric(horizontal: S.x4),
        child: entries.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: S.x3),
                child: Text(
                  'Nothing yet',
                  style: F.cap.copyWith(color: p.ink3),
                ),
              )
            : Column(
                children: [
                  for (final e in entries)
                    PickRow(
                      e.quantity == null
                          ? e.label
                          : '${e.label} · ${portionText(e.quantity!, e.unit)}',
                      macroLine(
                        kcal: e.kcal,
                        protein: e.proteinG,
                        carbs: e.carbsG,
                        fat: e.fatG,
                        fibre: e.fibreG,
                      ),
                      trailing: LucideIcons.x,
                      onTap: onEntry == null ? null : () => onEntry!(e),
                    ),
                ],
              ),
      ),
      action: 'Add',
      onAction: onAdd,
    );
  }
}

/// Closed months do not read their daily entries until opened.
class _FoodHistoryMonth extends StatefulWidget {
  const _FoodHistoryMonth({
    super.key,
    required this.month,
    required this.profile,
    required this.runs,
    required this.onChanged,
  });
  final String month;
  final Map<String, dynamic> profile;
  final List<RunSummary> runs;
  final VoidCallback onChanged;

  @override
  State<_FoodHistoryMonth> createState() => _FoodHistoryMonthState();
}

class _FoodHistoryMonthState extends State<_FoodHistoryMonth>
    with RevisionReload {
  late bool _open = widget.month == todayLabel().substring(0, 7);
  NutritionWindow? _window;
  Map<String, double?> _maintenance = const {}, _acsmMaintenance = const {};
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    if (_open) _load();
  }

  @override
  void reload() {
    if (_open) {
      _load();
    } else {
      _window = null;
    }
  }

  Future<void> _load() async {
    final t = beginRead(#month);
    try {
      final win = await NutritionDb.month(await LocalDb.instance, widget.month);
      final pr = Profile.fromMap(widget.profile);
      final maintenance = <String, double?>{},
          acsmMaintenance = <String, double?>{};
      for (final d in win.days.where((d) => d.logged)) {
        if (!mounted || !stillNewest(#month, t)) return;
        final repo = repoOf(context);
        if (repo != null) {
          final upkeep = await DayUpkeep.read(
            repo,
            d.date,
            pr,
            eaten: d.kcal.value ?? 0,
            runs: widget.runs,
          );
          maintenance[d.date] = upkeep.parts?.total;
          acsmMaintenance[d.date] = upkeep.acsmParts?.total;
        }
      }
      if (stillNewest(#month, t)) {
        setState(() {
          _window = win;
          _maintenance = maintenance;
          _acsmMaintenance = acsmMaintenance;
          _failed = false;
        });
      }
    } catch (_) {
      if (stillNewest(#month, t)) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final days = _window?.days
        .where((d) => d.logged)
        .toList()
        .reversed
        .toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: S.x3),
      child: Surface(
        pad: const EdgeInsets.symmetric(horizontal: S.x4),
        child: ExpansionTile(
          key: PageStorageKey('food-${widget.month}'),
          initiallyExpanded: _open,
          tilePadding: EdgeInsets.zero,
          shape: const Border(),
          collapsedShape: const Border(),
          iconColor: p.on(C.domFood),
          collapsedIconColor: p.ink3,
          title: Text(
            MaterialLocalizations.of(
              c,
            ).formatMonthYear(DateTime.parse('${widget.month}-01')),
            style: F.body.copyWith(color: p.ink, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            days == null
                ? 'Browse daily entries'
                : '${days.length} day${days.length == 1 ? '' : 's'} logged · ${_window!.counted.length} completed',
            style: F.over.copyWith(color: p.ink3),
          ),
          onExpansionChanged: (open) {
            setState(() => _open = open);
            if (open && (_window == null || _failed)) _load();
          },
          children: [
            if (_failed)
              StatusCard(
                'Month could not load',
                'Try reading it again.',
                fix: 'Retry',
                onFix: _load,
              )
            else if (days == null)
              const Padding(
                padding: EdgeInsets.all(S.x4),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (days.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: S.x4),
                child: Text(
                  'No food logged this month yet.',
                  style: F.cap.copyWith(color: p.ink3),
                ),
              )
            else
              for (final d in days)
                _HistoryRow(
                  day: d,
                  goal: _targetOf(widget.profile, 'kcal_target'),
                  maintenance: _maintenance[d.date],
                  acsmMaintenance: _acsmMaintenance[d.date],
                  onTap: () async {
                    await Navigator.of(c).push(
                      MaterialPageRoute<void>(
                        builder: (routeContext) =>
                            detailScaffold(routeContext, dayTitle(d.date), [
                              NutritionDayView(
                                date: d.date,
                                onChanged: widget.onChanged,
                              ),
                            ]),
                      ),
                    );
                    if (mounted) _load();
                  },
                ),
          ],
        ),
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.day,
    required this.goal,
    this.maintenance,
    this.acsmMaintenance,
    this.onTap,
  });

  final NutritionDay day;
  final double? goal, maintenance, acsmMaintenance;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final kcal = day.kcal.value;
    final g = goal;
    final protein = day.protein.value;
    return Pressable(
      onTap: onTap,
      semanticLabel: prettyDay(day.date),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: S.x3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: S.x3,
              runSpacing: S.x1,
              children: [
                Text(prettyDay(day.date), style: F.body.copyWith(color: p.ink)),
                Text(
                  kcal == null ? '–' : '${kcal.round()} kcal',
                  style: F.body.copyWith(
                    color: g != null && kcal != null && kcal > g
                        ? p.on(C.red)
                        : p.ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            Text(
              [
                if (protein != null) 'Protein ${protein.round()} g',
                if (day.state == DayLogState.inProgress) 'So far',
                if (day.state == DayLogState.partial) 'Partial log',
                if (maintenance != null &&
                    kcal != null &&
                    day.countsTowardAverages)
                  'Budget ${thousands(maintenance)} · ACSM ${acsmMaintenance == null ? '—' : thousands(acsmMaintenance)} · '
                      '${thousands((kcal - maintenance!).abs())} '
                      '${kcal > maintenance! ? 'over' : 'under'}',
              ].join(' · '),
              style: F.cap.copyWith(color: p.ink3),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════ GOALS ══════════════════

/// Edit the five targets. Shows the measured daily burn as a reference — a
/// starting point for a calorie goal, never added to it.
Future<bool> editNutritionGoals(BuildContext c) async {
  final app = c.read<AppState>();
  if (!c.mounted) return false;
  final saved = await showModalBottomSheet<bool>(
    context: c,
    isScrollControlled: true,
    useSafeArea: true,
    sheetAnimationStyle: sheetMotion(c),
    backgroundColor: P.of(c).card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(R.xxl)),
    ),
    builder: (_) => _NutritionGoalsSheet(app),
  );
  return saved == true;
}

class _NutritionGoalsSheet extends StatefulWidget {
  const _NutritionGoalsSheet(this.app);
  final AppState app;
  @override
  State<_NutritionGoalsSheet> createState() => _NutritionGoalsSheetState();
}

class _NutritionGoalsSheetState extends State<_NutritionGoalsSheet> {
  late final Map<String, TextEditingController> ctrls;
  bool busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    ctrls = {
      for (final t in kNutritionTargets)
        t.$1: TextEditingController(
          text:
              _targetOf(
                widget.app.user ?? const {},
                t.$1,
              )?.round().toString() ??
              '',
        ),
    };
  }

  @override
  void dispose() {
    for (final t in ctrls.values) {
      t.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (busy) return;
    final typed = {
      for (final e in ctrls.entries)
        e.key: Typed.of(e.value.text, nonNegative: true),
    };
    final bad = [
      for (final t in kNutritionTargets)
        if (typed[t.$1]!.bad) t.$2,
    ];
    if (bad.isNotEmpty) {
      setState(
        () => error =
            '${bad.join(', ')}: enter a non-negative number, or leave blank.',
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.app.updateProfile({
        for (final e in typed.entries) e.key: e.value.value,
      });
      widget.app.bumpInsights();
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error =
              'Targets could not save. Your values are still here; try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext s) => InputSheet(
    children: [
      Text('Daily targets', style: F.head.copyWith(color: P.of(s).ink)),
      const SizedBox(height: S.x2),
      Text(
        'Set once. Your calorie goal stays exactly what you type.',
        style: F.cap.copyWith(color: P.of(s).ink3),
      ),
      const SizedBox(height: S.x4),
      for (final t in kNutritionTargets) ...[
        OsTextField(
          controller: ctrls[t.$1]!,
          label: '${t.$2} (${t.$3})',
          hint: 'none',
          keyboard: const TextInputType.numberWithOptions(decimal: true),
        ),
        const SizedBox(height: S.x3),
      ],
      if (error != null) ...[
        Text(error!, style: F.cap.copyWith(color: P.of(s).on(C.red))),
        const SizedBox(height: S.x3),
      ],
      BigButton(
        busy ? 'Saving…' : 'Save',
        color: C.domFood,
        onTap: busy ? null : _save,
      ),
    ],
  );
}

// ══════════════════ MAINTENANCE ══════════════════

/// Steps for [date]: today's live count, or the stored day's.
Future<num?> stepsOn(BuildContext c, String date) async {
  final repo = repoOf(c);
  if (repo == null) return null;
  try {
    if (date == todayLabel()) {
      final daily = (await repo.getToday())['daily'];
      return metricOf(daily is Map ? daily['steps'] : null).value;
    }
    final day = await repo.getDaySteps(date);
    return (day['day_total'] as num?) ?? (day['total'] as num?);
  } catch (_) {}
  return null;
}

/// Every run this phone holds, for the Running row. Empty when unreadable.
Future<List<RunSummary>> _allRuns(LocalRepository? repo) async =>
    repo == null ? const [] : loadRuns(repo);

/// What one day's maintenance is made of: resting energy, the steps walked
/// outside runs, the runs themselves (Method 1, by distance), and 10% of the
/// food logged. A floor: lifts and other workouts are not added.
/// The day's maintenance as a floor, shown beside the food and never changing
/// the calorie goal. Tap for what each part is.
class MaintenanceCard extends StatelessWidget {
  const MaintenanceCard(this.upkeep, {super.key, this.today = false});

  final DayUpkeep upkeep;
  final bool today;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final m = upkeep.parts;
    if (m == null) {
      return const StatusCard(
        'Maintenance needs your profile',
        'Add your age, height and weight in Settings → Profile.',
        icon: LucideIcons.flame,
      );
    }
    final eaten = upkeep.eaten;
    final diff = eaten - m.total;
    return Surface(
      onTap: () => showMaintenance(c, upkeep, today: today),
      semanticLabel:
          'Maintenance ${thousands(m.total)} kcal. Shows how it is '
          'worked out.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Daily maintenance',
                  style: F.body.copyWith(
                    color: p.ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(LucideIcons.info, size: 16, color: p.ink3),
            ],
          ),
          const SizedBox(height: S.x2),
          CaloriePair(
            budget: m.total,
            acsm: upkeep.acsmParts?.total,
            note:
                'Whole-day resting energy + movement and food logged. ${upkeep.distanceSource}.',
          ),
          const SizedBox(height: S.x3),
          InlineMetrics([
            ('BMR', thousands(m.bmr), C.steps),
            ('STEPS', thousands(m.steps), C.green),
            if (upkeep.runs.count > 0) ('RUNNING', thousands(m.run), C.run),
            ('FOOD', thousands(m.food), C.domFood),
          ]),
          if (eaten > 0) ...[
            const SizedBox(height: S.x3),
            Text(
              'Eaten ${thousands(eaten)} · ${thousands(diff.abs())} '
              '${diff > 0 ? 'over' : 'under'} Budget maintenance',
              style: F.cap.copyWith(color: p.ink2),
            ),
          ],
        ],
      ),
    );
  }
}

/// What each part of maintenance is and the numbers it came from, one short
/// line each.
Future<void> showMaintenance(
  BuildContext c,
  DayUpkeep u, {
  bool today = false,
}) => showModalBottomSheet<void>(
  context: c,
  sheetAnimationStyle: sheetMotion(c),
  backgroundColor: P.of(c).card,
  isScrollControlled: true,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(R.xxl)),
  ),
  builder: (s) => _MaintenanceDetails(u, today: today),
);

class _MaintenanceDetails extends StatefulWidget {
  const _MaintenanceDetails(this.initial, {this.today = false});
  final DayUpkeep initial;
  final bool today;
  @override
  State<_MaintenanceDetails> createState() => _MaintenanceDetailsState();
}

class _MaintenanceDetailsState extends State<_MaintenanceDetails>
    with RevisionReload {
  late DayUpkeep _upkeep = widget.initial;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void reload() => _load();
  Future<void> _load() async {
    final repo = repoOf(context);
    final date = widget.today ? todayLabel() : widget.initial.date;
    if (repo == null || date == null) return;
    final t = beginRead(#maintenance);
    try {
      final u = await DayUpkeep.read(
        repo,
        date,
        Profile.fromMap(context.read<AppState>().user),
      );
      if (stillNewest(#maintenance, t)) {
        setState(() {
          _upkeep = u;
          _error = null;
        });
      }
    } catch (_) {
      if (stillNewest(#maintenance, t)) {
        setState(
          () => _error =
              'Update could not load. Showing the last successful calculation.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext c) =>
      _maintenanceContents(c, _upkeep, widget.today, error: _error);
}

Widget _maintenanceContents(
  BuildContext c,
  DayUpkeep u,
  bool today, {
  String? error,
}) {
  final m = u.parts;
  if (m == null) {
    return const StatusCard(
      'Maintenance needs your profile',
      'Add age, height and weight.',
    );
  }
  final pr = u.profile;
  String kg(double? w) => w == null
      ? ''
      : (w == w.roundToDouble()
            ? '${w.round()} kg'
            : '${w.toStringAsFixed(1)} kg');
  final walked = u.walkedSteps;
  final rows = <(String, double, String)>[
    (
      'Resting',
      m.bmr,
      'What your body burns at rest over a whole day, from age '
          '${pr.ageYears}, ${pr.heightCm?.toStringAsFixed(1)} cm and '
          '${kg(pr.weightKg)}.',
    ),
    (
      'Steps',
      m.steps,
      walked == null
          ? 'No steps counted yet.'
          : u.runs.steps > 0
          ? '${thousands(walked)} steps outside your '
                '${u.runs.count == 1 ? 'run' : 'runs'}, at ${kg(pr.weightKg)}.'
          : '${thousands(walked)} steps at ${kg(pr.weightKg)}.',
    ),
    if (u.runs.count > 0)
      (
        'Running',
        m.run,
        '${u.runs.km.toStringAsFixed(2)} km in ${u.runs.count} '
            '${u.runs.count == 1 ? 'run' : 'runs'}: conservative distance energy '
            'costs using each workout’s recorded weight.',
      ),
    (
      'Food',
      m.food,
      u.eaten > 0
          ? '10% of the ${thousands(u.eaten)} kcal you logged goes to digesting '
                'it.'
          : 'Nothing logged yet. 10% of what you log is added.',
    ),
  ];
  final p = P.of(c);
  return SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(S.x5),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (error != null)
            Text(error, style: F.cap.copyWith(color: p.on(C.red))),
          Text('Daily maintenance', style: F.head.copyWith(color: p.ink)),
          const SizedBox(height: S.x1),
          CaloriePair(
            budget: m.total,
            acsm: u.acsmParts?.total,
            note:
                'Two estimates, not a guaranteed lower/upper range. ${u.distanceSource}.',
          ),
          if (u.acsmParts case final a?) ...[
            const SizedBox(height: S.x3),
            Text(
              'ACSM movement: walking ${thousands(a.steps)} kcal · running ${thousands(a.run)} kcal. '
              'Resting and food are identical in both columns.',
              style: F.cap.copyWith(color: p.ink2),
            ),
          ],
          const SizedBox(height: S.x3),
          Text('Budget breakdown', style: F.head.copyWith(color: p.ink)),
          for (final (name, kcal, why) in rows) ...[
            const SizedBox(height: S.x4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: F.body.copyWith(
                      color: p.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '${thousands(kcal)} kcal',
                  style: F.n17.copyWith(color: p.ink),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(why, style: F.cap.copyWith(color: p.ink2, height: 1.4)),
          ],
          const SizedBox(height: S.x5),
          Text(
            'Conservative estimate: a whole day’s BMR, plus movement and '
            'food logged so far. Active calories are energy above resting; '
            'resting calories are already included in BMR. Walking workouts '
            'are included through steps. HR estimates and other workouts are '
            'not added. Estimates have individual uncertainty.'
            '${u.overlapUnknown ? " Run-step overlap is unavailable, so movement uses the larger estimate without adding both." : ""}',
            style: F.cap.copyWith(color: p.ink3, height: 1.4),
          ),
        ],
      ),
    ),
  );
}
