// Build 89 (Akshat, item 4 option B): an optional evening question — "Is
// today's food complete?" — beside the automatic count. One tap on "Mark
// complete" opens the app and marks today; "Not yet" only dismisses. Either
// way the automatic rule (`dayLogState`) still decides an unmarked day.

import 'package:shared_preferences/shared_preferences.dart';

import '../notify/notification_event.dart';
import '../notify/notification_service.dart';
import 'day_label.dart';
import 'db.dart';
import 'nutrition_store.dart';

const String kFoodDayCategory = 'whoop.food.day';
const String kFoodCompleteAction = 'whoop.food.complete';
const String kFoodNotYetAction = 'whoop.food.notyet';

class FoodDayReminder {
  static const _kOn = 'food.day_reminder';
  static const _kHour = 'food.day_reminder.hour';
  static const _kMinute = 'food.day_reminder.minute';

  /// On unless switched off.
  static Future<bool> enabled() async =>
      (await SharedPreferences.getInstance()).getBool(_kOn) ?? true;

  static Future<({int hour, int minute})> time() async {
    final p = await SharedPreferences.getInstance();
    return (hour: p.getInt(_kHour) ?? 21, minute: p.getInt(_kMinute) ?? 30);
  }

  static Future<void> setEnabled(bool on) async {
    await (await SharedPreferences.getInstance()).setBool(_kOn, on);
    await arm();
  }

  /// Schedule (or cancel) the daily question. Tonight's is skipped once today
  /// is already marked either way.
  static Future<void> arm() async {
    final n = NotificationService.instance;
    if (!await enabled()) {
      await n.cancel(NotificationService.idFoodDayReminder);
      return;
    }
    final t = await time();
    final today = todayLabel();
    final marked =
        (await NutritionDb.dayMarks(await LocalDb.instance, today))[today] !=
        null;
    await n.scheduleDaily(
      id: NotificationService.idFoodDayReminder,
      category: NotifCategory.reminders,
      title: "Is today's food complete?",
      body: 'Mark it complete, or leave it — a day with half your goal or '
          'more counts on its own.',
      hour: t.hour,
      minute: t.minute,
      route: '/food',
      skipToday: marked,
      iosCategory: kFoodDayCategory,
    );
  }

  /// "Mark complete" from the notification. The question is asked in the
  /// evening, so an answer before 5 am belongs to the day before.
  static Future<void> onComplete() async {
    final now = DateTime.now();
    final day = now.hour < 5
        ? dayLabelOf(DateTime(now.year, now.month, now.day - 1))
        : todayLabel();
    await NutritionDb.setDayMark(await LocalDb.instance, day, 'complete');
    await arm();
  }
}
