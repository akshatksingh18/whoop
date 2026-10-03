// Nutrition — a food log in the MyFitnessPal shape, kept simple.
//
//   · Calories left = your goal − food. Exercise is NOT added back: the goal
//     is the number you chose, and a wrist estimate of burn is not precise
//     enough to spend.
//   · Protein, carbs, fat and fibre against your own targets.
//   · Breakfast, lunch, dinner and snacks, each with its own Add — from saved
//     meals, from your foods by weight, or quick add / barcode.
//   · Maintenance: what the day cost as a floor (BMR + steps + 10% of the
//     food logged), shown beside the food, never changing the goal.
//   · History: every day of the last month against the goal.
//   · Foods: the foods and saved meals you log from.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../data/db.dart';
import '../../data/day_label.dart';
import '../../compute/profile.dart' show Profile, maintenance;
import '../../data/local_repository.dart';
import '../../data/nutrition_store.dart';
import '../../gps/run_history.dart';
import '../../state/app_state.dart';
import '../ui2.dart';
import 'food_picker.dart';
import 'home_screen.dart'
    show metricOf, pointsOf, prettyDay, pullToRefresh, repoOf, thousands;
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
  List<Map<String, Object?>> _foods = const [];
  List<MealTemplate> _meals = const [];

  /// Steps per day for the month, for each day's maintenance figure.
  Map<String, num> _steps = const {};
  List<RunSummary> _runs = const [];
  bool _loading = true;

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
    final db = await LocalDb.instance;
    final month = await NutritionDb.window(db, days: 31);
    final foods = await MyFoods.all(db);
    final meals = await MyFoods.meals(db);
    final steps = mounted ? await _monthSteps(context) : const <String, num>{};
    final runs = mounted ? await _allRuns(repoOf(context)) : const <RunSummary>[];
    if (!stillNewest(#nutrition, t)) return;
    setState(() {
      _month = month;
      _foods = foods;
      _meals = meals;
      _steps = steps;
      _runs = runs;
      _loading = false;
    });
    // Counted when the read has LANDED, so a test waiting on it also waits
    // for the database it opened.
    NutritionScreen.debugLoads++;
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
            child: Icon(LucideIcons.target, size: 22, color: P.of(c).on(C.domFood)),
          ),
        ),
        SubTabs(const ['Today', 'History', 'Foods'], _tab,
            (i) => setState(() => _tab = i),
            color: C.domFood),
        const SizedBox(height: S.x5),
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else
          switch (_tab) {
            0 => NutritionDayView(
                key: ValueKey(_dayKey), date: _date, onChanged: _load),
            1 => _history(c),
            _ => _foodsTab(c),
          },
      ],
    ),
    );
  }

  /// Bumped by a pull so today's view reads its steps and runs again.
  int _dayKey = 0;

  // ── HISTORY ──────────────────────────────────────────────────────────────

  Widget _history(BuildContext c) {
    final p = P.of(c);
    final profile = context.watch<AppState>().user ?? const {};
    final goal = _targetOf(profile, 'kcal_target');
    final days = [...?_month?.days.reversed.where((d) => d.logged)];
    if (days.isEmpty) {
      return const StatusCard(
          'Nothing logged this month', 'Days you log appear here.',
          icon: LucideIcons.calendarDays);
    }
    final kcals = [for (final d in days) if (d.kcal.value != null) d.kcal.value!];
    final avg = kcals.isEmpty ? null : kcals.reduce((a, b) => a + b) / kcals.length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (avg != null)
        Surface(
          child: Row(children: [
            Expanded(
              child: Text('Average over ${kcals.length} logged days',
                  style: F.body.copyWith(color: p.ink2)),
            ),
            Text('${avg.round()} kcal',
                style: F.n17.copyWith(color: p.ink, fontWeight: FontWeight.w600)),
          ]),
        ),
      const SizedBox(height: S.x3),
      Surface(
        pad: const EdgeInsets.symmetric(horizontal: S.x4),
        child: Column(children: [
          for (final d in days)
            _HistoryRow(
              day: d,
              goal: goal,
              maintenance: DayUpkeep(
                Profile.fromMap(profile),
                steps: _steps[d.date],
                runs: runEnergyOn(_runs, d.date,
                    weightKg: Profile.fromMap(profile).weightKg,
                    daySteps: _steps[d.date]),
                eaten: d.kcal.value ?? 0,
              ).parts?.total,
              onTap: () async {
                await Navigator.of(c).push(MaterialPageRoute<void>(
                  builder: (_) => detailScaffold(context, prettyDay(d.date), [
                    NutritionDayView(date: d.date, onChanged: _load),
                  ]),
                ));
                await _load();
              },
            ),
        ]),
      ),
    ]);
  }

  // ── FOODS ────────────────────────────────────────────────────────────────

  Widget _foodsTab(BuildContext c) {
    final p = P.of(c);
    Future<void> edit(Future<Object?> Function() f) async {
      await f();
      await _load();
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
                      style: F.cap.copyWith(color: p.ink3)),
                )
              : Column(children: [
                  for (final m in _meals)
                    PickRow(
                      m.label,
                      '${mealName(m.meal)} · ${m.items.length} '
                      'food${m.items.length == 1 ? '' : 's'}',
                      trailing: LucideIcons.chevronRight,
                      onTap: () => edit(() => _mealActions(c, m)),
                    ),
                ]),
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
                      'Add a food once from its label; log it by weight after.',
                      style: F.cap.copyWith(color: p.ink3)),
                )
              : Column(children: [
                  for (final f in _foods)
                    PickRow(
                      (f['label'] ?? '').toString(),
                      'per 100 g: ${macroLine(kcal: (f['kcal_100'] as num?)?.toDouble(), protein: (f['protein_g_100'] as num?)?.toDouble(), carbs: (f['carbs_g_100'] as num?)?.toDouble(), fat: (f['fat_g_100'] as num?)?.toDouble(), fibre: (f['fibre_g_100'] as num?)?.toDouble())}',
                      trailing: LucideIcons.chevronRight,
                      onTap: () => edit(() => _foodActions(c, f)),
                    ),
                ]),
        ),
        action: 'New',
        onAction: () => edit(() => FoodEditor.show(c)),
      ),
    ]);
  }

  Future<void> _mealActions(BuildContext c, MealTemplate m) async {
    final choice = await _chooseAction(c, m.label);
    if (!c.mounted) return;
    if (choice == 'edit') {
      await MealEditor.show(c, existing: m);
    } else if (choice == 'delete' &&
        await confirmRemove(c,
            title: 'Delete ${m.label}?',
            body: 'Days you already logged keep their entries.')) {
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
        await confirmRemove(c,
            title: 'Delete $label?',
            body: 'Days you already logged keep their entries; saved meals '
                'that use it skip it.')) {
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
                BigButton('Edit',
                    color: C.domFood, onTap: () => Navigator.of(s).pop('edit')),
                const SizedBox(height: S.x3),
                BigButton('Delete',
                    color: C.red,
                    soft: true,
                    onTap: () => Navigator.of(s).pop('delete')),
              ]),
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

