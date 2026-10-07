// Food, in the MyFitnessPal shape but cleaner (Akshat's 3 October brief):
//
//   · Day header: ‹ Today ›, swipe between days, tap the date for a calendar.
//   · Meal cards: "Oats and 4 more · 854 kcal", a Log button, and a ⋯ menu
//     with Copy from, Copy to and Save meal. Tapping a card opens that meal.
//   · Meal page: every item, under its sub-heading ("Oatmeal", "Omelette"),
//     swipe either way to delete, hold to drag, tap to change the grams or
//     move it to a group.
//   · Log screen: a meal selector, search, My foods / My meals in Akshat's
//     own dragged order; + opens the portion (or saved-meal review) first.
//   · Food detail: grams, meal, time, calories and macros as % of the daily
//     goals, and "Often eaten with" for one-tap companions.
//   · Quick add with a NAME (MyFitnessPal's is anonymous), meal and time.
//
// No ads, no upsells, macros always free.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart' show Database;

import '../../data/db.dart';
import '../../data/day_label.dart';
import '../../data/nutrition_store.dart';
import '../../state/app_state.dart';
import '../ui2.dart';
import 'food_picker.dart';
import 'food_group_picker.dart';
import 'home_screen.dart' show prettyDay, thousands;
import 'journal_compose.dart' show OsTextField;
import 'log_food.dart' show offCredit;
import 'metric_detail.dart' show detailScaffold;

// ══════════════════ DAYS ══════════════════

/// 'Today', 'Yesterday', or 'Tue, 29 Sep'.
String dayTitle(String date) {
  final today = todayLabel();
  if (date == today) return 'Today';
  final t = DateTime.parse(today);
  if (date == dayLabelOf(DateTime(t.year, t.month, t.day - 1))) {
    return 'Yesterday';
  }
  return prettyDay(date);
}

/// [date] moved by [days], as a day label.
String shiftDay(String date, int days) {
  final d = DateTime.parse(date);
  return dayLabelOf(DateTime(d.year, d.month, d.day + days));
}

/// The calendar, up to today.
Future<String?> pickDate(BuildContext c, String current) async {
  final now = DateTime.now();
  final picked = await showDatePicker(
    context: c,
    initialDate: DateTime.parse(current),
    firstDate: DateTime.parse(current).isBefore(DateTime(now.year - 2))
        ? DateTime.parse(current)
        : DateTime(now.year - 2),
    lastDate: DateTime(now.year, now.month, now.day),
  );
  return picked == null ? null : dayLabelOf(picked);
}

/// ‹ Day › with the date opening a calendar. [onDay] gets the new label.
class DayHeader extends StatelessWidget {
  const DayHeader(this.date, this.onDay, {super.key});
  final String date;
  final ValueChanged<String> onDay;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final atToday = date == todayLabel();
    return Row(
      children: [
        Pressable(
          semanticLabel: 'Previous day',
          onTap: () => onDay(shiftDay(date, -1)),
          child: Icon(LucideIcons.chevronLeft, size: 22, color: p.ink2),
        ),
        Expanded(
          child: Pressable(
            semanticLabel: 'Choose a day, ${dayTitle(date)}',
            onTap: () async {
              final d = await pickDate(c, date);
              if (d != null) onDay(d);
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  dayTitle(date),
                  style: F.body.copyWith(
                    color: p.ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: S.x1),
                Icon(LucideIcons.chevronDown, size: 16, color: p.ink3),
              ],
            ),
          ),
        ),
        Pressable(
          semanticLabel: 'Next day',
          onTap: atToday ? null : () => onDay(shiftDay(date, 1)),
          child: Icon(
            LucideIcons.chevronRight,
            size: 22,
            color: atToday ? p.line : p.ink2,
          ),
        ),
      ],
    );
  }
}

// ══════════════════ MEAL CARDS ══════════════════

IconData mealIcon(String meal) => switch (meal) {
  'breakfast' => LucideIcons.coffee,
  'lunch' => LucideIcons.sandwich,
  'dinner' => LucideIcons.utensils,
  _ => LucideIcons.cookie,
};

double _kcalOf(List<FoodEntry> es) => es.fold(0.0, (a, e) => a + (e.kcal ?? 0));

/// One meal on the day: what is in it, its calories, Log, and the ⋯ menu.
class MealCard extends StatelessWidget {
  const MealCard({
    super.key,
    required this.date,
    required this.meal,
    required this.entries,
    required this.onChanged,
  });

  final String date, meal;
  final List<FoodEntry> entries;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final summary = entries.isEmpty
        ? 'Nothing logged'
        : entries.length == 1
        ? entries.first.label
        : '${entries.first.label} and ${entries.length - 1} more';
    return Padding(
      padding: const EdgeInsets.only(top: S.x3),
      child: Surface(
        onTap: () => openMeal(c, date, meal, onChanged),
        semanticLabel: '${mealName(meal)}, $summary',
        child: Row(
          children: [
            Icon(mealIcon(meal), size: 20, color: p.on(C.domFood)),
            const SizedBox(width: S.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mealName(meal),
                    style: F.body.copyWith(
                      color: p.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: F.cap.copyWith(color: p.ink2),
                  ),
                  if (entries.isNotEmpty)
                    Text(
                      _mealTotals(entries),
                      style: F.over.copyWith(color: p.ink3),
                    ),
                ],
              ),
            ),
            Pressable(
              semanticLabel: '${mealName(meal)} options',
              onTap: () => mealMenu(c, date, meal, entries, onChanged),
              child: Icon(LucideIcons.ellipsis, size: 20, color: p.ink3),
            ),
            const SizedBox(width: S.x1),
            Pressable(
              semanticLabel: 'Log ${mealName(meal)}',
              onTap: () => openLog(c, date, meal, onChanged),
              child: Pill('Log', C.domFood),
            ),
          ],
        ),
      ),
    );
  }
}

/// "776 kcal · P 77 · C 43 · F 32" for a meal card: the same rounding as
/// the meal page, and only the macros that were logged.
String _mealTotals(List<FoodEntry> es) {
  double? sum(double? Function(FoodEntry) f) {
    double? t;
    for (final e in es) {
      final v = f(e);
      if (v != null) t = (t ?? 0) + v;
    }
    return t;
  }

  return [
    '${thousands(_kcalOf(es))} kcal',
    if (sum((e) => e.proteinG) case final v?) 'P ${v.round()}',
    if (sum((e) => e.carbsG) case final v?) 'C ${v.round()}',
    if (sum((e) => e.fatG) case final v?) 'F ${v.round()}',
  ].join(' · ');
}

Future<void> openMeal(
  BuildContext c,
  String date,
  String meal,
  VoidCallback onChanged,
) async {
  await Navigator.of(c).push(
    MaterialPageRoute<void>(
      builder: (_) => MealPage(date: date, meal: meal),
    ),
  );
  if (c.mounted) onChanged();
}

Future<void> openLog(
  BuildContext c,
  String date,
  String meal,
  VoidCallback onChanged,
) async {
  await Navigator.of(c).push(
    MaterialPageRoute<void>(
      builder: (_) => LogFoodScreen(date: date, meal: meal),
    ),
  );
  if (c.mounted) onChanged();
}

Future<T?> _sheet<T>(BuildContext c, WidgetBuilder b) =>
    showModalBottomSheet<T>(
      context: c,
      isScrollControlled: true,
      useSafeArea: true,
      sheetAnimationStyle: sheetMotion(c),
      backgroundColor: P.of(c).card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(R.xxl)),
      ),
      builder: b,
    );

Widget _body(BuildContext s, List<Widget> children) =>
    InputSheet(children: children);

