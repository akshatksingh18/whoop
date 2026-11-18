// Real late native action -> pending page -> refused receipt/retry -> one merge.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' show DatabaseException;
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/home_region.dart';
import 'package:whoop_companion/data/pushups.dart';
import 'package:whoop_companion/data/pushup_reminders.dart';
import 'package:whoop_companion/notify/notification_service.dart';
import 'package:whoop_companion/ui2/screens/pushups_screen.dart';
import 'coverage_pushup_screen_actions_test.dart'
    show command, flush, action, tap;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

// Keep the shared fake-clock/SQLite driver, while preserving the original
// error instead of its older bool-inferred onError conversion.
Future<void> guardedCommand(
  WidgetTester t,
  Future<void> Function() work,
) async {
  Object? problem;
  StackTrace? trace;
  await command(t, () async {
    try {
      await work();
    } catch (e, st) {
      problem = e;
      trace = st;
    }
  });
  if (problem != null) Error.throwWithStackTrace(problem!, trace!);
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const bridge = MethodChannel('whoop/home_region');
  const notifications = MethodChannel(
    'dexterous.com/flutter/local_notifications',
  );
  const timezone = MethodChannel('flutter_timezone');
  final service = NotificationService.instance;
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('pushup-pending-action-pages', fresh: true);
  });
  tearDownAll(LocalDb.close);
  testWidgets(
    'pending native done/pause survives refusal and Home navigation before one durable merge',
    (t) async {
      final oldCancel = service.debugCancel;
      final oldProbe = service.debugProbePermission;
      final oldPlatform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      IOSFlutterLocalNotificationsPlugin.registerWith();
      binding.defaultBinaryMessenger
        ..setMockMethodCallHandler(timezone, (_) async => 'America/Chicago')
        ..setMockMethodCallHandler(notifications, (c) async {
          return switch (c.method) {
            'initialize' => true,
            'pendingNotificationRequests' => <Map<String, Object>>[],
            _ => null,
          };
        });
      service.debugCancel = (_) async {};
      service.debugProbePermission = () async => false;
      addTearDown(() {
        service.debugCancel = oldCancel;
        service.debugProbePermission = oldProbe;
        debugDefaultTargetPlatformOverride = oldPlatform;
        binding.defaultBinaryMessenger.setMockMethodCallHandler(bridge, null);
        binding.defaultBinaryMessenger.setMockMethodCallHandler(
          notifications,
          null,
        );
        binding.defaultBinaryMessenger.setMockMethodCallHandler(timezone, null);
      });
      try {
        // Keep every refused/retried command in its owning application queue zone.
        for (final kind in ['done', 'pause']) {
          for (final refused in [false, true]) {
            for (final away in [false, true]) {
              final id = 'authored-$kind-$refused-$away';
              final now = DateTime.now();
              final session = PushupSession(
                id: id,
                day: todayLabel(now),
                started: DateTime(now.year, now.month, now.day),
                interval: 30,
                goal: 8,
                state: PushupState.paused,
              );
              var deliver = false, deliveries = 0;
              binding.defaultBinaryMessenger.setMockMethodCallHandler(bridge, (
                c,
              ) async {
                if (c.method == 'drain') {
                  if (deliver) {
                    deliver = false;
                    deliveries++;
                    // This is after reconcile's real inbox snapshot, before its
                    // existing Home-boundary IPC returns and before page status.
                    await PushupReminders.onAction(
                      NotificationResponse(
                        notificationResponseType:
                            NotificationResponseType.selectedNotificationAction,
                        id: 17,
                        actionId: kind == 'done'
                            ? kPushupDoneAction
                            : kPushupPauseAction,
                        payload: '/workouts/pushups?s=$id&a=17',
                      ),
                      background: true,
                    );
                  }
                  return <Object?>[];
                }
                if (c.method == 'status') {
                  return <String, Object>{
                    'authorization': 'always',
                    'monitoring': true,
                    'monitored': true,
                    'backgroundRefresh': 'available',
                  };
                }
                return null;
              });
              final history = (await t.runAsync(() async {
                await resetCoverageStore();
                await PushupDb.save(session);
                final past = now.subtract(const Duration(days: 2));
                await PushupDb.save(
                  PushupSession(
                    id: 'authored-retained-history',
                    day: todayLabel(past),
                    started: past,
                    ended: past.add(const Duration(minutes: 30)),
                    interval: 45,
                    state: PushupState.ended,
                  ),
                );
                if (away) {
                  await HomeRegion.setHome((lat: 0, lon: 0, radius: 150));
                  await HomeRegion.saveAutomation(
                    HomeAutomation(presence: HomePresence.outside),
                  );
                }
                return (await LocalDb.instance).query(
                  'pushup_session',
                  where: 'id = ?',
                  whereArgs: ['authored-retained-history'],
                );
              }))!;
              deliver = true;
              await localizedPage(t, const PushupsScreen(), settle: false);
              await flush(t);
              expect(deliveries, 1);
              expect(find.text('1 waiting to merge'), findsOneWidget);
              expect((await t.runAsync(Pushups.status))!.active!.count, 0);
              if (away) {
                expect(
                  (await readPage(t)).join(' '),
                  contains('On \u00b7 away from Home'),
                );
                await tap(t, action('Home auto-pause'));
                expect(find.byType(HomeSetupScreen), findsOneWidget);
                Navigator.of(t.element(find.byType(HomeSetupScreen))).pop();
                await flush(t);
                expect(find.text('1 waiting to merge'), findsOneWidget);
              }
              if (refused) {
                await t.runAsync(
                  () async => (await LocalDb.instance).execute(
                    "CREATE TRIGGER authored_pending_refusal BEFORE INSERT ON pushup_session BEGIN SELECT RAISE(ABORT, 'authored pending refusal'); END",
                  ),
                );
                await guardedCommand(t, () async {
                  await expectLater(
                    Pushups.reconcile(),
                    throwsA(isA<DatabaseException>()),
                  );
                });
                await flush(t);
                expect(find.text('1 waiting to merge'), findsOneWidget);
                expect((await t.runAsync(Pushups.status))!.active!.count, 0);
                await t.runAsync(
                  () async => (await LocalDb.instance).execute(
                    'DROP TRIGGER authored_pending_refusal',
                  ),
                );
              }
              await guardedCommand(t, Pushups.reconcile);
              await flush(t);
              final saved = (await t.runAsync(PushupDb.active))!;
              expect(saved.count, kind == 'done' ? 1 : 0);
              expect(saved.state, PushupState.paused);
              expect(saved.receipts, ['$id|17|17|$kind']);
              expect(await t.runAsync(PushupReminders.readInbox), isEmpty);
              expect(find.text('1 waiting to merge'), findsNothing);
              final original = saved.toJson();
              await guardedCommand(t, () async {
                await PushupReminders.onAction(
                  NotificationResponse(
                    notificationResponseType:
                        NotificationResponseType.selectedNotificationAction,
                    id: 17,
                    actionId: kind == 'done'
                        ? kPushupDoneAction
                        : kPushupPauseAction,
                    payload: '/workouts/pushups?s=$id&a=17',
                  ),
                  background: true,
                );
                await Pushups.reconcile();
              });
              await flush(t);
              expect((await t.runAsync(PushupDb.active))!.toJson(), original);
              expect(
                await t.runAsync(
                  () async => (await LocalDb.instance).query(
                    'pushup_session',
                    where: 'id = ?',
                    whereArgs: ['authored-retained-history'],
                  ),
                ),
                history,
              );
              expect(t.takeException(), isNull);
              await t.pumpWidget(const SizedBox());
              await t.pumpAndSettle();
            }
          }
        }
      } finally {
        debugDefaultTargetPlatformOverride = oldPlatform;
      }
    },
    timeout: const Timeout(Duration(seconds: 180)),
  );
}
