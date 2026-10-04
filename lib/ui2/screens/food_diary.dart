// Food, in the MyFitnessPal shape but cleaner (Akshat's 3 October brief):
//
//   · Day header: ‹ Today ›, swipe between days, tap the date for a calendar.
//   · Meal cards: "Oats and 4 more · 854 kcal", a Log button, and a ⋯ menu
//     with Copy from, Copy to and Save meal. Tapping a card opens that meal.
//   · Meal page: every item, under its sub-heading ("Oatmeal", "Omelette"),
//     swipe left to delete, tap to change the grams or move it to a group.
//   · Log screen: a meal selector, search, Recent / My meals / My foods, a
//     sort, + to log at once, tap for the food's detail.
//   · Food detail: grams, meal, time, calories and macros as % of the daily
//     goals, and "Often eaten with" for one-tap companions.
//   · Quick add with a NAME (MyFitnessPal's is anonymous), meal and time.
//
// No ads, no upsells, macros always free.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../data/db.dart';
import '../../data/day_label.dart';
import '../../data/nutrition_store.dart';
import '../../state/app_state.dart';
import '../ui2.dart';
import 'food_picker.dart';
import 'home_screen.dart' show prettyDay, thousands;
import 'journal_compose.dart' show OsTextField;
import 'log_food.dart' show scanFoodProduct, offCredit;
import '../../data/off_lookup.dart';
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
    return Row(children: [
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
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(dayTitle(date),
                style: F.body.copyWith(color: p.ink, fontWeight: FontWeight.w600)),
            const SizedBox(width: S.x1),
            Icon(LucideIcons.chevronDown, size: 16, color: p.ink3),
          ]),
        ),
      ),
      Pressable(
        semanticLabel: 'Next day',
        onTap: atToday ? null : () => onDay(shiftDay(date, 1)),
        child: Icon(LucideIcons.chevronRight,
            size: 22, color: atToday ? p.line : p.ink2),
      ),
    ]);
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
  const MealCard(
      {super.key,
      required this.date,
      required this.meal,
      required this.entries,
      required this.onChanged});

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
        child: Row(children: [
          Icon(mealIcon(meal), size: 20, color: p.on(C.domFood)),
          const SizedBox(width: S.x3),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(mealName(meal),
                  style: F.body.copyWith(color: p.ink, fontWeight: FontWeight.w600)),
              Text(summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: F.cap.copyWith(color: p.ink2)),
              if (entries.isNotEmpty)
                Text('${thousands(_kcalOf(entries))} kcal',
                    style: F.over.copyWith(color: p.ink3)),
            ]),
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
        ]),
      ),
    );
  }
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

Future<T?> _sheet<T>(BuildContext c, WidgetBuilder b) => showModalBottomSheet<T>(
      context: c,
      isScrollControlled: true,
      sheetAnimationStyle: sheetMotion(c),
      backgroundColor: P.of(c).card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(R.xxl)),
      ),
      builder: b,
    );

