// "After this, today" (Build 90, Akshat's option B): while an amount is being
// chosen, what is left of the day's goals once this food is logged, and a
// one-tap amount that uses up the calories left. Shared by the food screen he
// logs from (`FoodDetailSheet`) and the amount sheet (`GramsSheet`).
//
// Nothing is guessed: no goal hides the card, an item with unknown calories
// (logged, or ticked to log alongside) makes what is left an "at most", and
// the fit then says "at most" too (Build 91, Codex audit F01); a food without
// calories offers no fit.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/day_label.dart' show dayLabelOf, todayLabel;
import '../../data/db.dart';
import '../../data/nutrition_store.dart';
import '../ui2.dart';
import 'home_screen.dart' show prettyDay, thousands;

/// One food's nutrients, as `nutrientsFor` returns them.
typedef Nutrients = ({
  double? kcal,
  double? protein,
  double? carbs,
  double? fat,
  double? fibre,
});

/// [a] + [b], nutrient by nutrient; a nutrient neither has stays null.
Nutrients addNutrients(Nutrients a, Nutrients b) {
  double? add(double? x, double? y) =>
      x == null && y == null ? null : (x ?? 0) + (y ?? 0);
  return (
    kcal: add(a.kcal, b.kcal),
    protein: add(a.protein, b.protein),
    carbs: add(a.carbs, b.carbs),
    fat: add(a.fat, b.fat),
    fibre: add(a.fibre, b.fibre),
  );
}

/// What is left of [goal] after the day's [eaten] and [thisAmount], or null
/// without a goal, an unloaded day or an unknown amount for this food.
/// `atMost` when some logged item had no value for this nutrient (the day's
/// total is a floor, so what is left is a ceiling).
({double value, bool atMost})? leftAfter(
  double? goal,
  NutrientTotal? eaten,
  double? thisAmount,
) {
  if (goal == null || goal <= 0 || eaten == null || thisAmount == null) {
    return null;
  }
  return (
    value: goal - (eaten.value ?? 0) - thisAmount,
    atMost: eaten.unknown > 0,
  );
}

/// Whether a fit or "left" figure is only a ceiling: some logged item, or a
/// ticked companion ([otherUnknown]), has no calories, so they may already
/// have used some of what looks free.
bool fitIsCeiling(NutrientTotal? eaten, {bool otherUnknown = false}) =>
    otherUnknown || (eaten?.unknown ?? 0) > 0;

/// The amount of a food, in its current unit, that uses up the calories left
/// after the day's [eaten] and [otherKcal] (ticked companions), rounded DOWN
/// (whole grams or millilitres, half units otherwise) so it never goes over.
/// Null when nothing is left, the food has no calories, or less than one step
/// would fit.
double? fitAmount({
  required double? goal,
  required NutrientTotal? eaten,
  required double? kcalPerUnit,
  required String unit,
  double otherKcal = 0,
}) {
  if (goal == null || goal <= 0 || eaten == null) return null;
  if (kcalPerUnit == null || !kcalPerUnit.isFinite || kcalPerUnit <= 0) {
    return null;
  }
  final left = goal - (eaten.value ?? 0) - otherKcal;
  if (left <= 0) return null;
  final step = const {'g', 'ml'}.contains(unit.toLowerCase()) ? 1.0 : 0.5;
  final amount = (left / kcalPerUnit / step).floor() * step;
  return amount < step ? null : amount;
}

/// The day's logged food for [date], leaving out [excludeId] (the entry being
/// edited, so it counts once). Null when it cannot be read.
Future<NutritionDay?> loadDayIntake(String date, {String? excludeId}) async {
  try {
    final db = await LocalDb.instance;
    final es = [
      for (final e in await NutritionDb.entriesForDay(db, date))
        if (e.id != excludeId) e,
    ];
    return rollupDay(date, es, today: todayLabel());
  } catch (_) {
    return null;
  }
}

/// The "Fit what's left · 243 g" chip; "at most 243 g" when [atMost].
class FitChip extends StatelessWidget {
  const FitChip({
    super.key,
    required this.label,
    required this.onTap,
    this.atMost = false,
  });
  final String label;
  final VoidCallback onTap;
  final bool atMost;
  @override
  Widget build(BuildContext c) {
    final amount = atMost ? 'at most $label' : label;
    return Pressable(
      semanticLabel: 'Fit what is left, $amount',
      onTap: onTap,
      child: Pill(
        'Fit what\'s left · $amount',
        C.domFood,
        icon: LucideIcons.target,
      ),
    );
  }
}

