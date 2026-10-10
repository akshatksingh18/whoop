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
import '../../data/off_lookup.dart';
import '../ui2.dart';
import 'journal_compose.dart' show OsTextField;
import 'food_diary.dart' show askText;
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

/// A saved meal's calories at its saved amounts, from [defs] (key → food).
/// Null when no item has a calorie figure; foods no longer saved are skipped.
double? mealKcal(MealTemplate m, Map<String, Map<String, Object?>> defs) {
  double? sum;
  for (final (key, amount) in m.items) {
    final d = defs[key];
    final per100 = (d?['kcal_100'] as num?)?.toDouble();
    if (d == null || per100 == null) continue;
    final base = toBase(d, amount, m.units[key] ?? foodUnit(d));
    if (base != null) sum = (sum ?? 0) + per100 * base / 100;
  }
  return sum;
}

/// One line for a saved meal's row: calories, food count and usual slot.
String mealSummary(MealTemplate m, Map<String, Map<String, Object?>> defs) {
  final kcal = mealKcal(m, defs);
  final n = m.items.length;
  return [
    if (kcal != null) '${kcal.round()} kcal',
    '$n food${n == 1 ? '' : 's'}',
    mealName(m.meal),
  ].join(' · ');
}

/// Whether a food or meal name matches a typed search (case-insensitive).
bool nameMatches(Object? name, String query) =>
    (name ?? '').toString().toLowerCase().contains(query.trim().toLowerCase());

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
      // The sheet closes through InputSheet (pull, handle, ✕), which can ask
      // before discarding typed values; the route's own drag would not ask.
      enableDrag: false,
      sheetAnimationStyle: sheetMotion(c),
      backgroundColor: P.of(c).card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(R.xxl)),
      ),
      builder: b,
    );

Widget _sheetBody(
  BuildContext s,
  List<Widget> children, {
  bool Function()? changed,
}) => InputSheet(changed: changed, children: children);

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
                    style: F.body.copyWith(
                      color: p.ink,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
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
              // The row's action in a round well (build 85).
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: p.wash(C.domFood),
                  shape: BoxShape.circle,
                ),
                child: Icon(trailing, size: 16, color: p.on(C.domFood)),
              ),
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
    final portion = await GramsSheet.show(context, def);
    if (portion == null || !mounted) return;
    final db = await LocalDb.instance;
    await NutritionDb.put(
      db,
      entryFromFood(
        def,
        portion.base,
        id: NutritionDb.newId(),
        date: widget.date,
        meal: widget.meal,
        atTs: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        amount: portion.amount,
        unit: portion.unit,
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
        OsTextField(
          controller: _query,
          label: 'Search your foods',
          clearable: true,
        ),
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
  const GramsSheet({
    super.key,
    required this.def,
    this.initial,
    this.initialUnit,
    this.action = 'Add',
  });

  final Map<String, Object?> def;
  final double? initial;

  /// The unit [initial] is in; null is the label unit.
  final String? initialUnit;
  final String action;

  /// The portion as entered and its label-unit amount, or null if cancelled.
  static Future<Portion?> show(
    BuildContext c,
    Map<String, Object?> def, {
    double? initial,
    String? initialUnit,
    String action = 'Add',
  }) => _sheet<Portion>(
    c,
    (_) => GramsSheet(
      def: def,
      initial: initial,
      initialUnit: initialUnit,
      action: action,
    ),
  );

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
  late final _unit = ValueNotifier<String>(
    widget.initialUnit != null &&
            unitInBase(widget.def, widget.initialUnit!) != null
        ? widget.initialUnit!
        : foodUnit(widget.def),
  );

  @override
  void initState() {
    super.initState();
    _g.addListener(() => setState(() {}));
    _unit.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _g.dispose();
    _unit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final grams = Typed.of(_g.text).value;
    final base = grams == null || grams <= 0
        ? null
        : toBase(widget.def, grams, _unit.value);
    final n = base == null ? null : nutrientsFor(widget.def, base);
    return _sheetBody(c, [
      Text(
        (widget.def['label'] ?? '').toString(),
        style: F.head.copyWith(color: p.ink),
      ),
      const SizedBox(height: S.x4),
      AmountInput(controller: _g, def: widget.def, unit: _unit),
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
        widget.action,
        color: C.domFood,
        onTap: grams == null || grams <= 0 || base == null
            ? null
            : () => Navigator.of(
                c,
              ).pop((amount: grams, unit: _unit.value, base: base)),
      ),
    ]);
  }
}

// ══════════════════ NEW / EDIT FOOD ══════════════════

/// Type a food once, the way the label reads it. Returns the saved row.
/// The category filter every food list shares (Food → Foods, the log
/// screen's My foods, the saved-meal picker): "All" plus the categories the
/// foods actually carry, one row, scrolling sideways. Null is All.
class FoodCategoryFilter extends StatelessWidget {
  const FoodCategoryFilter({
    super.key,
    required this.foods,
    required this.selected,
    required this.onSelect,
  });

  final Iterable<Map<String, Object?>> foods;
  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext c) {
    final cats = foodCategoriesIn(foods);
    // One category (or none) is nothing to filter by.
    if (cats.length < 2) return const SizedBox.shrink();
    Widget chip(String label, String? value) => Padding(
      padding: const EdgeInsets.only(right: S.x2),
      child: Pressable(
        semanticLabel: selected == value ? '$label, selected' : 'Show $label',
        onTap: () => onSelect(value),
        child: Pill(label, selected == value ? C.domFood : C.n400),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: S.x2),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [chip('All', null), for (final cat in cats) chip(cat, cat)],
        ),
      ),
    );
  }
}

/// [foods] in [category] (null keeps all).
List<Map<String, Object?>> foodsIn(
  List<Map<String, Object?>> foods,
  String? category,
) => category == null
    ? foods
    : [
        for (final f in foods)
          if (labelKey(foodCategory(f)) == labelKey(category)) f,
      ];

class FoodEditor extends StatefulWidget {
  const FoodEditor({super.key, this.existing, this.reviewBarcode = false});