Widget _body(BuildContext s, List<Widget> children) => SafeArea(
  top: false,
  child: Padding(
      padding: EdgeInsets.only(
          left: S.x5,
          right: S.x5,
          top: S.x5,
          bottom: MediaQuery.of(s).viewInsets.bottom + S.x5),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
  ),
    );

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
Future<void> mealMenu(BuildContext c, String date, String meal,
    List<FoodEntry> entries, VoidCallback onChanged) async {
  final choice = await _sheet<String>(
    c,
    (s) => _body(s, [
      Text(mealName(meal), style: F.head.copyWith(color: P.of(s).ink)),
      const SizedBox(height: S.x3),
      PickRow('Copy from', 'Bring in a meal from another day',
          trailing: LucideIcons.copy, onTap: () => Navigator.of(s).pop('from')),
      if (entries.isNotEmpty) ...[
        PickRow('Copy to', 'Log this meal on another day or meal',
            trailing: LucideIcons.copyPlus, onTap: () => Navigator.of(s).pop('to')),
        PickRow('Save meal', 'Keep it in My meals for one-tap logging',
            trailing: LucideIcons.bookmark, onTap: () => Navigator.of(s).pop('save')),
      ],
    ]),
  );
  if (!c.mounted || choice == null) return;
  final db = await LocalDb.instance;
  if (!c.mounted) return;
  switch (choice) {
    case 'from':
      final src = await pickDayMeal(c,
          title: 'Copy from', date: shiftDay(date, -1), meal: meal, showCount: true);
      if (src == null) return;
      final n = await NutritionDb.copyMeal(db,
          fromDate: src.date, fromMeal: src.meal, toDate: date, toMeal: meal);
      if (c.mounted) {
        _say(c, n == 0 ? 'Nothing to copy there' : 'Copied $n item${n == 1 ? '' : 's'}');
      }
    case 'to':
      final dst = await pickDayMeal(c,
          title: 'Copy to', date: date == todayLabel() ? date : todayLabel(), meal: meal);
      if (dst == null) return;
      final n = await NutritionDb.copyMeal(db,
          fromDate: date, fromMeal: meal, toDate: dst.date, toMeal: dst.meal);
      if (c.mounted) {
        _say(c, 'Copied $n item${n == 1 ? '' : 's'} to ${mealName(dst.meal)}, '
            '${dayTitle(dst.date)}');
      }
    case 'save':
      final name = await askText(c, 'Save meal', 'Name', mealName(meal));
      if (name == null) return;
      final r = await MyFoods.saveMeal(db, label: name, meal: meal, entries: entries);
      if (c.mounted) {
        _say(
            c,
            r.saved == 0
                ? 'Only your own foods can go in a saved meal'
                : 'Saved "$name"${r.skipped > 0 ? ' · ${r.skipped} quick add${r.skipped == 1 ? '' : 's'} left out' : ''}');
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
}) async {
  final t = TextEditingController(text: initial);
  String? error;
  bool closing = false;
  final ok = await _sheet<bool>(
    c,
    (s) => StatefulBuilder(
      builder: (s, update) => _body(s, [
        _sheetTitle(s, title),
      const SizedBox(height: S.x4),
        OsTextField(controller: t, label: label, keyboard: keyboard),
        if (error != null)
          Text(error!, style: F.cap.copyWith(color: P.of(s).on(C.red))),
      const SizedBox(height: S.x4),
        BigButton(
          'Save',
          color: C.domFood,
          onTap: () {
            if (closing) return;
            final value = t.text.trim();
            final invalid =
                validate?.call(value) ??
                (value.isEmpty ? 'Enter $label.' : null);
            if (invalid != null) {
              update(() => error = invalid);
              return;
            }
            closing = true;
            Navigator.of(s).pop(true);
          },
        ),
    ]),
    ),
  );
  final v = t.text.trim();
  t.dispose();
  return ok == true && v.isNotEmpty ? v : null;
}

/// Choose a day and a meal (copy from / copy to).
Future<({String date, String meal})?> pickDayMeal(BuildContext c,
        {required String title,
        required String date,
        required String meal,
        bool showCount = false}) =>
    _sheet<({String date, String meal})>(
        c,
        (_) => _DayMealSheet(
            title: title, date: date, meal: meal, showCount: showCount));

class _DayMealSheet extends StatefulWidget {
  const _DayMealSheet(
      {required this.title,
      required this.date,
      required this.meal,
      required this.showCount});
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
      if (stillNewest(#copyDay, t))
        setState(() {
          _there = es;
          _reading = false;
        });
    } catch (_) {
      if (stillNewest(#copyDay, t))
        setState(() {
          _failed = true;
          _reading = false;
        });
    }
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final inMeal = [for (final e in _there) if (e.meal == _meal) e];
    return _body(c, [
      Text(widget.title, style: F.head.copyWith(color: p.ink)),
      const SizedBox(height: S.x4),
      DayHeader(_date, (d) {
        setState(() => _date = d);
        _read();
      }),
      const SizedBox(height: S.x4),
      Wrap(spacing: S.x2, runSpacing: S.x2, children: [
        for (final m in kMeals)
          Pressable(
            onTap: () => setState(() => _meal = m),
            semanticLabel: mealName(m),
            child: Pill(mealName(m), _meal == m ? C.domFood : C.n400,
                icon: _meal == m ? LucideIcons.check : null),
          ),
      ]),
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
            style: F.cap.copyWith(color: p.ink3)),
      ],
      const SizedBox(height: S.x5),
      BigButton(widget.title,
          color: C.domFood,
        onTap: widget.showCount && (_reading || _failed || inMeal.isEmpty)
              ? null
              : () => Navigator.of(c).pop((date: _date, meal: _meal))),
    ]);
  }
}

// ══════════════════ MEAL PAGE ══════════════════

/// One meal on one day: totals, items under their sub-headings, swipe to
/// delete, tap to change.
class MealPage extends StatefulWidget {
  const MealPage({super.key, required this.date, required this.meal});
  final String date, meal;

  @override
  State<MealPage> createState() => _MealPageState();
}

class _MealPageState extends State<MealPage> with RevisionReload {
  late String _date = widget.date;
  List<FoodEntry>? _entries;
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
      final es = await NutritionDb.entriesForDay(await LocalDb.instance, date);
      if (stillNewest(#mealDay, t))
        setState(() {
          _entries = [
            for (final e in es)
              if (e.meal == widget.meal) e,
          ];
          _failed = false;
        });
    } catch (_) {
      if (stillNewest(#mealDay, t)) setState(() => _failed = true);
    }
  }

  Future<void> _delete(FoodEntry e) async {
    // Remove the dismissed widget immediately, before the async DB write.
    setState(() => _entries = _entries?.where((x) => x.id != e.id).toList());
    try {
    await NutritionDb.delete(await LocalDb.instance, e.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Deleted ${e.label}'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () async {
              try {
                await NutritionDb.put(await LocalDb.instance, e);
              } catch (_) {
                if (mounted)
                  _say(
                    context,
                    'Could not restore this entry. Please try again.',
                  );
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

  Future<void> _itemActions(FoodEntry e) async {
    try {
    final db = await LocalDb.instance;
    final def = e.foodKey == null ? null : await NutritionDb.foodDef(db, e.foodKey!);
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
          PickRow('Change amount', '${e.quantity!.round()} g now',
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
            onTap: () => Navigator.of(s).pop('group')),
        PickRow('Delete', 'Remove it from this day',
            trailing: LucideIcons.trash2,
            onTap: () => Navigator.of(s).pop('delete')),
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
        final grams = await GramsSheet.show(context, def!, initial: e.quantity);
        if (grams == null) return;
        await NutritionDb.put(
            db,
            entryFromFood(def, grams,
                    id: e.id, date: e.date, meal: e.meal, atTs: e.atTs)
                .inGroup(e.group));
      case 'group':
        if (!mounted) return;
        final g = await _pickGroup(context, groups, e.group);
        if (g == null) return;
        await NutritionDb.put(db, e.inGroup(g));
      case 'delete':
        await NutritionDb.delete(db, e.id);
    }
    if (mounted) await _load();
    } catch (_) {
      if (mounted) _say(context, 'Could not change this entry. Please try again.');
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
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: S.x2, crossAxisAlignment: WrapCrossAlignment.end, children: [
              Text(thousands(sum((e) => e.kcal) ?? 0),
                  style: F.n34.copyWith(color: p.ink)),
              Padding(
                padding: const EdgeInsets.only(bottom: S.x1),
                child: Text('kcal', style: F.cap.copyWith(color: p.ink3)),
              ),
            ]),
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
          ]),
        ),
        if (es.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: S.x4),
            child: Text('Nothing logged in ${mealName(widget.meal)} this day.',
                style: F.cap.copyWith(color: p.ink3)),
          ),
        for (final g in order) ...[
          const SizedBox(height: S.x4),
          if (order.length > 1 || g.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: S.x2, left: S.x1),
              child: Row(children: [
                Expanded(
                  child: Text(g.isEmpty ? 'Other' : g,
                      style: F.cap.copyWith(
                          color: p.ink2, fontWeight: FontWeight.w600)),
                ),
                Text('${thousands(_kcalOf(groups[g]!))} kcal',
                    style: F.cap.copyWith(color: p.ink3)),
              ]),
            ),
          Surface(
            pad: const EdgeInsets.symmetric(horizontal: S.x4),
            child: Column(children: [
              for (final e in groups[g]!)
                Dismissible(
                  key: ValueKey(e.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: S.x4),
                    color: p.on(C.red),
                    child: Icon(LucideIcons.trash2, color: p.ink),
                  ),
                  onDismissed: (_) => _delete(e),
                  child: _EntryRow(e, onTap: () => _itemActions(e)),
                ),
            ]),
          ),
        ],
        const SizedBox(height: S.x5),
        BigButton('Add food',
            icon: LucideIcons.plus,
            color: C.domFood,
            onTap: () => openLog(c, _date, widget.meal, _load)),
        if (es.isNotEmpty) ...[
          const SizedBox(height: S.x3),
          BigButton('Copy, or save as a meal',
              icon: LucideIcons.copy,
              color: C.domFood,
              soft: true,
              onTap: () => mealMenu(c, _date, widget.meal, es, _load)),
        ],
        const SizedBox(height: S.x3),
        Text('Swipe an item left to delete it. Tap it to change it.',
            textAlign: TextAlign.center,
            style: F.over.copyWith(color: p.ink3)),
      ],
    ]);
  }
}