class _NutritionDayViewState extends State<NutritionDayView> {
  NutritionDay? _day;
  num? _steps;
  List<RunSummary> _runs = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(NutritionDayView old) {
    super.didUpdateWidget(old);
    if (old.date != widget.date) _load();
  }

  Future<void> _load() async {
    final db = await LocalDb.instance;
    final es = await NutritionDb.entriesForDay(db, widget.date);
    final steps = mounted ? await stepsOn(context, widget.date) : null;
    final runs = mounted ? await _allRuns(repoOf(context)) : const <RunSummary>[];
    if (mounted) {
      setState(() {
        _day = rollupDay(widget.date, es, today: todayLabel());
        _steps = steps;
        _runs = runs;
      });
    }
  }

  Future<void> _changed() async {
    await _load();
    widget.onChanged?.call();
  }

  Future<void> _add(String meal) async {
    final ok = await AddFoodSheet.show(context, date: widget.date, meal: meal);
    if (ok == true) await _changed();
  }

  Future<void> _entryActions(FoodEntry e) async {
    final db = await LocalDb.instance;
    final def = e.foodKey == null ? null : await NutritionDb.foodDef(db, e.foodKey!);
    if (!mounted) return;
    // A food logged by weight can have its grams changed; anything else can
    // only be removed.
    if (def != null && e.quantity != null) {
      final grams = await GramsSheet.show(context, def, initial: e.quantity);
      if (grams == null) return;
      await NutritionDb.put(
          db,
          entryFromFood(def, grams,
              id: e.id, date: e.date, meal: e.meal, atTs: e.atTs));
    } else {
      if (!await confirmRemove(context,
          title: 'Remove ${e.label}?', body: 'It leaves this day.')) {
        return;
      }
      await NutritionDb.delete(db, e.id);
    }
    await _changed();
  }

  Future<void> _remove(FoodEntry e) async {
    if (!await confirmRemove(context,
        title: 'Remove ${e.label}?', body: 'It leaves this day.')) {
      return;
    }
    await NutritionDb.delete(await LocalDb.instance, e.id);
    await _changed();
  }

