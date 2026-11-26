// Optional AppState steps whose failure costs only themselves: a wrongly typed
// recovery-ready guard and an unopenable database each log and leave the app
// running. Authored preferences and an unopenable database path, no recording.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whoop_companion/compute/derivation_engine.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/data/models.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/state/prefs.dart';
import 'package:whoop_companion/sync/paired_device.dart';

import '../support/coverage_store.dart';

class _App extends AppState {
  _App() : super.forTesting();
  @override
  Future<void> syncNow() async {}
}

/// Runs [onRescore] where the pass re-scores recent sessions: after the day
/// run, inside the post-drain block.
class _Reader extends LocalRepositoryImpl {
  _Reader(this.onRescore) : super(getProfileMap: () => const {});
  final Future<void> Function() onRescore;
  @override
  Future<int> repairSessionCalorieBasis() async => 0;
  @override
  Future<int> rescoreRecentSessions({int sinceDays = 3}) async {
    await onRescore();
    return 0;
  }
}

Future<void> _heavyJob(AppState app) async {
  await LocalDb.enqueueDeriveJob(
    type: 'derive_heavy',
    reason: 'authored best-effort job',
  );
  await app.pullRefresh(timeout: const Duration(seconds: 15));
}

Future<void> _until(bool Function() done) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!done() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('app-best-effort'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  test(
    'an unreadable recovery-ready guard skips the push only',
    () async {
      final date = todayLabel();
      await LocalDb.putDayResult(
        dayId: date,
        algoVersion: kAlgoVersion,
        finalized: true,
        payloadJson: jsonEncode({'sleep': <String, dynamic>{}}),
        windowJson: '{}',
        readiness: 72,
      );
      SharedPreferences.setMockInitialValues({'last_recovery_notif_day': 7});
      await Prefs.ensureLoaded();
      final app = _App();
      app.repo = LocalRepositoryImpl(getProfileMap: () => app.user);
      try {
        await LocalDb.enqueueDeriveJob(
          type: 'derive_heavy',
          reason: 'authored best-effort job',
        );
        await app.pullRefresh(timeout: const Duration(seconds: 15));
        await _until(
          () => app.logLines.any(
            (s) => s.startsWith('[notify] recovery-ready skipped: '),
          ),
        );
        expect(
          app.logLines.where(
            (s) => s.startsWith('[notify] recovery-ready skipped: '),
          ),
          hasLength(1),
        );
        expect((await LocalDb.dayResult(date))!['readiness'], 72);
      } finally {
        app.dispose();
        await app.engine.disconnect();
      }
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  test(
    'a heavy pass refreshes a moved baseline and returns freed pages',
    () async {
      final at = localDayStartSec('2021-04-06')! + 12 * 3600;
      await LocalDb.insertRecord(
        RawRecord(
          counter: 1,
          packetType: 47,
          hex: 'authored-rescan',
          capturedAt: at * 1000,
          recTs: at,
        ),
        Sample(tsEpoch: at, counter: 1, hr: 60, ax: 0, ay: 0, az: 1),
      );
      // 65 MB of freed pages: past the one-off VACUUM's 64 MB threshold.
      final db = await LocalDb.instance;
      await db.execute('CREATE TABLE authored_ballast (b BLOB)');
      await db.execute(
        'INSERT INTO authored_ballast VALUES (zeroblob(65 << 20))',
      );
      await db.execute('DROP TABLE authored_ballast');
      final app = _App();
      app.repo = LocalRepositoryImpl(getProfileMap: () => app.user);
      try {
        await LocalDb.enqueueDeriveJob(
          type: 'derive_heavy',
          reason: 'authored best-effort job',
        );
        await app.pullRefresh(timeout: const Duration(seconds: 15));
        await _until(
          () => app.logLines.any((s) => s.startsWith('[db] vacuum returned')),
        );
        expect(
          app.logLines.where((s) => s.startsWith('[db] vacuum returned 65 MB')),
          hasLength(1),
        );
        final deadline = DateTime.now().add(const Duration(seconds: 10));
        while (await LocalDb.getCursor('baseline_sig') == null &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(await LocalDb.getCursor('baseline_sig'), isNotNull);
        expect(
          app.logLines,
          contains(startsWith('[derive] rescan: baseline changed')),
        );
        expect(await LocalDb.freelistBytes(), lessThan(1 << 20));
      } finally {
        app.dispose();
        await app.engine.disconnect();
      }
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  test('an unopenable database costs only the schema check', () async {
    final app = AppState.forTesting()
      ..paired = PairedDevice('authored-band', null);
    // A database path under a regular file cannot be opened or rebuilt, as a
    // revoked container would refuse it.
    final original = LocalDb.dbName;
    final dir = Directory.systemTemp.createTempSync('authored-blocker-');
    final blocker = File('${dir.path}/file')..writeAsStringSync('');
    await LocalDb.close();
    LocalDb.dbName = '${blocker.path}/unopenable.sqlite';
    try {
      await app.runCadenceChecks();
      await _until(
        () => app.logLines.any(
          (s) => s.startsWith('[db] schemaHealth check skipped: '),
        ),
      );
      expect(
        app.logLines.where(
          (s) => s.startsWith('[db] schemaHealth check skipped: '),
        ),
        hasLength(1),
      );
    } finally {
      LocalDb.dbName = original;
      dir.deleteSync(recursive: true);
      app.dispose();
    }
    expect(await LocalDb.instance, isNotNull);
  });

  test(
    'a failed post-drain refresh is logged and the job completes',
    () async {
      final db = await LocalDb.instance;
      final app = _App();
      app.repo = _Reader(
        () => db.execute(
          'ALTER TABLE compute_freshness RENAME TO authored_held_freshness',
        ),
      );
      try {
        await _heavyJob(app);
        await _until(
          () => app.logLines.any(
            (s) => s.startsWith('[derive] post-drain failed: '),
          ),
        );
        expect(
          app.logLines.where(
            (s) => s.startsWith('[derive] post-drain failed: '),
          ),
          hasLength(1),
        );
        expect(app.logLines.any((s) => s.contains('job requeued')), isFalse);
      } finally {
        await db.execute(
          'ALTER TABLE authored_held_freshness RENAME TO compute_freshness',
        );
        app.dispose();
        await app.engine.disconnect();
      }
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  test(
    'reset waits for a running pass before wiping',
    () async {
      final hold = Completer<void>(), held = Completer<void>();
      final app = _App();
      app.repo = _Reader(() async {
        held.complete();
        await hold.future;
      });
      try {
        final pass = _heavyJob(app);
        await held.future;
        var reset = false;
        final wipe = app.resetAllData().then((_) => reset = true);
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(
          reset,
          isFalse,
          reason: 'the wipe waits behind the running pass',
        );
        hold.complete();
        await pass;
        await wipe;
        expect(reset, isTrue);
      } finally {
        if (!hold.isCompleted) hold.complete();
        app.dispose();
        await app.engine.disconnect();
      }
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  test(
    'a nap edit left pending by a killed app is rebuilt at startup',
    () async {
      const day = '2021-04-06';
      final start = localDayStartSec(day)! + 14 * 3600;
      await LocalDb.putNapEdit(
        dayId: day,
        startTs: start,
        endTs: start + 1800,
        source: 'added',
      );
      expect(await LocalDb.pendingNapDays(), [day]);
      final app = _App();
      try {
        await app.debugInit();
        await _until(() => !app.napRebuilding);
        final deadline = DateTime.now().add(const Duration(seconds: 10));
        while ((await LocalDb.pendingNapDays()).isNotEmpty &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(await LocalDb.pendingNapDays(), isEmpty);
        expect(await LocalDb.napEdits(day), hasLength(1));
      } finally {
        app.dispose();
        await app.engine.disconnect();
      }
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );
}
