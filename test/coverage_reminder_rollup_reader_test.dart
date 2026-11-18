// Real foreground reminder wiring over authored legacy/corrupt/quiet rollups.
// The native cancel seam is substituted; no OS delivery is claimed.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/notify/notification_prefs.dart';
import 'package:whoop_companion/notify/notification_service.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final svc = NotificationService.instance;
  final cancelled = <int?>[];
  setUpAll(() => coverageStore('reminder-rollup-reader'));
  setUp(() async {
    await resetCoverageStore();
    cancelled.clear();
    svc.debugCancel = (id) async {
      cancelled.add(id);
    };
    svc.debugProbePermission = () async => false;
    svc.debugRequestPermission = () async => false;
    svc.invalidatePermissionCache();
    await const NotificationPrefs(remindersEnabled: true).save();
  });
  tearDown(() {
    svc.debugCancel = null;
    svc.debugProbePermission = null;
    svc.debugRequestPermission = null;
    svc.invalidatePermissionCache();
  });
  tearDownAll(LocalDb.close);
  final fixtures = {
    'invalid JSON': '{',
    'non-object JSON': '[]',
    'non-list recent': jsonEncode({'recent': 'authored legacy value'}),
    'quiet mixed recent': jsonEncode({
      'recent': [
        null,
        'authored stray entry',
        for (var i = 1; i <= 7; i++) {'date': '2021-04-0$i', 'rhr': 52.0},
      ],
    }),
  };
  for (final fixture in fixtures.entries) {
    test(
      '${fixture.key} rollup cancels stale recap without inventing a finding',
      () async {
        await LocalDb.putBaseline('crossday', fixture.value);
        final app = AppState.forTesting();
        addTearDown(app.dispose);
        await app.refreshReminders();
        expect(cancelled, contains(NotificationService.idWeeklyRecap));
        expect(
          (await LocalDb.baseline('crossday'))!['payload_json'],
          fixture.value,
        );
        expect(
          await (await LocalDb.instance).query(
            'baselines',
            where: 'key LIKE ?',
            whereArgs: ['calculation:notification.report.%'],
          ),
          isEmpty,
        );
        expect(
          app.logLines.where(
            (line) => line.contains('schedule reminders skipped'),
          ),
          isEmpty,
        );
      },
    );
  }
}