  @override
  Widget build(BuildContext c) {
    final profile = c.watch<AppState>().user ?? const {};
    final d = _day;
    if (d == null) return const Center(child: CircularProgressIndicator());
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      CalorieCard(
          eaten: d.kcal.value, goal: _targetOf(profile, 'kcal_target')),
      const SizedBox(height: S.x3),
      MaintenanceCard(
          DayUpkeep(
            Profile.fromMap(profile),
            steps: _steps,
            runs: runEnergyOn(_runs, widget.date,
                weightKg: Profile.fromMap(profile).weightKg, daySteps: _steps),
            eaten: d.kcal.value ?? 0,
          ),
          today: widget.date == todayLabel()),
      const SizedBox(height: S.x3),
      MacroCard(day: d, profile: profile),
      for (final m in kMeals)
        MealSection(
          meal: m,
          entries: d.mealEntries(m),
          onAdd: () => _add(m),
          onEntry: _entryActions,
          onRemove: _remove,
        ),
    ]);
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
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Calories', style: F.body.copyWith(color: p.ink, fontWeight: FontWeight.w600)),
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
                color: left != null && left < 0 ? p.on(C.red) : p.ink),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: S.x1),
            child: Text(
              left == null ? 'kcal eaten' : (left < 0 ? 'kcal over' : 'kcal left'),
              style: F.cap.copyWith(color: p.ink3),
            ),
          ),
        ]),
        if (g != null && g > 0) ...[
          const SizedBox(height: S.x3),
          ProgressCard('Food', '${food.round()}', 'of ${g.round()} kcal goal',
              (food / g).clamp(0.0, 1.0).toDouble(), C.domFood),
        ] else ...[
          const SizedBox(height: S.x2),
          Text('Set a calorie goal with the target button above.',
              style: F.cap.copyWith(color: p.ink3)),
        ],
      ]),
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
      ('Protein', day.protein.value, _targetOf(profile, 'protein_target'), C.red),
      ('Carbs', day.carbs.value, _targetOf(profile, 'carbs_target'), C.blue),
      ('Fat', day.fat.value, _targetOf(profile, 'fat_target'), C.yellow),
      ('Fibre', day.fibre.value, _targetOf(profile, 'fibre_target'), C.green),
    ];
    return Surface(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: S.x3),
          ProgressCard(
            rows[i].$1,
            '${(rows[i].$2 ?? 0).round()} g',
            rows[i].$3 == null ? '' : 'of ${rows[i].$3!.round()} g',
            rows[i].$3 == null || rows[i].$3! <= 0
                ? 0
                : ((rows[i].$2 ?? 0) / rows[i].$3!).clamp(0.0, 1.0).toDouble(),
            rows[i].$4,
          ),
        ],
      ]),
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
      entries.isEmpty ? mealName(meal) : '${mealName(meal)} · ${kcal.round()} kcal',
      Surface(
        pad: const EdgeInsets.symmetric(horizontal: S.x4),
        child: entries.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: S.x3),
                child: Text('Nothing yet', style: F.cap.copyWith(color: p.ink3)),
              )
            : Column(children: [
                for (final e in entries)
                  PickRow(
                    e.quantity == null ? e.label : '${e.label} · ${e.quantity!.round()} g',
                    macroLine(
                        kcal: e.kcal,
                        protein: e.proteinG,
                        carbs: e.carbsG,
                        fat: e.fatG,
                        fibre: e.fibreG),
                    trailing: LucideIcons.x,
                    onTap: onEntry == null ? null : () => onEntry!(e),
                  ),
              ]),
      ),
      action: 'Add',
      onAction: onAdd,
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow(
      {required this.day, required this.goal, this.maintenance, this.onTap});

  final NutritionDay day;
  final double? goal, maintenance;
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
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
                child: Text(prettyDay(day.date),
                    style: F.body.copyWith(color: p.ink))),
            Text(kcal == null ? '–' : '${kcal.round()} kcal',
                style: F.body.copyWith(
                    color: g != null && kcal != null && kcal > g
                        ? p.on(C.red)
                        : p.ink,
                    fontWeight: FontWeight.w600)),
          ]),
          Text(
              [
                if (protein != null) 'Protein ${protein.round()} g',
                if (maintenance != null && kcal != null)
                  'Maintenance ${thousands(maintenance)} · '
                      '${thousands((kcal - maintenance!).abs())} '
                      '${kcal > maintenance! ? 'over' : 'under'}',
              ].join(' · '),
              style: F.cap.copyWith(color: p.ink3)),
          if (g != null && g > 0 && kcal != null) ...[
            const SizedBox(height: S.x1),
            ProgressCard('', '', '', (kcal / g).clamp(0.0, 1.0).toDouble(),
                C.domFood),
          ],
        ]),
      ),
    );
  }
}

