// A refused preference write can leave a persistent reverse reservation.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/notify/notification_event.dart';
import 'package:whoop_companion/notify/notification_ids.dart';

class RefusedNotificationStore extends InMemorySharedPreferencesStore {
  RefusedNotificationStore()
    : super.withData({'flutter.authored-unrelated': 17});

  final refused = <String>{};

  @override
  Future<bool> setValue(String type, String key, Object value) =>
      refused.contains(key)
      ? Future.value(false)
      : super.setValue(type, key, value);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final retryOwner in [false, true]) {
    test(
      'a survived reverse reservation is protected on restart: retry owner=$retryOwner',
      () async {
        final previous = SharedPreferencesStorePlatform.instance;
        final store = RefusedNotificationStore();
        final ids = NotificationIds.instance;
        void restart() {
          ids.resetForTest();
          SharedPreferences.resetStatic();
        }

        SharedPreferencesStorePlatform.instance = store;
        restart();
        addTearDown(() {
          SharedPreferencesStorePlatform.instance = previous;
          restart();
        });

        final day = todayLabel();
        NotificationEvent event(String kind) => NotificationEvent(
          dedupeKey: '$day:authored_$kind',
          category: NotifCategory.reminders,
          title: 'Authored reminder',
          body: 'Synthetic scheduled context',
          date: day,
        );
        final original = event('original');
        final neighbor = event('neighbor');
        final forward = 'flutter.notif_osid:reminders:${original.dedupeKey}';
        const next = 'flutter.notif_osnext:reminders';
        const reverse = 'flutter.notif_osslot:reminders:0';
        store.refused.addAll([forward, next]);
        final first = await ids.idFor(original);
        final saved = await store.getAll();
        final base = NotificationIds.bandBaseFor(NotifCategory.reminders);
        expect(first, base);
        expect(saved[reverse], original.dedupeKey);
        expect(saved.containsKey(forward), isFalse);
        expect(saved.containsKey(next), isFalse);

        restart();
        store.refused.clear();
        final id = await ids.idFor(retryOwner ? original : neighbor);
        final repaired = await store.getAll();
        expect(id, retryOwner ? first : first + 1);
        expect(repaired[reverse], original.dedupeKey);
        expect(repaired[next], retryOwner ? 1 : 2);
        if (retryOwner) {
          expect(repaired[forward], 0);
          restart();
          expect(await ids.idFor(original), first);
          expect(await ids.idFor(neighbor), first + 1);
        } else {
          expect(
            repaired['flutter.notif_osslot:reminders:1'],
            neighbor.dedupeKey,
          );
          expect(
            repaired['flutter.notif_osid:reminders:${neighbor.dedupeKey}'],
            1,
          );
        }
        expect((await store.getAll())['flutter.authored-unrelated'], 17);
      },
    );
  }
}
