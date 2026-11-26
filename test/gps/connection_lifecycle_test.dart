// AppState's real connection orchestration, with only the band transport replaced.
// All storage, identifiers and profile values are synthetic. No radio claims.
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/ble/ble_engine.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/state/prefs.dart';
import 'package:whoop_companion/sync/band_ownership.dart';
import 'package:whoop_companion/sync/file_log.dart';
import 'package:whoop_companion/sync/paired_device.dart';
import 'package:whoop_companion/gps/workout_clock.dart';
import 'package:whoop_companion/gps/screen_wake.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../support/root_path_provider.dart';

class LifecycleBand extends BleEngine {
  LifecycleBand() : super(onRecord: (_, _) async {}, onState: (_) {});
  final calls = <String>[];
  bool connected = false;
  bool streamsArmed = false;
  Duration? rxAge;
  @override
  Duration get sinceLastRx => rxAge ?? super.sinceLastRx;
  Duration delay = const Duration(seconds: 10);
  Future<bool> Function(String)? connecting;
  Future<void> Function(String)? command;
  Future<SyncReport> Function()? syncing;
  @override
  bool get isConnected => connected;
  @override
  bool get liveEnabled => streamsArmed;
  @override
  Duration reconnectDelay(int attempt) => delay;
  @override
  Future<bool> connectToRemoteId(
    String remoteId, {
    String? generationHint,
  }) async {
    calls.add('connect:$remoteId');
    connected = await (connecting?.call(remoteId) ?? Future.value(false));
    state.connection = connected ? 'connected' : 'disconnected';
    return connected;
  }

  @override
  Future<void> disconnect() async {
    calls.add('disconnect');
    connected = false;
    state.connection = 'disconnected';
  }

  @override
  Future<void> getBattery() async {
    calls.add('battery');
    await command?.call('battery');
  }

  @override
  Future<void> getStrapName() async {
    calls.add('name');
    await command?.call('name');
  }

  @override
  Future<void> enableLiveStreams() async {
    calls.add('live');
    await command?.call('live');
  }

  @override
  Future<void> applyHighFreqWakeWindow({
    required bool enabled,
    required DateTime? targetWake,
    Duration duration = const Duration(seconds: 7200),
    int intervalSeconds = 180,
    String reason = 'wake_window',
  }) async {
    calls.add('wake-window');
    await command?.call('wake-window');
  }

  @override
  Future<void> requestHistorySync() async {
    calls.add('history');
  }