// ══════════════════ GOALS ══════════════════

/// Edit the five targets. Shows the measured daily burn as a reference — a
/// starting point for a calorie goal, never added to it.
Future<bool> editNutritionGoals(BuildContext c) async {
  final app = c.read<AppState>();
  final profile = app.user ?? const {};
  final ctrls = {
    for (final t in kNutritionTargets)
      t.$1: TextEditingController(
          text: _targetOf(profile, t.$1)?.round().toString() ?? ''),
  };
  if (!c.mounted) return false;
  final saved = await showModalBottomSheet<bool>(
    context: c,
    isScrollControlled: true,
    sheetAnimationStyle: sheetMotion(c),
    backgroundColor: P.of(c).card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(R.xxl)),
    ),
    builder: (s) => Padding(
      padding: EdgeInsets.only(
          left: S.x5,
          right: S.x5,
          top: S.x5,
          bottom: MediaQuery.of(s).viewInsets.bottom + S.x5),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Daily targets', style: F.head.copyWith(color: P.of(s).ink)),
            const SizedBox(height: S.x2),
            Text('Set once. Your calorie goal stays exactly what you type.',
                style: F.cap.copyWith(color: P.of(s).ink3)),
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
            BigButton('Save',
                color: C.domFood, onTap: () => Navigator.of(s).pop(true)),
          ],
        ),
      ),
    ),
  );
  final typed = {for (final e in ctrls.entries) e.key: Typed.of(e.value.text)};
  for (final t in ctrls.values) {
    t.dispose();
  }
  if (saved != true || !c.mounted) return false;
  final bad = [
    for (final t in kNutritionTargets)
      if (typed[t.$1]!.bad) t.$2,
  ];
  if (bad.isNotEmpty) {
    sayUnreadable(c, bad);
    return false;
  }
  await app.updateProfile({for (final e in typed.entries) e.key: e.value.value});
  return true;
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
    for (final p in pointsOf(await repo.getChart('steps'))) {
      if (dayLabelOf(DateTime.fromMillisecondsSinceEpoch(p.t * 1000)) == date) {
        return p.v;
      }
    }
  } catch (_) {}
  return null;
}

/// Steps per day over the stored history, plus today's live count.
Future<Map<String, num>> _monthSteps(BuildContext c) async {
  final repo = repoOf(c);
  if (repo == null) return const {};
  final out = <String, num>{};
  try {
    for (final p in pointsOf(await repo.getChart('steps'))) {
      out[dayLabelOf(DateTime.fromMillisecondsSinceEpoch(p.t * 1000))] = p.v;
    }
    final daily = (await repo.getToday())['daily'];
    final today = metricOf(daily is Map ? daily['steps'] : null).value;
    if (today != null) out[todayLabel()] = today;
  } catch (_) {}
  return out;
}

/// Every run this phone holds, for the Running row. Empty when unreadable.
Future<List<RunSummary>> _allRuns(LocalRepository? repo) async {
  if (repo == null) return const [];
  try {
    return await loadRuns(repo);
  } catch (_) {
    return const [];
  }
}

/// What one day's maintenance is made of: resting energy, the steps walked
/// outside runs, the runs themselves (Method 1, by distance), and 10% of the
/// food logged. A floor: lifts and other workouts are not added.
class DayUpkeep {
  const DayUpkeep(this.profile,
      {required this.steps, this.runs = kNoRunDay, this.eaten = 0});

  final Profile profile;

  /// The day's steps, runs included.
  final num? steps;
  final RunDay runs;
  final double eaten;

  ({double bmr, double steps, double run, double food, double total})?
      get parts => maintenance(profile,
          steps: steps,
          eatenKcal: eaten,
          runKcal: runs.kcal,
          runSteps: runs.steps);