void _say(BuildContext c, String text) {
  final messenger = ScaffoldMessenger.maybeOf(c);
  messenger?.hideCurrentSnackBar();
  messenger?.showSnackBar(
    SnackBar(content: Text(text), duration: Motion.notice),
  );
}

Widget _sheetTitle(BuildContext c, String title) => Row(
  children: [
    Expanded(
      child: Text(title, style: F.head.copyWith(color: P.of(c).ink)),
    ),
    Pressable(
      semanticLabel: 'Close',
      onTap: () => Navigator.of(c).maybePop(),
      child: Icon(LucideIcons.x, size: 20, color: P.of(c).ink3),
    ),
  ],
);

/// Copy from · Copy to · Save meal.
Future<void> mealMenu(
  BuildContext c,
  String date,
  String meal,
  List<FoodEntry> entries,
  VoidCallback onChanged,
) async {
  final choice = await _sheet<String>(
    c,
    (s) => _body(s, [
      Text(mealName(meal), style: F.head.copyWith(color: P.of(s).ink)),
      const SizedBox(height: S.x3),
      PickRow(
        'Copy from',
        'Bring in a meal from another day',
        trailing: LucideIcons.copy,
        onTap: () => Navigator.of(s).pop('from'),
      ),
      if (entries.isNotEmpty) ...[
        PickRow(
          'Copy to',
          'Log this meal on another day or meal',
          trailing: LucideIcons.copyPlus,
          onTap: () => Navigator.of(s).pop('to'),
        ),
        PickRow(
          'Save meal',
          'Keep it in My meals for one-tap logging',
          trailing: LucideIcons.bookmark,
          onTap: () => Navigator.of(s).pop('save'),
        ),
      ],
    ]),
  );
  if (!c.mounted || choice == null) return;
  final db = await LocalDb.instance;
  if (!c.mounted) return;
  switch (choice) {
    case 'from':
      final src = await pickDayMeal(
        c,
        title: 'Copy from',
        date: shiftDay(date, -1),
        meal: meal,
        showCount: true,
      );
      if (src == null) return;
      final n = await NutritionDb.copyMeal(
        db,
        fromDate: src.date,
        fromMeal: src.meal,
        toDate: date,
        toMeal: meal,
      );
      if (c.mounted) {
        _say(
          c,
          n == 0
              ? 'Nothing to copy there'
              : 'Copied $n item${n == 1 ? '' : 's'}',
        );
      }
    case 'to':
      final dst = await pickDayMeal(
        c,
        title: 'Copy to',
        date: date == todayLabel() ? date : todayLabel(),
        meal: meal,
      );
      if (dst == null) return;
      final n = await NutritionDb.copyMeal(
        db,
        fromDate: date,
        fromMeal: meal,
        toDate: dst.date,
        toMeal: dst.meal,
      );
      if (c.mounted) {
        _say(
          c,
          'Copied $n item${n == 1 ? '' : 's'} to ${mealName(dst.meal)}, '
          '${dayTitle(dst.date)}',
        );
      }
    case 'save':
      final name = await askText(c, 'Save meal', 'Name', mealName(meal));
      if (name == null) return;
      final r = await MyFoods.saveMeal(
        db,
        label: name,
        meal: meal,
        entries: entries,
      );
      if (c.mounted) {
        _say(
          c,
          r.saved == 0
              ? 'Only your own foods can go in a saved meal'
              : 'Saved "$name"${r.skipped > 0 ? ' · ${r.skipped} quick add${r.skipped == 1 ? '' : 's'} left out' : ''}',
        );
      }
  }
  onChanged();
}

/// One line of text, or null when cancelled.
Future<String?> askText(
  BuildContext c,
  String title,
  String label,
  String initial, {
  String? Function(String)? validate,
  TextInputType? keyboard,
}) => _sheet<String>(
  c,
  (_) => _TextPrompt(title, label, initial, validate, keyboard),
);

class _TextPrompt extends StatefulWidget {
  const _TextPrompt(
    this.title,
    this.label,
    this.initial,
    this.validate,
    this.keyboard,
  );
  final String title, label, initial;
  final String? Function(String)? validate;
  final TextInputType? keyboard;
  @override
  State<_TextPrompt> createState() => _TextPromptState();
}

class _TextPromptState extends State<_TextPrompt> {
  late final _text = TextEditingController(text: widget.initial);
  String? _error;
  bool _closing = false;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _save() {
    if (_closing) return;
    final value = _text.text.trim();
    final error =
        widget.validate?.call(value) ??
        (value.isEmpty ? 'Enter ${widget.label}.' : null);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    _closing = true;
    FocusScope.of(context).unfocus();
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext c) => _body(c, [
    _sheetTitle(c, widget.title),
    const SizedBox(height: S.x4),
    OsTextField(
      controller: _text,
      label: widget.label,
      keyboard: widget.keyboard,
    ),
    if (_error != null)
      Text(_error!, style: F.cap.copyWith(color: P.of(c).on(C.red))),
    const SizedBox(height: S.x4),
    BigButton('Save', color: C.domFood, onTap: _save),
  ]);
}

/// Choose a day and a meal (copy from / copy to).
Future<({String date, String meal})?> pickDayMeal(
  BuildContext c, {
  required String title,
  required String date,
  required String meal,
  bool showCount = false,
}) => _sheet<({String date, String meal})>(
  c,
  (_) =>
      _DayMealSheet(title: title, date: date, meal: meal, showCount: showCount),
);

class _DayMealSheet extends StatefulWidget {
  const _DayMealSheet({
    required this.title,
    required this.date,
    required this.meal,
    required this.showCount,
  });
  final String title, date, meal;
  final bool showCount;

  @override
  State<_DayMealSheet> createState() => _DayMealSheetState();
}

class _DayMealSheetState extends State<_DayMealSheet> with RevisionReload {
  late String _date = widget.date;
  late String _meal = widget.meal;
  List<FoodEntry> _there = const [];
  bool _reading = true, _failed = false;

