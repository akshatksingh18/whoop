// Synthetic preference faults; no device delivery is inferred by these tests.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:whoop_companion/notify/notification_log.dart';

class _Store extends SharedPreferencesStorePlatform {
  _Store(this.values);
  final Map<String, Object> values;
  bool refuse = true, throwing = false;
  int writes = 0;
  @override
  Future<Map<String, Object>> getAll() async => Map.of(values);
  @override
  Future<bool> clear() async {
    values.clear();
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    values.remove(key);
    return true;
  }

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key.endsWith('notify.log')) {
      writes++;
      if (throwing) throw StateError('Synthetic storage failure');
      if (refuse) return false;
    }
    values[key] = value;
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final log = NotificationLog.instance;
  final now = DateTime(2026, 10, 20, 12);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    log.clock = () => now;
  });
  tearDown(() {
    log.clock = DateTime.now;
  });
  for (final throwing in [false, true]) {
    for (final all in [false, true]) {
      test(
        'read retry is durable after ${throwing ? 'throw' : 'false'}, all=$all',
        () async {
          final real = SharedPreferencesStorePlatform.instance;
          final n = LoggedNotification(
            key: 'synthetic',
            at: now,
            title: 'Synthetic notice',
            body: '',
            category: 'reminders',
          );
          final store = _Store({
            'flutter.notify.log': jsonEncode([n.toJson()]),
          })..throwing = throwing;
          SharedPreferencesStorePlatform.instance = store;
          SharedPreferences.resetStatic();
          addTearDown(() {
            SharedPreferencesStorePlatform.instance = real;
            SharedPreferences.resetStatic();
          });
          await log.entries();
          expect(log.unread.value, 1);
          Future<void> mark() => all ? log.markAllRead() : log.markRead(n.key);
          await expectLater(mark(), throwsA(isA<StateError>()));
          expect(log.unread.value, 1);
          expect((await log.entries()).single.read, false);
          await expectLater(mark(), throwsA(isA<StateError>()));
          expect(store.writes, greaterThanOrEqualTo(2));
          store.refuse = false;
          store.throwing = false;
          await mark();
          expect(log.unread.value, 0);
          SharedPreferences.resetStatic();
          expect((await log.entries()).single.read, true);
        },
      );
    }
  }
  test(
    'notification origins survive dating, marking read and cold cache',
    () async {
      await log.record(
        title: 'Synthetic sent notice',
        body: '',
        category: 'reminders',
        route: '/food',
      );
      await log.plan(
        id: 97,
        first: now.subtract(const Duration(minutes: 1)),
        repeat: PlanRepeat.once,
        title: 'Synthetic scheduled notice',
        body: '',
        category: 'reminders',
        route: '/food',
      );
      await log.reconcile();
      final entries = await log.entries();
      expect(entries.map((e) => e.origin).toSet(), {
        NotificationOrigin.submitted,
        NotificationOrigin.scheduled,
      });
      expect(
        entries.every(
          (e) => Uri.parse(e.route!).queryParameters['day'] == '2026-10-20',
        ),
        true,
      );
      await log.markAllRead();
      SharedPreferences.resetStatic();
      expect((await log.entries()).map((e) => e.origin).toSet(), {
        NotificationOrigin.submitted,
        NotificationOrigin.scheduled,
      });
      expect(
        LoggedNotification.fromJson({
          'k': 'legacy',
          'at': now.millisecondsSinceEpoch,
          't': 'Old',
        })!.origin,
        NotificationOrigin.unknown,
      );
    },
  );
}
