// My foods and saved meals: label numbers stored per 100 g, logged by weight.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/nutrition_store.dart';

void main() {
  // "50 g of oats is 200 kcal, 6.5 g protein, 33 g carbs" — no fat or fibre.
  final oats = myFoodDef(
      key: 'my:oats', label: 'Oats', refGrams: 50, kcal: 200, protein: 6.5, carbs: 33);

  test('label numbers are stored per 100 g', () {
    expect(oats['kcal_100'], 400);
    expect(oats['protein_g_100'], 13);
    expect(oats['carbs_g_100'], 66);
    expect(oats['fat_g_100'], isNull, reason: 'never typed is unknown, not zero');
    expect(oats['serving_g'], 50);
  });

  test('53 g scales every number from the same label', () {
    final n = nutrientsFor(oats, 53);
    expect(n.kcal, closeTo(212, 1e-9));
    expect(n.protein, closeTo(6.89, 1e-9));
    expect(n.carbs, closeTo(34.98, 1e-9));
    expect(n.fat, isNull);
  });

  test('a logged food carries its weight and key', () {
    final e = entryFromFood(oats, 53,
        id: 'x', date: '2026-09-30', meal: 'breakfast');
    expect(e.quantity, 53);
    expect(e.foodKey, 'my:oats');
    expect(e.meal, 'breakfast');
    expect(e.kcal, closeTo(212, 1e-9));
  });

  test('a saved meal round-trips through its row, and a damaged row is empty',
      () {
    const m = MealTemplate(
        key: 'meal:1',
        label: 'My breakfast',
        meal: 'breakfast',
        items: [('my:oats', 50), ('my:whey', 30)]);
    final back = MealTemplate.fromRow(m.toRow(0));
    expect(back.label, 'My breakfast');
    expect(back.items, [('my:oats', 50.0), ('my:whey', 30.0)]);
    final bad = MealTemplate.fromRow(
        {'key': 'k', 'label': 'x', 'meal': 'lunch', 'items_json': 'not json'});
    expect(bad.items, isEmpty);
  });
}
