// Logging food the way it is actually eaten: the same few foods and meals,
// again and again.
//
//   · A FOOD is typed once from its label ("50 g oats = 200 kcal, 6.5 g
//     protein, 33 g carbs"), stored per 100 chosen units (grams by default), then logged by amount — 53 g
//     scales every number.
//   · A SAVED MEAL is a named set of those foods at fixed grams ("My
//     breakfast"). One tap writes one entry per food into the chosen meal.
//   · Anything else goes through the existing quick-add / barcode sheet.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/db.dart';
import '../../data/nutrition_store.dart';
import '../ui2.dart';
import 'journal_compose.dart' show OsTextField;
import 'log_food.dart';

const _mealNames = {
  'breakfast': 'Breakfast',
  'lunch': 'Lunch',
  'dinner': 'Dinner',
  'snack': 'Snacks',
};

String mealName(String meal) => _mealNames[meal] ?? meal;

String _n(double? v, [int dp = 0]) => v == null ? '–' : v.toStringAsFixed(dp);

/// One-line nutrient summary, e.g. "200 kcal · P 6.5 · C 33 · F 3.5 · Fb 5".
String macroLine({
  double? kcal,
  double? protein,
  double? carbs,
  double? fat,
  double? fibre,
}) {
  final parts = [
    if (kcal != null) '${kcal.round()} kcal',
    if (protein != null) 'P ${_n(protein, 1)}',
    if (carbs != null) 'C ${_n(carbs, 1)}',
    if (fat != null) 'F ${_n(fat, 1)}',
    if (fibre != null) 'Fb ${_n(fibre, 1)}',
  ];
  return parts.isEmpty ? 'No nutrition numbers' : parts.join(' · ');
}

/// Nutrition shown for the food's own labelled serving, including counted units.
String foodServingLine(Map<String, Object?> def) {
  final amount = (def['serving_g'] as num?)?.toDouble() ?? 100;
  final n = nutrientsFor(def, amount);
  return '${portionText(amount, foodUnit(def))}: ${macroLine(kcal: n.kcal, protein: n.protein, carbs: n.carbs, fat: n.fat, fibre: n.fibre)}';
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

Widget _sheetBody(BuildContext s, List<Widget> children) =>
    InputSheet(children: children);

/// A tappable list row: title, detail, optional trailing icon.
class PickRow extends StatelessWidget {
  const PickRow(
    this.title,
    this.detail, {
    super.key,
    this.onTap,
    this.trailing = LucideIcons.plus,
    this.onLong,
  });

  final String title, detail;
  final VoidCallback? onTap, onLong;
  final IconData? trailing;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Pressable(
      onTap: onTap,
      semanticLabel: '$title, $detail',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: S.x3),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: F.body.copyWith(color: p.ink),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    detail,
                    style: F.cap.copyWith(color: p.ink3),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: S.x3),
              Icon(trailing, size: 18, color: p.on(C.domFood)),
            ],
          ],
        ),
      ),
    );
  }
}

// ══════════════════ ADD FOOD ══════════════════

class AddFoodSheet extends StatefulWidget {
  const AddFoodSheet({super.key, required this.date, required this.meal});

  final String date, meal;

  /// Resolves true when anything was logged.
  static Future<bool?> show(
    BuildContext c, {
    required String date,
    required String meal,
  }) => _sheet<bool>(c, (_) => AddFoodSheet(date: date, meal: meal));

  @override
  State<AddFoodSheet> createState() => _AddFoodSheetState();
}

class _AddFoodSheetState extends State<AddFoodSheet> {
  List<Map<String, Object?>> _foods = const [];
  List<MealTemplate> _meals = const [];
  final _query = TextEditingController();

  @override
  void initState() {
    super.initState();
    _query.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final db = await LocalDb.instance;
    final foods = await MyFoods.all(db);
    final meals = await MyFoods.meals(db);
    if (mounted) setState(() => (_foods = foods, _meals = meals));
  }