/// A sub-heading for an item: an existing one, a new one, or none ('').
Future<String?> _pickGroup(
    BuildContext c, List<String> groups, String current) async {
  final t = TextEditingController();
  final picked = await _sheet<String>(
    c,
    (s) => _body(s, [
      Text('Sub-heading', style: F.head.copyWith(color: P.of(s).ink)),
      const SizedBox(height: S.x3),
      for (final g in groups)
        PickRow(g, g == current ? 'Current' : 'Move here',
            trailing: g == current ? LucideIcons.check : LucideIcons.cornerDownRight,
            onTap: () => Navigator.of(s).pop(g)),
      if (current.isNotEmpty)
        PickRow('No sub-heading', 'Back to the main list',
            trailing: LucideIcons.x, onTap: () => Navigator.of(s).pop('')),
      const SizedBox(height: S.x3),
      OsTextField(controller: t, label: 'New sub-heading', hint: 'Omelette'),
      const SizedBox(height: S.x3),
      BigButton('Use this name', color: C.domFood, onTap: () {
        final v = t.text.trim();
        if (v.isNotEmpty) Navigator.of(s).pop(v);
      }),
    ]),
  );
  t.dispose();
  return picked;
}

class _EntryRow extends StatelessWidget {
  const _EntryRow(this.e, {this.onTap});
  final FoodEntry e;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final detail = [
      if (e.quantity != null) '${e.quantity!.round()} g',
      if (e.proteinG != null) 'P ${e.proteinG!.round()}',
      if (e.carbsG != null) 'C ${e.carbsG!.round()}',
      if (e.fatG != null) 'F ${e.fatG!.round()}',
    ].join(' · ');
    return Pressable(
      onTap: onTap,
      semanticLabel: '${e.label}, ${e.kcal?.round() ?? 'no'} kcal',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: S.x3),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: F.body.copyWith(color: p.ink)),
              if (detail.isNotEmpty)
                Text(detail, style: F.cap.copyWith(color: p.ink3)),
            ]),
          ),
          const SizedBox(width: S.x3),
          Text(e.kcal == null ? '–' : '${e.kcal!.round()}',
              style: F.n17.copyWith(color: p.ink)),
        ]),
      ),
    );
  }
}

