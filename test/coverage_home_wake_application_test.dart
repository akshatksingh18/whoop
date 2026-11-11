// Native region signals reach the real application callback, even at a failed
// startup gate. Native delivery is scripted; persistence and reconciliation are real.
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:whoop_companion/app.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/home_region.dart';
import 'package:whoop_companion/data/pushup_reminders.dart';
import 'package:whoop_companion/data/pushups.dart';
import 'package:whoop_companion/notify/notification_service.dart';
import 'package:whoop_companion/state/locale_controller.dart';
import 'package:whoop_companion/state/units_controller.dart';
import 'package:whoop_companion/theme/theme_controller.dart';
import 'coverage_app_gate_contracts_test.dart' show GateApp;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  final binding = LiveTestWidgetsFlutterBinding()
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  final messenger = binding.defaultBinaryMessenger;
  const home = MethodChannel('whoop/home_region');
  const notifications = MethodChannel(
    'dexterous.com/flutter/local_notifications',
  );
  const timezone = MethodChannel('flutter_timezone');
  const codec = StandardMethodCodec();
  final service = NotificationService.instance;
  final inbox = <Map<String, Object>>[];
  final acknowledgements = <List<Object?>>[];
  var refuseAck = false;
  late PushupSession session;
  setUpAll(loadAuditFonts);
  setUp(() async {
    await coverageStore('home-wake-application', fresh: true);
    await resetCoverageStore();
    inbox.clear();
    acknowledgements.clear();
    refuseAck = false;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    IOSFlutterLocalNotificationsPlugin.registerWith();
    service.debugRequestPermission = () async => true;
    service.debugProbePermission = () async => true;
    service.invalidatePermissionCache();
    messenger.setMockMethodCallHandler(timezone, (_) async => 'UTC');
    messenger.setMockMethodCallHandler(
      notifications,
      (call) async => switch (call.method) {
        'initialize' => true,
        'pendingNotificationRequests' => <Map<String, Object>>[],
        _ => null,
      },
    );
    messenger.setMockMethodCallHandler(home, (call) async {
      if (call.method == 'drain') return List.of(inbox);
      if (call.method == 'ack') {
        acknowledgements.add(List<Object?>.from(call.arguments as List));
        final saved = await PushupDb.active();
        for (final event in inbox) {
          expect(saved!.receipts, contains('home:${event['id']}'));
        }
        if (refuseAck) {
          throw PlatformException(code: 'authored_home_ack_refusal');
        }
        inbox.clear();
      }
      return null;
    });
    await HomeRegion.setHome((lat: 0, lon: 0, radius: 150));
  });
  tearDown(() async {
    await Pushups.reconcile();
    HomeRegion.onEvent = null;
    service.debugRequestPermission = null;
    service.debugProbePermission = null;
    service.invalidatePermissionCache();
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(home, null);
    messenger.setMockMethodCallHandler(notifications, null);
    messenger.setMockMethodCallHandler(timezone, null);
  });
  tearDownAll(LocalDb.close);
  Future<void> signal(String method) async {
    final reply = Completer<void>();
    await messenger.handlePlatformMessage(
      home.name,
      codec.encodeMethodCall(MethodCall(method)),
      (bytes) {
        if (bytes != null) codec.decodeEnvelope(bytes);
        reply.complete();
      },
    );
    await reply.future;
  }

  Future<void> open(WidgetTester t) async {
    final app = GateApp()..initError = 'Authored startup retry';
    final theme = ThemeController.seed(AppThemeChoice.system, Brightness.light);
    final locale = LocaleController.seed('en');
    final units = UnitsController.withUnits();
    addTearDown(app.dispose);
    addTearDown(theme.dispose);
    addTearDown(locale.dispose);
    addTearDown(units.dispose);
    await localizedPage(
      t,
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: theme),
          ChangeNotifierProvider.value(value: locale),
          ChangeNotifierProvider.value(value: units),
        ],
        child: const WhoopApp(),
      ),
      app: app,
    );
    await t.runAsync(Pushups.reconcile);
    debugPrint('Authored Home fixture: startup reconciled');
  }

  for (final enter in [false, true]) {
    for (final refuse in [false, true]) {
      testWidgets(
        'actual app Home ${enter ? 'arrival' : 'exit'} ack-refused=$refuse preserves receipt and replays once',
        (t) async {
          try {
            final now = DateTime.now();
            session = PushupSession(
              id: 'authored-home-day',
              day: todayLabel(),
              started: now.subtract(const Duration(minutes: 10)),
              interval: 45,
              state: enter ? PushupState.paused : PushupState.running,
              pauseReason: enter ? kHomeAwayReason : null,
              anchor: enter ? null : now.add(const Duration(minutes: 40)),
            );
            final old = PushupSession(
              id: 'authored-home-history',
              day: todayLabel(now.subtract(const Duration(days: 2))),
              started: now.subtract(const Duration(days: 2)),
              ended: now
                  .subtract(const Duration(days: 2))
                  .add(const Duration(hours: 1)),
              interval: 30,
              state: PushupState.ended,
            );
            late List<Map<String, Object?>> history;
            final db = (await t.runAsync(() async {
              await PushupDb.save(session);
              await PushupDb.save(old);
              final db = await LocalDb.instance;
              history = await db.query(
                'pushup_session',
                where: 'id=?',
                whereArgs: [old.id],
              );
              return db;
            }))!;
            debugPrint('Authored Home fixture: storage seeded');
            await open(t);
            await t.runAsync(() async {
              final before = (await PushupDb.active())!;
              expect(
                before.state,
                enter ? PushupState.paused : PushupState.running,
              );
              inbox.add({
                'id': 'authored-boundary',
                'kind': enter ? 'enter' : 'exit',
                'at': now.millisecondsSinceEpoch / 1000,
              });
              refuseAck = refuse;
              await signal('unknown-event');
              await Future<void>.delayed(const Duration(milliseconds: 20));
              expect(acknowledgements, isEmpty);
              expect(inbox, hasLength(1));
              await signal('event');
              for (var i = 0; i < 100 && acknowledgements.isEmpty; i++) {
                await Future<void>.delayed(const Duration(milliseconds: 10));
              }
              expect(acknowledgements, hasLength(1));
              var saved = (await PushupDb.active())!;
              expect(
                saved.state,
                enter ? PushupState.running : PushupState.paused,
              );
              expect(saved.pauseReason, enter ? isNull : kHomeAwayReason);
              expect(saved.receipts, contains('home:authored-boundary'));
              expect(
                saved.events.where((e) => e.id == 'home:authored-boundary'),
                hasLength(1),
              );
              expect(saved.events.single.source, kHomeAwayReason);
              if (enter) {
                expect(saved.anchor, isNotNull);
              } else {
                expect(saved.anchor, isNull);
              }
              expect(inbox, refuse ? hasLength(1) : isEmpty);
              refuseAck = false;
              await signal('event');
              await Pushups.reconcile();
              saved = (await PushupDb.active())!;
              expect(
                saved.events.where((e) => e.id == 'home:authored-boundary'),
                hasLength(1),
              );
              expect(acknowledgements, hasLength(refuse ? 2 : 1));
              expect(inbox, isEmpty);
              expect(
                (await HomeRegion.automation()).presence,
                enter ? HomePresence.inside : HomePresence.outside,
              );
              expect(
                await db.query(
                  'pushup_session',
                  where: 'id=?',
                  whereArgs: [old.id],
                ),
                history,
              );
              expect(await db.query('sessions'), isEmpty);
              expect(await db.query('day_result'), isEmpty);
              expect(await HomeRegion.boundary(), (
                lat: 0.0,
                lon: 0.0,
                radius: 150.0,
              ));
            });
          } finally {
            debugDefaultTargetPlatformOverride = null;
          }
        },
        timeout: const Timeout(Duration(seconds: 45)),
      );
    }
  }
}
