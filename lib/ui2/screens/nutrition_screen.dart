// Nutrition — a food log in the MyFitnessPal shape, kept simple.
//
//   · Calories left = your goal − food. Exercise is NOT added back: the goal
//     is the number you chose, and a wrist estimate of burn is not precise
//     enough to spend.
//   · Protein, carbs, fat and fibre against your own targets.
//   · Breakfast, lunch, dinner and snacks, each with its own Add — from saved
//     meals, from your foods by weight, or quick add / barcode.
//   · Maintenance: what the day cost as a floor (BMR + steps + runs + digestion of the
//     food logged), shown beside the food, never changing the goal.
//   · History: a trailing chart and calendar-month groups of retained entries.
//   · Foods: the foods and saved meals you log from.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../data/db.dart';
import '../../data/body_log.dart' show BodyLogDb;
import '../../data/day_label.dart';
import '../../compute/profile.dart' show Profile;
import '../../compute/day_upkeep.dart';
export '../../compute/day_upkeep.dart' show DayUpkeep;
import '../../data/local_repository.dart';
import '../../data/nutrition_store.dart';
import '../../data/food_day_reminder.dart' show FoodDayReminder;
import '../../gps/run_history.dart';
import '../../state/app_state.dart';
import '../ui2.dart';
import '../energy_comparison.dart';
import 'food_diary.dart';
import 'progress_routes.dart';
import 'food_day_copy.dart';
import 'food_picker.dart';
import 'home_screen.dart'
    show metricOf, prettyDay, pullToRefresh, repoOf, thousands;