/// The card under the amount: calories left (or over) after this food, an
/// eaten / this / free bar over the goal, and protein left.
class LeftAfterCard extends StatelessWidget {
  const LeftAfterCard({
    super.key,
    required this.day,
    required this.kcalGoal,
    required this.proteinGoal,
    required this.thisKcal,
    required this.thisProtein,
    this.thisKcalPartial = false,
    this.thisProteinPartial = false,
    this.date,
  });

  /// The diary day the food goes on; null means today. The heading names it
  /// ("After this, yesterday"), never claiming today for another day
  /// (Build 91, Codex audit F12).
  final String? date;

  static String _dayWord(String? date) {
    final today = todayLabel();
    if (date == null || date == today) return 'today';
    final t = DateTime.parse(today);
    if (date == dayLabelOf(DateTime(t.year, t.month, t.day - 1))) {
      return 'yesterday';
    }
    return prettyDay(date);
  }

  final NutritionDay? day;
  final double? kcalGoal, proteinGoal, thisKcal, thisProtein;

  /// Part of this plate (a ticked companion) has no value for the nutrient,
  /// so what is left after it is only a ceiling.
  final bool thisKcalPartial, thisProteinPartial;

  @override
  Widget build(BuildContext c) {
    final d = day;
    final goal = kcalGoal;
    final left = leftAfter(goal, d?.kcal, thisKcal);
    if (d == null || goal == null || goal <= 0) return const SizedBox.shrink();
    final p = P.of(c);
    final eaten = d.kcal.value ?? 0;
    final over = left != null && left.value < 0;
    final big = thisKcal == null
        ? 'This food\'s calories are unknown'
        : over
        ? 'Over by ${thousands(-left.value)} kcal'
        : '${left!.atMost || thisKcalPartial ? 'At most ' : ''}'
              '${thousands(left.value)} kcal left';
    final protein = leftAfter(proteinGoal, d.protein, thisProtein);
    final proteinCeiling = (protein?.atMost ?? false) || thisProteinPartial;
    final eatenFrac = (eaten / goal).clamp(0.0, 1.0).toDouble();
    final thisFrac = ((thisKcal ?? 0) / goal)
        .clamp(0.0, 1.0 - eatenFrac)
        .toDouble();
    final thisColor = over ? p.on(C.alert) : p.on(C.food);
    final eatenColor = p.on(C.food).withValues(alpha: .55);
    return Semantics(
      container: true,
      label:
          'After this, ${_dayWord(date)}: $big'
          '${protein == null ? '' : ', protein ${protein.value.round()} grams left'}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(S.x4, S.x3, S.x4, S.x3),
        decoration: BoxDecoration(color: p.card2, borderRadius: R.rLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: S.x2,
              children: [
                Text(
                  'After this, ${_dayWord(date)}',
                  style: F.cap.copyWith(
                    color: p.ink2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  big,
                  style: (thisKcal == null ? F.body : F.n24).copyWith(
                    color: over ? p.on(C.alert) : p.ink,
                  ),
                ),
              ],
            ),
            const SizedBox(height: S.x2),
            ClipRRect(
              borderRadius: R.rPill,
              child: SizedBox(
                height: 10,
                child: LayoutBuilder(
                  builder: (c, box) => Stack(
                    children: [
                      Positioned.fill(child: ColoredBox(color: p.track)),
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        width: box.maxWidth * eatenFrac,
                        child: ColoredBox(color: eatenColor),
                      ),
                      Positioned(
                        left: box.maxWidth * eatenFrac,
                        top: 0,
                        bottom: 0,
                        width: math.max(0, box.maxWidth * thisFrac),
                        child: ColoredBox(color: thisColor),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: S.x2),
            Wrap(
              spacing: S.x3,
              runSpacing: S.x1,
              children: [
                _key(
                  p,
                  eatenColor,
                  'eaten ${d.kcal.isFloor ? 'at least ' : ''}${thousands(eaten)}',
                ),
                _key(
                  p,
                  thisColor,
                  'this ${thisKcal == null ? '–' : thousands(thisKcal)}',
                ),
                Text(
                  'goal ${thousands(goal)}',
                  style: F.cap.copyWith(color: p.ink2),
                ),
              ],
            ),
            if (protein != null) ...[
              const SizedBox(height: S.x1),
              Text(
                protein.value < 0
                    ? 'Protein goal met'
                    : 'Protein: ${proteinCeiling ? 'at most ' : ''}'
                          '${protein.value.round()} g left of '
                          '${proteinGoal!.round()}',
                style: F.body.copyWith(color: p.ink),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static Widget _key(P p, Color color, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(color: color, borderRadius: R.rSm),
      ),
      const SizedBox(width: S.x1),
      Flexible(
        child: Text(label, style: F.cap.copyWith(color: p.ink2)),
      ),
    ],
  );
}