// ══════════════════ LOG SCREEN ══════════════════

enum _Sort { recent, az, za }

/// Log food into a meal: search, Recent / My meals / My foods, + to log.
class LogFoodScreen extends StatefulWidget {
  const LogFoodScreen({super.key, required this.date, required this.meal});
  final String date, meal;

  @override
  State<LogFoodScreen> createState() => _LogFoodScreenState();
}

class _LogFoodScreenState extends State<LogFoodScreen> with RevisionReload {
  late String _meal = widget.meal;
  int _tab = 2;
  _Sort _sort = _Sort.recent;
  final _q = TextEditingController();
  List<FoodEntry> _recent = const [];
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
    final r = await NutritionDb.recent(db, limit: 40);
    final m = await MyFoods.meals(db);
    final f = await MyFoods.all(db);
      if (stillNewest(#foodPicker, t))
        setState(() {
          _recent = r;
          _meals = m;
          _foods = f;
          _loading = false;
          _failed = false;
        });
    } catch (_) {
      if (stillNewest(#foodPicker, t))
        setState(() {
          _loading = false;
          _failed = true;
        });
    }
  }

  int get _ts =>
      foodEntryTime(widget.date, _meal).millisecondsSinceEpoch ~/ 1000;

  Future<void> _act(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) _say(context, 'Could not finish. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scan() async {
    final meal = _meal;
    var typeInstead = false;
    final result = await scanFoodProduct(context, onManual: () => typeInstead = true);
    if (!mounted) return;
    if (result == null) {
      if (typeInstead) await QuickAddSheet.show(context, date: widget.date, meal: meal);
      return;
    }
    final product = result.product;
    if (product != null && !product.isBare) {
      await FoodDetailSheet.show(
        context,
        def: product.toDefRow(),
        date: widget.date,
        meal: meal,
        grams: product.defaultPortionG,
      );
    } else {
      final message = switch (result.outcome) {
        OffOutcome.notFound => 'This barcode is not in Open Food Facts yet.',
        OffOutcome.flagged =>
          'This product is flagged as incorrect; its numbers were not used.',
        OffOutcome.unreachable =>
          'The lookup could not connect. Cached products still work offline.',
        OffOutcome.refused => 'Barcode lookup is off.',
        OffOutcome.ok => 'The product has no usable nutrition numbers.',
      };
      final manual = await _sheet<bool>(
        context,
        (s) => _body(s, [
          _sheetTitle(s, 'Add from the label'),
          const SizedBox(height: S.x3),
          Text(message, style: F.body.copyWith(color: P.of(s).ink2)),
          const SizedBox(height: S.x4),
          BigButton(
            'Quick add',
            color: C.domFood,
            onTap: () => Navigator.of(s).pop(true),
          ),
        ]),
      );
      if (manual == true && mounted)
        await QuickAddSheet.show(context, date: widget.date, meal: meal);
    }
    if (mounted) await _load();
  }

  Future<void> _quickLogFood(Map<String, Object?> def) async {
    final db = await LocalDb.instance;
    final key = def['key'] as String;
    final grams = await NutritionDb.lastGrams(db, key) ??
        (def['serving_g'] as num?)?.toDouble() ??
        100;
    await NutritionDb.put(
        db,
        entryFromFood(def, grams,
            id: NutritionDb.newId(), date: widget.date, meal: _meal, atTs: _ts));
    if (mounted) _say(context, 'Added ${def['label']} · ${grams.round()} g');
  }

  Future<void> _quickLogRecent(FoodEntry e) async {
    final db = await LocalDb.instance;
    await NutritionDb.put(
        db,
        e.copyTo(widget.date, _meal, newId: NutritionDb.newId(), newGroup: '')
            .withTime(_ts));
    if (mounted) _say(context, 'Added ${e.label}');
  }

  Future<void> _logMeal(MealTemplate m) async {
    final n = await MyFoods.logMeal(await LocalDb.instance, m, widget.date, _meal);
    if (mounted) _say(context, n == 0
        ? 'No foods remain in ${m.label}. Edit the saved meal first.'
        : 'Added ${m.label} · $n item${n == 1 ? '' : 's'}');
  }

  Future<void> _detail(Map<String, Object?> def, {double? grams}) async {
    final ok = await FoodDetailSheet.show(context,
        def: def, date: widget.date, meal: _meal, grams: grams);
    if (ok == true && mounted) _say(context, 'Added ${def['label']}');
  }

  Future<void> _pickMeal() async {
    final m = await _sheet<String>(
      context,
      (s) => _body(s, [
        Text('Log to', style: F.head.copyWith(color: P.of(s).ink)),
        const SizedBox(height: S.x2),
        for (final m in kMeals)
          PickRow(mealName(m), m == _meal ? 'Selected' : '',
              trailing: m == _meal ? LucideIcons.check : null,
              onTap: () => Navigator.of(s).pop(m)),
      ]),
    );
    if (m != null) setState(() => _meal = m);
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final q = _q.text.trim().toLowerCase();
    bool hit(String s) => q.isEmpty || s.toLowerCase().contains(q);
    final foods = [for (final f in _foods) if (hit('${f['label']}')) f];
    if (_sort != _Sort.recent) {
      foods.sort((a, b) => '${a['label']}'
          .toLowerCase()
          .compareTo('${b['label']}'.toLowerCase()));
      if (_sort == _Sort.za) foods.setAll(0, foods.reversed.toList());
    }
    final recent = [for (final e in _recent) if (hit(e.label)) e];
    final meals = [for (final m in _meals) if (hit(m.label)) m];

    Widget row(
      String title,
      String detail,
      Future<void> Function() onPlus,
      Future<void> Function() onTap,
    ) => Padding(
          padding: const EdgeInsets.only(bottom: S.x2),
          child: Surface(
        onTap: _busy ? null : () => _act(onTap),
            semanticLabel: '$title, $detail',
            pad: const EdgeInsets.fromLTRB(S.x4, S.x3, S.x2, S.x3),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: F.body.copyWith(color: p.ink)),
                  Text(detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: F.cap.copyWith(color: p.ink3)),
                ]),
              ),
              Pressable(
                semanticLabel: 'Log $title',
              onTap: _busy ? null : () => _act(onPlus),
                child: Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: p.wash(C.domFood), shape: BoxShape.circle),
                  child: Icon(LucideIcons.plus, size: 18, color: p.on(C.domFood)),
                ),
              ),
            ]),
          ),
        );

    Widget tile(IconData icon, String label, VoidCallback onTap) => Expanded(
          child: Surface(
        onTap: _busy ? null : onTap,
            semanticLabel: label,
            pad: const EdgeInsets.symmetric(vertical: S.x3),
            child: Column(children: [
              Icon(icon, size: 20, color: p.on(C.domFood)),
              const SizedBox(height: S.x1),
              Text(label,
                  textAlign: TextAlign.center,
                  style: F.over.copyWith(color: p.ink2)),
            ]),
          ),
        );

    final list = <Widget>[
      if (_tab == 0) ...[
        if (recent.isEmpty) _empty(p, 'Things you log show up here.'),
        for (final e in recent)
          row(
            e.label,
            [
              if (e.kcal != null) '${e.kcal!.round()} kcal',
              if (e.quantity != null) '${e.quantity!.round()} g',
            ].join(', '),
            () => _quickLogRecent(e),
            () async {
              final db = await LocalDb.instance;
              final def =
                  e.foodKey == null ? null : await NutritionDb.foodDef(db, e.foodKey!);
              if (!mounted) return;
              if (def != null) {
                await _detail(def, grams: e.quantity);
              } else {
                await QuickAddSheet.show(context,
                    date: widget.date, meal: _meal, from: e);
              }
            },
          ),
      ],
      if (_tab == 1) ...[
        if (meals.isEmpty)
          _empty(p, 'Save a meal from its ⋯ menu to log it in one tap.'),
        for (final m in meals)
          row(
            m.label,
            '${m.items.length} food${m.items.length == 1 ? '' : 's'} · ${mealName(m.meal)}',
            () => _logMeal(m),
            () async {
              await MealEditor.show(context, existing: m);
              await _load();
            },
          ),
      ],
      if (_tab == 2) ...[
        if (foods.isEmpty) _empty(p, 'Create a food once from its label.'),
        for (final f in foods)
          row(
            '${f['label']}',
            [
              if (f['kcal_100'] is num && f['serving_g'] is num)
                '${((f['kcal_100'] as num) * (f['serving_g'] as num) / 100).round()} kcal',
              if (f['serving_g'] is num) '${(f['serving_g'] as num).round()} g',
            ].join(', '),
            () => _quickLogFood(f),
            () => _detail(f),
          ),
      ],
    ];

    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(S.x4, S.x2, S.x4, S.x10),
          children: [
            Row(children: [
              Pressable(
                semanticLabel: 'Back',
                onTap: () => Navigator.of(c).maybePop(),
                child: Icon(LucideIcons.arrowLeft, size: 22, color: p.ink),
              ),
              Expanded(
                child: Pressable(
                  semanticLabel: 'Log to ${mealName(_meal)}',
                  onTap: _pickMeal,
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(mealName(_meal),
                        style: F.head.copyWith(color: p.on(C.domFood))),
                    const SizedBox(width: S.x1),
                    Icon(LucideIcons.chevronDown, size: 18, color: p.on(C.domFood)),
                  ]),
                ),
              ),
              const SizedBox(width: 22),
            ]),
            Center(
              child: Text(dayTitle(widget.date),
                  style: F.over.copyWith(color: p.ink3)),
            ),
            const SizedBox(height: S.x3),
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
                await QuickAddSheet.show(c, date: widget.date, meal: _meal);
                await _load();
              }),
                ),
              const SizedBox(width: S.x2),
                tile(LucideIcons.scanBarcode, 'Scan', () => _act(_scan)),
              ],
            ),
            const SizedBox(height: S.x4),
            SubTabs(const ['Recent', 'My meals', 'My foods'], _tab,
                (i) => setState(() => _tab = i),
                color: C.domFood),
            if (_tab == 2) ...[
              const SizedBox(height: S.x2),
              Align(
                alignment: Alignment.centerRight,
                child: Pressable(
                  semanticLabel: 'Sort',
                  onTap: () => setState(() =>
                      _sort = _Sort.values[(_sort.index + 1) % _Sort.values.length]),
                  child: Pill(
                      switch (_sort) {
                        _Sort.recent => 'Recently eaten',
                        _Sort.az => 'A to Z',
                        _Sort.za => 'Z to A',
                      },
                      C.n400,
                      icon: LucideIcons.arrowUpDown),
                ),
              ),
            ],
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
        child: Text(text,
            textAlign: TextAlign.center, style: F.cap.copyWith(color: p.ink3)),
      );
}

