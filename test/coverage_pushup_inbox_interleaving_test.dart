// Synthetic native deliveries cross the real snapshot/commit/cleanup boundary.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite/sqflite.dart' show DatabaseException;
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/pushup_reminders.dart';
import 'package:whoop_companion/data/pushups.dart';
import 'support/coverage_store.dart';

class _InterleavedPaths extends PathProviderPlatform {
  _InterleavedPaths(this.root);
  final String root;
  int reads = 0;
  Future<void> Function()? beforeCleanup;

  @override
  Future<String?> getApplicationSupportPath() async {
    reads++;
    // readInbox resolves the legacy file and current directory first. The next
    // resolution is cleanup, after the real receipt has committed to SQLite.
    if (reads == 3 && beforeCleanup != null) {
      final action = beforeCleanup!;
      beforeCleanup = null;
      await action();
    }
    return root;
  }

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final originalPaths = PathProviderPlatform.instance;
  const notifications = MethodChannel(
    'dexterous.com/flutter/local_notifications',
  );
  const home = MethodChannel('whoop/home_region');
  late _InterleavedPaths paths;
  late PushupSession session;

  setUp(() async {
    await coverageStore('pushup-inbox-interleaving', fresh: true);
    await resetCoverageStore();
    final root = File(LocalDb.dbName).parent.path;
    paths = _InterleavedPaths(root);
    PathProviderPlatform.instance = paths;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    IOSFlutterLocalNotificationsPlugin.registerWith();
    messenger
      ..setMockMethodCallHandler(notifications, (call) async {
        return switch (call.method) {
          'initialize' => true,
          'pendingNotificationRequests' => <Map<String, Object>>[],
          _ => null,
        };
      })
      ..setMockMethodCallHandler(home, (_) async => null);
    session = PushupSession(
      day: todayLabel(),
      started: DateTime.now().subtract(const Duration(minutes: 1)),
      interval: 45,
      state: PushupState.paused,
    );
    await PushupDb.save(session);
    final past = DateTime.now().subtract(const Duration(days: 2));
    await PushupDb.save(
      PushupSession(
        id: 'retained-history',
        day: todayLabel(past),
        started: past,
        ended: past.add(const Duration(hours: 1)),
        interval: 30,
        goal: 8,
        state: PushupState.ended,
        events: [PushupEvent(at: past, kind: PushupEventKind.done)],
      ),
    );
  });
  tearDown(() async {
    final db = await LocalDb.instance;
    await db.execute('DROP TRIGGER IF EXISTS authored_receipt_refusal');
    await LocalDb.close();
    PathProviderPlatform.instance = originalPaths;
    debugDefaultTargetPlatformOverride = null;
    messenger
      ..setMockMethodCallHandler(notifications, null)
      ..setMockMethodCallHandler(home, null);
  });

  NotificationResponse response(int id, String kind) => NotificationResponse(
    notificationResponseType:
        NotificationResponseType.selectedNotificationAction,
    id: id,
    actionId: kind == 'done' ? kPushupDoneAction : kPushupPauseAction,
        payload: '/workouts/pushups?s=${session.id}&a=$id',
  );
  String receipt(int id, String kind) => '${session.id}|$id|$id|$kind';

  for (final legacy in [true, false]) {
    for (final kind in ['done', 'pause']) {
      for (final refused in [false, true]) {
        test(
          '${legacy ? 'legacy' : 'current'} snapshot retains late $kind'
          '${refused ? ' through receipt refusal/retry' : ''} exactly once',
          () async {
            final db = await LocalDb.instance;
            final history = await db.query(
              'pushup_session',
              where: 'id = ?',
              whereArgs: ['retained-history'],
            );
            final firstId = legacy ? 'legacy-first' : receipt(1, 'done');
            if (legacy) {
              await File('${paths.root}/pushups_inbox.json').writeAsString(
                jsonEncode([
                  PushupAction(
                    id: firstId,
                    kind: 'done',
                    sessionId: session.id,
                    at: DateTime.now(),
                  ).toJson(),
                ]),
              );
            } else {
              await PushupReminders.onAction(
                response(1, 'done'),
                background: true,
              );
            }
            var delivered = 0;
            void arm() {
              paths.reads = 0;
              paths.beforeCleanup = () async {
                // Verify the scheduling boundary against durable state, rather
                // than injecting an artificial reader result or sleeping.
                final saved = (await PushupDb.active())!;
                expect(saved.count, 1);
                expect(saved.receipts, [firstId]);
                delivered++;
                await PushupReminders.onAction(
                  response(2, kind),
                  background: true,
                );
              };
            }

            arm();
            if (refused) {
              await db.execute(
                "CREATE TRIGGER authored_receipt_refusal BEFORE "
                "INSERT ON pushup_session BEGIN SELECT RAISE(ABORT,"
                "'authored refusal'); END",
              );
              await expectLater(
                Pushups.reconcile(),
                throwsA(isA<DatabaseException>()),
              );
              expect(delivered, 0);
              // This inspection is outside the failed command: disarm its
              // scheduling hook before observing the retained inbox.
              paths.beforeCleanup = null;
              expect((await PushupDb.active())!.receipts, isEmpty);
              expect((await PushupDb.active())!.count, 0);
              expect((await PushupReminders.readInbox()).map((a) => a.id), [
                firstId,
              ]);
              await db.execute('DROP TRIGGER authored_receipt_refusal');
              arm();
            }
            await Pushups.reconcile();
            expect(delivered, 1);
            expect(paths.beforeCleanup, isNull);
            final firstSaved = (await PushupDb.active())!;
            expect(firstSaved.count, 1);
            expect(firstSaved.receipts, [firstId]);
            final waiting = await PushupReminders.readInbox();
            expect(waiting.map((a) => a.id), [receipt(2, kind)]);
            expect(waiting.single.kind, kind);
            expect(waiting.single.sessionId, session.id);
            expect(waiting.single.source, 'notification');

            await Pushups.reconcile();
            final complete = (await PushupDb.active())!;
            expect(complete.count, kind == 'done' ? 2 : 1);
            expect(complete.receipts, [firstId, receipt(2, kind)]);
            expect(complete.state, PushupState.paused);
            if (kind == 'pause') {
              expect(complete.pauseReason, 'notification');
              expect(
                complete.events.where((e) => e.kind == PushupEventKind.pause),
                hasLength(1),
              );
            }
            expect(await PushupReminders.readInbox(), isEmpty);
            final originalEvents = complete.events
                .map((e) => e.toJson())
                .toList();
            await PushupReminders.onAction(response(2, kind), background: true);
            await Pushups.reconcile();
            final replayed = (await PushupDb.active())!;
            expect(replayed.receipts, complete.receipts);
            expect(
              replayed.events.map((e) => e.toJson()).toList(),
              originalEvents,
            );
            expect(await PushupReminders.readInbox(), isEmpty);
            expect(
              await db.query(
                'pushup_session',
                where: 'id = ?',
                whereArgs: ['retained-history'],
              ),
              history,
            );
          },
        );
      }
    }
  }
}