  @override
  Future<SyncReport> runSync({
    Duration timeout = const Duration(seconds: 600),
  }) async {
    calls.add('sync');
    return await (syncing?.call() ?? Future.value(SyncReport(0, 0, true)));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState app;
  late LifecycleBand band;
  late Directory root;
  var disposed = false;
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    root = (await Directory(
      'build/coverage-remainder/connection-lifecycle',
    ).create(recursive: true)).absolute;
    PathProviderPlatform.instance = RootPathProvider(root.path);
    LocalDb.dbName = '${root.path}/synthetic.sqlite';
    await LocalDb.close();
    await databaseFactory.deleteDatabase(LocalDb.dbName);
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.ensureLoaded();
    await LocalDb.wipeAll();
    DayClock.install([], []);
    BandOwnership.resetForTest();
    band = LifecycleBand();
    app = AppState.forTesting(engine: band)
      ..paired = PairedDevice('synthetic-band-a', null, generation: 'gen4');
    disposed = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_timezone'),
          (_) async => 'UTC',
        );
  });
  tearDown(() async {
    if (!disposed) app.dispose();
    BandOwnership.resetForTest();
    DayClock.install([], []);
    await FileLog.write('Synthetic lifecycle test barrier');
  });
  tearDownAll(LocalDb.close);

  Future<void> stop(String action) async {
    if (action == 'dispose') {
      app.dispose();
      disposed = true;
    } else {
      await (action == 'end' ? app.endSession() : app.unpair());
    }
  }

  for (final armed in [false, true]) {
    test(
      'COV-47 foreground reclaim keeps a fresh link and re-arms live HR $armed',
      () async {
        // A failed initial reach still establishes the ordinary reconnect intent.
        band.connecting = (_) async => false;
        await app.openSession();
        final connects = band.calls
            .where((c) => c.startsWith('connect:'))
            .length;
        band.connected = true;
        band.rxAge = Duration.zero;
        band.streamsArmed = armed;
        await app.pauseForBackground();
        band.calls.clear();
        await app.openSession();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(
          band.calls.where((c) => c.startsWith('connect:')),
          isEmpty,
          reason:
              'Fresh foreground reclaim must not bounce a healthy connection',
        );
        expect(connects, 1);
        expect(band.calls, containsAll(['battery', 'name']));
        expect(band.calls.where((c) => c == 'live').length, 1);
        expect(app.busy, isFalse);
        await app.endSession();
        expect(BandOwnership.foregroundIntent, isFalse);
      },
    );
  }

  test(
    'COV-47 a stale resumed link is disconnected before another reach attempt',
    () async {
      band.connecting = (_) async => false;
      await app.openSession();
      band.connected = true;
      band.rxAge = const Duration(days: 1);
      await app.pauseForBackground();
      band.calls.clear();
      await app.openSession();
      expect(
        band.calls,
        containsAllInOrder(['disconnect', 'connect:synthetic-band-a']),
      );
      expect(app.busy, isFalse);
      expect(band.calls, isNot(contains('live')));
      await app.endSession();
    },
  );

  for (final action in ['end', 'unpair', 'dispose']) {
    test('a reconnect returning after $action sends no setup commands', () async {
      await app.openSession(); // Refused; supervisor now owns retry.
      final gate = Completer<bool>();
      final connecting = Completer<void>();
      band.delay = Duration.zero;
      band.connecting = (_) {
        connecting.complete();
        return gate.future;
      };
      final retry = app.debugReconnect();
      await connecting.future;
      expect(band.calls.where((s) => s.startsWith('connect:')), hasLength(2));
      await stop(action);
      band.calls.clear();
      gate.complete(true); // A retired platform connect returns late.
      await retry;
      // Its engine owns teardown of the old GATT session. AppState must not
      // arm live, query battery, start history or acquire a new ownership claim.
      expect(band.calls, isEmpty);
      expect(BandOwnership.owner, isNull);
      expect(BandOwnership.foregroundIntent, isFalse);
    });
  }

  test('an old retry cannot reconnect after a new session starts', () async {
    await app.openSession();
    band.delay = const Duration(milliseconds: 20);
    final retry = app.debugReconnect(); // Retry waits for its backoff.
    await app.endSession();
    app.paired = PairedDevice('synthetic-band-b', null, generation: 'gen5');
    await app.openSession(); // New foreground attempt also refuses.
    band.calls.clear();
    await retry;
    expect(band.calls.where((s) => s.startsWith('connect:')), isEmpty);
    expect(BandOwnership.owner, isNull);
    expect(BandOwnership.foregroundIntent, isFalse);
  });

  for (final path in ['foreground', 'retry']) {
    for (final pause in ['connect', 'battery', 'name', 'wake-window', 'live']) {
      for (final action in ['end', 'unpair', 'dispose']) {
        test('$path setup paused at $pause retires after $action', () async {
          if (path == 'retry') await app.openSession();
          band.delay = Duration.zero;
          final reached = Completer<void>(), release = Completer<void>();
          band.connecting = (_) async {
            if (pause == 'connect') {
              reached.complete();
              await release.future;
            }
            return true;
          };
          band.command = (at) async {
            if (at == pause) {
              reached.complete();
              await release.future;
            }
          };
          final opening = path == 'retry'
              ? app.debugReconnect()
              : app.openSession();
          await reached.future;
          await stop(action);
          band.calls.clear();
          release.complete();
          await opening;
          expect(band.calls, isEmpty);
          expect(app.busy, isFalse);
          expect(BandOwnership.owner, isNull);
          expect(BandOwnership.foregroundIntent, isFalse);
          expect(
            app.logLines.any((s) => s.contains('draining backlog')),
            false,
          );
        });
      }
    }
    for (final action in ['end', 'unpair', 'dispose']) {
      test(
        '$path waiting for a headless lease retires after $action',
        () async {
          if (path == 'retry') await app.openSession();
          band.calls.clear();
          band.delay = Duration.zero;
          final lease = BandOwnership.tryAcquireHeadless()!;
          final requested = Completer<void>();
          BandOwnership.registerHeadlessStop(
            lease,
            (_) => requested.complete(),
          );
          final opening = path == 'retry'
              ? app.debugReconnect()
              : app.openSession();
          await requested.future;
          await stop(action);
          band.calls.clear();
          BandOwnership.release(lease);
          await opening;
          expect(band.calls, isEmpty);
          expect(app.busy, isFalse);
          expect(BandOwnership.owner, isNull);
          expect(BandOwnership.foregroundIntent, isFalse);
        },
      );
    }
  }

  test(
    'closed and disposed retry entry points do not acquire the band',
    () async {
      await app.debugReconnect(); // Paired, but no session wants a link.
      await app.openSession();
      app.dispose();
      disposed = true;
      band.calls.clear();
      await app.debugReconnect();
      await app.openSession();
      expect(band.calls, isEmpty);
      expect(BandOwnership.owner, isNull);
      expect(BandOwnership.foregroundIntent, isFalse);
    },
  );

  for (final failure in ['refused', 'throws']) {
    test(
      'retry survives a $failure attempt and stops once the session ends',
      () async {
        await app.openSession();
        band.calls.clear();
        band.delay = Duration.zero;
        var attempts = 0;
        band.connecting = (_) async {
          attempts++;
          if (attempts == 1 && failure == 'throws') {
            throw StateError('synthetic transient transport failure');
          }
          if (attempts == 2) await app.endSession();
          return false;
        };
        await app.debugReconnect();
        expect(attempts, 2);
        expect(band.calls.where((c) => c.startsWith('connect:')), [
          'connect:synthetic-band-a',
          'connect:synthetic-band-a',
        ]);
        expect(BandOwnership.foregroundIntent, isFalse);
        band.calls.clear();
        await app.debugReconnect();
        expect(
          band.calls,
          isEmpty,
          reason: 'An ended session is respected at entry',
        );
      },
    );
  }

  for (final path in ['foreground', 'retry', 'background retry']) {
    for (final refused in [false, true]) {
      test(
        'COV-47 current $path drain publishes only its own calculation intent $refused',
        () async {
          if (path != 'foreground') await app.openSession();
          if (path == 'background retry') await app.pauseForBackground();
          band.delay = Duration.zero;
          band.connecting = (_) async => true;
          final reached = Completer<void>(), report = Completer<SyncReport>();
          band.syncing = () {
            reached.complete();
            return report.future;
          };
          await (path == 'foreground'
              ? app.openSession()
              : app.debugReconnect());
          await reached.future;
          expect(app.derivePending, false);
          if (refused) {
            report.completeError(StateError('synthetic current drain refusal'));
          } else {
            report.complete(SyncReport(4, 1, true));
          }
          for (var i = 0; i < 200; i++) {
            final done = refused
                ? app.logLines.any(
                    (s) => s.contains('synthetic current drain refusal'),
                  )
                : app.derivePending;
            if (done) break;
            await Future<void>.delayed(const Duration(milliseconds: 5));
          }
          expect(app.busy, false);
          expect(app.deriving, false);
          expect(app.derivePending, !refused);
          final jobs = await LocalDb.computeJobs(state: 'queued');
          expect(jobs, refused ? isEmpty : hasLength(1));
          if (refused) {
            expect(
              app.logLines.any(
                (s) => s.contains('synthetic current drain refusal'),
              ),
              true,
            );
          } else {
            expect(jobs.single['type'], 'derive_heavy');
            expect(jobs.single['reason'], 'capture_settled');
            expect(band.calls.where((s) => s == 'wake-window'), hasLength(2));
            expect((await LocalDb.syncLedgerEntry())!['status'], 'complete');
          }
          expect(
            await (await LocalDb.instance).query('day_result'),
            isEmpty,
            reason:
                'This tests queue publication, not a local full-night derive',
          );
          await app.endSession();
        },
      );
    }
  }

  test(
    'COV-47 current background reconnect throttles successive heavy requests',
    () async {
      await app.openSession();
      await app.pauseForBackground();
      band.delay = Duration.zero;
      band.connecting = (_) async => true;
      band.syncing = () async => SyncReport(4, 1, true);
      for (final kind in ['derive_heavy', 'derive_light']) {
        band.connected = false;
        await app.debugReconnect();
        List<Map<String, dynamic>> jobs = [];
        for (var i = 0; i < 200; i++) {
          jobs = await LocalDb.computeJobs(state: 'queued');
          if (jobs.isNotEmpty) break;
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        expect(jobs, hasLength(1));
        expect(jobs.single['type'], kind);
        expect(
          jobs.single['reason'],
          kind == 'derive_heavy' ? 'capture_settled' : 'stored_data',
        );
        expect(app.deriving, false);
        // Acknowledge the authored worker boundary without running a night derive.
        // The next reconnect must still honor the earlier heavy-request timestamp.
        await LocalDb.completeComputeJob(jobs.single['id'] as String);
      }
      expect(await (await LocalDb.instance).query('day_result'), isEmpty);
      await app.endSession();
    },
  );

  for (final path in ['foreground', 'retry', 'background retry']) {
    test(
      '$path success arms the correct stream; late drain does not revive it',
      () async {
        if (path != 'foreground') await app.openSession();
        if (path == 'background retry') await app.pauseForBackground();
        band.calls.clear();
        band.delay = Duration.zero;
        band.connecting = (_) async => true;
        final reached = Completer<void>(), release = Completer<SyncReport>();
        band.syncing = () {
          reached.complete();
          return release.future;
        };
        await (path == 'foreground' ? app.openSession() : app.debugReconnect());
        await reached.future;
        expect(
          band.calls,
          containsAllInOrder([
            'connect:synthetic-band-a',
            'wake-window',
            'live',
            'history',
            'sync',
          ]),
        );
        expect(app.busy, false);
        expect(BandOwnership.owner, BandOwnerKind.foreground);
        await app.endSession();
        band.calls.clear();
        release.complete(SyncReport(4, 1, true));
        // Let the public connection's fire-and-forget drain continuation settle.
        for (var i = 0; i < 10; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        expect(band.calls, isEmpty);
        expect(app.deriving, false);
        expect(app.derivePending, false);
        expect(BandOwnership.owner, isNull);
      },
    );
  }

  for (final at in ['plan read', 'command write']) {
    test(
      'periodic backfill held at $at cannot act on a replacement session',
      () async {
        await app.openSession(); // Establish session intent without a link.
        band.connected = true;
        final reached = Completer<void>(), release = Completer<void>();
        Future<void>? transaction;
        if (at == 'plan read') {
          transaction = (await LocalDb.instance).transaction((_) async {
            reached.complete();
            await release.future;
          });
          await reached.future;
        } else {
          band.command = (cmd) async {
            if (cmd == 'wake-window') {
              reached.complete();
              await release.future;
            }
          };
        }
        final pending = app.debugPeriodicBackfill();
        if (at == 'command write') {
          await reached.future;
        } else {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        await app.endSession();
        band.connected = true;
        band.calls.clear();
        release.complete();
        await transaction;
        await pending;
        expect(band.calls, isEmpty);
        expect(app.deriving, false);
        expect(app.derivePending, false);
      },
    );
  }

  for (final action in ['end', 'unpair', 'dispose']) {
    for (final result in ['success', 'throws']) {
      test(
        'COV-45 background startup connect $result after $action cannot arm streams',
        () async {
          await PairedDevice.save('synthetic-band-a', null, generation: 'gen4');
          await app.pauseForBackground();
          final reached = Completer<void>(), release = Completer<bool>();
          band.connecting = (_) {
            reached.complete();
            return release.future;
          };
          final startup = app.debugInit();
          await reached.future.timeout(const Duration(seconds: 5));
          expect(app.initialized, true);
          await stop(action);
          band.streamsArmed = true;
          band.calls.clear();
          if (result == 'success') {
            release.complete(true);
          } else {
            release.completeError(StateError('synthetic late connect refusal'));
          }
          await startup;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          expect(band.calls, isEmpty);
          expect(BandOwnership.owner, isNull);
          expect(BandOwnership.foregroundIntent, false);
          expect(app.logLines.any((s) => s.contains('arming recovery')), false);
        },
      );
    }
    test(
      'COV-45 background startup waiting for a headless lease retires after $action',
      () async {
        await PairedDevice.save('synthetic-band-a', null, generation: 'gen4');
        await app.pauseForBackground();
        final lease = BandOwnership.tryAcquireHeadless()!;
        final reached = Completer<void>();
        BandOwnership.registerHeadlessStop(lease, (_) => reached.complete());
        final startup = app.debugInit();
        await reached.future.timeout(const Duration(seconds: 5));
        await stop(action);
        band.calls.clear();
        BandOwnership.release(lease);
        await startup;
        expect(band.calls, isEmpty);
        expect(BandOwnership.owner, isNull);
        expect(BandOwnership.foregroundIntent, false);
      },
    );
  }
  for (final result in ['success', 'refused', 'throws']) {
    test(
      'COV-45 current background startup $result keeps its normal recovery policy',
      () async {
        await PairedDevice.save('synthetic-band-a', null, generation: 'gen4');
        await app.pauseForBackground();
        band.connecting = (_) async {
          if (result == 'throws') throw StateError('synthetic connect failure');
          return result == 'success';
        };
        await app.debugInit();
        expect(app.initialized, true);
        expect(app.initError, isNull);
        expect(band.calls.where((s) => s.startsWith('connect:')), [
          'connect:synthetic-band-a',
        ]);
        expect(
          band.calls.where((s) => s == 'live' || s == 'history' || s == 'sync'),
          isEmpty,
        );
        expect(
          app.logLines.any((s) => s.contains('arming recovery')),
          result != 'success',
        );
        expect(BandOwnership.owner, BandOwnerKind.foreground);
        await app.endSession();
        expect(BandOwnership.owner, isNull);
      },
    );
  }
  for (final refused in [false, true]) {
    test(
      'COV-45 background backfill throttles wake planning without requesting history $refused',
      () async {
        await app.openSession(); // Establish intent without a connection.
        band.connected = true;
        await app.pauseForBackground();
        band.calls.clear();
        band.command = (at) async {
          if (refused && at == 'wake-window') {
            throw StateError('synthetic wake-plan refusal');
          }
        };
        await app.debugPeriodicBackfill();
        await app.debugPeriodicBackfill();
        expect(band.calls, ['wake-window']);
        expect(app.derivePending, false);
        expect(await LocalDb.syncLedgerEntry(), isNull);
        expect(
          app.logLines.where((s) => s.contains('backgrounded;')),
          hasLength(2),
        );
        if (refused) {
          expect(
            app.logLines.any((s) => s.contains('synthetic wake-plan refusal')),
            true,
          );
        }
      },
    );
  }
  for (final count in [0, 4]) {
    test(
      'COV-45 foreground periodic completion publishes only actual record progress $count',
      () async {
        await app.openSession();
        band.connected = true;
        band.calls.clear();
        band.syncing = () async => SyncReport(count, count == 0 ? 0 : 1, true);
        await app.debugPeriodicBackfill();
        expect(band.calls, ['wake-window', 'history', 'sync']);
        if (count > 0) {
          for (var i = 0; i < 200 && !app.derivePending; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 5));
          }
        }
        expect(app.derivePending, count > 0);
        expect(
          app.logLines.any(
            (s) => s.contains('Periodic backlog check: $count records'),
          ),
          true,
        );
        expect((await LocalDb.syncLedgerEntry())!['status'], 'complete');
      },
    );
  }
  for (final failure in ['wake-window', 'sync']) {
    test('COV-45 periodic $failure refusal remains retryable', () async {
      await app.openSession();
      band.connected = true;
      band.command = (at) async {
        if (at == failure) throw StateError('synthetic setup refusal');
      };
      band.syncing = () async {
        if (failure == 'sync') throw StateError('synthetic transfer refusal');
        return SyncReport(0, 0, true);
      };
      band.calls.clear();
      await app.debugPeriodicBackfill();
      expect(app.derivePending, false);
      if (failure == 'sync') {
        expect(
          app.logLines.any(
            (s) => s.contains('Periodic history refresh failed'),
          ),
          true,
        );
        expect(await LocalDb.syncLedgerEntry(), isNull);
      } else {
        // Wake-window planning is best-effort; its failure must not suppress
        // an otherwise healthy historical transfer.
        expect(band.calls, ['wake-window', 'history', 'sync']);
        expect(
          app.logLines.any((s) => s.contains('synthetic setup refusal')),
          true,
        );
        expect((await LocalDb.syncLedgerEntry())!['status'], 'complete');
      }
      band.command = null;
      band.syncing = () async => SyncReport(0, 0, true);
      band.calls.clear();
      await app.debugPeriodicBackfill();
      expect(band.calls, ['wake-window', 'history', 'sync']);
      expect((await LocalDb.syncLedgerEntry())!['status'], 'complete');
    });
  }
  test(
    'COV-45 periodic tick cannot overlap an in-flight periodic transfer',
    () async {
      await app.openSession();
      band.connected = true;
      final reached = Completer<void>(), release = Completer<SyncReport>();
      band.syncing = () {
        reached.complete();
        return release.future;
      };
      final first = app.debugPeriodicBackfill();
      await reached.future;
      band.calls.clear();
      await app.debugPeriodicBackfill();
      final secondCalls = List.of(band.calls);
      final wasSkipped = app.logLines.any(
        (s) => s.contains('a sync burst is already running'),
      );
      release.complete(SyncReport(0, 0, true));
      await first;
      expect(secondCalls, isEmpty);
      expect(wasSkipped, true);
    },
  );
  for (final action in ['end', 'unpair', 'dispose']) {
    test(
      'COV-45 periodic report returning after $action cannot publish or derive',
      () async {
        await app.openSession();
        band.connected = true;
        final reached = Completer<void>(), release = Completer<SyncReport>();
        band.syncing = () {
          reached.complete();
          return release.future;
        };
        final first = app.debugPeriodicBackfill();
        await reached.future;
        await stop(action);
        band.connected = true;
        band.calls.clear();
        release.complete(SyncReport(9, 1, true));
        await first;
        expect(band.calls, isEmpty);
        expect(app.deriving, false);
        expect(app.derivePending, false);
        expect(await LocalDb.syncLedgerEntry(), isNull);
        expect(
          app.logLines.any((s) => s.contains('Periodic backlog check: 9')),
          false,
        );
      },
    );
  }
  for (final age in [const Duration(minutes: 3), const Duration(hours: 12)]) {
    test(
      'orphan recovery returning after disposal leaves the ${age.inHours == 0 ? 'recent' : 'stale'} session untouched',
      () async {
        final start =
            DateTime.now().subtract(age).millisecondsSinceEpoch ~/ 1000;
        await LocalDb.putSession({
          'id': 'synthetic-orphan',
          'type': 'swimming',
          'start_ts': start,
          'status': 'live',
          'created_at': start * 1000,
        });
        final reached = Completer<void>(), release = Completer<void>();
        final tx = (await LocalDb.instance).transaction((_) async {
          reached.complete();
          await release.future;
        });
        await reached.future;
        final recovery = app.debugReconcileOrphanedLiveWorkout();
        await Future<void>.delayed(const Duration(milliseconds: 10));
        app.dispose();
        disposed = true;
        release.complete();
        await tx;
        await recovery;
        try {
          expect(app.activeWorkout, isNull);
          expect(
            (await LocalDb.session('synthetic-orphan'))!['status'],
            'live',
          );
          expect(WorkoutClock.current, isNull);
          expect(ScreenWake.isHeld, false);
        } finally {
          // Before the repair, recovery re-armed a real periodic timer after
          // disposal. Retire it through the existing deletion teardown.
          if (app.activeWorkout != null) {
            await app.deleteWorkout('synthetic-orphan');
          }
          WorkoutClock.current = null;
        }
      },
    );
  }
}
