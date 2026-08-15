// Logging an eating occasion.
//
// The primary unit is the OCCASION, not the food. The big button at the top
// writes a complete, valid entry with no numbers in it at all — a trial
// comparing detailed against simplified logging found 49% of days logged
// versus 97%, with identical six-month weight loss. Macro detail is the tier
// underneath, opened deliberately, and never the path a new user is walked
// down.
//
// There is no barcode scan and no photo estimate. The sheet does not say so
// either — a card explaining a feature that does not exist is an advert for
// it. See docs/internal/UI_ROADMAP.md. The store's guard for a future photo path
// (`FoodEntry.sanitised`, which never lets a photo carry a total) stays where
// it is, because it is a data rule rather than a screen.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/db.dart';
import '../../data/day_label.dart';
import '../../data/nutrition_store.dart';
import '../ui2.dart';
import 'journal_compose.dart' show OsTextField;

class LogFoodSheet extends StatefulWidget {
  const LogFoodSheet({super.key, this.date, this.meal = 'snack'});

  final String? date;
  final String meal;

  /// Show as a bottom sheet. Resolves true when something was logged.
  static Future<bool?> show(
    BuildContext c, {
    String? date,
    String meal = 'snack',
  }) => showModalBottomSheet<bool>(
    context: c,
    isScrollControlled: true,
    sheetAnimationStyle: sheetMotion(c),
    backgroundColor: P.of(c).card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(R.xxl)),
    ),
    builder: (_) => LogFoodSheet(date: date, meal: meal),
  );

  @override
  State<LogFoodSheet> createState() => _LogFoodSheetState();
}

class _LogFoodSheetState extends State<LogFoodSheet> {
  late final String _date = widget.date ?? todayLabel();
  late String _meal = widget.meal;

  final _label = TextEditingController();
  final _kcal = TextEditingController();
  final _protein = TextEditingController();
  final _carbs = TextEditingController();
  final _fat = TextEditingController();
  final _fibre = TextEditingController();

  List<FoodEntry> _recent = const [];
  bool _detail = false;

  @override
  void initState() {
    super.initState();
    _loadRecent();
  }

  @override
  void dispose() {
    for (final t in [_label, _kcal, _protein, _carbs, _fat]) {
      t.dispose();
    }
    super.dispose();
  }

  Future<void> _loadRecent() async {
    final db = await LocalDb.instance;
    final r = await NutritionDb.recent(db);
    if (mounted) setState(() => _recent = r);
  }

  Future<void> _write(FoodEntry e) async {
    final db = await LocalDb.instance;
    await NutritionDb.put(db, e);
    if (mounted) Navigator.of(context).pop(true);
  }

  FoodEntry _base({
    required String label,
    FoodSource source = FoodSource.manual,
  }) => FoodEntry(
    id: NutritionDb.newId(),
    date: _date,
    meal: _meal,
    label: label,
    atTs: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    source: source,
  );