  Future<void> _logMeal(MealTemplate m) async {
    final db = await LocalDb.instance;
    await MyFoods.logMeal(db, m, widget.date, widget.meal);
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _logFood(Map<String, Object?> def) async {
    final grams = await GramsSheet.show(context, def);
    if (grams == null || !mounted) return;
    final db = await LocalDb.instance;
    await NutritionDb.put(
      db,
      entryFromFood(
        def,
        grams,
        id: NutritionDb.newId(),
        date: widget.date,
        meal: widget.meal,
        atTs: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      ),
    );
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _newFood() async {
    final def = await FoodEditor.show(context);
    if (def == null || !mounted) return;
    await _load();
    if (mounted) await _logFood(def);
  }

  Future<void> _quickAdd() async {
    final ok = await LogFoodSheet.show(
      context,
      date: widget.date,
      meal: widget.meal,
    );
    if (ok == true && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final q = _query.text.trim().toLowerCase();
    final foods = [
      for (final f in _foods)
        if (q.isEmpty ||
            (f['label'] ?? '').toString().toLowerCase().contains(q))
          f,
    ];
    // This meal's saved meals first, then the rest.
    final meals = [
      ..._meals.where((m) => m.meal == widget.meal),
      ..._meals.where((m) => m.meal != widget.meal),
    ];
    return _sheetBody(c, [
      Text(
        'Add to ${mealName(widget.meal)}',
        style: F.head.copyWith(color: p.ink),
      ),
      const SizedBox(height: S.x4),
      if (meals.isNotEmpty) ...[
        Text('SAVED MEALS', style: F.over.copyWith(color: p.ink3)),
        for (final m in meals)
          PickRow(
            m.label,
            '${m.items.length} food${m.items.length == 1 ? '' : 's'} · '
            '${mealName(m.meal)}',
            onTap: () => _logMeal(m),
          ),
        const SizedBox(height: S.x4),
      ],
      Text('MY FOODS', style: F.over.copyWith(color: p.ink3)),
      const SizedBox(height: S.x2),
      if (_foods.length > 6)
        OsTextField(controller: _query, label: 'Search your foods'),
      if (foods.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: S.x3),
          child: Text(
            _foods.isEmpty
                ? 'No foods yet. Add one from its nutrition label.'
                : 'No match.',
            style: F.cap.copyWith(color: p.ink3),
          ),
        ),
      for (final f in foods.take(40))
        PickRow(
          (f['label'] ?? '').toString(),
          foodServingLine(f),
          onTap: () => _logFood(f),
        ),
      const SizedBox(height: S.x4),
      BigButton(
        'New food',
        icon: LucideIcons.plus,
        color: C.domFood,
        onTap: _newFood,
      ),
      const SizedBox(height: S.x3),
      BigButton(
        'Quick add or scan a barcode',
        icon: LucideIcons.scanBarcode,
        color: C.domFood,
        soft: true,
        onTap: _quickAdd,
      ),
    ]);
  }
}

// ══════════════════ GRAMS ══════════════════

/// How much of [def] was eaten, with every number following the weight.
class GramsSheet extends StatefulWidget {
  const GramsSheet({super.key, required this.def, this.initial});

  final Map<String, Object?> def;
  final double? initial;

  static Future<double?> show(
    BuildContext c,
    Map<String, Object?> def, {
    double? initial,
  }) => _sheet<double>(c, (_) => GramsSheet(def: def, initial: initial));

  @override
  State<GramsSheet> createState() => _GramsSheetState();
}

class _GramsSheetState extends State<GramsSheet> {
  late final TextEditingController _g = TextEditingController(
    text: portionText(
      widget.initial ?? (widget.def['serving_g'] as num?)?.toDouble() ?? 100,
      '',
    ).trim(),
  );

  @override
  void initState() {
    super.initState();
    _g.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _g.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final grams = Typed.of(_g.text).value;
    final n = grams == null || grams <= 0
        ? null
        : nutrientsFor(widget.def, grams);
    return _sheetBody(c, [
      Text(
        (widget.def['label'] ?? '').toString(),
        style: F.head.copyWith(color: p.ink),
      ),
      const SizedBox(height: S.x4),
      OsTextField(
        controller: _g,
        label: 'Amount (${foodUnit(widget.def)})',
        keyboard: const TextInputType.numberWithOptions(decimal: true),
      ),
      const SizedBox(height: S.x3),
      Text(
        n == null
            ? 'Enter a positive amount in ${foodUnit(widget.def)}.'
            : macroLine(
                kcal: n.kcal,
                protein: n.protein,
                carbs: n.carbs,
                fat: n.fat,
                fibre: n.fibre,
              ),
        style: F.body.copyWith(color: p.ink, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: S.x5),
      BigButton(
        'Add',
        color: C.domFood,
        onTap: grams == null || grams <= 0
            ? null
            : () => Navigator.of(c).pop(grams),
      ),
    ]);
  }
}

// ══════════════════ NEW / EDIT FOOD ══════════════════

/// Type a food once, the way the label reads it. Returns the saved row.
class FoodEditor extends StatefulWidget {
  const FoodEditor({super.key, this.existing});

  final Map<String, Object?>? existing;

  static Future<Map<String, Object?>?> show(
    BuildContext c, {
    Map<String, Object?>? existing,
  }) => _sheet<Map<String, Object?>>(c, (_) => FoodEditor(existing: existing));

  @override
  State<FoodEditor> createState() => _FoodEditorState();
}

class _FoodEditorState extends State<FoodEditor> {
  bool _saving = false;
  String? _error;
  final _label = TextEditingController();
  final _ref = TextEditingController(text: '100');
  final _unit = TextEditingController(text: 'g');
  final _kcal = TextEditingController();
  final _protein = TextEditingController();
  final _carbs = TextEditingController();
  final _fat = TextEditingController();
  final _fibre = TextEditingController();

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      // Shown back on its own serving when it has one, else per 100 g.
      final ref = (e['serving_g'] as num?)?.toDouble() ?? 100;
      String at(String k) {
        final v = (e[k] as num?)?.toDouble();
        return v == null ? '' : _trim(v * ref / 100);
      }

      _label.text = (e['label'] ?? '').toString();
      _unit.text = foodUnit(e);
      _ref.text = _trim(ref);
      _kcal.text = at('kcal_100');
      _protein.text = at('protein_g_100');
      _carbs.text = at('carbs_g_100');
      _fat.text = at('fat_g_100');
      _fibre.text = at('fibre_g_100');
    }
  }

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toString();

  @override
  void dispose() {
    for (final t in [
      _label,
      _ref,
      _unit,
      _kcal,
      _protein,
      _carbs,
      _fat,
      _fibre,
    ]) {
      t.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final fields = {
      'Amount': _ref,
      'Calories': _kcal,
      'Protein': _protein,
      'Carbs': _carbs,
      'Fat': _fat,
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
    final ref = Typed.of(_ref.text).value;
    final label = _label.text.trim();
    if (label.isEmpty || ref == null || ref <= 0) {
      setState(
        () => _error =
            'Enter a description and a serving size greater than zero.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final def = myFoodDef(
      key:
          (widget.existing?['key'] as String?) ??
          'my:${DateTime.now().microsecondsSinceEpoch}',
      label: label,
      refGrams: ref,
      unit: _unit.text.trim(),
      kcal: Typed.of(_kcal.text).value,
      protein: Typed.of(_protein.text).value,
      carbs: Typed.of(_carbs.text).value,
      fat: Typed.of(_fat.text).value,
      fibre: Typed.of(_fibre.text).value,
    );
    if (widget.existing?['source'] == 'barcode') def['source'] = 'barcode';
    try {
      await NutritionDb.putFoodDef(await LocalDb.instance, def);
      if (mounted) Navigator.of(context).pop(def);
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
    Widget field(TextEditingController t, String label) => Padding(
      padding: const EdgeInsets.only(bottom: S.x3),
      child: OsTextField(controller: t, label: label, keyboard: num),
    );
    return _sheetBody(c, [
      Text(
        widget.existing == null ? 'New food' : 'Edit food',
        style: F.head.copyWith(color: p.ink),
      ),
      const SizedBox(height: S.x2),
      Text(
        'Copy the numbers off the label for one serving.',
        style: F.cap.copyWith(color: p.ink3),
      ),
      const SizedBox(height: S.x4),
      OsTextField(controller: _label, label: 'Description', hint: 'Oats'),
      const SizedBox(height: S.x3),
      OsTextField(
        controller: _unit,
        label: 'Serving unit',
        hint: 'g, link, slice, cup…',
      ),
      const SizedBox(height: S.x2),
      Wrap(
        spacing: S.x2,
        runSpacing: S.x2,
        children: [
          for (final unit in const [
            'g',
            'ml',
            'link',
            'slice',
            'cup',
            'serving',
          ])
            Pressable(
              semanticLabel: 'Unit $unit',
              onTap: () => setState(() {
                _unit.text = unit;
                if (widget.existing == null) {
                  _ref.text = unit == 'g' || unit == 'ml' ? '100' : '1';
                }
              }),
              child: Pill(unit, C.n400),
            ),
        ],
      ),
      const SizedBox(height: S.x3),
      field(_ref, 'Serving amount'),
      field(_kcal, 'Calories (kcal)'),
      field(_protein, 'Protein (g)'),
      field(_carbs, 'Carbs (g)'),
      field(_fat, 'Fat (g)'),
      field(_fibre, 'Fibre (g)'),
      const SizedBox(height: S.x2),
      if (_error != null)
        Text(_error!, style: F.cap.copyWith(color: p.on(C.red))),
      BigButton(
        _saving ? 'Saving…' : 'Save',
        color: C.domFood,
        onTap: _saving ? null : _save,
      ),
    ]);
  }
}

// ══════════════════ SAVED MEAL ══════════════════

/// Name a meal, pick its usual slot, and add foods at their usual grams.
class MealEditor extends StatefulWidget {
  const MealEditor({super.key, this.existing});

  final MealTemplate? existing;

  static Future<bool?> show(BuildContext c, {MealTemplate? existing}) =>
      _sheet<bool>(c, (_) => MealEditor(existing: existing));

  @override
  State<MealEditor> createState() => _MealEditorState();
}

class _MealEditorState extends State<MealEditor> {
  bool _saving = false, _failed = false;
  String? _error;
  late final _label = TextEditingController(text: widget.existing?.label ?? '');
  late String _meal = widget.existing?.meal ?? 'breakfast';
  late final List<(String, double)> _items = [...?widget.existing?.items];
  Map<String, Map<String, Object?>> _defs = const {};

  @override
  void initState() {
    super.initState();
    _loadDefs();
  }

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  Future<void> _loadDefs() async {
    try {
      final all = await MyFoods.all(await LocalDb.instance);
      if (mounted) {
        setState(() => _defs = {for (final d in all) d['key'] as String: d});
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _addItem() async {
    final foods = _defs.values.toList();
    final def = await _sheet<Map<String, Object?>>(
      context,
      (s) => _sheetBody(s, [
        Text('Pick a food', style: F.head.copyWith(color: P.of(s).ink)),
        const SizedBox(height: S.x3),
        if (foods.isEmpty)
          Text(
            'Add foods first, under Nutrition › Foods.',
            style: F.cap.copyWith(color: P.of(s).ink3),
          ),
        for (final f in foods)
          PickRow(
            (f['label'] ?? '').toString(),
            'per 100 ${foodUnit(f)}',
            onTap: () => Navigator.of(s).pop(f),
          ),
      ]),
    );
    if (def == null || !mounted) return;
    final grams = await GramsSheet.show(context, def);
    if (grams == null || !mounted) return;
    setState(() => _items.add((def['key'] as String, grams)));
  }

  Future<void> _save() async {
    if (_saving) return;
    final label = _label.text.trim();
    if (label.isEmpty || _items.isEmpty) {
      setState(() => _error = 'Enter a name and add at least one food.');
      return;
    }
    if (_failed) {
      setState(() => _error = 'Load your saved foods before saving this meal.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final items = [..._items];
    try {
      await MyFoods.putMeal(
        await LocalDb.instance,
        MealTemplate(
          key:
              widget.existing?.key ??
              'meal:${DateTime.now().microsecondsSinceEpoch}',
          label: label,
          meal: _meal,
          items: items,
          units: {
            for (final item in items) item.$1: foodUnit(_defs[item.$1] ?? {}),
          },
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not save. Your meal is still here; try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    double? total(String k) {
      double? sum;
      for (final (key, g) in _items) {
        final d = _defs[key];
        final v = (d?[k] as num?)?.toDouble();
        if (v != null) sum = (sum ?? 0) + v * g / 100;
      }
      return sum;
    }

    return _sheetBody(c, [
      Text(
        widget.existing == null ? 'New saved meal' : 'Edit saved meal',
        style: F.head.copyWith(color: p.ink),
      ),
      const SizedBox(height: S.x4),
      OsTextField(controller: _label, label: 'Name', hint: 'My breakfast'),
      if (_failed)
        StatusCard(
          'Foods could not load',
          'Retry before editing this meal.',
          fix: 'Retry',
          onFix: () {
            setState(() => _failed = false);
            _loadDefs();
          },
        ),
      const SizedBox(height: S.x3),
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
      const SizedBox(height: S.x4),
      for (var i = 0; i < _items.length; i++)
        PickRow(
          (_defs[_items[i].$1]?['label'] ?? 'Deleted food').toString(),
          portionText(_items[i].$2, foodUnit(_defs[_items[i].$1] ?? {})),
          trailing: LucideIcons.x,
          onTap: () => setState(() => _items.removeAt(i)),
        ),
      if (_items.isNotEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: S.x2),
          child: Text(
            macroLine(
              kcal: total('kcal_100'),
              protein: total('protein_g_100'),
              carbs: total('carbs_g_100'),
              fat: total('fat_g_100'),
              fibre: total('fibre_g_100'),
            ),
            style: F.body.copyWith(color: p.ink, fontWeight: FontWeight.w600),
          ),
        ),
      const SizedBox(height: S.x2),
      BigButton(
        'Add a food',
        icon: LucideIcons.plus,
        color: C.domFood,
        soft: true,
        onTap: _addItem,
      ),
      const SizedBox(height: S.x3),
      if (_error != null)
        Text(_error!, style: F.cap.copyWith(color: p.on(C.red))),
      BigButton(
        _saving ? 'Saving…' : 'Save',
        color: C.domFood,
        onTap: _saving ? null : _save,
      ),
    ]);
  }
}