  final Map<String, Object?>? existing;
  final bool reviewBarcode;

  static Future<Map<String, Object?>?> show(
    BuildContext c, {
    Map<String, Object?>? existing,
    bool reviewBarcode = false,
  }) => _sheet<Map<String, Object?>>(
    c,
    (_) => FoodEditor(existing: existing, reviewBarcode: reviewBarcode),
  );

  /// A library scan never writes a diary entry or saves before confirmation.
  static Future<Map<String, Object?>?> scanAndSave(BuildContext c) async {
    var manual = false;
    final result = await scanFoodProduct(
      c,
      cacheProduct: false,
      onManual: () => manual = true,
    );
    if (!c.mounted) return null;
    if (result == null) return manual ? show(c) : null;
    if (result.product case final product?) {
      final saved = await NutritionDb.foodDef(
        await LocalDb.instance,
        product.barcode,
      );
      if (!c.mounted) return null;
      return show(
        c,
        existing: saved ?? product.toDefRow(),
        reviewBarcode: true,
      );
    }
    final reason = switch (result.outcome) {
      OffOutcome.notFound => 'This barcode is not in Open Food Facts yet.',
      OffOutcome.flagged =>
        'This product is flagged as incorrect; its numbers were not used.',
      OffOutcome.unreachable =>
        'The lookup could not connect. Saved barcode foods still work offline.',
      OffOutcome.refused => 'Barcode lookup is off.',
      OffOutcome.ok => 'The product has no usable nutrition numbers.',
    };
    final useLabel = await _sheet<bool>(
      c,
      (context) => _sheetBody(context, [
        Text(
          'Add from the label',
          style: F.head.copyWith(color: P.of(context).ink),
        ),
        const SizedBox(height: S.x3),
        Text(reason, style: F.body.copyWith(color: P.of(context).ink3)),
        const SizedBox(height: S.x4),
        BigButton(
          'Create a food',
          color: C.domFood,
          onTap: () => Navigator.of(context).pop(true),
        ),
      ]),
    );
    if (useLabel != true || !c.mounted) return null;
    return show(c);
  }

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

  /// For a label per count ("6 pieces (85 g)"): what the whole serving
  /// weighs, in grams, as the pack prints it. Stored as a "g" unit of
  /// serving/weight label units, so the food logs in grams as well — and
  /// nobody divides 85 by 6.
  final _servingWeight = TextEditingController();

  /// Units stored on the food that the serving line does not show (a
  /// third unit from an older build). Kept on save, never shown.
  List<FoodMeasure> _kept = const [];
  Map<String, double> _keptCounts = const {};

  /// The food's category ('' for none), shared by every food list's filter.
  String _category = '';

  bool get _countLabel {
    final u = _unit.text.trim().toLowerCase();
    return u.isNotEmpty && u != 'g' && u != 'ml';
  }

  /// The user's labels across My foods, loaded once; suggestions fill in
  /// only while there are fewer than a few of their own.
  List<String> _labels = const [];

  List<String> get _labelChoices {
    final out = <String, String>{
      for (final l in _labels) labelKey(l): l,
      if (_category.trim().isNotEmpty) labelKey(_category): _category.trim(),
    };
    if (out.length < 4) {
      for (final l in kFoodCategories) {
        out.putIfAbsent(labelKey(l), () => l);
      }
    }
    return out.values.toList();
  }

  Future<void> _loadLabels() async {
    try {
      final labels = foodLabelsIn(await MyFoods.all(await LocalDb.instance));
      if (mounted) setState(() => _labels = labels);
    } catch (_) {
      /* the suggestions still work */
    }
  }

  Future<void> _newLabel() async {
    final name = await askText(
      context,
      'New label',
      'Label',
      '',
      validate: (v) => v.trim().isEmpty
          ? 'Type a name.'
          : v.trim().length > 30
          ? 'Use 30 characters or fewer.'
          : null,
    );
    if (name == null || !mounted) return;
    final t = name.trim();
    // An existing label typed in another case is that label, not a new one.
    final same = _labelChoices.where((l) => labelKey(l) == labelKey(t));
    setState(() => _category = same.isEmpty ? t : same.first);
  }

  @override
  void initState() {
    super.initState();
    _loadLabels();
    _unit.addListener(() => setState(() {}));
    final e = widget.existing;
    if (e != null) {
      final base = foodUnit(e);
      final perGram = base.toLowerCase() == 'g';
      // Shown back on its own serving when it has one, else per 100 g.
      var ref = (e['serving_g'] as num?)?.toDouble() ?? 100;
      var unit = base;
      var shownAt = ref; // label units the macros below are shown for
      final counts = measureCounts(e);
      final kept = <FoodMeasure>[];
      for (final m in foodMeasures(e)) {
        final l = m.label.toLowerCase();
        if (!perGram && l == 'g') {
          _servingWeight.text = _trim(ref / m.amount);
        } else if (perGram && unit == base && l != 'g' && l != 'ml') {
          // A per-gram food with a named unit ("Link · 71 g") opens on its
          // serving line: 1 link · 71 g.
          final n = counts[m.label] ?? 1;
          unit = m.label;
          ref = n;
          shownAt = m.amount * n;
          _servingWeight.text = _trim(shownAt);
        } else {
          kept.add(m);
        }
      }
      // A scanned pack that prints "6 pieces (85 g)" opens on that serving.
      final scanned = servingCountOf((e['serving_label'] ?? '').toString());
      if (perGram && unit == base && scanned != null) {
        unit = scanned.name;
        ref = scanned.count;
        shownAt = scanned.grams;
        _servingWeight.text = _trim(scanned.grams);
      }
      _kept = kept;
      _keptCounts = {for (final m in kept) m.label: ?counts[m.label]};
      String at(String k) {
        final v = (e[k] as num?)?.toDouble();
        return v == null ? '' : _trim(v * shownAt / 100);
      }

      _label.text = (e['label'] ?? '').toString();
      _category = (e['category'] ?? '').toString().trim();
      _unit.text = unit;
      _ref.text = _trim(ref);
      _kcal.text = at('kcal_100');
      _protein.text = at('protein_g_100');
      _carbs.text = at('carbs_g_100');
      _fat.text = at('fat_g_100');
      _fibre.text = at('fibre_g_100');
    }
    _start = _snapshot;
  }