  double? _num(TextEditingController t) {
    final s = t.text.trim();
    if (s.isEmpty) return null; // blank is unknown, never zero.
    return double.tryParse(s);
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(c).bottom),
      child: SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(S.x5, S.x4, S.x5, S.x6),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Log an eating occasion',
                      style: F.t2.copyWith(color: p.ink)),
                ),
                Pressable(
                  semanticLabel: 'Close',
                  onTap: () => Navigator.of(c).pop(),
                  child: Icon(LucideIcons.x, size: 20, color: p.ink3),
                ),
              ],
            ),
            const SizedBox(height: S.x4),
            Row(
              children: [
                for (final m in kMeals) ...[
                  Expanded(
                    child: Pressable(
                      onTap: () => setState(() => _meal = m),
                      semanticLabel: m,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: S.x3),
                        decoration: BoxDecoration(
                          color: m == _meal ? p.fill(C.domFood) : p.card2,
                          borderRadius: R.rSm,
                        ),
                        child: Center(
                          child: Text(
                            _mealLabel(m),
                            style: F.cap.copyWith(
                              color: m == _meal ? p.inkOnFill : p.ink2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (m != kMeals.last) const SizedBox(width: S.x2),
                ],
              ],
            ),
            const SizedBox(height: S.x5),
            BigButton(
              'I ate ${_mealLabel(_meal).toLowerCase()}',
              icon: LucideIcons.check,
              color: C.domFood,
              onTap: () => _write(_base(label: _mealLabel(_meal))),
            ),
            const SizedBox(height: S.x2),
            Text(
              'One tap is a complete log. Energy stays unknown, and the day '
              'says so rather than guessing.',
              style: F.cap.copyWith(color: p.ink3, height: 1.45),
            ),
            if (_recent.isNotEmpty)
              Section(
                'Again',
                Surface(
                  pad: const EdgeInsets.symmetric(horizontal: S.x4),
                  child: Column(
                    children: [
                      for (final r in _recent.take(5))
                        FoodRow(
                          entry: r,
                          trailing: LucideIcons.circlePlus,
                          onTap: () => _write(
                            FoodEntry(
                              id: NutritionDb.newId(),
                              date: _date,
                              meal: _meal,
                              label: r.label,
                              atTs:
                                  DateTime.now().millisecondsSinceEpoch ~/ 1000,
                              foodKey: r.foodKey,
                              quantity: r.quantity,
                              unit: r.unit,
                              kcal: r.kcal,
                              proteinG: r.proteinG,
                              carbsG: r.carbsG,
                              fatG: r.fatG,
                              fibreG: r.fibreG,
                              source: FoodSource.repeat,
                              confirmed: r.confirmed,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: S.x5),
            Pressable(
              onTap: () => setState(() => _detail = !_detail),
              child: Row(
                children: [
                  Icon(
                    _detail ? LucideIcons.chevronDown : LucideIcons.chevronRight,
                    size: 18,
                    color: p.ink3,
                  ),
                  const SizedBox(width: S.x2),
                  Expanded(
                    child: Text(
                      'Add the numbers',
                      style: F.body.copyWith(color: p.ink2),
                    ),
                  ),
                ],
              ),
            ),
            if (_detail) ...[
              const SizedBox(height: S.x3),
              OsTextField(
                controller: _label,
                label: 'What',
                hint: 'Chicken and rice',
              ),
              const SizedBox(height: S.x4),
              _NumberRow(
                fields: [
                  ('Energy', 'kcal', _kcal),
                  ('Protein', 'g', _protein),
                ],
              ),
              const SizedBox(height: S.x4),
              _NumberRow(
                fields: [
                  ('Carbs', 'g', _carbs),
                  ('Fat', 'g', _fat),
                ],
              ),
              const SizedBox(height: S.x4),
              // The week card has always averaged fibre; nothing could enter
              // it, so the row read "Not recorded" forever.
              _NumberRow(fields: [('Fibre', 'g', _fibre)]),
              const SizedBox(height: S.x3),
              Text(
                'Leave anything blank you do not know. Blank stays blank — it '
                'never becomes a zero.',
                style: F.cap.copyWith(color: p.ink3, height: 1.45),
              ),
              const SizedBox(height: S.x4),
              BigButton(
                'Save',
                color: C.domFood,
                soft: true,
                onTap: () {
                  final label = _label.text.trim();
                  if (label.isEmpty) return;
                  final b = _base(label: label);
                  _write(
                    FoodEntry(
                      id: b.id,
                      date: b.date,
                      meal: b.meal,
                      label: label,
                      atTs: b.atTs,
                      kcal: _num(_kcal),
                      proteinG: _num(_protein),
                      carbsG: _num(_carbs),
                      fatG: _num(_fat),
                      fibreG: _num(_fibre),
                      confirmed: true,
                    ),
                  );
                },
              ),
            ],
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
  _ => 'Snack',
};

/// One logged entry. The provenance line is not decoration: a manufacturer
/// panel and a typed guess are different claims, and the row says which it is.
class FoodRow extends StatelessWidget {
  const FoodRow({
    super.key,
    required this.entry,
    this.trailing,
    this.onTap,
  });

  final FoodEntry entry;
  final IconData? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Pressable(
      onTap: onTap,
      semanticLabel: '${entry.label}. ${_detail(entry)}',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: S.x3),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: p.card2, borderRadius: R.rSm),
              child: Icon(LucideIcons.utensils, size: 16, color: p.ink3),
            ),
            const SizedBox(width: S.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.label, style: F.body.copyWith(color: p.ink)),
                  Text(
                    _detail(entry),
                    style: F.over.copyWith(color: p.ink3),
                  ),
                ],
              ),
            ),
            // The "Verified" branch is unreachable: only `manual` and
            // `repeat` are ever written, because there is no food database to
            // verify against. Every entry here is yours, and only that is said.
            const SizedBox(width: S.x2),
            const Pill('Yours', C.n400),
            if (trailing != null) ...[
              const SizedBox(width: S.x2),
              Icon(trailing, size: 20, color: p.on(C.domFood)),
            ],
          ],
        ),
      ),
    );
  }

  static String _detail(FoodEntry e) {
    // No photo pipeline exists, so `FoodSource.photo` is never written and the
    // branch that read it could never run.
    if (e.isBareOccasion) return 'LOGGED · ENERGY NOT RECORDED';
    final parts = <String>['${e.kcal!.round()} kcal'];
    if (e.proteinG != null) parts.add('${e.proteinG!.round()}P');
    if (e.carbsG != null) parts.add('${e.carbsG!.round()}C');
    if (e.fatG != null) parts.add('${e.fatG!.round()}F');
    return parts.join(' · ');
  }
}

class _NumberRow extends StatelessWidget {
  const _NumberRow({required this.fields});
  final List<(String, String, TextEditingController)> fields;

  @override
  Widget build(BuildContext c) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (var i = 0; i < fields.length; i++) ...[
        Expanded(
          child: OsTextField(
            controller: fields[i].$3,
            label: '${fields[i].$1} (${fields[i].$2})',
            hint: 'unknown',
            keyboard: const TextInputType.numberWithOptions(decimal: true),
          ),
        ),
        if (i < fields.length - 1) const SizedBox(width: S.x3),
      ],
    ],
  );
}