  @override
  void reload() => _read();

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    if (!widget.showCount) return;
    final t = beginRead(#copyDay);
    final date = _date;
    setState(() {
      _reading = true;
      _failed = false;
    });
    try {
      final es = await NutritionDb.entriesForDay(await LocalDb.instance, date);
      if (stillNewest(#copyDay, t)) {
        setState(() {
          _there = es;
          _reading = false;
        });
      }
    } catch (_) {
      if (stillNewest(#copyDay, t)) {
        setState(() {
          _failed = true;
          _reading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final inMeal = [
      for (final e in _there)
        if (e.meal == _meal) e,
    ];
    return _body(c, [
      Text(widget.title, style: F.head.copyWith(color: p.ink)),
      const SizedBox(height: S.x4),
      DayHeader(_date, (d) {
        setState(() => _date = d);
        _read();
      }),
      const SizedBox(height: S.x4),
      Wrap(
        spacing: S.x2,
        runSpacing: S.x2,
        children: [
          for (final m in kMeals)
            Pressable(
              onTap: () => setState(() => _meal = m),
              semanticLabel: mealName(m),
              child: Pill(
                mealName(m),
                _meal == m ? C.domFood : C.n400,
                icon: _meal == m ? LucideIcons.check : null,
              ),
            ),
        ],
      ),
      if (widget.showCount) ...[
        const SizedBox(height: S.x3),
        if (_failed)
          StatusCard(
            'Food could not load',
            'Try again before copying.',
            fix: 'Retry',
            onFix: _read,
          )
        else if (_reading)
          const Center(child: CircularProgressIndicator())
        else
          Text(
            inMeal.isEmpty
                ? 'Nothing in ${mealName(_meal)} that day'
                : '${inMeal.length} item${inMeal.length == 1 ? '' : 's'} · '
                      '${thousands(_kcalOf(inMeal))} kcal',
            style: F.cap.copyWith(color: p.ink3),
          ),
      ],
      const SizedBox(height: S.x5),
      BigButton(
        widget.title,
        color: C.domFood,
        onTap: widget.showCount && (_reading || _failed || inMeal.isEmpty)
            ? null
            : () => Navigator.of(c).pop((date: _date, meal: _meal)),
      ),
    ]);
  }
}

// ══════════════════ MEAL PAGE ══════════════════

/// One meal on one day: totals, items under their sub-headings, swipe to
/// delete, tap to change.
/// The saved foods behind [es], for showing each portion's weight.
Future<Map<String, Map<String, Object?>>> _defsFor(
  Database db,
  List<FoodEntry> es,
) async {
  final out = <String, Map<String, Object?>>{};
  for (final k in {for (final e in es) ?e.foodKey}) {
    final d = await NutritionDb.foodDef(db, k);
    if (d != null) out[k] = d;
  }
  return out;
}

/// Everything eaten on one day on one page: day totals, then Breakfast,
/// Lunch, Dinner and Snacks with their sub-headings. A meal (or any item in
/// it) opens that meal's page for changes.
class DayFoodPage extends StatefulWidget {
  const DayFoodPage({super.key, required this.date});
  final String date;

  @override
  State<DayFoodPage> createState() => _DayFoodPageState();
}

class _DayFoodPageState extends State<DayFoodPage> with RevisionReload {
  late String _date = widget.date;
  List<FoodEntry>? _entries;
  Map<String, Map<String, Object?>> _defs = const {};
  bool _failed = false;

  @override
  void reload() => _load();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final t = beginRead(#foodDayPage);
    final date = _date;
    try {
      final db = await LocalDb.instance;
      final es = await NutritionDb.entriesForDay(db, date);
      final defs = await _defsFor(db, es);
      if (stillNewest(#foodDayPage, t)) {
        setState(() => (_entries = es, _defs = defs, _failed = false));
      }
    } catch (_) {
      if (stillNewest(#foodDayPage, t)) setState(() => _failed = true);
    }
  }

  Future<void> _open(String meal) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => MealPage(date: _date, meal: meal)),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final es = _entries;
    return detailScaffold(c, 'Day of food', [
      DayHeader(_date, (d) {
        setState(() => (_date = d, _entries = null));
        _load();
      }),
      const SizedBox(height: S.x4),
      if (_failed)
        StatusCard(
          'Food could not load',
          'Your saved log is intact.',
          fix: 'Retry',
          onFix: _load,
        )
      else if (es == null)
        const Center(child: CircularProgressIndicator())
      else ...[
        Surface(
          child: Text(
            es.isEmpty ? 'Nothing logged this day' : _mealTotals(es),
            style: F.body.copyWith(color: p.ink, fontWeight: FontWeight.w600),
          ),
        ),
        for (final m in kMeals) ..._meal(c, p, m, [
          for (final e in es)
            if (e.meal == m) e,
        ]),
        const SizedBox(height: S.x5),
      ],
    ]);
  }

  List<Widget> _meal(BuildContext c, P p, String meal, List<FoodEntry> es) {
    final groups = <String, List<FoodEntry>>{};
    for (final e in es) {
      (groups[e.group] ??= []).add(e);
    }
    final order = [
      ...groups.keys.where((k) => k.isNotEmpty),
      if (groups.containsKey('')) '',
    ];
    return [
      const SizedBox(height: S.x5),
      Pressable(
        onTap: () => _open(meal),
        semanticLabel: '${mealName(meal)}, open to change',
        child: Row(
          children: [
            Icon(mealIcon(meal), size: 18, color: p.on(C.domFood)),
            const SizedBox(width: S.x2),
            Expanded(
              child: Text(
                mealName(meal),
                style: F.body.copyWith(
                  color: p.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              es.isEmpty ? 'Nothing logged' : _mealTotals(es),
              style: F.cap.copyWith(color: p.ink3),
            ),
            const SizedBox(width: S.x1),
            Icon(LucideIcons.chevronRight, size: 16, color: p.ink3),
          ],
        ),
      ),
      if (es.isNotEmpty) ...[
        const SizedBox(height: S.x2),
        Surface(
          pad: const EdgeInsets.symmetric(horizontal: S.x4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final g in order) ...[
                if (order.length > 1 || g.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: S.x3),
                    child: Text(
                      g.isEmpty ? 'Other' : g,
                      style: F.over.copyWith(color: p.ink3),
                    ),
                  ),
                for (final e in groups[g]!)
                  _EntryRow(e, def: _defs[e.foodKey], onTap: () => _open(meal)),
              ],
            ],
          ),
        ),
      ],
    ];
  }
}

class MealPage extends StatefulWidget {
  const MealPage({super.key, required this.date, required this.meal});
  final String date, meal;

  @override
  State<MealPage> createState() => _MealPageState();
}

class _MealPageState extends State<MealPage> with RevisionReload {
  late String _date = widget.date;
  List<FoodEntry>? _entries;
  Map<String, Map<String, Object?>> _defs = const {};
  bool _failed = false;

  @override
  void reload() => _load();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final t = beginRead(#mealDay);
    final date = _date;
    try {
      final db = await LocalDb.instance;
      final es = await NutritionDb.entriesForDay(db, date);
      final defs = await _defsFor(db, es);
      if (stillNewest(#mealDay, t)) {
        setState(() {
          _entries = [
            for (final e in es)
              if (e.meal == widget.meal) e,
          ];
          _defs = defs;
          _failed = false;
        });
      }
    } catch (_) {
      if (stillNewest(#mealDay, t)) setState(() => _failed = true);
    }
  }

  Future<void> _delete(FoodEntry e) async {
    // Remove the dismissed widget immediately, before the async DB write.
    beginRead(#mealDay); // An older read must not resurrect the dismissed row.
    setState(() => _entries = _entries?.where((x) => x.id != e.id).toList());
    try {
      await NutritionDb.delete(await LocalDb.instance, e.id);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.clearSnackBars();
      messenger.showSnackBar(
        SnackBar(
          content: Text('Deleted ${e.label}'),
          duration: Motion.notice,
          // Flutter otherwise keeps every snackbar with an action open.
          persist: false,
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () async {
              try {
                await NutritionDb.put(await LocalDb.instance, e);
                if (mounted) await _load();
              } catch (_) {
                if (mounted) {
                  _say(
                    context,
                    'Could not restore this entry. Please try again.',
                  );
                }
              }
            },
          ),
        ),
      );
    } catch (_) {
      if (mounted) _say(context, 'Food was not deleted. Please try again.');
    }
    if (mounted) await _load();
  }

  /// Save a drag: new order, and a new sub-heading for anything dropped under
  /// another one.
  Future<void> _arrange(List<(String, FoodEntry)> arranged) async {
    beginRead(#mealDay);
    setState(
      () => _entries = [for (final (g, e) in arranged) e.inGroup(g)],
    );
    try {
      final db = await LocalDb.instance;
      for (final (g, e) in arranged) {
        if (e.group != g) await NutritionDb.put(db, e.inGroup(g));
      }
      await NutritionDb.reorderEntries(db, [for (final (_, e) in arranged) e.id]);
    } catch (_) {
      if (mounted) {
        _say(context, 'The change was not saved. Please try again.');
      }
    }
    if (mounted) await _load();
  }

  Future<void> _itemActions(FoodEntry e) async {
    try {
      final db = await LocalDb.instance;
      final def = e.foodKey == null
          ? null
          : await NutritionDb.foodDef(db, e.foodKey!);
      if (!mounted) return;
      final groups = {
        for (final x in _entries ?? const <FoodEntry>[])
          if (x.group.isNotEmpty) x.group,
      }.toList();
      final choice = await _sheet<String>(
        context,
        (s) => _body(s, [
          Text(e.label, style: F.head.copyWith(color: P.of(s).ink)),
          const SizedBox(height: S.x3),
          if (def != null && e.quantity != null)
            PickRow(
              'Change amount',
              '${portionText(e.quantity!, e.unit)} now',
              trailing: LucideIcons.scale,
              onTap: () => Navigator.of(s).pop('grams'),
            ),
          if (def == null || e.quantity == null)
            PickRow(
              'Edit entry',
              'Change calories, macros, meal or time',
              trailing: LucideIcons.pencil,
              onTap: () => Navigator.of(s).pop('edit'),
            ),
          PickRow(
            'Put under a sub-heading',
            e.group.isEmpty ? 'e.g. Oatmeal, Omelette' : 'Now under ${e.group}',
            trailing: LucideIcons.layers,
            onTap: () => Navigator.of(s).pop('group'),
          ),
          PickRow(
            'Delete',
            'Remove it from this day',
            trailing: LucideIcons.trash2,
            onTap: () => Navigator.of(s).pop('delete'),
          ),
        ]),
      );
      if (!mounted || choice == null) return;
      switch (choice) {
        case 'edit':
          await QuickAddSheet.show(
            context,
            date: e.date,
            meal: e.meal,
            from: e,
            editing: true,
          );
        case 'grams':
          if (unitInBase(def!, e.unit) == null) {
            // A unit the food no longer knows: scale the entry as logged.
            final g = await GramsSheet.show(context, {
              ...def,
              'unit': e.unit,
              'measures_json': '',
            }, initial: e.quantity);
            if (g == null) return;
            await NutritionDb.put(db, e.atQuantity(g.amount));
          } else {
            final g = await GramsSheet.show(
              context,
              def,
              initial: e.quantity,
              initialUnit: e.unit,
              action: 'Save',
            );
            if (g == null) return;
            await NutritionDb.put(
              db,
              entryFromFood(
                def,
                g.base,
                id: e.id,
                date: e.date,
                meal: e.meal,
                atTs: e.atTs,
                amount: g.amount,
                unit: g.unit,
              ).inGroup(e.group),
            );
          }
        case 'group':
          if (!mounted) return;
          final g = await pickFoodGroup(context, groups, e.group);
          if (g == null) return;
          await NutritionDb.put(db, e.inGroup(g));
        case 'delete':
          await NutritionDb.delete(db, e.id);
      }
      if (mounted) await _load();
    } catch (_) {
      if (mounted) {
        _say(context, 'Could not change this entry. Please try again.');
      }
    }
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final es = _entries;
    final groups = <String, List<FoodEntry>>{};
    for (final e in es ?? const <FoodEntry>[]) {
      (groups[e.group] ??= []).add(e);
    }
    // Ungrouped items last when there are sub-headings, untitled otherwise.
    final order = [
      ...groups.keys.where((k) => k.isNotEmpty),
      if (groups.containsKey('')) '',
    ];
    double? sum(double? Function(FoodEntry) f) {
      double? t;
      for (final e in es ?? const <FoodEntry>[]) {
        final v = f(e);
        if (v != null) t = (t ?? 0) + v;
      }
      return t;
    }

    return detailScaffold(c, mealName(widget.meal), [
      DayHeader(_date, (d) {
        setState(() => (_date = d, _entries = null));
        _load();
      }),
      const SizedBox(height: S.x4),
      if (_failed)
        StatusCard(
          'Meal could not load',
          'Try reading your saved food again.',
          fix: 'Retry',
          onFix: _load,
        )
      else if (es == null)
        const Center(child: CircularProgressIndicator())
      else ...[
        Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: S.x2,
                crossAxisAlignment: WrapCrossAlignment.end,
                children: [
                  Text(
                    thousands(sum((e) => e.kcal) ?? 0),
                    style: F.n34.copyWith(color: p.ink),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: S.x1),
                    child: Text('kcal', style: F.cap.copyWith(color: p.ink3)),
                  ),
                ],
              ),
              const SizedBox(height: S.x3),
              InlineMetrics([
                if (sum((e) => e.proteinG) case final v?)
                  ('PROTEIN', '${v.round()} g', C.red),
                if (sum((e) => e.carbsG) case final v?)
                  ('CARBS', '${v.round()} g', C.blue),
                if (sum((e) => e.fatG) case final v?)
                  ('FAT', '${v.round()} g', C.yellow),
                if (sum((e) => e.fibreG) case final v?)
                  ('FIBRE', '${v.round()} g', C.green),
              ]),
            ],
          ),
        ),
        if (es.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: S.x4),
            child: Text(
              'Nothing logged in ${mealName(widget.meal)} this day.',
              style: F.cap.copyWith(color: p.ink3),
            ),
          ),
        if (es.isNotEmpty) ...[
          const SizedBox(height: S.x4),
          // One list across sub-headings: hold an item and drop it under any
          // heading (or No sub-heading) to move it; swipe either way deletes.
          Surface(
            pad: const EdgeInsets.symmetric(horizontal: S.x4),
            child: GroupedDragList<FoodEntry>(
              items: [for (final g in order) ...groups[g]!],
              groupOf: (e) => e.group,
              headerBuilder: (c, g, items) => Padding(
                padding: const EdgeInsets.only(top: S.x3, bottom: S.x1),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        g.isEmpty ? 'No sub-heading' : g,
                        style: F.cap.copyWith(
                          color: p.ink2,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (items.isNotEmpty)
                      Text(
                        '${thousands(_kcalOf(items))} kcal',
                        style: F.cap.copyWith(color: p.ink3),
                      ),
                  ],
                ),
              ),
              onChanged: _arrange,
              itemBuilder: (c, e) => SwipeDelete(
                key: ValueKey(e.id),
                onDelete: () => _delete(e),
                child: _EntryRow(
                  e,
                  def: _defs[e.foodKey],
                  onTap: () => _itemActions(e),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: S.x5),
        BigButton(
          'Add food',
          icon: LucideIcons.plus,
          color: C.domFood,
          onTap: () => openLog(c, _date, widget.meal, _load),
        ),
        if (es.isNotEmpty) ...[
          const SizedBox(height: S.x3),
          BigButton(
            'Copy, or save as a meal',
            icon: LucideIcons.copy,
            color: C.domFood,
            soft: true,
            onTap: () => mealMenu(c, _date, widget.meal, es, _load),
          ),
        ],
        const SizedBox(height: S.x3),
        Text(
          'Tap an item to change it. Hold and drag to reorder or move it under '
          'another sub-heading. Swipe either way to delete.',
          textAlign: TextAlign.center,
          style: F.over.copyWith(color: p.ink3),
        ),
      ],
    ]);
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow(this.e, {this.onTap, this.def});
  final FoodEntry e;
  final VoidCallback? onTap;

  /// The saved food, when known, so "3 links" also reads "· 213 g".
  final Map<String, Object?>? def;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final detail = [
      if (e.quantity != null) portionWithWeight(e.quantity!, e.unit, def),
      if (e.proteinG != null) 'P ${e.proteinG!.round()}',
      if (e.carbsG != null) 'C ${e.carbsG!.round()}',
      if (e.fatG != null) 'F ${e.fatG!.round()}',
    ].join(' · ');
    return Pressable(
      onTap: onTap,
      semanticLabel: '${e.label}, ${e.kcal?.round() ?? 'no'} kcal',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: S.x3),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: F.body.copyWith(color: p.ink),
                  ),
                  if (detail.isNotEmpty)
                    Text(detail, style: F.cap.copyWith(color: p.ink3)),
                ],
              ),
            ),
            const SizedBox(width: S.x3),
            Text(
              e.kcal == null ? '–' : '${e.kcal!.round()}',
              style: F.n17.copyWith(color: p.ink),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════ LOG SCREEN ══════════════════

/// Log food into a meal: search, My foods / My meals, + to log.
class LogFoodScreen extends StatefulWidget {
  const LogFoodScreen({super.key, required this.date, required this.meal});
  final String date, meal;

  @override
  State<LogFoodScreen> createState() => _LogFoodScreenState();
}

class _LogFoodScreenState extends State<LogFoodScreen> with RevisionReload {
  late String _meal = widget.meal;
  String? _group;
  int _tab = 0;
  final _q = TextEditingController();
  List<MealTemplate> _meals = const [];
  List<Map<String, Object?>> _foods = const [];
  bool _loading = true, _failed = false, _busy = false;

  @override
  void reload() => _load();

  @override
  void initState() {
    super.initState();
    _q.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final t = beginRead(#foodPicker);
    try {
      final db = await LocalDb.instance;
      final m = await MyFoods.meals(db);
      final f = await MyFoods.all(db);
      if (stillNewest(#foodPicker, t)) {
        setState(() {
          _meals = m;
          _foods = f;
          _loading = false;
          _failed = false;
        });
      }
    } catch (_) {
      if (stillNewest(#foodPicker, t)) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  Future<void> _act(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        _say(
          context,
          e is StateError
              ? e.message.toString()
              : 'Could not finish. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scan() async {
    final meal = _meal;
    final def = await FoodEditor.scanAndSave(context);
    if (def == null || !mounted) return;
    await FoodDetailSheet.show(
      context,
      def: def,
      date: widget.date,
      meal: meal,
      group: _group ?? '',
    );
    if (mounted) await _load();
  }

  /// + on a food: the portion screen first, prefilled with the amount logged
  /// last time (or the label serving). Nothing is written until Log.
  Future<void> _plusFood(Map<String, Object?> def) => _detail(def);

  /// + on a saved meal: every item's amount reviewed first, then one Log.
  Future<void> _logMeal(MealTemplate m) async {
    final review = await MealReviewSheet.show(context, m);
    if (review == null || !mounted) return;
    final n = await MyFoods.logMeal(
      await LocalDb.instance,
      m,
      widget.date,
      _meal,
      group: _group,
      amounts: review.amounts,
      units: review.units,
    );
    if (mounted) {
      _say(
        context,
        n == 0
            ? 'No foods remain in ${m.label}. Edit the saved meal first.'
            : 'Added ${m.label} · $n item${n == 1 ? '' : 's'}',
      );
    }
  }

  /// The portion screen, opened on the amount and unit last logged for
  /// this food ("3 links"), or its label serving the first time.
  Future<void> _detail(Map<String, Object?> def) async {
    final last = await NutritionDb.lastPortion(
      await LocalDb.instance,
      def['key'] as String,
    );
    if (!mounted) return;
    final ok = await FoodDetailSheet.show(
      context,
      def: def,
      date: widget.date,
      meal: _meal,
      grams: last?.amount,
      unit: last?.unit,
      group: _group ?? '',
    );
    if (ok == true && mounted) _say(context, 'Added ${def['label']}');
  }

  Future<bool> _removeSaved(
    String key,
    String label, {
    required bool meal,
  }) async {
    if (_busy) return false;
    final ok = await confirmRemove(
      context,
      title: 'Remove $label?',
      body:
          'Remove it from My ${meal ? "meals" : "foods"}? Your diary entries stay saved.',
    );
    if (!ok || !mounted || _busy) return false;
    var removed = false;
    await _act(() async {
      final db = await LocalDb.instance;
      if (meal) {
        await MyFoods.deleteMeal(db, key);
      } else {
        await MyFoods.deleteFood(db, key);
      }
      removed = true;
      await _load();
    });
    return removed;
  }

  /// Save a dragged order; the Foods tab reads the same one.
  Future<void> _reorderSaved({
    required bool meal,
    required List<String> keys,
  }) async {
    setState(() {
      if (meal) {
        final by = {for (final m in _meals) m.key: m};
        _meals = [for (final k in keys) ?by[k]];
      } else {
        final by = {for (final f in _foods) f['key'] as String: f};
        _foods = [for (final k in keys) ?by[k]];
      }
    });
    try {
      final db = await LocalDb.instance;
      meal
          ? await MyFoods.reorderMeals(db, keys)
          : await MyFoods.reorderFoods(db, keys);
    } catch (_) {
      if (mounted) _say(context, 'The new order was not saved. Please try again.');
    }
    if (mounted) await _load();
  }

  Future<void> _pickMeal() async {
    final m = await _sheet<String>(
      context,
      (s) => _body(s, [
        Text('Log to', style: F.head.copyWith(color: P.of(s).ink)),
        const SizedBox(height: S.x2),
        for (final m in kMeals)
          PickRow(
            mealName(m),
            m == _meal ? 'Selected' : '',
            trailing: m == _meal ? LucideIcons.check : null,
            onTap: () => Navigator.of(s).pop(m),
          ),
      ]),
    );
    if (m != null) {
      setState(() {
        _meal = m;
        _group = null;
      });
    }
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final q = _q.text.trim().toLowerCase();
    bool hit(String s) => q.isEmpty || s.toLowerCase().contains(q);
    // One order, Akshat's own (dragged here or on Food → Foods). Search
    // filters it without changing it; dragging is off while searching.
    final foods = [
      for (final f in _foods)
        if (hit('${f['label']}')) f,
    ];
    final meals = [
      for (final m in _meals)
        if (hit(m.label)) m,
    ];

    Widget row(
      String title,
      String detail,
      Future<void> Function() onPlus,
      Future<void> Function() onTap,
      String key,
      bool meal,
    ) => SwipeDelete(
      key: ValueKey('saved-$key'),
      // Reload owns removal; a failed/cancelled write keeps the row.
      onDelete: () => _removeSaved(key, title, meal: meal),
      child: Padding(
        padding: const EdgeInsets.only(bottom: S.x2),
        child: Surface(
          onTap: _busy ? null : () => _act(onTap),
          semanticLabel: '$title, $detail',
          pad: const EdgeInsets.fromLTRB(S.x4, S.x3, S.x2, S.x3),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: F.body.copyWith(color: p.ink),
                    ),
                    Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: F.cap.copyWith(color: p.ink3),
                    ),
                  ],
                ),
              ),
              Pressable(
                semanticLabel: 'Log $title',
                onTap: _busy ? null : () => _act(onPlus),
                child: Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: p.wash(C.domFood),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    LucideIcons.plus,
                    size: 18,
                    color: p.on(C.domFood),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    Widget tile(IconData icon, String label, VoidCallback onTap) => Expanded(
      child: Surface(
        onTap: _busy ? null : onTap,
        semanticLabel: label,
        pad: const EdgeInsets.symmetric(vertical: S.x3),
        child: Column(
          children: [
            Icon(icon, size: 20, color: p.on(C.domFood)),
            const SizedBox(height: S.x1),
            Text(
              label,
              textAlign: TextAlign.center,
              style: F.over.copyWith(color: p.ink2),
            ),
          ],
        ),
      ),
    );

    Widget mealRow(MealTemplate m) => row(
      m.label,
      '${m.items.length} food${m.items.length == 1 ? '' : 's'} · ${mealName(m.meal)}',
      () => _logMeal(m),
      () async {
        await MealEditor.show(context, existing: m);
        await _load();
      },
      m.key,
      true,
    );
    Widget foodRow(Map<String, Object?> f) => row(
      '${f['label']}',
      [
        if (f['kcal_100'] is num && f['serving_g'] is num)
          '${((f['kcal_100'] as num) * (f['serving_g'] as num) / 100).round()} kcal',
        if (f['serving_g'] is num)
          portionText(f['serving_g'] as num, foodUnit(f)),
      ].join(', '),
      () => _plusFood(f),
      () => _detail(f),
      f['key'] as String,
      false,
    );
    final searching = q.isNotEmpty;
    final list = <Widget>[
      if (_tab == 1) ...[
        if (meals.isEmpty)
          _empty(p, 'Save a meal from its ⋯ menu to log it in one tap.'),
        if (searching)
          for (final m in meals) mealRow(m)
        else
          DragList(
            length: meals.length,
            itemBuilder: (_, i) => mealRow(meals[i]),
            onReorder: (from, to) => _reorderSaved(
              meal: true,
              keys: [for (final m in reordered(meals, from, to)) m.key],
            ),
          ),
      ],
      if (_tab == 0) ...[
        if (foods.isEmpty) _empty(p, 'Create a food once from its label.'),
        if (searching)
          for (final f in foods) foodRow(f)
        else
          DragList(
            length: foods.length,
            itemBuilder: (_, i) => foodRow(foods[i]),
            onReorder: (from, to) => _reorderSaved(
              meal: false,
              keys: [
                for (final f in reordered(foods, from, to)) f['key'] as String,
              ],
            ),
          ),
      ],
    ];

    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(S.x4, S.x2, S.x4, S.x10),
          children: [
            Row(
              children: [
                Pressable(
                  semanticLabel: 'Back',
                  onTap: () => Navigator.of(c).maybePop(),
                  child: Icon(LucideIcons.arrowLeft, size: 22, color: p.ink),
                ),
                Expanded(
                  child: Pressable(
                    semanticLabel: 'Log to ${mealName(_meal)}',
                    onTap: _pickMeal,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          mealName(_meal),
                          style: F.head.copyWith(color: p.on(C.domFood)),
                        ),
                        const SizedBox(width: S.x1),
                        Icon(
                          LucideIcons.chevronDown,
                          size: 18,
                          color: p.on(C.domFood),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 22),
              ],
            ),
            Center(
              child: Text(
                dayTitle(widget.date),
                style: F.over.copyWith(color: p.ink3),
              ),
            ),
            const SizedBox(height: S.x3),
            MealGroupPicker(
              date: widget.date,
              meal: _meal,
              group: _group ?? '',
              onChanged: (g) => setState(() => _group = g),
            ),
            const SizedBox(height: S.x2),
            OsTextField(controller: _q, label: 'Search', hint: 'Oats, eggs…'),
            const SizedBox(height: S.x3),
            Row(
              children: [
                tile(
                  LucideIcons.plus,
                  'Create a food',
                  () => _act(() async {
                    final def = await FoodEditor.show(c);
                    await _load();
                    if (def != null && mounted) await _detail(def);
                  }),
                ),
                const SizedBox(width: S.x2),
                tile(
                  LucideIcons.zap,
                  'Quick add',
                  () => _act(() async {
                    await QuickAddSheet.show(
                      c,
                      date: widget.date,
                      meal: _meal,
                      group: _group ?? '',
                    );
                    await _load();
                  }),
                ),
                const SizedBox(width: S.x2),
                tile(LucideIcons.scanBarcode, 'Scan', () => _act(_scan)),
              ],
            ),
            const SizedBox(height: S.x4),
            SubTabs(
              const ['My foods', 'My meals'],
              _tab,
              (i) => setState(() => _tab = i),
              color: C.domFood,
            ),
            const SizedBox(height: S.x2),
            Text(
              'Hold a row to drag it into your own order. Swipe to delete.',
              style: F.over.copyWith(color: p.ink3),
            ),
            const SizedBox(height: S.x3),
            if (_busy)
              Padding(
                padding: const EdgeInsets.only(bottom: S.x3),
                child: Text('Working…', style: F.over.copyWith(color: p.ink3)),
              ),
            if (_failed)
              StatusCard(
                'Foods could not load',
                'Try reading your saved foods again.',
                fix: 'Retry',
                onFix: _load,
              )
            else if (_loading)
              const Center(child: CircularProgressIndicator())
            else
              ...list,
          ],
        ),
      ),
    );
  }

  Widget _empty(P p, String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: S.x5),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: F.cap.copyWith(color: p.ink3),
    ),
  );
}

// ══════════════════ FOOD DETAIL ══════════════════

/// A food before it is logged: grams, meal, time, nutrition as % of the
/// daily goals, and the foods usually eaten with it.
class FoodDetailSheet extends StatefulWidget {
  const FoodDetailSheet({
    super.key,
    required this.def,
    required this.date,
    required this.meal,
    this.grams,
    this.unit,
    this.group = '',
  });

  final Map<String, Object?> def;
  final String date, meal;

  /// The starting amount, in [unit] (the label unit when null).
  final double? grams;
  final String? unit;
  final String group;

  static Future<bool?> show(
    BuildContext c, {
    required Map<String, Object?> def,
    required String date,
    required String meal,
    double? grams,
    String? unit,
    String group = '',
  }) => _sheet<bool>(
    c,
    (_) => FoodDetailSheet(
      def: def,
      date: date,
      meal: meal,
      grams: grams,
      unit: unit,
      group: group,
    ),
  );

  @override
  State<FoodDetailSheet> createState() => _FoodDetailSheetState();
}

class _FoodDetailSheetState extends State<FoodDetailSheet> {
  late Map<String, Object?> _def = widget.def;
  bool _saving = false;
  String? _error;
  late final TextEditingController _g = TextEditingController(
    text: _trim(
      widget.grams ?? (widget.def['serving_g'] as num?)?.toDouble() ?? 100,
    ),
  );
  late String _meal = widget.meal;
  late String _group = widget.group;
  late final _unit = ValueNotifier<String>(
    widget.unit != null && unitInBase(widget.def, widget.unit!) != null
        ? widget.unit!
        : foodUnit(widget.def),
  );
  late TimeOfDay _time = TimeOfDay.fromDateTime(
    foodEntryTime(widget.date, widget.meal),
  );
  List<Map<String, Object?>> _with = const [];
  final _picked = <String>{};

  static String _trim(double v) => editableNumber(v);

  @override
  void initState() {
    super.initState();
    _g.addListener(() => setState(() {}));
    _unit.addListener(() => setState(() {}));
    _loadWith();
  }

  @override
  void dispose() {
    _g.dispose();
    _unit.dispose();
    super.dispose();
  }

  Future<void> _loadWith() async {
    final key = _def['key'] as String?;
    if (key == null) return;
    try {
      final w = await NutritionDb.eatenWith(await LocalDb.instance, key);
      if (mounted) setState(() => _with = w);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Companion foods could not load. You can still log this food.',
        );
      }
    }
  }

  int get _ts {
    final d = DateTime.parse(widget.date);
    return DateTime(
          d.year,
          d.month,
          d.day,
          _time.hour,
          _time.minute,
        ).millisecondsSinceEpoch ~/
        1000;
  }

  Future<void> _log() async {
    if (_saving) return;
    final grams = Typed.of(_g.text).value;
    final base = grams == null ? null : toBase(_def, grams, _unit.value);
    if (grams == null || grams <= 0 || base == null) {
      setState(() => _error = 'Enter an amount greater than zero.');
      return;
    }
    final unit = _unit.value;
    setState(() {
      _saving = true;
      _error = null;
    });
    final meal = _meal, ts = _ts;
    final companions = [
      for (final w in _with)
        if (_picked.contains(w['key'])) w,
    ];
    try {
      final db = await LocalDb.instance;
      await db.transaction((tx) async {
        await NutritionDb.put(
          tx,
          entryFromFood(
            _def,
            base,
            id: NutritionDb.newId(),
            date: widget.date,
            meal: meal,
            atTs: ts,
            amount: grams,
            unit: unit,
          ).inGroup(_group),
          notify: false,
        );
        var i = 0;
        for (final w in companions) {
          final g =
              (w['usual_g'] as num?)?.toDouble() ??
              (w['serving_g'] as num?)?.toDouble() ??
              100;
          await NutritionDb.put(
            tx,
            entryFromFood(
              w,
              g,
              id: '${NutritionDb.newId()}_${i++}',
              date: widget.date,
              meal: meal,
              atTs: ts,
            ).inGroup(_group),
            notify: false,
          );
        }
      });
      NutritionDb.changed();
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not save. Your portion is still here; try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final profile = c.watch<AppState>().user ?? const <String, dynamic>{};
    double? goal(String k) => (profile[k] as num?)?.toDouble();
    final grams = Typed.of(_g.text).value;
    final base = grams == null ? null : toBase(_def, grams, _unit.value);
    final n = base == null ? null : nutrientsFor(_def, base);
    String pct(double? v, double? g) =>
        v == null || g == null || g <= 0 ? '' : '${(v / g * 100).round()}%';
    final macros = <(String, double?, double?, Color)>[
      ('Calories', n?.kcal, goal('kcal_target'), C.domFood),
      ('Protein', n?.protein, goal('protein_target'), C.red),
      ('Carbs', n?.carbs, goal('carbs_target'), C.blue),
      ('Fat', n?.fat, goal('fat_target'), C.yellow),
      ('Fibre', n?.fibre, goal('fibre_target'), C.green),
    ];
    return _body(c, [
      _sheetTitle(c, '${_def['label']}'),
      const SizedBox(height: S.x4),
      // One amount control everywhere: − / +, and chips labelled once
      // (eggs: 1 · 2 · 3 · 4; a weighed food: its measures and grams).
      AmountInput(controller: _g, def: _def, unit: _unit),
      const SizedBox(height: S.x2),
      MealGroupPicker(
        date: widget.date,
        meal: _meal,
        group: _group,
        onChanged: (g) => setState(() => _group = g),
      ),
      const SizedBox(height: S.x4),
      Wrap(
        spacing: S.x2,
        runSpacing: S.x2,
        children: [
          for (final m in kMeals)
            Pressable(
              onTap: () => setState(() {
                _meal = m;
                _group = '';
              }),
              semanticLabel: mealName(m),
              child: Pill(
                mealName(m),
                _meal == m ? C.domFood : C.n400,
                icon: _meal == m ? LucideIcons.check : null,
              ),
            ),
          Pressable(
            semanticLabel: 'Time ${_time.format(c)}',
            onTap: () async {
              final t = await showTimePicker(context: c, initialTime: _time);
              if (t != null && mounted) setState(() => _time = t);
            },
            child: Pill(_time.format(c), C.n400, icon: LucideIcons.clock),
          ),
        ],
      ),
      const SizedBox(height: S.x4),
      Surface(
        elevation: 0,
        color: p.card2,
        child: Column(
          children: [
            // Name left, amount and % of goal right, every row aligned.
            for (final (name, v, g, col) in macros)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: S.x1),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(name, style: F.body.copyWith(color: p.ink)),
                    ),
                    Text(
                      v == null
                          ? '–'
                          : name == 'Calories'
                          ? '${v.round()} kcal'
                          : '${v.toStringAsFixed(1)} g',
                      style: F.body.copyWith(
                        color: p.ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(
                      width: 48,
                      child: Text(
                        pct(v, g),
                        textAlign: TextAlign.right,
                        style: F.cap.copyWith(color: p.on(col)),
                      ),
                    ),
                  ],
                ),
              ),
            if (macros.any((m) => m.$3 != null))
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '% of your daily goal',
                  style: F.over.copyWith(color: p.ink3),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: S.x2),
      PickRow(
        'Edit saved food',
        'Changes its label values and measures for every future log',
        trailing: LucideIcons.pencil,
        onTap: _saving
            ? null
            : () async {
                final def = await FoodEditor.show(c, existing: _def);
                if (def != null && mounted) setState(() => _def = def);
              },
      ),
      if (_def['source'] == 'barcode') ...[
        const SizedBox(height: S.x2),
        offCredit(),
      ],
      if (_error != null)
        Text(_error!, style: F.cap.copyWith(color: p.on(C.red))),
      if (_with.isNotEmpty) ...[
        const SizedBox(height: S.x4),
        Text('Often eaten with', style: F.over.copyWith(color: p.ink3)),
        for (final w in _with)
          Pressable(
            semanticLabel: 'Also log ${w['label']}',
            onTap: () => setState(() {
              final k = w['key'] as String;
              _picked.contains(k) ? _picked.remove(k) : _picked.add(k);
            }),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: S.x2),
              child: Row(
                children: [
                  Icon(
                    _picked.contains(w['key'])
                        ? LucideIcons.squareCheck
                        : LucideIcons.square,
                    size: 20,
                    color: p.on(C.domFood),
                  ),
                  const SizedBox(width: S.x3),
                  Expanded(
                    child: Text(
                      '${w['label']}',
                      style: F.body.copyWith(color: p.ink),
                    ),
                  ),
                  if (w['usual_g'] is num)
                    Text(
                      portionText(w['usual_g'] as num, foodUnit(w)),
                      style: F.cap.copyWith(color: p.ink3),
                    ),
                ],
              ),
            ),
          ),
      ],
      const SizedBox(height: S.x5),
      BigButton(
        _saving
            ? 'Saving…'
            : _picked.isEmpty
            ? 'Log'
            : 'Log ${_picked.length + 1} foods',
        color: C.domFood,
        onTap: _saving ? null : _log,
      ),
    ]);
  }
}

// ══════════════════ QUICK ADD ══════════════════

/// Calories and macros without a saved food, WITH a name so the day still
/// says what it was. [from] pre-fills from an earlier entry.
class QuickAddSheet extends StatefulWidget {
  const QuickAddSheet({
    super.key,
    required this.date,
    required this.meal,
    this.from,
    this.editing = false,
    this.group = '',
  });
  final String date, meal;
  final FoodEntry? from;
  final bool editing;
  final String group;

  static Future<bool?> show(
    BuildContext c, {
    required String date,
    required String meal,
    FoodEntry? from,
    bool editing = false,
    String group = '',
  }) => _sheet<bool>(
    c,
    (_) => QuickAddSheet(
      date: date,
      meal: meal,
      from: from,
      editing: editing,
      group: group,
    ),
  );

  @override
  State<QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends State<QuickAddSheet> {
  late final _name = TextEditingController(text: widget.from?.label ?? '');
  late final _kcal = TextEditingController(text: _t(widget.from?.kcal));
  late final _p = TextEditingController(text: _t(widget.from?.proteinG));
  late final _c = TextEditingController(text: _t(widget.from?.carbsG));
  late final _f = TextEditingController(text: _t(widget.from?.fatG));
  late final _fibre = TextEditingController(text: _t(widget.from?.fibreG));

  /// What the portion weighed, for reference: stored as the entry's amount in
  /// grams ("Protein shake · 250 g"). It never scales the numbers typed here.
  late final _grams = TextEditingController(
    text: widget.from?.unit == 'g' ? _t(widget.from?.quantity) : '',
  );

  /// Also keep it as a food in My foods, its serving being this weight (or one
  /// serving without one), so next time it logs from the list.
  bool _saveFood = false;
  bool _saving = false;
  String? _error;
  late String _meal = widget.meal;
  late String _group = widget.editing
      ? widget.from?.group ?? widget.group
      : widget.group;
  late TimeOfDay _time = TimeOfDay.fromDateTime(
    widget.editing && widget.from?.atTs != null
        ? DateTime.fromMillisecondsSinceEpoch(widget.from!.atTs! * 1000)
        : foodEntryTime(widget.date, widget.meal),
  );

  static String _t(double? v) => editableNumber(v);

  @override
  void dispose() {
    for (final t in [_name, _kcal, _p, _c, _f, _fibre, _grams]) {
      t.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final fields = {
      'Calories': _kcal,
      'Protein': _p,
      'Carbs': _c,
      'Fat': _f,
      'Fibre': _fibre,
      'Weight': _grams,
    };
    final bad = [
      for (final e in fields.entries)
        if (Typed.of(e.value.text, nonNegative: true).bad) e.key,
    ];
    if (bad.isNotEmpty) {
      setState(
        () => _error = 'Check ${bad.join(', ')}: enter a non-negative number.',
      );
      return;
    }
    final kcal = Typed.of(_kcal.text).value;
    if (kcal == null) {
      setState(() => _error = 'Enter calories. Other macros can stay blank.');
      return;
    }
    final grams = Typed.of(_grams.text).value;
    if (grams != null && grams <= 0) {
      setState(() => _error = 'Enter a weight above zero, or leave it blank.');
      return;
    }
    final name = _name.text.trim();
    if (_saveFood && name.isEmpty) {
      setState(() => _error = 'Name it to save it to My foods.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final d = DateTime.parse(widget.date);
    final original = widget.editing ? widget.from : null;
    final previousTime = original?.atTs == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(original!.atTs! * 1000);
    final keepTime =
        previousTime != null &&
        dayLabelOf(previousTime) == widget.date &&
        previousTime.hour == _time.hour &&
        previousTime.minute == _time.minute;
    try {
      final db = await LocalDb.instance;
      String? savedKey;
      if (_saveFood) {
        final def = myFoodDef(
          key: 'my:${DateTime.now().microsecondsSinceEpoch}',
          label: name,
          refGrams: grams ?? 1,
          unit: grams == null ? 'serving' : 'g',
          kcal: kcal,
          protein: Typed.of(_p.text).value,
          carbs: Typed.of(_c.text).value,
          fat: Typed.of(_f.text).value,
          fibre: Typed.of(_fibre.text).value,
        );
        await NutritionDb.putFoodDef(db, def);
        savedKey = def['key'] as String;
      }
      await NutritionDb.put(
        db,
        FoodEntry(
          id: original?.id ?? NutritionDb.newId(),
          date: widget.date,
          meal: _meal,
          label: name.isEmpty ? 'Quick add' : name,
          atTs: keepTime
              ? original!.atTs
              : DateTime(
                      d.year,
                      d.month,
                      d.day,
                      _time.hour,
                      _time.minute,
                    ).millisecondsSinceEpoch ~/
                    1000,
          kcal: kcal,
          proteinG: Typed.of(_p.text).value,
          carbsG: Typed.of(_c.text).value,
          fatG: Typed.of(_f.text).value,
          fibreG: Typed.of(_fibre.text).value,
          foodKey: savedKey ?? original?.foodKey,
          quantity: grams ?? (savedKey != null ? 1 : null),
          unit: grams != null
              ? 'g'
              : savedKey != null
              ? 'serving'
              : original?.unit ?? 'g',
          sugarG: original?.sugarG,
          satFatG: original?.satFatG,
          sodiumMg: original?.sodiumMg,
          ironMg: original?.ironMg,
          calciumMg: original?.calciumMg,
          source: original?.source ?? FoodSource.manual,
          note: original?.note ?? '',
          group: _group,
          confirmed: true,
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not save. Your values are still here; try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    const num = TextInputType.numberWithOptions(decimal: true);
    Widget pair(Widget a, Widget b) => Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: a),
        const SizedBox(width: S.x2),
        Expanded(child: b),
      ],
    );
    return _body(c, [
      _sheetTitle(c, widget.editing ? 'Edit entry' : 'Quick add'),
      const SizedBox(height: S.x4),
      OsTextField(
        controller: _name,
        label: 'Name',
        hint: 'Protein shake at the gym',
      ),
      const SizedBox(height: S.x3),
      Wrap(
        spacing: S.x2,
        runSpacing: S.x2,
        children: [
          for (final m in kMeals)
            Pressable(
              onTap: () => setState(() {
                _meal = m;
                _group = '';
              }),
              semanticLabel: mealName(m),
              child: Pill(
                mealName(m),
                _meal == m ? C.domFood : C.n400,
                icon: _meal == m ? LucideIcons.check : null,
              ),
            ),
          Pressable(
            semanticLabel: 'Time ${_time.format(c)}',
            onTap: () async {
              final t = await showTimePicker(context: c, initialTime: _time);
              if (t != null && mounted) setState(() => _time = t);
            },
            child: Pill(_time.format(c), C.n400, icon: LucideIcons.clock),
          ),
        ],
      ),
      const SizedBox(height: S.x3),
      MealGroupPicker(
        date: widget.date,
        meal: _meal,
        group: _group,
        onChanged: (g) => setState(() => _group = g),
      ),
      const SizedBox(height: S.x3),
      pair(
        OsTextField(controller: _kcal, label: 'Calories (kcal)', keyboard: num),
        OsTextField(
          controller: _grams,
          label: 'Weight (g)',
          hint: 'Optional',
          keyboard: num,
        ),
      ),
      const SizedBox(height: S.x3),
      pair(
        OsTextField(controller: _p, label: 'Protein (g)', keyboard: num),
        OsTextField(controller: _c, label: 'Carbs (g)', keyboard: num),
      ),
      const SizedBox(height: S.x3),
      pair(
        OsTextField(controller: _f, label: 'Fat (g)', keyboard: num),
        OsTextField(controller: _fibre, label: 'Fibre (g)', keyboard: num),
      ),
      const SizedBox(height: S.x2),
      Text(
        'Blank macros are not tracked. Enter 0 for a known zero.',
        style: F.over.copyWith(color: p.ink3),
      ),
      if (!widget.editing) ...[
        const SizedBox(height: S.x3),
        Align(
          alignment: Alignment.centerLeft,
          child: Pressable(
            semanticLabel: 'Save to My foods',
            onTap: () => setState(() => _saveFood = !_saveFood),
            child: Pill(
              'Save to My foods',
              _saveFood ? C.domFood : C.n400,
              icon: _saveFood ? LucideIcons.check : LucideIcons.plus,
            ),
          ),
        ),
      ],
      if (_error != null) ...[
        const SizedBox(height: S.x3),
        Text(_error!, style: F.cap.copyWith(color: p.on(C.red))),
      ],
      const SizedBox(height: S.x5),
      BigButton(
        _saving
            ? 'Saving…'
            : widget.editing
            ? 'Save changes'
            : 'Add',
        icon: LucideIcons.check,
        color: C.domFood,
        onTap: _saving ? null : _save,
      ),
    ]);
  }
}