extension on FoodEntry {
  /// The same entry at a different time (epoch seconds).
  FoodEntry withTime(int ts) => FoodEntry(
        id: id,
        date: date,
        meal: meal,
        label: label,
        atTs: ts,
        foodKey: foodKey,
        quantity: quantity,
        unit: unit,
        kcal: kcal,
        proteinG: proteinG,
        carbsG: carbsG,
        fatG: fatG,
        fibreG: fibreG,
        sugarG: sugarG,
        satFatG: satFatG,
        sodiumMg: sodiumMg,
        ironMg: ironMg,
        calciumMg: calciumMg,
        source: source,
        confirmed: confirmed,
        note: note,
        group: group,
      );
}

// ══════════════════ FOOD DETAIL ══════════════════

/// A food before it is logged: grams, meal, time, nutrition as % of the
/// daily goals, and the foods usually eaten with it.
class FoodDetailSheet extends StatefulWidget {
  const FoodDetailSheet(
      {super.key,
      required this.def,
      required this.date,
      required this.meal,
      this.grams});

  final Map<String, Object?> def;
  final String date, meal;
  final double? grams;

  static Future<bool?> show(BuildContext c,
          {required Map<String, Object?> def,
          required String date,
          required String meal,
          double? grams}) =>
      _sheet<bool>(c,
          (_) => FoodDetailSheet(def: def, date: date, meal: meal, grams: grams));