  /// Everything typed, as one comparable value: [_start] is how it opened.
  String get _snapshot => [
    for (final t in [
      _label,
      _ref,
      _unit,
      _kcal,
      _protein,
      _carbs,
      _fat,
      _fibre,
      _servingWeight,
    ])
      t.text,
    _category,
  ].join('\u0000');
  late final String _start;

  static String _trim(double v) => editableNumber(v);

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
      _servingWeight,
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
    final unit = _unit.text.trim();
    final measures = <FoodMeasure>[];
    final weight = Typed.of(_servingWeight.text, nonNegative: true);
    if (_countLabel && !weight.blank) {
      if (weight.value == null || weight.value! <= 0) {
        setState(
          () => _error =
              'Enter what the serving weighs in grams, or leave it blank.',
        );
        return;
      }
      measures.add((label: 'g', amount: ref / weight.value!));
    }
    // Old label units in one new one: known when the unit is unchanged, or
    // when a per-gram food moves to its count serving with a weight.
    final old = widget.existing;
    final oldUnit = old == null ? null : foodUnit(old);
    final double? oldPerNew =
        old == null || oldUnit!.toLowerCase() == unit.toLowerCase()
        ? 1
        : oldUnit.toLowerCase() == 'g' && measures.isNotEmpty
        ? weight.value! / ref
        : null;
    // Units the editor no longer shows stay, re-expressed in the new unit.
    final counts = <String, double>{};
    if (oldPerNew != null) {
      for (final m in _kept) {
        final l = m.label.toLowerCase();
        if (l == unit.toLowerCase() ||
            measures.any((x) => x.label.toLowerCase() == l)) {
          continue;
        }
        measures.add((label: m.label, amount: m.amount / oldPerNew));
        if (_keptCounts[m.label] case final n?) counts[m.label] = n;
      }
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final ancillaryScale =
        oldPerNew ?? ((old?['serving_g'] as num?)?.toDouble() ?? 100) / ref;
    final def = <String, Object?>{
      for (final key in const ['brand', 'serving_label'])
        if (widget.existing?.containsKey(key) == true)
          key: widget.existing![key],
      for (final key in const ['sugar_g_100', 'sat_fat_g_100', 'sodium_mg_100'])
        if (widget.existing?.containsKey(key) == true)
          key: (widget.existing![key] as num?)?.toDouble() == null
              ? null
              : (widget.existing![key] as num).toDouble() * ancillaryScale,
      ...myFoodDef(
        key:
            (widget.existing?['key'] as String?) ??
            'my:${DateTime.now().microsecondsSinceEpoch}',
        label: label,
        refGrams: ref,
        unit: unit,
        kcal: Typed.of(_kcal.text).value,
        protein: Typed.of(_protein.text).value,
        carbs: Typed.of(_carbs.text).value,
        fat: Typed.of(_fat.text).value,
        fibre: Typed.of(_fibre.text).value,
        measures: measures,
        measureCounts: counts,
        category: _category,
      ),
    };
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
        widget.reviewBarcode
            ? 'Review scanned food'
            : widget.existing == null
            ? 'New food'
            : 'Edit food',
        style: F.head.copyWith(color: p.ink),
      ),
      const SizedBox(height: S.x2),
      Text(
        widget.reviewBarcode
            ? 'Check these numbers against the label for one serving. Missing values stay blank.'
            : 'Copy the numbers off the label for one serving.',
        style: F.cap.copyWith(color: p.ink3),
      ),
      const SizedBox(height: S.x4),
      if (widget.reviewBarcode) offCredit(),
      OsTextField(controller: _label, label: 'Description', hint: 'Oats'),
      const SizedBox(height: S.x4),
      Text('LABEL', style: F.over.copyWith(color: p.ink3)),
      const SizedBox(height: S.x2),
      Wrap(
        spacing: S.x2,
        runSpacing: S.x2,
        children: [
          for (final cat in _labelChoices)
            Pressable(
              semanticLabel: labelKey(_category) == labelKey(cat)
                  ? 'Label $cat, selected'
                  : 'Label $cat',
              // Tap again to clear: a food may have no label.
              onTap: () => setState(
                () =>
                    _category = labelKey(_category) == labelKey(cat) ? '' : cat,
              ),
              child: Pill(
                cat,
                labelKey(_category) == labelKey(cat) ? C.domFood : C.n400,
              ),
            ),
          Pressable(
            semanticLabel: 'New label',
            onTap: _newLabel,
            child: Pill('+ New label', C.n400),
          ),
        ],
      ),
      const SizedBox(height: S.x4),
      // The label's serving on one line, as the pack prints it: "per [50]
      // [g]", or "[6] [piece] · [85] g". Everything logged later scales from
      // it in the same unit.
      Text('NUTRITION LABEL IS FOR', style: F.over.copyWith(color: p.ink3)),
      const SizedBox(height: S.x2),
      Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            flex: 2,
            child: OsTextField(
              controller: _ref,
              label: 'Amount',
              keyboard: num,
            ),
          ),
          const SizedBox(width: S.x2),
          Expanded(
            flex: 3,
            child: OsTextField(
              controller: _unit,
              label: 'Unit',
              hint: 'g, link, slice…',
            ),
          ),
          if (_countLabel) ...[
            const SizedBox(width: S.x2),
            Expanded(
              flex: 2,
              child: OsTextField(
                controller: _servingWeight,
                label: 'Weight (g)',
                hint: '85',
                keyboard: num,
              ),
            ),
          ],
        ],
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
      const SizedBox(height: S.x4),
      field(_kcal, 'Calories (kcal)'),
      field(_protein, 'Protein (g)'),
      field(_carbs, 'Carbs (g)'),
      field(_fat, 'Fat (g)'),
      field(_fibre, 'Fibre (g)'),
      const SizedBox(height: S.x2),
      if (_countLabel)
        Padding(
          padding: const EdgeInsets.only(bottom: S.x2),
          child: Text(
            'Weight is optional: with it, this food logs in grams too.',
            style: F.cap.copyWith(color: p.ink3),
          ),
        ),
      const SizedBox(height: S.x2),
      if (_error != null)
        Text(_error!, style: F.cap.copyWith(color: p.on(C.red))),
      BigButton(
        _saving
            ? 'Saving…'
            : widget.reviewBarcode
            ? 'Save to My foods'
            : 'Save',
        color: C.domFood,
        onTap: _saving ? null : _save,
      ),
    ], changed: () => !_saving && _snapshot != _start);
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
  // The unit each food's amount is in ("link" or "g"), as saved.
  late final Map<String, String> _units = {...?widget.existing?.units};
  // Each item's sub-heading, aligned with [_items].
  late final List<String> _groups = [
    for (var i = 0; i < _items.length; i++) widget.existing?.groupAt(i) ?? '',
  ];
  Map<String, Map<String, Object?>> _defs = const {};

  /// The meal as one comparable value: name, slot, items, units, headings.
  String get _snapshot =>
      '${_label.text}|$_meal|$_items|$_groups|${_units.entries.toList()}';
  late final String _start = _snapshot;

  /// Sub-headings in the order they first appear; '' (none) last.
  List<String> get _order {
    final seen = <String>[];
    for (final g in _groups) {
      if (g.isNotEmpty && !seen.contains(g)) seen.add(g);
    }
    return [...seen, if (_groups.contains('')) ''];
  }

  /// Rewrite the list grouped in [_order], so a section is contiguous.
  void _normalise() {
    final order = _order;
    final pairs = [
      for (var i = 0; i < _items.length; i++) (_items[i], _groups[i]),
    ];
    pairs.sort((a, b) => order.indexOf(a.$2).compareTo(order.indexOf(b.$2)));
    _items
      ..clear()
      ..addAll(pairs.map((x) => x.$1));
    _groups
      ..clear()
      ..addAll(pairs.map((x) => x.$2));
  }

  /// A saved meal keeps ONE unit per food (`MealTemplate.units` is keyed by
  /// food). Before a copy of a food takes [unit], every other copy of it is
  /// converted to that unit, so changing one egg row to grams cannot silently
  /// turn another "2 eggs" into "2 g".
  void _useUnit(String key, String unit) {
    final def = _defs[key];
    final old = _units[key] ?? (def == null ? unit : foodUnit(def));
    if (def != null && old.toLowerCase() != unit.toLowerCase()) {
      final per = unitInBase(def, unit);
      for (var j = 0; j < _items.length; j++) {
        if (_items[j].$1 != key) continue;
        final base = toBase(def, _items[j].$2, old);
        if (base != null && per != null && per > 0) {
          _items[j] = (key, base / per);
        }
      }
    }
    _units[key] = unit;
  }

  void _addPortion(Map<String, Object?> def, Portion portion) {
    final key = def['key'] as String;
    setState(() {
      _useUnit(key, portion.unit);
      _items.add((key, portion.amount));
      _groups.add('');
    });
  }

  Future<void> _editItem(int i) async {
    final def = _defs[_items[i].$1];
    if (def == null) return;
    final result = await _sheet<(Portion, String)>(
      context,
      (s) => _ItemEditor(
        def: def,
        amount: _items[i].$2,
        unit: _units[_items[i].$1] ?? foodUnit(def),
        group: _groups[i],
        groups: _order.where((g) => g.isNotEmpty).toList(),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _useUnit(_items[i].$1, result.$1.unit);
      _items[i] = (_items[i].$1, result.$1.amount);
      _groups[i] = result.$2;
      _normalise();
    });
  }

  @override
  void initState() {
    super.initState();
    _start; // fix the starting point before anything is edited
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

  /// Add foods: search, each food's own serving, and the picker stays open
  /// so a whole meal goes in one visit. Each pick lands in the meal at once.
  Future<void> _addItem() => _sheet<void>(
    context,
    (_) => _MealFoodPicker(foods: _defs.values.toList(), onAdd: _addPortion),
  );

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
            for (final item in items)
              item.$1: _units[item.$1] ?? foodUnit(_defs[item.$1] ?? {}),
          },
          groups: [..._groups],
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
        final b = d == null ? null : toBase(d, g, _units[key] ?? foodUnit(d));
        if (v != null && b != null) sum = (sum ?? 0) + v * b / 100;
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
      GroupedDragList<int>(
        items: [for (var i = 0; i < _items.length; i++) i],
        groupOf: (i) => _groups[i],
        headerBuilder: (c, g, _) => Padding(
          padding: const EdgeInsets.only(top: S.x3, bottom: S.x1),
          child: Text(
            g.isEmpty ? 'No sub-heading' : g,
            style: F.cap.copyWith(color: p.ink2, fontWeight: FontWeight.w600),
          ),
        ),
        onChanged: (arranged) => setState(() {
          final items = [for (final (_, i) in arranged) _items[i]];
          _groups
            ..clear()
            ..addAll([for (final (g, _) in arranged) g]);
          _items
            ..clear()
            ..addAll(items);
        }),
        itemBuilder: (c, i) {
          final item = _items[i];
          return SwipeDelete(
            key: ValueKey('meal-item-$i-${item.$1}'),
            onDelete: () async => setState(() {
              _items.removeAt(i);
              _groups.removeAt(i);
            }),
            child: PickRow(
              (_defs[item.$1]?['label'] ?? 'Deleted food').toString(),
              portionWithWeight(
                item.$2,
                _units[item.$1] ?? foodUnit(_defs[item.$1] ?? {}),
                _defs[item.$1],
              ),
              trailing: LucideIcons.pencil,
              onTap: () => _editItem(i),
            ),
          );
        },
      ),
      if (_items.isNotEmpty)
        Text(
          'Tap to edit · hold to drag · swipe to remove',
          style: F.over.copyWith(color: p.ink3),
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
    ], changed: () => !_saving && _snapshot != _start);
  }
}