import 'journal_compose.dart' show OsTextField;
import 'metric_detail.dart' show detailScaffold;
import 'food_calendar.dart' show FoodWeekStrip, showFoodCalendar;

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

  void _reselected() {
    if (shellReselect.value.$1 != ShellDomain.nutrition || !mounted) return;
    if (_tab != 0 || _shownDay != null) {
      setState(() => (_tab = 0, _shownDay = null));
    }
  }

  @override
  void dispose() {
    shellReselect.removeListener(_reselected);
    _foodQuery.dispose();
    super.dispose();
  }

  /// Search over Foods (saved meals and My foods). While it holds text the
  /// lists show matches; dragging preserves the hidden items’ positions.
  late final _foodQuery = TextEditingController()
    ..addListener(() => setState(() {}));

  /// The Foods tab's category filter; null is All.
  String? _foodCat;

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
  bool _editingLibrary = false;

  /// The day the Today tab shows; null follows the calendar day.
  String? _shownDay;

  /// Read on every use, never captured once: the shell keeps this tab alive,
  /// so a field initialiser would still be yesterday after midnight.
  String get _date => todayLabel();

  @override
  void initState() {
    super.initState();
    shellReselect.addListener(_reselected);
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
        calculation: true,
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
        // The previous estimates stay on screen until the new ones land
        // (Build 90 phone review: clearing them here made the This week card
        // and the chart's maintenance lines vanish on every reload).
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
            // Build 89: the date of the day shown, opening a month calendar.
            kicker: prettyDay(_tab == 0 ? (_shownDay ?? _date) : _date),
            onKicker: _tab == 0
                ? () async {
                    final d = await showFoodCalendar(c, _shownDay ?? _date);
                    if (d != null && mounted) {
                      setState(() => _shownDay = d == _date ? null : d);
                    }
                  }
                : null,
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
          // Build 90: tighter gaps above the diary so the first meal clears
          // the tab bar at ordinary text on a 390 × 844 phone.
          const SizedBox(height: S.x2),
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
          // Build 89: the week of days, each marked counted / logged /
          // empty, in place of ‹ Today ›. Older days: the date above.
          FoodWeekStrip(date: day, onDay: go),
          if (day != _date)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => go(_date),
                child: Text(
                  'Back to today',
                  style: F.cap.copyWith(
                    color: P.of(c).ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          const SizedBox(height: S.x2),
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
      return '${dayTitle(d.date)}${d.state == DayLogState.inProgress ? ' · so far' : ''}\n${[if (mm != null) 'Budget ${thousands(mm)}', if (acsm[i] != null) 'Movement estimate ${thousands(acsm[i])}', e == null ? 'no food logged' : 'ate ${thousands(e)}', if (mm != null && e != null) '${e > mm ? '+' : '−'}${thousands((e - mm).abs())}'].join(' · ')}';
    }

    final pick = _histPick;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _weightCard(c, p, pr, days),
        if (_calorieLoading && _maintenance.isEmpty)
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
                // Build 90 review: each number once, each label saying what it
                // is. The Budget/Movement pair under it repeated AVG BUDGET
                // without saying it was an average.
                InlineMetrics([
                  (
                    deficit >= 0 ? 'WEEK DEFICIT' : 'WEEK SURPLUS',
                    thousands(deficit.abs()),
                    deficit >= 0 ? C.green : C.red,
                  ),
                  ('AVG EATEN', thousands(eatSum / counted), C.domFood),
                  ('AVG BUDGET', thousands(mSum / counted), C.steps),
                ]),
                const SizedBox(height: S.x2),
                Text(
                  [
                    'Per day on $counted completed '
                        'day${counted == 1 ? '' : 's'}; the deficit is their total.',
                    if (acsmCount == counted)
                      'Movement estimate averages '
                          '${thousands(acsmSum / counted)} kcal a day on the same days.',
                    'Today and detectably incomplete logs are excluded.',
                  ].join(' '),
                  style: F.cap.copyWith(color: p.ink2, height: 1.4),
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
                ('Movement estimate', p.on(C.teal)),
                ('Eaten', p.on(C.domFood)),
              ],
              xLabels: const ['30 days ago', 'Today'],
              child: Scrubber(
                // Three lines on one axis; point i sits at i/(n-1).
                value: pick == null || days.length < 2
                    ? null
                    : pick / (days.length - 1),
                step: days.length < 2 ? 1 : 1 / (days.length - 1),
                label: 'Maintenance and eaten by day',
                describe: (v) => says(
                  (v * (days.length - 1)).round().clamp(0, days.length - 1),
                ),
                onChanged: (v) => setState(
                  () => _histPick = (v * (days.length - 1)).round().clamp(
                    0,
                    days.length - 1,
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: LineChart(
                          m,
                          p.on(C.steps),
                          fill: false,
                          axis: axis,
                          cursor: pick,
                          cursorInk: p.ink,
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
          'Complete: a day you mark complete, with calories on every entry. Macro coverage is separate.',
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
                    Text(
                      w.isEmpty
                          ? 'Profile weight · not a weigh-in'
                          : 'Weight · ${prettyDay(w.last.date)}',
                      style: F.over.copyWith(color: p.ink3),
                    ),
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
                      ? 'Needs 14 days of food logs marked complete and 8 weigh-ins, 3 in each half.'
                      : '${coverage.complete}/${coverage.days} complete food days · needs 14 days and 8 weigh-ins, 3 in each half.')
                : !measured.shown
                ? 'Weight is too uneven to estimate maintenance yet '
                      '(±${thousands(measured.halfRange)} kcal). More weigh-ins narrow it.'
                : 'Estimated maintenance from food and weight: '
                      '${thousands(measured.displayRange.low)}–${thousands(measured.displayRange.high)} kcal · '
                      '${measured.kgPerWeek.abs() < 0.05 ? 'weight about steady' : '${measured.kgPerWeek < 0 ? 'losing' : 'gaining'} ${measured.kgPerWeek.abs().toStringAsFixed(2)} kg a week'} '
                      '(${measured.days} days, ${measured.weighIns} weigh-ins)'
                      '${measured.shortWindow ? ' · short-window conversion estimate' : ''}',
            style: F.cap.copyWith(
              color: measured == null || !measured.shown ? p.ink3 : p.ink2,
            ),
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
      final date = todayLabel();
      await BodyWeight.put(date, v, 'kg');
      // Body owns the day's first reading. Later weigh-ins stay in its history
      // and must not replace the canonical calculation weight.
      final daily = await BodyLogDb.weightOn(date);
      if (daily != null) await app.updateProfile({'weight_kg': daily.kg});
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
      if (_editingLibrary) return;
      _editingLibrary = true;
      try {
        await f();
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
      } finally {
        _editingLibrary = false;
      }
      if (mounted) await _load();
    }

    final q = _foodQuery.text.trim();
    // A category no food carries any more (it was edited away) is All.
    if (_foodCat != null && !foodCategoriesIn(_foods).contains(_foodCat)) {
      _foodCat = null;
    }
    // Matches can be dragged within their slots in the full saved order.
    final searching = q.isNotEmpty || _foodCat != null;
    final defs = {for (final f in _foods) f['key'] as String: f};
    final meals = searching
        ? [
            for (final m in _meals)
              if (nameMatches(m.label, q)) m,
          ]
        : _meals;
    final foods = searching
        ? [
            for (final f in foodsIn(_foods, _foodCat))
              if (q.isEmpty ||
                  nameMatches(f['label'], q) ||
                  nameMatches(f['brand'], q))
                f,
          ]
        : _foods;
    Widget mealTile(MealTemplate m) => SwipeDelete(
      key: ValueKey('meal-${m.key}'),
      onDelete: () => edit(() => _deleteMeal(c, m)),
      child: PickRow(
        m.label,
        mealSummary(m, defs),
        trailing: LucideIcons.chevronRight,
        onTap: () => edit(() => MealEditor.show(c, existing: m)),
      ),
    );
    Widget foodTile(Map<String, Object?> f) => SwipeDelete(
      key: ValueKey('food-${f['key']}'),
      onDelete: () => edit(() => _deleteFood(c, f)),
      child: PickRow(
        (f['label'] ?? '').toString(),
        foodServingLine(f),
        trailing: LucideIcons.chevronRight,
        onTap: () => edit(() => FoodEditor.show(c, existing: f)),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_meals.length + _foods.length > 0) ...[
          OsTextField(
            controller: _foodQuery,
            label: 'Search',
            clearable: true,
            hint: 'Oats, eggs, breakfast…',
          ),
          const SizedBox(height: S.x2),
          FoodCategoryFilter(
            foods: _foods,
            selected: _foodCat,
            onSelect: (cat) => setState(() => _foodCat = cat),
          ),
          if (foodLabelsIn(_foods).isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Pressable(
                semanticLabel: 'Manage labels',
                onTap: () => edit(() => _manageLabels(c)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: S.x2),
                  child: Text(
                    'Manage labels',
                    style: F.cap.copyWith(color: p.ink2),
                  ),
                ),
              ),
            ),
        ],
        // Saved meals carry no category, so a category filter shows foods only.
        if (_foodCat == null)
          Section(
            'Saved meals',
            Surface(
              pad: const EdgeInsets.symmetric(horizontal: S.x4),
              child: meals.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: S.x4),
                      child: Text(
                        searching
                            ? 'No matches'
                            : 'A saved meal is your usual breakfast or lunch, logged in one tap.',
                        style: F.cap.copyWith(color: p.ink3),
                      ),
                    )
                  : DragList(
                      length: meals.length,
                      onReorder: (from, to) => edit(() async {
                        final arranged = reorderedVisible(
                          _meals,
                          meals,
                          from,
                          to,
                          (m) => m.key,
                        );
                        final keys = [for (final m in arranged) m.key];
                        setState(() => _meals = arranged);
                        await MyFoods.reorderMeals(
                          await LocalDb.instance,
                          keys,
                        );
                        return null;
                      }),
                      itemBuilder: (_, i) => mealTile(meals[i]),
                    ),
            ),
            action: 'New',
            onAction: () => edit(() => MealEditor.show(c)),
          ),
        Section(
          'My foods',
          Surface(
            pad: const EdgeInsets.symmetric(horizontal: S.x4),
            child: foods.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: S.x4),
                    child: Text(
                      searching
                          ? 'No matches'
                          : 'Add a food once from its label; log any amount after.',
                      style: F.cap.copyWith(color: p.ink3),
                    ),
                  )
                : DragList(
                    length: foods.length,
                    onReorder: (from, to) => edit(() async {
                      final arranged = reorderedVisible(
                        _foods,
                        foods,
                        from,
                        to,
                        (f) => f['key'] as String,
                      );
                      final keys = [
                        for (final f in arranged) f['key'] as String,
                      ];
                      setState(() => _foods = arranged);
                      await MyFoods.reorderFoods(await LocalDb.instance, keys);
                      return null;
                    }),
                    itemBuilder: (_, i) => foodTile(foods[i]),
                  ),
          ),
          actions: Wrap(
            spacing: S.x2,
            children: [
              for (final label in const ['Scan', 'New'])
                Pressable(
                  semanticLabel: label == 'Scan'
                      ? 'Scan a food into My foods'
                      : 'Create a food',
                  onTap: () => edit(
                    () => label == 'Scan'
                        ? FoodEditor.scanAndSave(c)
                        : FoodEditor.show(c),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: S.x2,
                      vertical: S.x2,
                    ),
                    child: Text(
                      label,
                      style: F.cap.copyWith(
                        color: p.on(C.blue),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // Tap opens the editor; a swipe either way deletes after this confirm.
  Future<void> _deleteMeal(BuildContext c, MealTemplate m) async {
    if (await confirmRemove(
      c,
      title: 'Delete ${m.label}?',
      body: 'Days you already logged keep their entries.',
    )) {
      await MyFoods.deleteMeal(await LocalDb.instance, m.key);
    }
  }

  Future<void> _deleteFood(BuildContext c, Map<String, Object?> f) async {
    final label = (f['label'] ?? '').toString();
    if (await confirmRemove(
      c,
      title: 'Delete $label?',
      body:
          'Days you already logged keep their entries; saved meals '
          'that use it skip it.',
    )) {
      await MyFoods.deleteFood(await LocalDb.instance, f['key'] as String);
    }
  }

  /// Rename, merge (rename onto an existing label) or clear a label across
  /// every food carrying it (B86-08).
  Future<void> _manageLabels(BuildContext c) async {
    final labels = foodLabelsIn(_foods);
    final picked = await showModalBottomSheet<String>(
      context: c,
      useSafeArea: true,
      sheetAnimationStyle: sheetMotion(c),
      backgroundColor: P.of(c).card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(R.xxl)),
      ),
      builder: (s) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(S.x5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Labels', style: F.head.copyWith(color: P.of(s).ink)),
              const SizedBox(height: S.x2),
              Text(
                "Rename one, give it another label's name to merge them, or "
                'remove it from its foods with the bin.',
                style: F.cap.copyWith(color: P.of(s).ink3),
              ),
              const SizedBox(height: S.x3),
              for (final l in labels)
                Row(
                  children: [
                    Expanded(
                      child: PickRow(l, () {
                        final n = foodsIn(_foods, l).length;
                        return '$n ${n == 1 ? 'food' : 'foods'}';
                      }(), onTap: () => Navigator.of(s).pop('rename:$l')),
                    ),
                    // Build 89: remove straight from the list, left of the
                    // pencil, instead of renaming to an empty name.
                    IconButton(
                      tooltip: 'Remove $l',
                      onPressed: () => Navigator.of(s).pop('remove:$l'),
                      icon: Icon(LucideIcons.trash2, color: P.of(s).ink2),
                    ),
                    IconButton(
                      tooltip: 'Rename $l',
                      onPressed: () => Navigator.of(s).pop('rename:$l'),
                      icon: Icon(LucideIcons.pencil, color: P.of(s).ink2),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !c.mounted) return;
    final pick = picked.substring(picked.indexOf(':') + 1);
    if (picked.startsWith('remove:')) {
      final n = foodsIn(_foods, pick).length;
      if (await confirmRemove(
        c,
        title: 'Remove "$pick"?',
        body:
            'It comes off ${n == 1 ? 'the 1 food' : 'all $n foods'} that '
            'carry it. The foods themselves stay.',
      )) {
        await NutritionDb.renameFoodLabel(await LocalDb.instance, pick, '');
      }
      return;
    }
    final to = await askText(
      c,
      'Rename $pick',
      'Label (empty removes it)',
      pick,
      validate: (v) =>
          v.trim().length > 30 ? 'Use 30 characters or fewer.' : null,
    );
    if (to == null) return;
    // Merging keeps the existing label's spelling.
    final target = labels.firstWhere(
      (l) => labelKey(l) == labelKey(to) && labelKey(l) != labelKey(pick),
      orElse: () => to.trim(),
    );
    await NutritionDb.renameFoodLabel(await LocalDb.instance, pick, target);
  }
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

  /// The user's own complete/incomplete mark for this day; null is automatic.
  String? _mark;

  /// Saved foods last logged, for one-tap "Log again".
  List<({Map<String, Object?> def, double amount, String unit, double base})>
  _recent = const [];

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
      final mark = (await NutritionDb.dayMarks(db, date))[date];
      final recent = await NutritionDb.recentFoods(db);
      final d = rollupDay(date, es, today: todayLabel(), mark: mark);
      final upkeep = repo == null
          ? null
          : await DayUpkeep.read(repo, date, pr, eaten: d.kcal.value ?? 0);
      if (stillNewest(#foodDay, t)) {
        setState(() {
          _day = d;
          _upkeep = upkeep;
          _failed = false;
          _mark = mark;
          _recent = recent;
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

  /// The foods you log most, at the portion you last had, one tap each into
  /// the meal for this time of day — with Undo, because one tap is easy to
  /// make by accident.
  Future<void> _copyDay(BuildContext c) async {
    final from = await pickDate(c, shiftDay(widget.date, -1));
    if (from == null || !c.mounted) return;
    try {
      final entries = await NutritionDb.entriesForDay(
        await LocalDb.instance,
        from,
      );
      if (!c.mounted) return;
      final copied = await reviewFoodDayCopy(
        c,
        from: from,
        to: widget.date,
        entries: entries,
        onLog: (reviewed) async {
          await NutritionDb.logDayCopy(
            await LocalDb.instance,
            date: widget.date,
            reviewed: reviewed,
          );
        },
      );
      if (copied == true && mounted) await _changed();
    } catch (_) {
      if (c.mounted)
        ScaffoldMessenger.maybeOf(c)?.showSnackBar(
          const SnackBar(
            content: Text('Food could not load. Try copying again.'),
          ),
        );
    }
  }

  Widget _logAgain(BuildContext c, String meal) {
    final p = P.of(c);
    Future<void> log(
      ({Map<String, Object?> def, double amount, String unit, double base}) r,
    ) async {
      final db = await LocalDb.instance;
      final at = foodEntryTime(widget.date, meal);
      final e = entryFromFood(
        r.def,
        r.base,
        id: NutritionDb.newId(),
        date: widget.date,
        meal: meal,
        atTs: at.millisecondsSinceEpoch ~/ 1000,
        amount: r.amount,
        unit: r.unit,
      );
      await NutritionDb.put(db, e);
      await _changed();
      if (!c.mounted) return;
      final m = ScaffoldMessenger.maybeOf(c);
      m?.hideCurrentSnackBar();
      m?.showSnackBar(
        SnackBar(
          content: Text('${e.label} added to ${mealName(meal)}'),
          duration: Motion.notice * 2,
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () async {
              await NutritionDb.delete(await LocalDb.instance, e.id);
              await _changed();
            },
          ),
        ),
      );
    }

    if (bigText(c))
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Log again', style: F.body.copyWith(color: p.ink)),
          for (final r in _recent)
            TextButton.icon(
              onPressed: () => log(r),
              icon: const Icon(LucideIcons.plus),
              label: Text(
                '${r.def['label']} · ${portionText(r.amount, r.unit)}',
              ),
            ),
        ],
      );
    return Padding(
      padding: const EdgeInsets.only(top: S.x3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'LOG AGAIN · ${mealName(meal).toUpperCase()}',
            style: F.section.copyWith(color: p.ink3),
          ),
          const SizedBox(height: S.x2),
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _recent.length,
              separatorBuilder: (_, _) => const SizedBox(width: S.x2),
              itemBuilder: (_, i) {
                final r = _recent[i];
                final label = (r.def['label'] ?? '').toString();
                return Pressable(
                  semanticLabel:
                      'Log $label again, ${portionText(r.amount, r.unit)}',
                  onTap: () => log(r),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: S.x3),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: p.card2,
                      borderRadius: R.rPill,
                      border: Border.all(color: p.edge),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          LucideIcons.plus,
                          size: 14,
                          color: p.on(C.domFood),
                        ),
                        const SizedBox(width: S.x1),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 160),
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: F.cap.copyWith(color: p.ink),
                          ),
                        ),
                        const SizedBox(width: S.x1),
                        Text(
                          portionText(r.amount, r.unit),
                          style: F.over.copyWith(color: p.ink3),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Whether this day counts in the weekly averages. From Build 89 a past
  /// day counts on its own once it looks finished (half the calorie goal,
  /// every food with calories); a mark always wins either way.
  Widget _completeLine(BuildContext c, NutritionDay d) {
    final p = P.of(c);
    final say = switch (d.state) {
      DayLogState.complete =>
        _mark == 'complete' ? 'Marked complete' : 'Counted automatically',
      DayLogState.inProgress => 'Today · in progress',
      _ =>
        _mark == 'incomplete'
            ? 'Marked as missing food · left out of averages'
            : d.kcal.complete
            ? 'Under half your goal · left out of averages'
            : 'Left out of averages: a food has no calories',
    };
    Future<void> set(String? m) async {
      try {
        await NutritionDb.setDayMark(await LocalDb.instance, widget.date, m);
      } catch (_) {
        if (!c.mounted) return;
        ScaffoldMessenger.of(c).showSnackBar(
          const SnackBar(
            content: Text('Day status could not be saved. Try again.'),
          ),
        );
        return;
      }
      await _changed();
    }

    final action = _mark != null
        ? ('Undo', () => set(null))
        : d.state == DayLogState.complete
        ? ('Missing food', () => set('incomplete'))
        : d.kcal.complete
        ? (
            d.state == DayLogState.inProgress
                ? 'Mark complete'
                : 'Count this day',
            () => set('complete'),
          )
        : null;
    return Padding(
      padding: const EdgeInsets.only(top: S.x2),
      child: Row(
        children: [
          Icon(
            d.countsTowardAverages
                ? LucideIcons.circleCheck
                : LucideIcons.circleDashed,
            size: 14,
            color: d.countsTowardAverages ? p.on(C.green) : p.ink3,
          ),
          const SizedBox(width: S.x1),
          Expanded(
            child: Text(say, style: F.cap.copyWith(color: p.ink3)),
          ),
          if (action != null)
            // Flexible: at large text sizes the action wraps rather than
            // pushing the row past the panel's edge.
            Flexible(
              child: Pressable(
                semanticLabel: action.$1,
                onTap: action.$2,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: S.x2,
                    vertical: S.x1,
                  ),
                  child: Text(
                    action.$1,
                    textAlign: TextAlign.end,
                    style: F.cap.copyWith(
                      color: p.on(C.recovery),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// In the evening, how much protein is still to eat against the target.
  /// Shown here only, never as a notification.
  String? _proteinLeft(NutritionDay d, Map<String, dynamic> profile) {
    final target = _targetOf(profile, 'protein_target');
    if (target == null || widget.date != todayLabel()) return null;
    if (DateTime.now().hour < 17) return null;
    // Unknown protein is unknown, never 0 (B88-06): a day whose entries carry
    // no protein figure says nothing, and a floor can only bound what is left.
    if (d.logged && d.protein.known == 0) return null;
    final left = target - (d.protein.value ?? 0);
    if (left < 5) return null;
    return '${d.protein.isFloor ? 'At most ' : ''}${left.round()} g protein left today';
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
    final addTo = mealForHour(DateTime.now().hour);
    // Build 86 redesign, diary first: what was eaten against the goal with
    // all four macros in one card, the meals straight under it, and the
    // maintenance estimate below the diary as context, never as the goal.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CalorieCard(
          eaten: d.kcal.value,
          goal: _targetOf(profile, 'kcal_target'),
          maintenance: _upkeep?.parts?.total.toDouble(),
          day: d,
          profile: profile,
          note: _proteinLeft(d, profile),
          addLabel: 'Add to ${mealName(addTo)}',
          onAdd: () => openLog(c, widget.date, addTo, _changed),
          onTap: () async {
            await Navigator.of(c).push(
              MaterialPageRoute<void>(
                builder: (_) => DayFoodPage(date: widget.date),
              ),
            );
            if (mounted) await _changed();
          },
        ),
        // The same gap as every other card pair (Akshat's Build 90 phone
        // review: the meals panel sat flush against the calorie card).
        const SizedBox(height: S.x3),
        // Build 88 (mock `3-food`): the meals as rows of one panel, the day's
        // completion line closing it, and log-again under it.
        Surface(
          pad: const EdgeInsets.fromLTRB(S.x5, S.x1, S.x5, S.x3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final m in kMeals)
                MealCard(
                  date: widget.date,
                  meal: m,
                  entries: d.mealEntries(m),
                  onChanged: _changed,
                ),
              if (d.logged) _completeLine(c, d),
              const SizedBox(height: S.x2),
              _dayActions(c),
            ],
          ),
        ),
        if (_recent.isNotEmpty) ...[
          const SizedBox(height: S.x2),
          _logAgain(c, addTo),
        ],
        if (_upkeep != null) ...[
          const SizedBox(height: S.x3),
          MaintenanceCard(
            _upkeep!,
            today: widget.date == todayLabel(),
            compact: true,
          ),
        ],
      ],
    );
  }

  Widget _dayActions(BuildContext c) {
    final buttons = [
      TextButton.icon(
        onPressed: () => _copyDay(c),
        icon: const Icon(LucideIcons.copy, size: 16),
        label: Text(
          'Copy a day',
          style: F.cap.copyWith(color: P.of(c).on(C.food)),
        ),
      ),
      TextButton.icon(
        onPressed: () => openProgress(c, ProgressDest.food),
        icon: const Icon(LucideIcons.trendingUp, size: 16),
        label: Text(
          'Food progress',
          style: F.cap.copyWith(color: P.of(c).on(C.food)),
        ),
      ),
    ];
    return bigText(c)
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: buttons,
          )
        : Row(
            children: [for (final button in buttons) Expanded(child: button)],
          );
  }
}

/// How a day's intake reads against estimated maintenance — kept apart from
/// the diet goal (B86-09). Red means above the Budget maintenance estimate,
/// not a missed diet target; an unknown estimate is neutral, never green.
enum IntakeStatus { unknown, withinMaintenance, aboveMaintenance }

IntakeStatus intakeStatus(double? eaten, double? maintenance) {
  if (eaten == null || maintenance == null || maintenance <= 0) {
    return IntakeStatus.unknown;
  }
  return eaten.round() > maintenance.round()
      ? IntakeStatus.aboveMaintenance
      : IntakeStatus.withinMaintenance;
}

/// The meal a one-tap Add lands in at this hour of the day.
String mealForHour(int hour) => hour < 11
    ? 'breakfast'
    : hour < 15
    ? 'lunch'
    : hour < 18
    ? 'snack'
    : hour < 22
    ? 'dinner'
    : 'snack';

/// Goal, food, and what is left; with [day], the four macros under it in the
/// same card. Exercise never adds to the goal.
class CalorieCard extends StatelessWidget {
  const CalorieCard({
    super.key,
    required this.eaten,
    required this.goal,
    this.maintenance,
    this.onTap,
    this.day,
    this.profile = const {},
    this.note,
    this.addLabel,
    this.onAdd,
  });

  final double? eaten, goal;

  /// Retained for existing callers. Maintenance comparisons live in the
  /// maintenance panel; this card compares intake with the user's fixed goal.
  final double? maintenance;
  final VoidCallback? onTap;

  /// The day whose protein, carbs, fat and fibre show under the calories.
  final NutritionDay? day;
  final Map<String, dynamic> profile;

  /// One line under the macros, such as the evening protein still to eat.
  final String? note;

  /// Add food stays visible below the totals, using the existing logging route.
  final String? addLabel;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final food = eaten;
    final g = goal;
    // B88-06: the card follows the day's state. Today is "so far"; a total
    // summed past a food with no calories is a floor, so it can prove "above"
    // but never "below" maintenance or how much of the goal is left.
    final floor = day?.kcal.isFloor ?? false;
    final soFar = day?.state == DayLogState.inProgress;
    final hasGoal = g != null && g > 0;
    final over = hasGoal && food != null && food > g;
    final eatenText = food == null
        ? null
        : '${floor ? '≥' : ''}${thousands(food)}';
    final sideValue = !hasGoal || food == null
        ? null
        : thousands((g - food).abs());
    final sideWord = over
        ? (floor ? 'over, at least' : 'over')
        : (floor ? 'left, at most' : 'left');
    return Surface(
      pad: const EdgeInsets.all(S.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Pressable(
            onTap: onTap,
            semanticLabel: 'View food for the day',
            child: _CalorieHero(
              eaten: eatenText,
              goal: hasGoal ? thousands(g) : null,
              side: sideValue,
              sideWord: sideWord,
              soFar: soFar,
              over: over,
              frac: !hasGoal || food == null || floor
                  ? null
                  : ((g - food) / g).clamp(0.0, 1.0).toDouble(),
            ),
          ),
          if (day case final d?) ...[
            const SizedBox(height: S.x2),
            Divider(color: p.line, height: 1),
            _Macros(day: d, profile: profile),
          ],
          if (note case final line?) ...[
            const SizedBox(height: S.x2),
            Text(line, style: F.cap.copyWith(color: p.ink2)),
          ],
          if (onAdd != null) ...[
            const SizedBox(height: S.x2),
            BigButton(
              'Add food',
              icon: LucideIcons.plus,
              color: C.food,
              onTap: onAdd,
            ),
          ],
        ],
      ),
    );
  }
}

/// The selected B card: calories left inside the ring, eaten and goal beside it.
/// A partial intake can bound the balance but cannot fill an exact remaining arc.
class _CalorieHero extends StatelessWidget {
  const _CalorieHero({
    required this.eaten,
    required this.goal,
    required this.side,
    required this.sideWord,
    required this.soFar,
    this.over = false,
    this.frac,
  });

  final String? eaten, goal, side;
  final String sideWord;
  final bool soFar, over;
  final double? frac;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final large = bigText(c);
    final scale = MediaQuery.textScalerOf(c).scale(1).clamp(1.0, 2.0);
    final summary = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          soFar ? 'Eaten so far' : 'Eaten',
          style: F.cap.copyWith(color: p.ink2),
        ),
        const SizedBox(height: S.x2),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                eaten ?? 'Not logged',
                softWrap: false,
                key: const ValueKey('food-eaten'),
                style: (eaten == null ? F.body : F.n30).copyWith(color: p.ink),
              ),
              if (eaten != null && !large) ...[
                const SizedBox(width: S.x1),
                Text('kcal', style: F.cap.copyWith(color: p.ink2)),
              ],
            ],
          ),
        ),
        if (large && eaten != null)
          Text('kcal', style: F.cap.copyWith(color: p.ink2)),
        const SizedBox(height: S.x2),
        Text(
          goal == null ? 'No intake goal' : 'Goal $goal kcal',
          style: F.cap.copyWith(color: p.ink2),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (c, box) {
        final diameter = large
            ? (116 * scale).clamp(0.0, box.maxWidth).toDouble()
            : box.maxWidth < 300
            ? 104.0
            : 116.0;
        // Unknown intake is said once, under Eaten; the ring then reads
        // "— kcal left" (left is unknown), not a second "Not logged".
        final label = side == null
            ? (goal == null ? 'No goal' : 'kcal left')
            : 'kcal $sideWord';
        final ring = Semantics(
          label: side == null ? label : '$side $label',
          excludeSemantics: true,
          child: SizedBox(
            width: diameter,
            height: diameter,
            child: CustomPaint(
              key: const ValueKey('food-balance-ring'),
              painter: Ring(
                frac ?? 0,
                p.on(C.food),
                p.on(C.food).withValues(alpha: .22),
                stroke: 5,
                solid: true,
              ),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(S.x3),
                  child: MediaQuery.withClampedTextScaling(
                    maxScaleFactor: 2,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Text(
                            side ?? '—',
                            key: const ValueKey('food-balance'),
                            softWrap: false,
                            style: F.n24.copyWith(
                              color: p.on(over ? C.alert : C.food),
                            ),
                          ),
                        ),
                        const SizedBox(height: S.x1),
                        Text(
                          label,
                          textAlign: TextAlign.center,
                          style: F.over.copyWith(color: p.ink2),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        return large
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(alignment: Alignment.centerLeft, child: ring),
                  const SizedBox(height: S.x3),
                  summary,
                ],
              )
            : Row(
                children: [
                  ring,
                  const SizedBox(width: S.x4),
                  Expanded(child: summary),
                ],
              );
      },
    );
  }
}

/// All four nutrients remain visible. Compact bars describe the real target;
/// unknown and partial totals keep their labels rather than becoming zero.
class _Macros extends StatelessWidget {
  const _Macros({required this.day, required this.profile});
  final NutritionDay day;
  final Map<String, dynamic> profile;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final rows = [
      ('Protein', day.protein, _targetOf(profile, 'protein_target')),
      ('Carbs', day.carbs, _targetOf(profile, 'carbs_target')),
      ('Fat', day.fat, _targetOf(profile, 'fat_target')),
      ('Fibre', day.fibre, _targetOf(profile, 'fibre_target')),
    ];
    final valueStyle = F.cap.copyWith(
      color: p.ink2,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    TextSpan spanOf(int i) {
      final (_, total, target) = rows[i];
      final amount = total.value == null
          ? '—'
          : '${total.isFloor ? '≥' : ''}${thousands(total.value!)}';
      return TextSpan(
        style: valueStyle,
        children: [
          TextSpan(
            text: amount,
            style: (i == 0 ? F.n17 : F.body).copyWith(
              color: i == 0 ? p.on(C.food) : p.ink,
              fontWeight: FontWeight.w600,
            ),
          ),
          TextSpan(
            text: target != null && target > 0
                ? ' / ${thousands(target)} g'
                : ' g',
          ),
        ],
      );
    }

    // One value column for all four rows, as wide as the widest value, so
    // every bar ends at the same x (Build 90 review: the tracks were as long
    // as each row's own value allowed, so they ended at four places).
    var valueWidth = 0.0;
    for (var i = 0; i < rows.length; i++) {
      final tp = TextPainter(
        text: spanOf(i),
        textDirection: Directionality.of(c),
        textScaler: MediaQuery.textScalerOf(c),
        maxLines: 1,
      )..layout();
      valueWidth = math.max(valueWidth, tp.width.ceilToDouble());
      tp.dispose();
    }

    Widget macro(int i) {
      final (name, total, target) = rows[i];
      final value = Text.rich(
        spanOf(i),
        key: ValueKey('food-macro-$name'),
        softWrap: false,
      );
      final bar = target != null && target > 0 && total.value != null
          ? GoalBar(total.value! / target, color: p.on(C.food), height: 3)
          : SizedBox(
              height: 3,
              child: CustomPaint(
                painter: RangeChart(const [null], p.on(C.food), hatch: C.hatch),
              ),
            );
      return Padding(
        padding: const EdgeInsets.only(top: S.x2),
        child: bigText(c)
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(name, style: F.cap.copyWith(color: p.ink2)),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: value,
                  ),
                  const SizedBox(height: S.x1),
                  bar,
                ],
              )
            : Row(
                children: [
                  SizedBox(
                    width: 56,
                    child: Text(name, style: F.cap.copyWith(color: p.ink2)),
                  ),
                  Expanded(child: bar),
                  const SizedBox(width: S.x3),
                  SizedBox(
                    width: valueWidth,
                    child: Align(alignment: Alignment.centerRight, child: value),
                  ),
                ],
              ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++) macro(i),
        if (rows.any((r) => r.$2.value == null) ||
            rows.any((r) => r.$2.isFloor)) ...[
          const SizedBox(height: S.x1),
          Text(
            [
              if (rows.any((r) => r.$2.value == null))
                '— not logged · not zero',
              if (rows.any((r) => r.$2.isFloor)) '≥ partial total',
            ].join(' · '),
            style: F.over.copyWith(color: p.ink2),
          ),
        ],
      ],
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
                    color:
                        day.countsTowardAverages &&
                            intakeStatus(kcal, maintenance) ==
                                IntakeStatus.aboveMaintenance
                        ? p.on(C.red)
                        : p.ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            Text(
              [
                ...macroParts(
                  protein: protein,
                  carbs: day.carbs.value,
                  fat: day.fat.value,
                  fibre: day.fibre.value,
                ),
                if (day.state == DayLogState.inProgress) 'So far',
                if (day.state == DayLogState.partial) 'Partial log',
                if (maintenance != null &&
                    kcal != null &&
                    day.countsTowardAverages)
                  'Budget ${thousands(maintenance)} · movement estimate ${acsmMaintenance == null ? '—' : thousands(acsmMaintenance)} · '
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

  /// Build 89: the evening "Is today's food complete?" question.
  bool? _evening;

  @override
  void initState() {
    super.initState();
    FoodDayReminder.enabled().then((on) {
      if (mounted) setState(() => _evening = on);
    });
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
      if (_evening case final on?) ...[
        Pressable(
          semanticLabel: 'Evening check ${on ? 'on' : 'off'}',
          onTap: () async {
            await FoodDayReminder.setEnabled(!on);
            if (mounted) setState(() => _evening = !on);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: S.x2),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Evening check at 9:30 pm',
                        style: F.body.copyWith(color: P.of(s).ink),
                      ),
                      Text(
                        "Asks if today's food is complete. A day with half "
                        'your goal or more counts on its own either way.',
                        style: F.cap.copyWith(color: P.of(s).ink2),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: S.x3),
                Pill(on ? 'On' : 'Off', on ? C.domFood : C.n400),
              ],
            ),
          ),
        ),
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
/// outside runs, the runs themselves (Method 1, by distance), and the low-end
/// digestion cost of the food logged. A floor: lifting shows as a separate
/// line in the sheet and is never added.
/// The day's maintenance as a floor, shown beside the food and never changing
/// the calorie goal. Tap for what each part is.
///
/// Build 85: the two methods side by side, the Budget day as one stacked bar,
/// and eaten-against-Budget as the card's own row instead of a grey caption.
class MaintenanceCard extends StatelessWidget {
  const MaintenanceCard(
    this.upkeep, {
    super.key,
    this.today = false,
    this.compact = false,
  });
  final bool compact;

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
    if (compact)
      return Surface(
        framed: false,
        pad: const EdgeInsets.symmetric(vertical: S.x3),
        semanticLabel: 'Daily maintenance breakdown',
        onTap: () => showMaintenance(c, upkeep, today: today),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Estimated maintenance',
                    style: F.cap.copyWith(color: p.ink2),
                  ),
                ),
                Icon(LucideIcons.chevronRight, size: 16, color: p.ink3),
              ],
            ),
            const SizedBox(height: S.x2),
            EnergyComparison(
              budget: m.total,
              acsm: upkeep.acsmParts?.total,
              compact: true,
              note: '',
            ),
          ],
        ),
      );
    return Surface(
      onTap: () => showMaintenance(c, upkeep, today: today),
      semanticLabel:
          'Maintenance ${thousands(m.total)} kcal. Shows how it is '
          'worked out.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // A Wrap, so at large text the distance tag drops under the title
          // instead of squeezing it to one letter per line.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: S.x2,
                  runSpacing: S.x2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Daily maintenance',
                      style: F.body.copyWith(
                        color: p.ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Tag(upkeep.distanceTag, icon: LucideIcons.ruler),
                  ],
                ),
              ),
              const SizedBox(width: S.x2),
              Icon(LucideIcons.chevronRight, size: 16, color: p.ink3),
            ],
          ),
          const SizedBox(height: S.x3),
          EnergyComparison(
            budget: m.total,
            acsm: upkeep.acsmParts?.total,
            note: '',
          ),
          const SizedBox(height: S.x4),
          StackedBar(budgetSegments(upkeep)),
          if (eaten > 0) ...[
            const SizedBox(height: S.x4),
            CompareRow(
              leftLabel: 'Eaten',
              left: eaten,
              rightLabel: 'Budget',
              right: m.total,
              // Today's resting energy is the whole day's, but steps and food
              // are only so far, so the gap closes as the day goes on.
              suffix: today ? ' so far' : '',
            ),
          ],
        ],
      ),
    );
  }
}

