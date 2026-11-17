// Current device-alert policy with its real SharedPreferences store.
// Only presentation/cancellation are authored;no OS banner is shown.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whoop_companion/notify/device_alerts.dart';
import 'package:whoop_companion/notify/notification_event.dart';
import 'package:whoop_companion/notify/notification_service.dart';

class _Presentation implements DeviceAlertSink {
  bool accepted = true;
  final events = <NotificationEvent>[];
  final cancelled = <int>[];
  @override
  Future<bool> show(NotificationEvent e) async {
    events.add(e);
    return accepted;
  }

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
    () =>
        SharedPreferences.setMockInitialValues({'authored-unrelated': 'keep'}),
  );
  for (final refused in [false, true]) {
    test(
      'default low-battery store survives a fresh owner after refused presentation=$refused',
      () async {
        final first = _Presentation()..accepted = !refused;
        final alerts = DeviceAlerts(sink: first);
        alerts.onDeviceState(batteryPct: 5, charging: false);
        await alerts.settled;
        expect(first.events.single.osId, NotificationService.idLowBattery);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getInt('device_alerts.low_armed'), refused ? isNull : 0);
        if (refused) {
          first.accepted = true;
          alerts.onDeviceState(batteryPct: 5, charging: false);
          await alerts.settled;
          expect(first.events, hasLength(2));
          expect(prefs.getInt('device_alerts.low_armed'), 0);
        }
        SharedPreferences.resetStatic();
        final nextSink = _Presentation();
        final next = DeviceAlerts(sink: nextSink);
        next.onDeviceState(batteryPct: 5, charging: false);
        await next.settled;
        expect(
          nextSink.events,
          isEmpty,
          reason: 'The accepted drain stays spent across fresh owners',
        );
        next.onDeviceState(batteryPct: 40, charging: false);
        await next.settled;
        var persisted = await SharedPreferences.getInstance();
        expect(persisted.getInt('device_alerts.low_armed'), 1);
        next.onDeviceState(batteryPct: 6, charging: false);
        await next.settled;
        expect(nextSink.events.single.osId, NotificationService.idLowBattery);
        expect(persisted.getInt('device_alerts.low_armed'), 0);
        expect(persisted.getString('authored-unrelated'), 'keep');
      },
    );
  }
  test(
    'default charger store retains event identity through a fresh owner and duplicate replay',
    () async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final first = _Presentation();
      final alerts = DeviceAlerts(sink: first);
      alerts.onDeviceState(batteryPct: 60, charging: true, chargingTs: now);
      await alerts.settled;
      expect(first.events.single.osId, NotificationService.idCharging);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(DeviceAlerts.debugLastChargeTsKey), now);
      expect(
        prefs.getInt(DeviceAlerts.debugLastChargeWallKey),
        inInclusiveRange(now, now + 10),
      );
      SharedPreferences.resetStatic();
      final second = _Presentation();
      final restarted = DeviceAlerts(sink: second);
      restarted.onDeviceState(batteryPct: 60, charging: true, chargingTs: now);
      await restarted.settled;
      expect(second.events, isEmpty);
      final reloaded = await SharedPreferences.getInstance();
      expect(reloaded.getInt(DeviceAlerts.debugLastChargeTsKey), now);
      expect(reloaded.getString('authored-unrelated'), 'keep');
    },
  );
}