  @override
  State<FoodDetailSheet> createState() => _FoodDetailSheetState();
}

class _FoodDetailSheetState extends State<FoodDetailSheet> {
  late Map<String, Object?> _def = widget.def;
  bool _saving = false;
  String? _error;
  late final TextEditingController _g = TextEditingController(
      text: _trim(widget.grams ??
          (widget.def['serving_g'] as num?)?.toDouble() ??
          100));
  late String _meal = widget.meal;
  late TimeOfDay _time = TimeOfDay.fromDateTime(
    foodEntryTime(widget.date, widget.meal),
  );
  List<Map<String, Object?>> _with = const [];
  final _picked = <String>{};

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

  @override
  void initState() {
    super.initState();
    _g.addListener(() => setState(() {}));
    _loadWith();
  }

  @override
  void dispose() {
    _g.dispose();
    super.dispose();
  }

  Future<void> _loadWith() async {
    final key = _def['key'] as String?;
    if (key == null) return;
    try {
    final w = await NutritionDb.eatenWith(await LocalDb.instance, key);
    if (mounted) setState(() => _with = w);
    } catch (_) {
      if (mounted)
        setState(
          () => _error =
              'Companion foods could not load. You can still log this food.',
        );
    }
  }

  int get _ts {
    final d = DateTime.parse(widget.date);
    return DateTime(d.year, d.month, d.day, _time.hour, _time.minute)
            .millisecondsSinceEpoch ~/
        1000;
  }

