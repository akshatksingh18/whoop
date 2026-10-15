import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:openstrap_edge/data/nutrition_store.dart';

void main() {
  late Database db;
  const date = '2025-01-05';
  FoodEntry food({double? kcal = 1400}) => FoodEntry(
    id: 'synthetic-entry',
    date: date,
    meal: 'dinner',
    label: 'Synthetic meal',
    kcal: kcal,
    atTs: DateTime(2025, 1, 5, 19).millisecondsSinceEpoch ~/ 1000,
  );
  Future<NutritionDay> day() async => rollupDay(
    date,
    await NutritionDb.entriesForDay(db, date),
    today: '2025-01-06',
    mark: (await NutritionDb.dayMarks(db, date))[date],
  );
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    NutritionDb.resetCountingContext();
    autoCountKcalGoal = 2300;
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await createNutritionTables(db);
  });
  tearDown(() async {
    await db.close();
    autoCountKcalGoal = null;
  });

  test(
    'first-open legacy target freezes even when the profile goal changes',
    () async {
      await db.insert('food_entry', food().toRow(1));
      await NutritionDb.freezeCounting(db);
      final first = await day();
      expect(first.countsTowardAverages, true);
      expect(first.counting!.calorieGoal, 2300);
      autoCountKcalGoal = 3000;
      await NutritionDb.freezeCounting(db);
      final second = await day();
      expect(second.countsTowardAverages, true);
      expect(second.counting!.calorieGoal, 2300);
      expect(second.counting!.frozenAt, first.counting!.frozenAt);
      expect(countedAutomatically(second, null), true);
    },
  );
  test('manual marks win and keep distinct persisted provenance', () async {
    await NutritionDb.put(db, food());
    await NutritionDb.setDayMark(db, date, 'incomplete');
    expect((await day()).countsTowardAverages, false);
    expect((await day()).counting!.basis, 'marked_incomplete');
    await NutritionDb.setDayMark(db, date, 'complete');
    final marked = await day();
    expect(marked.countsTowardAverages, true);
    expect(marked.counting!.basis, 'marked_complete');
    expect(countedAutomatically(marked, 'complete'), false);
    await NutritionDb.setDayMark(db, date, null);
    expect((await day()).counting!.basis, 'automatic');
  });
  test(
    'editing and deleting refresh eligibility without replacing the frozen goal',
    () async {
      await NutritionDb.put(db, food());
      autoCountKcalGoal = 1800;
      await NutritionDb.put(db, food(kcal: null));
      expect((await day()).countsTowardAverages, false);
      expect((await day()).counting!.calorieGoal, 2300);
      await NutritionDb.setDayMark(db, date, 'complete');
      expect(
        (await day()).countsTowardAverages,
        false,
        reason: 'A manual mark cannot invent unknown energy',
      );
      await NutritionDb.delete(db, food().id);
      final evidence = (await db.query('food_day_count')).single;
      expect(evidence['counted'], 0);
    },
  );
  test(
    'a missing first-open goal stays absent rather than borrowing a later one',
    () async {
      autoCountKcalGoal = null;
      await db.insert('food_entry', food().toRow(1));
      await NutritionDb.freezeCounting(db, goalKnown: true);
      autoCountKcalGoal = 2000;
      expect((await day()).countsTowardAverages, false);
      expect((await day()).counting!.calorieGoal, isNull);
    },
  );
  test('pre-profile read cannot freeze an absent target', () async {
    autoCountKcalGoal = null;
    await db.insert('food_entry', food().toRow(1));
    await NutritionDb.entriesForDay(db, date);
    expect(await db.query('food_day_count'), isEmpty);
    autoCountKcalGoal = 2300;
    await NutritionDb.freezeCounting(db, goalKnown: true);
    expect((await day()).countsTowardAverages, true);
  });
  test(
    'eaten time stays on the viewed meal date; original logging time survives edits',
    () async {
      final mealTime = foodEntryTime(
        date,
        'dinner',
        now: DateTime(2025, 1, 10, 9),
      );
      expect(mealTime, DateTime(2025, 1, 5, 19));
      await NutritionDb.put(db, food());
      final first = (await NutritionDb.entriesForDay(db, date)).single;
      expect(first.loggedAt, greaterThan(first.atTs!));
      await NutritionDb.put(db, food(kcal: 1500));
      final edited = (await NutritionDb.entriesForDay(db, date)).single;
      expect(edited.atTs, first.atTs);
      expect(edited.loggedAt, first.loggedAt);
      expect(
        edited.copyTo('2025-01-06', 'dinner', newId: 'copy').loggedAt,
        isNull,
      );
    },
  );
  test('legacy unknown logging time stays NULL through an edit', () async {
    await db.insert('food_entry', food().toRow(1));
    await NutritionDb.put(db, food(kcal: 1500));
    expect((await NutritionDb.entriesForDay(db, date)).single.loggedAt, isNull);
  });
}
