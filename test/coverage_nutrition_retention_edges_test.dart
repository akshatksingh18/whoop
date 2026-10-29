// Legacy entry provenance and nutrient-specific means stay honest at the store seam.
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/nutrition_store.dart';
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('nutrition-retention-edges'));
  setUp(() async {
    await resetCoverageStore();
    autoCountKcalGoal = null;
  });
  tearDownAll(LocalDb.close);
  test(
    'unconfirmed photo-origin input keeps provenance and never persists guessed nutrients',
    () async {
      final db = await LocalDb.instance;
      const e = FoodEntry(
        id: 'synthetic-photo',
        date: '2021-04-06',
        meal: 'lunch',
        label: 'Synthetic label',
        atTs: 1617714000,
        loggedAt: 1617715000,
        quantity: 100,
        unit: 'g',
        kcal: 400,
        proteinG: 20,
        fibreG: 3,
        foodKey: 'synthetic-key',
        group: 'Bowl',
        note: 'Authored test note',
        source: FoodSource.photo,
        confirmed: false,
      );
      await NutritionDb.put(db, e);
      final saved = (await NutritionDb.entriesForDay(db, e.date)).single;
      expect(saved.isBareOccasion, isTrue);
      expect(saved.quantity, isNull);
      expect(saved.kcal, isNull);
      expect(saved.proteinG, isNull);
      expect(saved.fibreG, isNull);
      expect(saved.label, e.label);
      expect(saved.atTs, e.atTs);
      expect(saved.loggedAt, e.loggedAt);
      expect(saved.foodKey, e.foodKey);
      expect(saved.group, 'Bowl');
      expect(saved.note, e.note);
      expect(saved.source, FoodSource.photo);
    },
  );
  test(
    'window means name complete nutrient days and exclude floors independently',
    () {
      FoodEntry entry(
        String id,
        String day,
        double kcal,
        double? protein,
        double? fibre,
      ) => FoodEntry(
        id: id,
        date: day,
        meal: 'lunch',
        label: id,
        kcal: kcal,
        proteinG: protein,
        fibreG: fibre,
      );
      const today = '2021-04-09';
      final window = NutritionWindow([
        rollupDay(
          '2021-04-06',
          [
            entry('a', '2021-04-06', 400, 10, 0),
            entry('b', '2021-04-06', 600, null, null),
          ],
          today: today,
          mark: 'complete',
        ),
        rollupDay(
          '2021-04-07',
          [entry('c', '2021-04-07', 800, 20, 3)],
          today: today,
          mark: 'complete',
        ),
        rollupDay(
          '2021-04-08',
          [entry('d', '2021-04-08', 500, 30, 5)],
          today: today,
          mark: 'incomplete',
        ),
        rollupDay(today, [entry('e', today, 900, 40, 6)], today: today),
      ]);
      expect(window.span, 4);
      expect(window.daysLogged, 4);
      expect(window.daysExcluded, 2);
      expect(window.meanKcal.value, 900);
      expect(window.meanKcal.days, 2);
      expect(window.meanProtein.value, 20);
      expect(window.meanProtein.days, 1);
      expect(window.meanProtein.floorDays, 1);
      expect(window.meanFibre.value, 3);
      expect(window.meanFibre.floorDays, 1);
      expect(const NutritionWindow([]).meanProtein.value, isNull);
    },
  );
  test(
    'moving an existing entry refreshes both count rows and preserves its original log time',
    () async {
      final db = await LocalDb.instance;
      const from = '2021-04-06', to = '2021-04-07';
      // Count rows are frozen only after the profile goal has hydrated.
      autoCountKcalGoal = 2000;
      const e = FoodEntry(
        id: 'synthetic-move',
        date: from,
        meal: 'lunch',
        label: 'Synthetic move',
        kcal: 500,
        loggedAt: 1617715000,
      );
      await NutritionDb.setDayMark(db, from, 'complete');
      await NutritionDb.setDayMark(db, to, 'complete');
      await NutritionDb.put(db, e);
      await NutritionDb.put(db, e.copyTo(to, 'dinner', newId: e.id));
      expect(await NutritionDb.entriesForDay(db, from), isEmpty);
      final moved = (await NutritionDb.entriesForDay(db, to)).single;
      expect(moved.loggedAt, e.loggedAt);
      expect(moved.meal, 'dinner');
      final counts = {
        for (final row in await db.query('food_day_count'))
          row['date']: row['counted'],
      };
      expect(counts[from], 0);
      expect(counts[to], 1);
      expect((await NutritionDb.recent(db)).single.id, e.id);
    },
  );
  test(
    'portion and day-mark validation refuses invalid input before any write',
    () async {
      const unmeasured = FoodEntry(
        id: 'synthetic',
        date: '2021-04-06',
        meal: 'lunch',
        label: 'Synthetic',
      );
      for (final amount in [0.0, -1.0, double.nan, double.infinity, 10.0]) {
        expect(() => unmeasured.atQuantity(amount), throwsArgumentError);
      }
      for (final grams in [0.0, -1.0, double.nan, double.infinity]) {
        expect(
          () =>
              myFoodDef(key: 'synthetic', label: 'Synthetic', refGrams: grams),
          throwsArgumentError,
        );
      }
      expect(
        () => myFoodDef(
          key: 'synthetic',
          label: 'Synthetic',
          refGrams: 100,
          kcal: -1,
        ),
        throwsArgumentError,
      );
      final db = await LocalDb.instance;
      await expectLater(
        NutritionDb.setDayMark(db, todayLabel(), 'invented'),
        throwsArgumentError,
      );
      expect(await db.query('food_day_mark'), isEmpty);
      expect(await db.query('food_entry'), isEmpty);
    },
  );
}