  Future<void> _log() async {
    if (_saving) return;
    final grams = Typed.of(_g.text).value;
    if (grams == null || grams <= 0) {
      setState(() => _error = 'Enter an amount greater than 0 g.');
      return;
    }
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
            grams,
            id: NutritionDb.newId(),
            date: widget.date,
            meal: meal,
            atTs: ts,
          ),
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
            ),
            notify: false,
          );
    }
      });
      NutritionDb.changed();
    if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted)
        setState(() {
          _saving = false;
          _error = 'Could not save. Your portion is still here; try again.';
        });
    }
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final profile = c.watch<AppState>().user ?? const <String, dynamic>{};
    double? goal(String k) => (profile[k] as num?)?.toDouble();
    final grams = Typed.of(_g.text).value;
    final n = grams == null ? null : nutrientsFor(_def, grams);
    final serving = (_def['serving_g'] as num?)?.toDouble();
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
      OsTextField(
        controller: _g,
        label: 'Amount (g)',
        keyboard: const TextInputType.numberWithOptions(decimal: true),
      ),
      if (serving != null) ...[
        const SizedBox(height: S.x2),
        Wrap(spacing: S.x2, children: [
          for (final k in const [0.5, 1.0, 2.0])
            Pressable(
              semanticLabel: '$k servings',
              onTap: () => _g.text = _trim(serving * k),
              child: Pill(
                  '${k == 0.5 ? '½' : k.round()} serving${k > 1 ? 's' : ''} · '
                  '${_trim(serving * k)} g',
                  C.n400),
            ),
        ]),
      ],
      const SizedBox(height: S.x4),
      Wrap(spacing: S.x2, runSpacing: S.x2, children: [
        for (final m in kMeals)
          Pressable(
            onTap: () => setState(() => _meal = m),
            semanticLabel: mealName(m),
            child: Pill(mealName(m), _meal == m ? C.domFood : C.n400,
                icon: _meal == m ? LucideIcons.check : null),
          ),
        Pressable(
          semanticLabel: 'Time ${_time.format(c)}',
          onTap: () async {
            final t = await showTimePicker(context: c, initialTime: _time);
              if (t != null && mounted) setState(() => _time = t);
          },
          child: Pill(_time.format(c), C.n400, icon: LucideIcons.clock),
        ),
      ]),
      const SizedBox(height: S.x4),
      Surface(
        elevation: 0,
        color: p.card2,
        child: Column(children: [
          for (final (name, v, g, col) in macros)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: S.x1),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: S.x2,
                  runSpacing: S.x1,
                  children: [
                    Text(name, style: F.body.copyWith(color: p.ink)),
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
                    if (pct(v, g).isNotEmpty)
                      Text(pct(v, g), style: F.cap.copyWith(color: p.on(col))),
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
        'Check label values',
        'Edit nutrition before logging',
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
              child: Row(children: [
                Icon(
                    _picked.contains(w['key'])
                        ? LucideIcons.squareCheck
                        : LucideIcons.square,
                    size: 20,
                    color: p.on(C.domFood)),
                const SizedBox(width: S.x3),
                Expanded(
                    child: Text('${w['label']}',
                        style: F.body.copyWith(color: p.ink))),
                if (w['usual_g'] is num)
                  Text('${(w['usual_g'] as num).round()} g',
                      style: F.cap.copyWith(color: p.ink3)),
              ]),
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
  });
  final String date, meal;
  final FoodEntry? from;
  final bool editing;

  static Future<bool?> show(
    BuildContext c, {
    required String date,
    required String meal,
    FoodEntry? from,
    bool editing = false,
  }) => _sheet<bool>(
    c,
    (_) => QuickAddSheet(date: date, meal: meal, from: from, editing: editing),
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
  bool _saving = false;
  String? _error;
  late String _meal = widget.meal;
  late TimeOfDay _time = TimeOfDay.fromDateTime(
    widget.editing && widget.from?.atTs != null
        ? DateTime.fromMillisecondsSinceEpoch(widget.from!.atTs! * 1000)
        : foodEntryTime(widget.date, widget.meal),
  );

  static String _t(double? v) => v == null
      ? ''
      : (v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1));

  @override
  void dispose() {
    for (final t in [_name, _kcal, _p, _c, _f, _fibre]) {
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
    setState(() {
      _saving = true;
      _error = null;
    });
    final d = DateTime.parse(widget.date);
    final original = widget.editing ? widget.from : null;
    final previousTime = original?.atTs == null ? null :
        DateTime.fromMillisecondsSinceEpoch(original!.atTs! * 1000);
    final keepTime = previousTime != null && dayLabelOf(previousTime) == widget.date &&
        previousTime.hour == _time.hour && previousTime.minute == _time.minute;
    try {
    await NutritionDb.put(
      await LocalDb.instance,
      FoodEntry(
          id: original?.id ?? NutritionDb.newId(),
        date: widget.date,
        meal: _meal,
        label: _name.text.trim().isEmpty ? 'Quick add' : _name.text.trim(),
          atTs: keepTime ? original!.atTs :
              DateTime(
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
          foodKey: original?.foodKey,
          quantity: original?.quantity,
          unit: original?.unit ?? 'g',
          sugarG: original?.sugarG,
          satFatG: original?.satFatG,
          sodiumMg: original?.sodiumMg,
          ironMg: original?.ironMg,
          calciumMg: original?.calciumMg,
          source: original?.source ?? FoodSource.manual,
          note: original?.note ?? '',
          group: original?.group ?? '',
        confirmed: true,
      ),
    );
    if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted)
        setState(() {
          _saving = false;
          _error = 'Could not save. Your values are still here; try again.';
        });
    }
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    const num = TextInputType.numberWithOptions(decimal: true);
    return _body(c, [
      _sheetTitle(c, widget.editing ? 'Edit entry' : 'Quick add'),
      const SizedBox(height: S.x4),
      OsTextField(controller: _name, label: 'Name', hint: 'Protein shake at the gym'),
      const SizedBox(height: S.x3),
      Wrap(spacing: S.x2, runSpacing: S.x2, children: [
        for (final m in kMeals)
          Pressable(
            onTap: () => setState(() => _meal = m),
            semanticLabel: mealName(m),
            child: Pill(mealName(m), _meal == m ? C.domFood : C.n400,
                icon: _meal == m ? LucideIcons.check : null),
          ),
        Pressable(
          semanticLabel: 'Time ${_time.format(c)}',
          onTap: () async {
            final t = await showTimePicker(context: c, initialTime: _time);
              if (t != null && mounted) setState(() => _time = t);
          },
          child: Pill(_time.format(c), C.n400, icon: LucideIcons.clock),
        ),
      ]),
      const SizedBox(height: S.x3),
      OsTextField(controller: _kcal, label: 'Calories (kcal)', keyboard: num),
      const SizedBox(height: S.x3),
      OsTextField(controller: _p, label: 'Protein (g)', keyboard: num),
      const SizedBox(height: S.x3),
      ExpansionTile(
        tilePadding: EdgeInsets.zero,
        shape: const Border(),
        collapsedShape: const Border(),
        initiallyExpanded: [_c, _f, _fibre].any((t) => t.text.isNotEmpty),
        title: Text(
          'Other macros (optional)',
          style: F.body.copyWith(color: p.ink2),
        ),
        children: [
          OsTextField(controller: _c, label: 'Carbs (g)', keyboard: num),
          const SizedBox(height: S.x3),
          OsTextField(controller: _f, label: 'Fat (g)', keyboard: num),
          const SizedBox(height: S.x3),
          OsTextField(controller: _fibre, label: 'Fibre (g)', keyboard: num),
          const SizedBox(height: S.x3),
        ],
      ),
      Text(
        'Blank macros are not tracked. Enter 0 for a known zero.',
        style: F.over.copyWith(color: p.ink3),
      ),
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