// ══════════════════ SHARED PIECES ══════════════════

/// A portion as entered ("3 link") and its amount in the food's label unit.
typedef Portion = ({double amount, String unit, double base});

/// Whether [def] is logged by weight or volume rather than by count.
bool weighedFood(Map<String, Object?> def) {
  final u = foodUnit(def).toLowerCase();
  return u == 'g' || u == 'ml';
}

String _amount(double v) =>
    v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

/// How much of a food, in any of its units: a unit switch when the food has
/// more than one ("g | link"), one large field with − and + either side, the
/// same portion in the other unit underneath ("3 links = 213 g"), and chips
/// for the usual amounts, each labelled once.
///
/// − / + step by one of the selected unit; holding repeats, faster. A count
/// unit offers ½ and 1–4; a weight unit offers the food's count units with
/// their weights ("2 links · 142 g"). Switching unit converts the amount.
/// [unit] is owned by the caller, which logs in it; null keeps the label unit.
class AmountInput extends StatelessWidget {
  const AmountInput({
    super.key,
    required this.controller,
    required this.def,
    this.unit,
  });

  final TextEditingController controller;
  final Map<String, Object?> def;
  final ValueNotifier<String>? unit;

  static bool _weight(String u) =>
      u.toLowerCase() == 'g' || u.toLowerCase() == 'ml';