  /// The steps costed as walking: the day's, less the runs'.
  num? get walkedSteps =>
      steps == null ? null : (steps! - runs.steps).clamp(0, steps!);
}

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
      return const StatusCard('Maintenance needs your profile',
          'Add your age, height and weight in Settings → Profile.',
          icon: LucideIcons.flame);
    }
    final eaten = upkeep.eaten;
    final diff = eaten - m.total;
    return Surface(
      onTap: () => showMaintenance(c, upkeep, today: today),
      semanticLabel: 'Maintenance ${thousands(m.total)} kcal. Shows how it is '
          'worked out.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(today ? 'Maintenance so far' : 'Maintenance',
                style: F.body.copyWith(color: p.ink, fontWeight: FontWeight.w600)),
          ),
          Icon(LucideIcons.info, size: 16, color: p.ink3),
        ]),
        const SizedBox(height: S.x2),
        Wrap(spacing: S.x2, crossAxisAlignment: WrapCrossAlignment.end, children: [
          Text(thousands(m.total), style: F.n34.copyWith(color: p.on(C.steps))),
          Padding(
            padding: const EdgeInsets.only(bottom: S.x1),
            child: Text('kcal', style: F.cap.copyWith(color: p.ink3)),
          ),
        ]),
        const SizedBox(height: S.x3),
        InlineMetrics([
          ('RESTING', thousands(m.bmr), C.steps),
          ('STEPS', thousands(m.steps), C.green),
          if (upkeep.runs.count > 0) ('RUNNING', thousands(m.run), C.run),
          ('FOOD', thousands(m.food), C.domFood),
        ]),
        if (eaten > 0) ...[
          const SizedBox(height: S.x3),
          Text(
              'Eaten ${thousands(eaten)} · ${thousands(diff.abs())} '
              '${diff > 0 ? 'over' : 'under'} maintenance',
              style: F.cap.copyWith(color: p.ink2)),
        ],
      ]),
    );
  }
}

/// What each part of maintenance is and the numbers it came from, one short
/// line each.
Future<void> showMaintenance(BuildContext c, DayUpkeep u, {bool today = false}) {
  final m = u.parts;
  if (m == null) return Future.value();
  final pr = u.profile;
  String kg(double? w) => w == null
      ? ''
      : (w == w.roundToDouble() ? '${w.round()} kg' : '${w.toStringAsFixed(1)} kg');
  final walked = u.walkedSteps;
  final rows = <(String, double, String)>[
    (
      'Resting',
      m.bmr,
      'What your body burns at rest over a whole day, from age '
          '${pr.ageYears}, ${pr.heightCm?.toStringAsFixed(1)} cm and '
          '${kg(pr.weightKg)}.'
    ),
    (
      'Steps',
      m.steps,
      walked == null
          ? 'No steps counted yet.'
          : u.runs.steps > 0
              ? '${thousands(walked)} steps outside your '
                  '${u.runs.count == 1 ? 'run' : 'runs'}, at ${kg(pr.weightKg)}.'
              : '${thousands(walked)} steps at ${kg(pr.weightKg)}.'
    ),
    if (u.runs.count > 0)
      (
        'Running',
        m.run,
        '${u.runs.km.toStringAsFixed(2)} km in ${u.runs.count} '
            '${u.runs.count == 1 ? 'run' : 'runs'}: the least that distance '
            'costs at ${kg(pr.weightKg)}.'
      ),
    (
      'Food',
      m.food,
      u.eaten > 0
          ? '10% of the ${thousands(u.eaten)} kcal you logged goes to digesting '
              'it.'
          : 'Nothing logged yet. 10% of what you log is added.'
    ),
  ];
  return showModalBottomSheet<void>(
    context: c,
    sheetAnimationStyle: sheetMotion(c),
    backgroundColor: P.of(c).card,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(R.xxl)),
    ),
    builder: (s) {
      final p = P.of(s);
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(S.x5),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(today ? 'Maintenance so far' : 'Maintenance',
                    style: F.head.copyWith(color: p.ink)),
                const SizedBox(height: S.x1),
                Text('${thousands(m.total)} kcal',
                    style: F.n24.copyWith(color: p.on(C.steps))),
                for (final (name, kcal, why) in rows) ...[
                  const SizedBox(height: S.x4),
                  Row(children: [
                    Expanded(
                        child: Text(name,
                            style: F.body.copyWith(
                                color: p.ink, fontWeight: FontWeight.w600))),
                    Text('${thousands(kcal)} kcal',
                        style: F.n17.copyWith(color: p.ink)),
                  ]),
                  const SizedBox(height: 2),
                  Text(why, style: F.cap.copyWith(color: p.ink2, height: 1.4)),
                ],
                const SizedBox(height: S.x5),
                Text(
                    'This is the least you burned. Lifts and other workouts are '
                    'not added, so your real burn is this or more.',
                    style: F.cap.copyWith(color: p.ink3, height: 1.4)),
              ]),
        ),
      );
    },
  );
}
