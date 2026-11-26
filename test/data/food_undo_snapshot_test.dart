// Actual SQLite row preservation,transaction rollback and concurrent-ID ownership.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/nutrition_store.dart';
import '../support/coverage_store.dart';

const day = '2021-04-06';
const target = 'authored-undo-target';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  setUpAll(() => coverageStore('food-undo-snapshot'));
  setUp(() async {
    await resetCoverageStore();
    db = await LocalDb.instance;
    NutritionDb.resetCountingContext();
    await NutritionDb.freezeCounting(db, goal: 100, goalKnown: true);
    for (final (i, id) in [
      target,
      'authored-sibling',
      'authored-other-day',
    ].indexed) {
      await NutritionDb.put(
        db,
        FoodEntry(
          id: id,
          date: i == 2 ? '2021-04-07' : day,
          meal: 'breakfast',
          label: 'Authored $id',
          quantity: 37.5,
          kcal: i == 0 ? 0 : 120,
          proteinG: 0,
          carbsG: null,
          fibreG: null,
          atTs: 1617696900 + i,
          loggedAt: 1617807700 + i,
          source: FoodSource.barcode,
          confirmed: true,
          note: 'Authored original note',
          group: 'Authored original plate',
          conv: '{"unit":"g","ref":100}',
        ),
      );
    }
    await NutritionDb.reorderEntries(db, ['authored-sibling', target]);
    await db.update(
      'food_entry',
      {'created_at': 1234, 'updated_at': 5678},
      where: 'id=?',
      whereArgs: [target],
    );
    await NutritionDb.setDayMark(db, day, 'complete');
    await NutritionDb.setDayMark(db, '2021-04-07', 'incomplete');
  });
  tearDown(() async {
    for (final trigger in [
      'undo_delete_refused',
      'undo_insert_refused',
      'undo_count_refused',
    ]) {
      await db.execute('DROP TRIGGER IF EXISTS $trigger');
    }
  });
  tearDownAll(LocalDb.close);

  Future<List<Map<String, Object?>>> rows() =>
      db.query('food_entry', orderBy: 'id');
  Future<List<Map<String, Object?>>> counts() =>
      db.query('food_day_count', orderBy: 'date');
  Map<String, Object?> countMeaning(Map<String, Object?> row) =>
      Map.of(row)..remove('updated_at');
  Future<void> intact(
    List<Map<String, Object?>> before,
    List<Map<String, Object?>> countBefore,
  ) async {
    expect(await rows(), before);
    expect((await counts()).map(countMeaning), countBefore.map(countMeaning));
    expect(
      (await counts()).singleWhere((r) => r['date'] != day),
      countBefore.singleWhere((r) => r['date'] != day),
    );
  }

  for (final position in [null, 0, 7]) {
    test(
      'Undo restores every stored column and count with position $position',
      () async {
        await db.update(
          'food_entry',
          {'pos': position},
          where: 'id=?',
          whereArgs: [target],
        );
        final before = await rows(), countBefore = await counts();
        final snapshot = await NutritionDb.deleteForUndo(db, target);
        expect(snapshot, isNotNull);
        expect(await rows(), before.where((r) => r['id'] != target).toList());
        await NutritionDb.restoreDeleted(db, snapshot!);
        await intact(before, countBefore);
        expect(before.singleWhere((r) => r['id'] == target)['kcal'], 0);
        expect(before.singleWhere((r) => r['id'] == target)['carbs_g'], isNull);
      },
    );
  }
  test(
    'Undo preserves an unknown-energy original without admitting it to averages',
    () async {
      await db.update(
        'food_entry',
        {'kcal': null, 'logged_at': null, 'at_ts': null},
        where: 'id=?',
        whereArgs: [target],
      );
      await NutritionDb.setDayMark(db, day, 'complete');
      final before = await rows(), countBefore = await counts();
      final snapshot = (await NutritionDb.deleteForUndo(db, target))!;
      await NutritionDb.restoreDeleted(db, snapshot);
      await intact(before, countBefore);
      expect(
        (await counts()).singleWhere((r) => r['date'] == day)['counted'],
        0,
      );
    },
  );
  test(
    'snapshot captures the actual latest row rather than an older editable model',
    () async {
      final stale = (await NutritionDb.entriesForDay(
        db,
        day,
      )).singleWhere((e) => e.id == target);
      await db.update(
        'food_entry',
        {'note': 'Authored newer edit', 'pos': 9, 'updated_at': 9999},
        where: 'id=?',
        whereArgs: [target],
      );
      final before = await rows(), countBefore = await counts();
      final snapshot = (await NutritionDb.deleteForUndo(db, stale.id))!;
      await NutritionDb.restoreDeleted(db, snapshot);
      await intact(before, countBefore);
      expect(stale.note, 'Authored original note');
      expect(
        (await rows()).singleWhere((r) => r['id'] == target)['note'],
        'Authored newer edit',
      );
    },
  );
  test(
    'a missing row supplies no stale Undo token and changes no stored evidence',
    () async {
      final before = await rows(), countBefore = await counts();
      expect(await NutritionDb.deleteForUndo(db, 'authored-missing'), isNull);
      await intact(before, countBefore);
    },
  );
  test(
    'an identical second restore is idempotent without replacing or recounting',
    () async {
      final before = await rows(), countBefore = await counts();
      final snapshot = (await NutritionDb.deleteForUndo(db, target))!;
      await NutritionDb.restoreDeleted(db, snapshot);
      final committedCounts = await counts();
      await db.execute(
        "CREATE TRIGGER undo_insert_refused BEFORE INSERT ON food_entry BEGIN SELECT RAISE(ABORT,'identical restore must not insert'); END",
      );
      await NutritionDb.restoreDeleted(db, snapshot);
      await intact(before, countBefore);
      expect(await counts(), committedCounts);
    },
  );
  test(
    'a concurrent replacement keeps its ID,bytes and date;Undo refuses then can retry',
    () async {
      final before = await rows(), countBefore = await counts();
      final snapshot = (await NutritionDb.deleteForUndo(db, target))!;
      await NutritionDb.put(
        db,
        const FoodEntry(
          id: target,
          date: '2021-04-08',
          meal: 'dinner',
          label: 'Authored replacement',
          kcal: 75,
        ),
      );
      final replacement = await rows(), replacementCounts = await counts();
      final revision = NutritionDb.revision.value;
      await expectLater(
        NutritionDb.restoreDeleted(db, snapshot),
        throwsStateError,
      );
      expect(await rows(), replacement);
      expect(await counts(), replacementCounts);
      expect(NutritionDb.revision.value, revision);
      await NutritionDb.delete(db, target);
      await NutritionDb.restoreDeleted(db, snapshot);
      expect(await rows(), before);
      // The replacement date's count is retained as history,not rolled back by Undo.
      expect(
        (await counts()).where((r) => r['date'] == day).map(countMeaning),
        countBefore.where((r) => r['date'] == day).map(countMeaning),
      );
    },
  );
  for (final stage in ['delete', 'delete-count', 'insert', 'restore-count']) {
    test(
      '$stage refusal rolls back row and counts;the same operation remains retryable',
      () async {
        final before = await rows(), countBefore = await counts();
        DeletedFoodEntry? snapshot;
        if (stage == 'insert' || stage == 'restore-count') {
          snapshot = (await NutritionDb.deleteForUndo(db, target))!;
        }
        final heldRows = await rows(), heldCounts = await counts();
        final revision = NutritionDb.revision.value;
        final (name, table, event) = switch (stage) {
          'delete' => ('undo_delete_refused', 'food_entry', 'DELETE'),
          'insert' => ('undo_insert_refused', 'food_entry', 'INSERT'),
          _ => ('undo_count_refused', 'food_day_count', 'UPDATE'),
        };
        await db.execute(
          "CREATE TRIGGER $name BEFORE $event ON $table BEGIN SELECT RAISE(ABORT,'authored atomic refusal'); END",
        );
        if (snapshot == null) {
          await expectLater(
            NutritionDb.deleteForUndo(db, target),
            throwsA(isA<DatabaseException>()),
          );
        } else {
          await expectLater(
            NutritionDb.restoreDeleted(db, snapshot),
            throwsA(isA<DatabaseException>()),
          );
        }
        expect(await rows(), heldRows);
        expect(await counts(), heldCounts);
        expect(NutritionDb.revision.value, revision);
        await db.execute('DROP TRIGGER $name');
        snapshot ??= (await NutritionDb.deleteForUndo(db, target))!;
        await NutritionDb.restoreDeleted(db, snapshot);
        await intact(before, countBefore);
      },
    );
  }
}