  @override
  Widget build(BuildContext c) {
    final picker = unit;
    // Without a unit owner the amount stays in the label unit (no switch),
    // but the food's other units still label its chips.
    if (picker == null) {
      return _body(c, foodUnit(def), foodUnitNames(def), switchable: false);
    }
    return ValueListenableBuilder<String>(
      valueListenable: picker,
      builder: (c, u, _) => _body(c, u, foodUnitNames(def), switchable: true),
    );
  }

  Widget _body(
    BuildContext c,
    String unit,
    List<String> units, {
    required bool switchable,
  }) {
    final p = P.of(c);
    double now() => Typed.of(controller.text).value ?? 0;
    void set(double v) => controller.text = _amount(v < 0 ? 0 : v);
    final others = [
      for (final u in units)
        if (u.toLowerCase() != unit.toLowerCase()) u,
    ];
    String inUnit(double baseAmount, String u) {
      final per = unitInBase(def, u);
      return per == null || per <= 0
          ? ''
          : portionText(
              _weight(u)
                  ? (baseAmount / per).roundToDouble()
                  : double.parse((baseAmount / per).toStringAsFixed(2)),
              u,
            );
    }

    final ref = (def['serving_g'] as num?)?.toDouble();
    final chips = <(String, double)>[
      if (!_weight(unit)) ...[
        ('½ $unit', .5),
        for (final k in const [1, 2, 3, 4])
          (portionText(k, unit), k.toDouble()),
      ] else if (others.any((u) => !_weight(u))) ...[
        for (final u in others.where((u) => !_weight(u)).take(2))
          for (final k
              in u == others.firstWhere((x) => !_weight(x))
                  ? const [1, 2]
                  : const [1])
            if (toBase(def, k.toDouble(), u) case final b?)
              if (unitInBase(def, unit) case final per? when per > 0)
                (
                  '${portionText(k, u)} · ${portionText((b / per).roundToDouble(), unit)}',
                  (b / per).roundToDouble(),
                ),
      ] else if (ref != null && ref > 0 && unit == foodUnit(def))
        for (final k in const [.5, 1.0, 2.0])
          (portionText(ref * k, unit), ref * k),
    ];
    Widget stepper(IconData icon, String label, double delta) => Pressable(
      semanticLabel: label,
      repeat: true,
      onTap: () => set(now() + delta),
      child: Container(
        width: 48,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: p.wash(C.domFood),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 20, color: p.on(C.domFood)),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (switchable && units.length > 1) ...[
          Wrap(
            spacing: S.x2,
            children: [
              for (final u in units)
                Pressable(
                  semanticLabel: 'Amount in $u',
                  onTap: () {
                    if (u == unit) return;
                    final b = toBase(def, now(), unit);
                    final per = unitInBase(def, u);
                    this.unit?.value = u;
                    if (b != null && per != null && per > 0 && now() > 0) {
                      final v = b / per;
                      set(
                        _weight(u)
                            ? v.roundToDouble()
                            : double.parse(v.toStringAsFixed(2)),
                      );
                    }
                  },
                  child: Pill(
                    u,
                    u == unit ? C.domFood : C.n400,
                    icon: u == unit ? LucideIcons.check : null,
                  ),
                ),
            ],
          ),
          const SizedBox(height: S.x2),
        ],
        Row(
          children: [
            stepper(LucideIcons.minus, 'Less', -1),
            const SizedBox(width: S.x3),
            Expanded(
              child: OsTextField(
                controller: controller,
                label: 'Amount ($unit)',
                keyboard: const TextInputType.numberWithOptions(decimal: true),
              ),
            ),
            const SizedBox(width: S.x3),
            stepper(LucideIcons.plus, 'More', 1),
          ],
        ),
        if (switchable && others.isNotEmpty) ...[
          const SizedBox(height: S.x1),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (c, _, _) {
              final b = toBase(def, now(), unit);
              return Text(
                b == null || now() <= 0
                    ? ''
                    : '${portionText(now(), unit)} = ${inUnit(b, others.first)}',
                style: F.cap.copyWith(color: p.ink3),
              );
            },
          ),
        ],
        if (chips.isNotEmpty) ...[
          const SizedBox(height: S.x2),
          Wrap(
            spacing: S.x2,
            runSpacing: S.x2,
            children: [
              for (final (label, v) in chips)
                Pressable(
                  semanticLabel: label,
                  onTap: () => set(v),
                  child: Pill(label, C.n400),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// A list the user orders by holding a row and dragging it. Shrink-wrapped
/// for use inside a page or sheet that already scrolls; dragging to an edge
/// scrolls that page ([DragEdgeScroll]). Rows must be keyed.
class DragList extends StatefulWidget {
  const DragList({
    super.key,
    required this.length,
    required this.itemBuilder,
    required this.onReorder,
  });

  final int length;
  final IndexedWidgetBuilder itemBuilder;

  /// (from, to) as [ReorderableListView] reports it: `to` counts the moved
  /// row still in place.
  final void Function(int from, int to) onReorder;

  @override
  State<DragList> createState() => _DragListState();
}

class _DragListState extends State<DragList> {
  bool _dragging = false;

  @override
  Widget build(BuildContext c) => DragEdgeScroll(
    dragging: _dragging,
    child: ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      buildDefaultDragHandles: false,
      itemCount: widget.length,
      onReorderStart: (_) => setState(() => _dragging = true),
      onReorderEnd: (_) => setState(() => _dragging = false),
      onReorder: widget.onReorder,
      proxyDecorator: (child, _, _) =>
          Material(color: Colors.transparent, elevation: 4, child: child),
      itemBuilder: (c, i) {
        final row = widget.itemBuilder(c, i);
        return ReorderableDelayedDragStartListener(
          // Derived, not reused: one key per widget keeps finders unambiguous.
          key: ValueKey<Object>(('drag', row.key ?? i)),
          index: i,
          child: row,
        );
      },
    ),
  );
}

/// One drag list across sub-headings. Hold any item and drop it under
/// another heading — or under "No sub-heading" — to move it there; headings
/// themselves stay put. [onChanged] receives every item with its new heading,
/// in the new order. With no named headings it is a plain drag list. An empty
/// "No sub-heading" appears only while dragging, as somewhere to drop.
class GroupedDragList<T> extends StatefulWidget {
  const GroupedDragList({
    super.key,
    required this.items,
    required this.groupOf,
    required this.itemBuilder,
    required this.headerBuilder,
    required this.onChanged,
  });

  /// In display order.
  final List<T> items;
  final String Function(T) groupOf;

  /// Each row must carry a unique key.
  final Widget Function(BuildContext, T) itemBuilder;
  final Widget Function(BuildContext, String group, List<T> items)
  headerBuilder;
  final void Function(List<(String, T)> arranged) onChanged;

  @override
  State<GroupedDragList<T>> createState() => _GroupedDragListState<T>();
}

class _GroupedDragListState<T> extends State<GroupedDragList<T>> {
  bool _dragging = false;

  List<T> get items => widget.items;
  String groupOf(T i) => widget.groupOf(i);

  @override
  Widget build(BuildContext c) {
    // Named headings in first-appearance order, then ''. The '' heading is
    // ALWAYS a row once any heading exists: Flutter cancels a drag whenever
    // the row count changes, so adding it on drag start made the first hold
    // only reveal it. Empty and not dragging, it is a zero-height row.
    final named = <String>[];
    for (final i in items) {
      final g = groupOf(i);
      if (g.isNotEmpty && !named.contains(g)) named.add(g);
    }
    final loose = items.any((i) => groupOf(i).isEmpty);
    final groups = named.isEmpty ? const [''] : [...named, ''];
    final headed = named.isNotEmpty;
    final rows = <(String?, T?)>[
      for (final g in groups) ...[
        if (headed) (g, null),
        for (final i in items)
          if (groupOf(i) == g) (null, i),
      ],
    ];
    return DragEdgeScroll(
      dragging: _dragging,
      child: ReorderableListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        buildDefaultDragHandles: false,
        itemCount: rows.length,
        proxyDecorator: (child, _, _) =>
            Material(color: Colors.transparent, elevation: 4, child: child),
        onReorderStart: (_) => setState(() => _dragging = true),
        onReorderEnd: (_) => setState(() => _dragging = false),
        onReorder: (from, to) {
          _dragging = false;
          if (rows[from].$2 == null) return; // headings do not move
          final moved = [...rows];
          final row = moved.removeAt(from);
          moved.insert(to > from ? to - 1 : to, row);
          var current = headed ? groups.first : '';
          final out = <(String, T)>[];
          for (final (g, item) in moved) {
            if (item == null) {
              current = g!;
            } else {
              out.add((current, item));
            }
          }
          widget.onChanged(out);
        },
        itemBuilder: (c, i) {
          final (g, item) = rows[i];
          if (item == null) {
            final hidden = g!.isEmpty && !loose && !_dragging;
            return KeyedSubtree(
              key: ValueKey<Object>(('heading', g)),
              child: hidden
                  ? const SizedBox.shrink()
                  : widget.headerBuilder(c, g, [
                      for (final x in items)
                        if (groupOf(x) == g) x,
                    ]),
            );
          }
          final row = widget.itemBuilder(c, item);
          return ReorderableDelayedDragStartListener(
            key: ValueKey<Object>(('drag', row.key ?? i)),
            index: i,
            child: row,
          );
        },
      ),
    );
  }
}

/// Move [list]'s item [from] to [to] (reorderable-list arithmetic).
List<T> reordered<T>(List<T> list, int from, int to) {
  final out = [...list];
  final item = out.removeAt(from);
  out.insert(to > from ? to - 1 : to, item);
  return out;
}

/// Swipe either way to delete, the same on every food list. [onDelete]
/// confirms, writes and removes the row from its owner's state; the swipe
/// itself never removes it, so a cancelled or failed delete keeps the row.
class SwipeDelete extends StatelessWidget {
  const SwipeDelete({
    required Key super.key,
    required this.onDelete,
    required this.child,
  });

  final Future<void> Function() onDelete;
  final Widget child;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    Widget bg(Alignment a) => Container(
      alignment: a,
      padding: const EdgeInsets.symmetric(horizontal: S.x4),
      color: p.wash(C.red),
      child: Icon(LucideIcons.trash2, color: p.on(C.red)),
    );
    return Dismissible(
      key: ValueKey('swipe-${key.hashCode}'),
      confirmDismiss: (_) async {
        await onDelete();
        return false;
      },
      background: bg(Alignment.centerLeft),
      secondaryBackground: bg(Alignment.centerRight),
      child: child,
    );
  }
}

/// The saved-meal food picker: search, each food's labelled serving, and a
/// portion screen per pick; it stays open, listing what was added, until Done.
class _MealFoodPicker extends StatefulWidget {
  const _MealFoodPicker({required this.foods, required this.onAdd});

  final List<Map<String, Object?>> foods;
  final void Function(Map<String, Object?> def, Portion portion) onAdd;

  @override
  State<_MealFoodPicker> createState() => _MealFoodPickerState();
}

class _MealFoodPickerState extends State<_MealFoodPicker> {
  late final _q = TextEditingController()..addListener(() => setState(() {}));
  final _added = <String>[];

  /// The shared category filter; null is All.
  String? _cat;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _pick(Map<String, Object?> def) async {
    final portion = await GramsSheet.show(context, def);
    if (portion == null || !mounted) return;
    widget.onAdd(def, portion);
    setState(
      () => _added.add(
        '${def['label']} · ${portionText(portion.amount, portion.unit)}',
      ),
    );
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final q = _q.text.trim();
    final foods = [
      for (final f in foodsIn(widget.foods, _cat))
        if (q.isEmpty ||
            nameMatches(f['label'], q) ||
            nameMatches(f['brand'], q))
          f,
    ];
    return _sheetBody(c, [
      Text('Add foods', style: F.head.copyWith(color: p.ink)),
      const SizedBox(height: S.x3),
      if (widget.foods.isEmpty)
        Text(
          'Add foods first, under Food › Foods.',
          style: F.cap.copyWith(color: p.ink3),
        )
      else
        OsTextField(
          controller: _q,
          label: 'Search',
          hint: 'Oats, eggs…',
          clearable: true,
        ),
      const SizedBox(height: S.x2),
      FoodCategoryFilter(
        foods: widget.foods,
        selected: _cat,
        onSelect: (cat) => setState(() => _cat = cat),
      ),
      if (_added.isNotEmpty) ...[
        const SizedBox(height: S.x2),
        Text(
          'Added: ${_added.join(', ')}',
          style: F.cap.copyWith(color: p.on(C.domFood)),
        ),
      ],
      const SizedBox(height: S.x2),
      if (widget.foods.isNotEmpty && foods.isEmpty)
        Text('No matches', style: F.cap.copyWith(color: p.ink3)),
      for (final f in foods)
        PickRow(
          (f['label'] ?? '').toString(),
          foodServingLine(f),
          trailing: LucideIcons.plus,
          onTap: () => _pick(f),
        ),
      const SizedBox(height: S.x3),
      BigButton(
        _added.isEmpty ? 'Done' : 'Done · ${_added.length} added',
        color: C.domFood,
        onTap: () => Navigator.of(c).pop(),
      ),
    ]);
  }
}

/// A sub-heading for an item: an existing one, a new one, or none ('').
Future<String?> pickFoodGroup(
  BuildContext c,
  List<String> groups,
  String current,
) async {
  final t = TextEditingController();
  final picked = await _sheet<String>(
    c,
    (s) => _sheetBody(s, [
      Text('Sub-heading', style: F.head.copyWith(color: P.of(s).ink)),
      const SizedBox(height: S.x3),
      for (final g in groups)
        PickRow(
          g,
          g == current ? 'Current' : 'Move here',
          trailing: g == current
              ? LucideIcons.check
              : LucideIcons.cornerDownRight,
          onTap: () => Navigator.of(s).pop(g),
        ),
      if (current.isNotEmpty)
        PickRow(
          'No sub-heading',
          'Back to the main list',
          trailing: LucideIcons.x,
          onTap: () => Navigator.of(s).pop(''),
        ),
      const SizedBox(height: S.x3),
      OsTextField(controller: t, label: 'New sub-heading', hint: 'Omelette'),
      const SizedBox(height: S.x3),
      BigButton(
        'Use this name',
        color: C.domFood,
        onTap: () {
          final v = t.text.trim();
          if (v.isNotEmpty) Navigator.of(s).pop(v);
        },
      ),
    ]),
  );
  t.dispose();
  return picked;
}

/// One saved-meal item: its amount and sub-heading.
class _ItemEditor extends StatefulWidget {
  const _ItemEditor({
    required this.def,
    required this.amount,
    required this.unit,
    required this.group,
    required this.groups,
  });

  final Map<String, Object?> def;
  final double amount;
  final String unit;
  final String group;
  final List<String> groups;

  @override
  State<_ItemEditor> createState() => _ItemEditorState();
}

class _ItemEditorState extends State<_ItemEditor> {
  late final _g = TextEditingController(text: _amount(widget.amount));
  late final _unit = ValueNotifier<String>(
    unitInBase(widget.def, widget.unit) != null
        ? widget.unit
        : foodUnit(widget.def),
  );
  late String _group = widget.group;

  @override
  void initState() {
    super.initState();
    _g.addListener(() => setState(() {}));
    _unit.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _g.dispose();
    _unit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final v = Typed.of(_g.text).value;
    final b = v == null || v <= 0 ? null : toBase(widget.def, v, _unit.value);
    final n = b == null ? null : nutrientsFor(widget.def, b);
    return _sheetBody(c, [
      Text(
        (widget.def['label'] ?? '').toString(),
        style: F.head.copyWith(color: p.ink),
      ),
      const SizedBox(height: S.x4),
      AmountInput(controller: _g, def: widget.def, unit: _unit),
      const SizedBox(height: S.x3),
      Text(
        n == null
            ? 'Enter a positive amount.'
            : macroLine(
                kcal: n.kcal,
                protein: n.protein,
                carbs: n.carbs,
                fat: n.fat,
                fibre: n.fibre,
              ),
        style: F.body.copyWith(color: p.ink, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: S.x3),
      PickRow(
        'Sub-heading',
        _group.isEmpty ? 'None' : _group,
        trailing: LucideIcons.layers,
        onTap: () async {
          final g = await pickFoodGroup(c, widget.groups, _group);
          if (g != null && mounted) setState(() => _group = g);
        },
      ),
      const SizedBox(height: S.x4),
      BigButton(
        'Done',
        color: C.domFood,
        onTap: v == null || v <= 0 || b == null
            ? null
            : () => Navigator.of(
                c,
              ).pop(((amount: v, unit: _unit.value, base: b), _group)),
      ),
    ]);
  }
}

/// A saved meal before it is logged: every item's amount editable, any item
/// switched off, then one Log. The saved meal itself is not changed.
class MealReviewSheet extends StatefulWidget {
  const MealReviewSheet({
    super.key,
    required this.meal,
    required this.defs,
    this.onEdit,
  });

  final MealTemplate meal;
  final Map<String, Map<String, Object?>> defs;

  /// Shows "Edit saved meal": closes the review and lets the caller open the
  /// editor (the same door a food's portion screen has to its editor).
  final VoidCallback? onEdit;

  /// Resolves to one amount per item (null = leave out) with its unit, or
  /// null if cancelled.
  static Future<({List<double?> amounts, List<String> units})?> show(
    BuildContext c,
    MealTemplate m, {
    VoidCallback? onEdit,
  }) async {
    final db = await LocalDb.instance;
    final defs = <String, Map<String, Object?>>{};
    for (final (key, _) in m.items) {
      final d = await NutritionDb.foodDef(db, key);
      if (d != null) defs[key] = d;
    }
    if (!c.mounted) return null;
    return _sheet<({List<double?> amounts, List<String> units})>(
      c,
      (_) => MealReviewSheet(meal: m, defs: defs, onEdit: onEdit),
    );
  }

  @override
  State<MealReviewSheet> createState() => _MealReviewSheetState();
}

class _MealReviewSheetState extends State<MealReviewSheet> {
  late final List<double> _amounts = [
    for (final (_, g) in widget.meal.items) g,
  ];
  late final List<bool> _on = [
    for (final (key, _) in widget.meal.items) widget.defs.containsKey(key),
  ];
  late final List<String> _units = [
    for (final (key, _) in widget.meal.items)
      widget.meal.units[key] ?? foodUnit(widget.defs[key] ?? const {}),
  ];

  Future<void> _edit(int i) async {
    final def = widget.defs[widget.meal.items[i].$1];
    if (def == null) return;
    final v = await GramsSheet.show(
      context,
      def,
      initial: _amounts[i],
      initialUnit: _units[i],
      action: 'Done',
    );
    if (v != null && mounted) {
      setState(
        () => (_amounts[i] = v.amount, _units[i] = v.unit, _on[i] = true),
      );
    }
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final m = widget.meal;
    double? total(String k) {
      double? sum;
      for (var i = 0; i < m.items.length; i++) {
        final d = widget.defs[m.items[i].$1];
        final v = (d?[k] as num?)?.toDouble();
        final b = d == null ? null : toBase(d, _amounts[i], _units[i]);
        if (_on[i] && v != null && b != null) sum = (sum ?? 0) + v * b / 100;
      }
      return sum;
    }

    return _sheetBody(c, [
      Text('Log ${m.label}', style: F.head.copyWith(color: p.ink)),
      const SizedBox(height: S.x1),
      Text(
        'Tap an amount to change it · untick what you skipped',
        style: F.cap.copyWith(color: p.ink3),
      ),
      const SizedBox(height: S.x3),
      for (var i = 0; i < m.items.length; i++) ...[
        if (m.hasGroups && (i == 0 || m.groupAt(i) != m.groupAt(i - 1)))
          Padding(
            padding: const EdgeInsets.only(top: S.x2, bottom: S.x1),
            child: Text(
              m.groupAt(i).isEmpty ? 'No sub-heading' : m.groupAt(i),
              style: F.cap.copyWith(color: p.ink2, fontWeight: FontWeight.w600),
            ),
          ),
        Row(
          children: [
            Pressable(
              semanticLabel: _on[i] ? 'Leave out' : 'Include',
              onTap: widget.defs.containsKey(m.items[i].$1)
                  ? () => setState(() => _on[i] = !_on[i])
                  : null,
              child: Padding(
                padding: const EdgeInsets.only(right: S.x3),
                child: Icon(
                  _on[i] ? LucideIcons.squareCheck : LucideIcons.square,
                  size: 20,
                  color: p.on(C.domFood),
                ),
              ),
            ),
            Expanded(
              child: PickRow(
                (widget.defs[m.items[i].$1]?['label'] ?? 'Deleted food')
                    .toString(),
                widget.defs.containsKey(m.items[i].$1)
                    ? portionWithWeight(
                        _amounts[i],
                        _units[i],
                        widget.defs[m.items[i].$1],
                      )
                    : 'No longer in My foods',
                trailing: LucideIcons.pencil,
                onTap: () => _edit(i),
              ),
            ),
          ],
        ),
      ],
      const SizedBox(height: S.x2),
      Text(
        macroLine(
          kcal: total('kcal_100'),
          protein: total('protein_g_100'),
          carbs: total('carbs_g_100'),
          fat: total('fat_g_100'),
          fibre: total('fibre_g_100'),
        ),
        style: F.body.copyWith(color: p.ink, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: S.x4),
      BigButton(
        'Log',
        color: C.domFood,
        onTap: !_on.contains(true)
            ? null
            : () => Navigator.of(c).pop((
                amounts: [
                  for (var i = 0; i < m.items.length; i++)
                    _on[i] ? _amounts[i] : null,
                ],
                units: _units,
              )),
      ),
      if (widget.onEdit != null) ...[
        const SizedBox(height: S.x2),
        PickRow(
          'Edit saved meal',
          'Change its foods, amounts or sub-headings',
          trailing: LucideIcons.pencil,
          onTap: () {
            widget.onEdit!();
            Navigator.of(c).pop();
          },
        ),
      ],
    ]);
  }
}