/// The Budget day's parts for [StackedBar], in one fixed order and colour.
List<(String, double, Color)> budgetSegments(DayUpkeep u) {
  final m = u.parts!;
  return [
    ('Resting', m.bmr, C.steps),
    ('Walking', m.steps, C.green),
    if (u.runs.count > 0) ('Running', m.run, C.run),
    ('Digestion', m.food, C.domFood),
  ];
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
  final a = u.acsmParts;
  final pr = u.profile;
  String kg(double? w) => w == null
      ? ''
      : (w == w.roundToDouble()
            ? '${w.round()} kg'
            : '${w.toStringAsFixed(1)} kg');
  final walked = u.walkedSteps;
  final lift = u.lifting;
  final p = P.of(c);
  // Each column lists its own parts, so neither method borrows a breakdown.
  final budgetParts = <(String, double)>[
    ('Resting', m.bmr),
    ('Walking', m.steps),
    if (u.runs.count > 0) ('Running', m.run),
    ('Digestion', m.food),
  ];
  final acsmParts = a == null
      ? const <(String, double)>[]
      : <(String, double)>[
          ('Resting', a.bmr),
          ('Walking', a.steps),
          if (u.runs.count > 0) ('Running', a.run),
          ('Digestion', a.food),
        ];
  return SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(S.x5),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (error != null)
            Text(error, style: F.cap.copyWith(color: p.on(C.red))),
          Text('Daily maintenance', style: F.t2.copyWith(color: p.ink)),
          const SizedBox(height: S.x2),
          Wrap(
            spacing: S.x2,
            runSpacing: S.x2,
            children: [
              Tag(u.distanceTag, icon: LucideIcons.ruler),
              Tag(
                today ? 'Resting all day · food and steps so far' : 'Whole day',
                icon: LucideIcons.clock,
              ),
              if (u.overlapUnknown)
                const Tag('Run steps overlap unknown', icon: LucideIcons.info),
            ],
          ),
          const SizedBox(height: S.x5),
          EnergyComparison(
            budget: m.total,
            acsm: a?.total,
            note: '',
            budgetParts: budgetParts,
            acsmParts: acsmParts,
            equationLabel: u.comparisonLabel,
          ),
          const SizedBox(height: S.x5),
          StackedBar(budgetSegments(u)),
          if (u.eaten > 0) ...[
            const SizedBox(height: S.x4),
            CompareRow(
              leftLabel: 'Eaten',
              left: u.eaten,
              rightLabel: 'Budget',
              right: m.total,
              suffix: today ? ' so far' : '',
            ),
          ],
          if (lift != null) ...[
            const SizedBox(height: S.x5),
            // Shown, never added: its own card under the total, in the
            // strength colour, saying so in its title.
            Container(
              padding: const EdgeInsets.all(S.x4),
              decoration: BoxDecoration(
                color: p.wash(C.domMove),
                borderRadius: R.rLg,
                border: Border.all(color: p.edge),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        LucideIcons.dumbbell,
                        size: 16,
                        color: p.on(C.domMove),
                      ),
                      const SizedBox(width: S.x2),
                      Expanded(
                        child: Text(
                          'Lifting (extra, not in maintenance)',
                          style: F.cap.copyWith(
                            color: p.ink,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        '+${thousands(lift.kcal)} kcal',
                        style: F.n17.copyWith(color: p.on(C.domMove)),
                      ),
                    ],
                  ),
                  const SizedBox(height: S.x2),
                  Wrap(
                    spacing: S.x2,
                    runSpacing: S.x2,
                    children: [
                      Tag(
                        '${lift.sessions} '
                        '${lift.sessions == 1 ? 'session' : 'sessions'}',
                      ),
                      Tag('With lifting ${thousands(m.total + lift.kcal)}'),
                      if (lift.approximate)
                        const Tag('Steps unknown · approximate'),
                    ],
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: S.x4),
          // Keyed: a reload that adds or drops a row above keeps it open.
          Explain(key: const ValueKey('maintenance-how'), [
            'ACSM applies to walking at 50–100 m/min and running above 5 mph. '
                'Unknown speeds and slower jogging are labelled movement estimates. '
                'All-day walking speed is not established from a daily step total.',
            'Resting: Mifflin–St Jeor for the whole day, from age '
                '${pr.ageYears}, ${pr.heightCm?.toStringAsFixed(1)} cm and '
                '${kg(pr.weightKg)}.',
            walked == null
                ? 'Walking: no steps counted yet.'
                : 'Walking, Budget: ${thousands(walked)} steps'
                      '${u.runs.steps > 0 ? ' outside your runs' : ''} × '
                      '${kg(pr.weightKg)} (Weyand). The movement equation prices the same '
                      'walking by distance as an estimate when speed is unknown.',
            if (u.runs.count > 0)
              'Running: ${u.runs.km.toStringAsFixed(2)} km in ${u.runs.count} '
                  '${u.runs.count == 1 ? 'run' : 'runs'}, by distance at each '
                  "run's recorded weight (Budget and movement equation).",
            u.eaten > 0
                ? 'Digestion, low end: protein 20%, carbs 5%, fat 0% '
                      '(5% for food without macros), on the '
                      '${thousands(u.eaten)} kcal logged.'
                : 'Digestion: nothing logged yet.',
            if (lift != null)
              'Lifting: (MET − 1) × weight × active time (start '
                  'to stop, minus pauses), less steps already counted. Heart '
                  'rate is not used. Bodyweight 3.0 MET, weights 3.5, calisthenics 3.8, '
                  'powerlifting 5.0; functional 3.5 is an estimate without a matched '
                  'Compendium entry. Never added to maintenance.',
          ]),
        ],
      ),
    ),
  );
}
