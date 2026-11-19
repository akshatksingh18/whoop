// This pull runs the full derivation pipeline. Execute it on Linux CI.
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/data/models.dart';
import 'package:whoop_companion/notify/notification_center.dart';
import 'package:whoop_companion/state/app_state.dart';

import 'support/coverage_store.dart';

class OfflineApp extends AppState {
  OfflineApp() : super.forTesting();

  @override
  Future<void> syncNow() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('pull-session-publication'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  test(
    'refresh publishes the saved session after delayed pulse records arrive',
    () async {
      final start = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 7200;
      final end = start + 180;
      final app = OfflineApp()
        ..user = {
          'age': 30,
          'weight_kg': 75,
          'height_cm': 180,
          'sex': 'm',
          'resting_hr': 55,
        };
      app.repo = LocalRepositoryImpl(
        getProfileMap: () => app.user,
        onSessionChanged: app.publishSessionChange,
      );
      final notifications = NotificationCenter.instance;
      final previous = notifications.presentSink;
      notifications.presentSink =
          (_, {bool allowPermissionPrompt = true}) async => false;
      try {
        await LocalDb.putSession({
          'id': 'authored-strength',
          'start_ts': start,
          'end_ts': end,
          'type': 'weight_training',
          'status': 'done',
          'source': 'manual',
          'created_at': start * 1000,
        });
        final before = (await LocalDb.session('authored-strength'))!;
        expect(before['trace_samples'], isNull);
        final raws = <RawRecord>[];
        final samples = <Sample>[];
        for (var at = start; at < end; at++) {
          raws.add(
            RawRecord(
              counter: at - start + 1,
              packetType: 47,
              hex: 'authored-delayed-$at',
              capturedAt: at * 1000,
              recTs: at,
            ),
          );
          samples.add(
            Sample(
              tsEpoch: at,
              counter: at - start + 1,
              hr: 145,
              rrIntervalsMs: const [],
              ax: 0,
              ay: 0,
              az: 0,
            ),
          );
        }
        await LocalDb.upsertDevice(adapterId: 'gen4');
        await LocalDb.commitSyncBatch(raws, samples, deviceFamily: 'gen4');
        const report = '[derive] rescored 1 session(s) from substrate';
        final revision = app.insightsRevision.value;
        await app.pullRefresh(timeout: const Duration(seconds: 75));
        final deadline = DateTime.now().add(const Duration(seconds: 75));
        while ((!app.logLines.any((line) => line.contains(report)) ||
                app.deriving ||
                app.derivePending) &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        final saved = (await LocalDb.session('authored-strength'))!;
        expect(app.deriving || app.derivePending, isFalse);
        expect(
          app.logLines.where((line) => line.contains(report)),
          hasLength(1),
        );
        expect(app.insightsRevision.value, greaterThan(revision));
        for (final key in [
          'id',
          'type',
          'source',
          'status',
          'start_ts',
          'end_ts',
          'created_at',
        ]) {
          expect(saved[key], before[key], reason: key);
        }
        expect(saved['trace_samples'], 180);
        expect(saved['avg_hr'], 145);
        expect(saved['strain'], isNotNull);
        expect(await LocalDb.lastDecodedRecTs(), end - 1);
      } finally {
        app.dispose();
        await app.engine.disconnect();
        notifications.presentSink = previous;
      }
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
