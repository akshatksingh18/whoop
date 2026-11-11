// Existing notification-completion convention, pinned independently of host hour.
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/food_day_reminder.dart';
import 'package:whoop_companion/data/nutrition_store.dart';
import 'package:whoop_companion/notify/notification_service.dart';
import 'package:whoop_companion/state/prefs.dart';
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('food-completion-clock'));
  setUp(() async {
    await resetCoverageStore();
    await Prefs.saveValues({'food.day_reminder': false});
    NotificationService.instance.debugCancel = (_) async {};
  });
  tearDown(() => NotificationService.instance.debugCancel = null);
  tearDownAll(LocalDb.close);
  for (final clock in [
    (4, 59, 59, '2021-04-06'),
    (5, 0, 0, '2021-04-07'),
    (23, 59, 59, '2021-04-07'),
  ]) {
    test(
      'COV-48 food completion at ${clock.$1}:${clock.$2}:${clock.$3} marks only the convention day',
      () async {
        final db = await LocalDb.instance;
        for (final day in ['2021-04-06', '2021-04-07']) {
          await NutritionDb.put(
            db,
            FoodEntry(
              id: 'authored-$day',
              date: day,
              meal: 'lunch',
              label: 'Synthetic meal',
              kcal: 400,
              atTs: localDayStartSec(day)! + 43200,
              loggedAt: 1617715000,
            ),
          );
        }
        final rows = await db.query('food_entry', orderBy: 'id');
        final at = DateTime(2021, 4, 7, clock.$1, clock.$2, clock.$3);
        expect(
          DayClock.localAt(at.millisecondsSinceEpoch ~/ 1000).hour,
          clock.$1,
        );
        await FoodDayReminder.onComplete(at: at);
        expect(await NutritionDb.dayMarks(db, '2021-04-06'), {
          clock.$4: 'complete',
        });
        expect(await db.query('food_entry', orderBy: 'id'), rows);
        await FoodDayReminder.onComplete(at: at);
        final marks = await db.query('food_day_mark');
        expect(marks, hasLength(1));
        expect(marks.single['date'], clock.$4);
        expect(marks.single['mark'], 'complete');
        expect(await db.query('food_entry', orderBy: 'id'), rows);
      },
    );
  }
}
