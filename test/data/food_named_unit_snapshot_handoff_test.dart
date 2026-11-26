// Named label units with only an explicit weight conversion are authored by the
// existing food-definition producer, then read through real stored diary rows.
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/nutrition_store.dart';
import '../support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('food-named-snapshot-handoff'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  for (final (amount, expected) in [
    (1.0, '1 g'),
    (35.5, '35.5 g · 0.5 links'),
    (142.0, '142 g · 2 links'),
  ]) {
    test(
      'stored $amount g keeps its original named-serving conversion after edits and deletion',
      () async {
        final db = await LocalDb.instance;
        final def = myFoodDef(
          key: 'authored-link',
          label: 'Authored food',
          refGrams: 1,
          unit: 'link',
          kcal: 200,
          protein: 10,
          fat: 0,
          measures: [(label: 'g', amount: 1 / 71)],
        );
        await NutritionDb.putFoodDef(db, def);
        final original = (await NutritionDb.foodDef(db, 'authored-link'))!;
        expect(foodUnitNames(original), ['link', 'g']);
        final base = toBase(original, amount, 'g')!;
        final entry = entryFromFood(
          original,
          base,
          id: 'authored-entry',
          date: '2021-04-06',
          meal: 'lunch',
          amount: amount,
          unit: 'g',
        );
        await NutritionDb.put(db, entry);
        final stored = (await NutritionDb.entriesForDay(
          db,
          '2021-04-06',
        )).single;
        final row = await db.query('food_entry');
        expect(stored.quantity, amount);
        expect(stored.unit, 'g');
        expect(stored.conv, isNotEmpty);
        expect(stored.kcal, closeTo(200 * amount / 71, 1e-9));
        expect(stored.fatG, 0);
        expect(stored.carbsG, isNull);
        expect(
          portionWithWeight(amount, 'g', conversionDef(stored, original)),
          expected,
        );

        final edited = myFoodDef(
          key: 'authored-link',
          label: 'Edited authored food',
          refGrams: 1,
          unit: 'link',
          kcal: 300,
          protein: 10,
          fat: 0,
          measures: [(label: 'g', amount: 1 / 100)],
        );
        await NutritionDb.putFoodDef(db, edited);
        final now = (await NutritionDb.foodDef(db, 'authored-link'))!;
        expect(unitInBase(now, 'g'), 1 / 100);
        expect(
          portionWithWeight(amount, 'g', conversionDef(stored, now)),
          expected,
        );
        await MyFoods.deleteFood(db, 'authored-link');
        expect(await NutritionDb.foodDef(db, 'authored-link'), isNull);
        final reopened = (await NutritionDb.entriesForDay(
          db,
          '2021-04-06',
        )).single;
        expect(
          portionWithWeight(amount, 'g', conversionDef(reopened, null)),
          expected,
        );
        expect(await db.query('food_entry'), row);
        expect(reopened.kcal, stored.kcal);
        expect(reopened.carbsG, isNull);
        expect(reopened.fatG, 0);
      },
    );
  }
}
