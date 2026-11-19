// Corrupt cached Home presence is unknown,not permission to drop native events.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/home_region.dart';
import 'package:whoop_companion/data/pushup_reminders.dart';
import 'package:whoop_companion/data/pushups.dart';
import 'package:whoop_companion/notify/notification_service.dart';
import 'support/coverage_store.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;
  const channel = MethodChannel('whoop/home_region');
  final service = NotificationService.instance;
  final inbox = <Map<String, Object>>[];
  final nativeMethods = <String>[];
  var refuseAck = false, acknowledgements = 0;
  setUpAll(() => coverageStore('home-state-recovery', fresh: true));
  setUp(() async {
    await resetCoverageStore();
    inbox.clear();
    nativeMethods.clear();
    refuseAck = false;
    acknowledgements = 0;
    service.debugCancel = (_) async {};
    service.debugProbePermission = () async => false;
    service.debugRequestPermission = () async => false;
    service.invalidatePermissionCache();
    messenger.setMockMethodCallHandler(channel, (call) async {
      nativeMethods.add(call.method);
      if (call.method == 'drain') return List.of(inbox);
      if (call.method == 'ack') {
        acknowledgements++;
        final s = (await PushupDb.active())!;
        for (final e in inbox) {
          expect(s.receipts, contains('home:${e['id']}'));
        }
        if (refuseAck) throw PlatformException(code: 'authored_ack_refusal');
        inbox.clear();
      }
      return null;
    });
    await HomeRegion.setHome((lat: 0, lon: 0, radius: 150));
  });
  tearDown(() {
    service.debugCancel = null;
    service.debugProbePermission = null;
    service.debugRequestPermission = null;
    service.invalidatePermissionCache();
    messenger.setMockMethodCallHandler(channel, null);
  });
  tearDownAll(LocalDb.close);
  for (final radius in [
    double.nan,
    HomeRegion.minRadius - 1,
    HomeRegion.maxRadius + 1,
  ]) {
    test(
      'rejected Home radius $radius preserves the saved boundary and native watch',
      () async {
        final prefs = await SharedPreferences.getInstance();
        final savedBoundary = prefs.getString('pushups.home.boundary');
        final savedState = prefs.getString('pushups.home.state');
        final before = List.of(nativeMethods);
        await expectLater(
          HomeRegion.setHome((lat: 0, lon: 0, radius: radius)),
          throwsArgumentError,
        );
        expect(prefs.getString('pushups.home.boundary'), savedBoundary);
        expect(prefs.getString('pushups.home.state'), savedState);
        expect(nativeMethods, before);
        expect(await HomeRegion.boundary(), (
          lat: 0.0,
          lon: 0.0,
          radius: 150.0,
        ));
        expect(await (await LocalDb.instance).query('pushup_session'), isEmpty);
      },
    );
  }
  for (final corrupt in ['not JSON', '[]']) {
    for (final arrival in [false, true]) {
      for (final refuse in [false, true]) {
        test(
          'Home cache $corrupt arrival=$arrival refused-ack=$refuse preserves the actual boundary receipt',
          () async {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('pushups.home.state', corrupt);
            final now = DateTime.now();
            final session = PushupSession(
              id: 'authored-cache-recovery',
              day: todayLabel(),
              started: now.subtract(const Duration(minutes: 10)),
              interval: 45,
              state: arrival ? PushupState.paused : PushupState.running,
              pauseReason: arrival ? kHomeAwayReason : null,
              anchor: arrival ? null : now.add(const Duration(minutes: 40)),
            );
            await PushupDb.save(session);
            final original = await (await LocalDb.instance).query(
              'pushup_session',
            );
            expect(
              (await HomeRegion.automation()).presence,
              HomePresence.unknown,
            );
            expect(prefs.getString('pushups.home.state'), corrupt);
            expect(
              await (await LocalDb.instance).query('pushup_session'),
              original,
            );
            inbox.add({
              'id': 'authored-state-event',
              'kind': arrival ? 'enter' : 'exit',
              'at': now.millisecondsSinceEpoch / 1000,
            });
            refuseAck = refuse;
            if (refuse) {
              // The coordinator reports the native refusal to its caller;
              // its already committed receipt must still survive the retry.
              await expectLater(
                Pushups.reconcile(),
                throwsA(
                  isA<PlatformException>().having(
                    (e) => e.code,
                    'code',
                    'authored_ack_refusal',
                  ),
                ),
              );
            } else {
              await Pushups.reconcile();
            }
            final saved = (await PushupDb.active())!;
            expect(
              saved.state,
              arrival ? PushupState.running : PushupState.paused,
            );
            expect(saved.pauseReason, arrival ? isNull : kHomeAwayReason);
            expect(saved.receipts, ['home:authored-state-event']);
            expect(saved.events, hasLength(1));
            expect(saved.events.single.id, 'home:authored-state-event');
            expect(saved.events.single.source, kHomeAwayReason);
            expect(inbox, refuse ? hasLength(1) : isEmpty);
            expect(acknowledgements, 1);
            final applied = saved.toJson();
            refuseAck = false;
            await Pushups.reconcile();
            expect((await PushupDb.active())!.toJson(), applied);
            expect(inbox, isEmpty);
            expect(acknowledgements, refuse ? 2 : 1);
            expect(
              (await HomeRegion.automation()).presence,
              arrival ? HomePresence.inside : HomePresence.outside,
            );
            expect(await HomeRegion.boundary(), (
              lat: 0.0,
              lon: 0.0,
              radius: 150.0,
            ));
            expect(await (await LocalDb.instance).query('sessions'), isEmpty);
            expect(await (await LocalDb.instance).query('day_result'), isEmpty);
          },
          timeout: const Timeout(Duration(seconds: 30)),
        );
      }
    }
  }
}
