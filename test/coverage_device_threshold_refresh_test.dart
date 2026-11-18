// Settings refreshes share the same serialized queue as real band updates.
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/notify/device_alerts.dart';
import 'package:whoop_companion/notify/notification_event.dart';
import 'package:whoop_companion/notify/notification_prefs.dart';
import 'package:whoop_companion/notify/notification_service.dart';

class _Sink implements DeviceAlertSink {
  final shown = <NotificationEvent>[];
  bool allow = true;
  @override
  Future<bool> show(NotificationEvent e) async {
    shown.add(e);
    return allow;
  }

  @override
  Future<void> cancel(int id) async {}
}

class _Store implements DeviceAlertStore {
  final values = <String, int>{};
  bool refuse = false;
  Completer<void>? started, release;
  @override
  Future<int?> readInt(String key) async {
    if (key == NotificationPrefs.batteryPctPrefKey) {
      if (refuse) throw StateError('authored threshold read refusal');
      final value = values[key];
      if (release case final gate?) {
        started!.complete();
        await gate.future;
        release = null;
      }
      return value;
    }
    return values[key];
  }

  @override
  Future<void> writeInt(String key, int value) async => values[key] = value;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Store store;
  late _Sink sink;
  late DeviceAlerts alerts;
  const key = NotificationPrefs.batteryPctPrefKey;
  setUp(() async {
    store = _Store()..values[key] = 30;
    sink = _Sink();
    alerts = DeviceAlerts(store: store, sink: sink);
    alerts.onDeviceState(batteryPct: 80);
    await alerts.settled;
    expect(sink.shown, isEmpty);
  });
  Future<void> battery(double value) async {
    alerts.onDeviceState(batteryPct: value);
    await alerts.settled;
  }

  for (final limit in [5, 40]) {
    test(
      'refresh clamps to $limit and keeps its strict lower boundary',
      () async {
        store.values[key] = limit == 5 ? -500 : 500;
        alerts.refreshThreshold();
        await alerts.settled;
        await battery(limit.toDouble());
        expect(sink.shown, isEmpty);
        await battery(limit - .5);
        expect(sink.shown, hasLength(1));
        expect(sink.shown.single.osId, NotificationService.idLowBattery);
        expect(sink.shown.single.title, 'Low battery');
        await battery(limit - 1);
        expect(sink.shown, hasLength(1));
        await battery(limit + 10);
        await battery(limit - 1);
        expect(sink.shown, hasLength(2));
      },
    );
  }
  for (final failure in [false, true]) {
    test(
      'a ${failure ? 'refused' : 'missing'} refreshed preference preserves the last threshold',
      () async {
        if (failure) {
          store.refuse = true;
        } else {
          store.values.remove(key);
        }
        alerts.refreshThreshold();
        await alerts.settled;
        await battery(25);
        expect(sink.shown, hasLength(1));
        expect(store.values['device_alerts.low_armed'], 0);
        await battery(40);
        store.refuse = false;
        store.values[key] = 10;
        alerts.refreshThreshold();
        await alerts.settled;
        await battery(20);
        expect(sink.shown, hasLength(1));
        await battery(9);
        expect(sink.shown, hasLength(2));
        expect(store.values[key], 10);
      },
    );
  }
  test(
    'an in-flight refresh finishes before a queued band update and later refresh',
    () async {
      store.values[key] = 35;
      store.started = Completer<void>();
      final release = store.release = Completer<void>();
      alerts.refreshThreshold();
      await store.started!.future;
      alerts.onDeviceState(batteryPct: 32);
      alerts.refreshThreshold();
      store.values[key] = 10;
      await Future<void>.delayed(Duration.zero);
      expect(sink.shown, isEmpty);
      release.complete();
      await alerts.settled;
      expect(sink.shown, hasLength(1));
      expect(sink.shown.single.body, contains('32%'));
      await battery(30);
      await battery(9);
      expect(sink.shown, hasLength(2));
      expect(sink.shown.last.body, contains('9%'));
      expect(store.values[key], 10);
    },
  );
  test(
    'a dropped alert remains eligible after a failed refresh and later succeeds once',
    () async {
      sink.allow = false;
      await battery(25);
      expect(sink.shown, hasLength(1));
      expect(store.values['device_alerts.low_armed'], isNot(0));
      store.refuse = true;
      alerts.refreshThreshold();
      await alerts.settled;
      sink.allow = true;
      await battery(25);
      await battery(24);
      expect(sink.shown, hasLength(2));
      expect(store.values['device_alerts.low_armed'], 0);
      expect(
        sink.shown.map((e) => e.osId),
        everyElement(NotificationService.idLowBattery),
      );
    },
  );
}
