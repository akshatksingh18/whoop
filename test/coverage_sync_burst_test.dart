// Historical catch-up orchestration against synthetic durable cursors/ledger.
// Transport reports are substituted; commit-before-ACK is tested separately.
import 'dart:async';
import 'dart:convert';
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
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

class _Band extends BleEngine {
  _Band() : super(onRecord: (_, _) async {}, onState: (_) {});
  final calls = <String>[];
  bool connected = true, stuck = false, offloading = false, foreground = true;
  int count = 0;
  int? newest;
  Future<SyncReport> Function(int)? syncing;
  Future<bool> Function()? requesting;
  var sessions = 0;
  @override
  bool get isConnected => connected;
  @override
  bool get historyStuckThisSession => stuck;
  @override
  bool get offloadActive => offloading;
  @override
  int get historyRecordCount => count;
  @override
  int? get strapHistoryNewestTs => newest;
  @override
  Duration get sinceLastRx => Duration.zero;
  @override
  Future<void> requestHistorySync() async {
    calls.add('request');
  }

  @override
  Future<bool> requestForegroundSync() async {
    calls.add('foreground');
    return await (requesting?.call() ?? Future.value(foreground));
  }

  @override
  Future<SyncReport> runSync({
    Duration timeout = const Duration(seconds: 600),
  }) async {
    calls.add('wait');
    return await syncing!(++sessions);
  }

  @override
  Future<void> disconnect() async {
    calls.add('disconnect');
    connected = false;
  }
}

Future<void> setFrontier(int value) =>
    LocalDb.setCursor('rec_ts_hw', value.toString());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState app;
  late _Band band;
  late Directory root;
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    root = (await Directory(
      'build/coverage-remainder/sync-burst',
    ).create(recursive: true)).absolute;
    PathProviderPlatform.instance = _Paths(root.path);
    LocalDb.dbName = '${root.path}/synthetic.sqlite';
    await LocalDb.close();
    await databaseFactory.deleteDatabase(LocalDb.dbName);
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.ensureLoaded();
    await LocalDb.wipeAll();
    DayClock.install([], []);
    band = _Band();
    app = AppState.forTesting(engine: band);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_timezone'),
          (_) async => 'UTC',
        );
  });
  tearDown(() async {
    app.dispose();
    BandOwnership.resetForTest();
    DayClock.install([], []);
    await FileLog.write('Synthetic catch-up test barrier');
  });
  tearDownAll(LocalDb.close);

  Future<Map<String, dynamic>> ledger() async =>
      jsonDecode((await LocalDb.syncLedgerEntry())!['meta_json'] as String)
          as Map<String, dynamic>;

  for (final connected in [false, true]) {
    test(
      '${connected ? 'terminal history' : 'no link'} never asks for a burst',
      () async {
        band.connected = connected;
        band.stuck = connected;
        final report = await app.debugRunSyncBurst();
        expect(report.complete, false);
        expect(report.records, 0);
        expect(band.calls, isEmpty);
        expect(await LocalDb.syncLedgerEntry(), isNull);
      },
    );
  }

  test(
    'received records without a batch ACK cannot prolong the drain',
    () async {
      band.newest = 2000;
      await setFrontier(1000);
      band.syncing = (_) async {
        band.count += 100;
        await setFrontier(1100);
        return SyncReport(100, 0, false);
      };
      final report = await app.debugRunSyncBurst();
      expect(report.records, 100);
      expect(band.calls, ['request', 'wait']);
      final meta = await ledger();
      expect(meta['frontier_advanced'], true);
      expect(meta['backlog_remains'], true);
      expect(meta['session_index'], 1);
      expect((await LocalDb.syncLedgerEntry())!['status'], 'session_end');
    },
  );

  for (final acknowledgedComplete in [false, true]) {
    test(
      'a ${acknowledgedComplete ? 'complete' : 'partial'} report with later flash data continues to the durable edge',
      () async {
        await setFrontier(1000);
        band.newest = 2000;
        band.syncing = (i) async {
          band.count += 10;
          await setFrontier(i == 1 ? 1400 : 2000);
          return SyncReport(10, 1, i == 2 || acknowledgedComplete);
        };
        final report = await app.debugRunSyncBurst();
        expect(report.complete, true);
        expect(band.calls, ['request', 'wait', 'request', 'wait']);
        final meta = await ledger();
        expect(meta['frontier_before_ts'], 1400);
        expect(meta['frontier_after_ts'], 2000);
        expect(meta['backlog_remains'], false);
        expect(meta['session_index'], 2);
        expect(app.lastRecordAt?.millisecondsSinceEpoch, 2000000);
        expect(
          await LocalDb.lastDecodedRecTs(),
          isNull,
          reason: 'The durable cursor also represents archived/R10 history',
        );
      },
    );
  }

  test(
    'stale timestamps with genuinely new packets drain through to newer data',
    () async {
      await setFrontier(1000);
      band.newest = 2000;
      band.syncing = (i) async {
        band.count += 5;
        if (i == 3) await setFrontier(2000);
        return SyncReport(5, 1, i == 3);
      };
      await app.debugRunSyncBurst();
      expect(band.sessions, 3);
      expect((await ledger())['session_index'], 3);
      expect(
        app.logLines.where((s) => s.contains('stale-timestamp block')),
        hasLength(2),
      );
    },
  );

  test(
    'connection lifetime packet totals are not new progress in this attempt',
    () async {
      await setFrontier(1000);
      band
        ..newest = 2000
        ..count = 9000
        ..syncing = (_) async => SyncReport(0, 1, false);
      await app.debugRunSyncBurst();
      expect(band.sessions, 1);
      expect(app.logLines.last, contains('no new history records'));
    },
  );

  test(
    'repeated stale records with a claimed backlog still have a hard bound',
    () async {
      await setFrontier(1000);
      band.newest = 2000;
      band.syncing = (_) async {
        band.count++;
        return SyncReport(1, 1, false);
      };
      await app.debugRunSyncBurst();
      expect(band.sessions, 20);
      expect((await ledger())['session_index'], 20);
      expect((await ledger())['backlog_remains'], true);
    },
  );

  for (final withFrontier in [false, true]) {
    test(
      'no known newer data stops without ${withFrontier ? 'advancing' : 'inventing'} a frontier',
      () async {
        if (withFrontier) await setFrontier(1000);
        band.syncing = (_) async => SyncReport(10, 1, false);
        await app.debugRunSyncBurst();
        expect(band.sessions, 1);
        expect(
          await LocalDb.getCursorInt('rec_ts_hw'),
          withFrontier ? 1000 : null,
        );
        expect((await ledger())['frontier_advanced'], false);
      },
    );
  }

  test('an unrequested empty wait gets exactly one explicit retry', () async {
    band.offloading = true;
    band.syncing = (_) async => SyncReport(0, 0, true);
    await app.foregroundCatchUp();
    expect(band.calls, ['foreground', 'wait', 'request', 'wait']);
    expect((await ledger())['session_index'], 2);
  });

  test(
    'foreground throttle refusal sends no request and writes no success',
    () async {
      band.foreground = false;
      await app.foregroundCatchUp();
      expect(band.calls, ['foreground']);
      expect(await LocalDb.syncLedgerEntry(), isNull);
    },
  );

  test(
    'a second wake joins neither a new burst nor a new throttle request',
    () async {
      final held = Completer<SyncReport>(), reached = Completer<void>();
      band.syncing = (_) {
        reached.complete();
        return held.future;
      };
      final first = app.foregroundCatchUp();
      await reached.future;
      await app.foregroundCatchUp();
      expect(band.calls, ['foreground', 'request', 'wait']);
      held.complete(SyncReport(0, 0, true));
      await first;
      expect(band.sessions, 1);
    },
  );

  test(
    'a transport failure releases single-flight for a successful retry',
    () async {
      band.syncing = (_) async => throw StateError('synthetic failed transfer');
      await app.foregroundCatchUp();
      expect(await LocalDb.syncLedgerEntry(), isNull);
      expect(app.logLines.last, contains('sync failed'));
      band.syncing = (_) async => SyncReport(0, 0, true);
      await app.foregroundCatchUp();
      expect(band.calls, [
        'foreground',
        'request',
        'wait',
        'foreground',
        'request',
        'wait',
      ]);
      expect((await LocalDb.syncLedgerEntry())!['status'], 'complete');
    },
  );

  test(
    'an old burst cannot request history from a replacement connection',
    () async {
      await setFrontier(1000);
      band.newest = 3000;
      final held = Completer<SyncReport>(), reached = Completer<void>();
      band.syncing = (i) async {
        if (i == 1) {
          reached.complete();
          return held.future;
        }
        return SyncReport(0, 0, false);
      };
      final first = app.debugRunSyncBurst();
      await reached.future;
      await app.endSession();
      // A fresh platform connection exists before the old wait returns.
      band.connected = true;
      band.count = 10;
      band.calls.clear();
      await setFrontier(2000);
      held.complete(SyncReport(10, 1, false));
      await first;
      expect(band.calls, isEmpty);
      expect(band.sessions, 1);
      expect(
        await LocalDb.syncLedgerEntry(),
        isNull,
        reason:
            'The retired report must not overwrite a current transfer status',
      );
    },
  );

  for (final entry in ['wake', 'forced']) {
    test(
      '$entry catch-up returning after End cannot restart calculation',
      () async {
        final held = Completer<SyncReport>(), reached = Completer<void>();
        band.syncing = (_) {
          reached.complete();
          return held.future;
        };
        final job = entry == 'wake'
            ? app.foregroundCatchUp()
            : app.forceResync();
        await reached.future;
        await app.endSession();
        band.connected = true;
        band.calls.clear();
        held.complete(SyncReport(10, 1, true));
        await job;
        expect(band.calls, isEmpty);
        expect(app.derivePending, false);
        expect(app.deriving, false);
        expect(await LocalDb.syncLedgerEntry(), isNull);
      },
    );
  }

  test(
    'an expired foreground request cannot start a replacement connection burst',
    () async {
      final reached = Completer<void>(), release = Completer<bool>();
      band.requesting = () {
        reached.complete();
        return release.future;
      };
      final job = app.foregroundCatchUp();
      await reached.future;
      await app.endSession();
      band.connected = true;
      band.calls.clear();
      release.complete(true);
      await job;
      expect(band.calls, isEmpty);
      expect(await LocalDb.syncLedgerEntry(), isNull);
    },
  );

  test(
    'a forced resync waiting for an older burst retires with its session',
    () async {
      final reached = Completer<void>(), release = Completer<SyncReport>();
      band.syncing = (_) {
        if (!reached.isCompleted) reached.complete();
        return release.future;
      };
      final old = app.foregroundCatchUp();
      await reached.future;
      final forced = app.forceResync();
      await app.endSession();
      band.connected = true;
      band.calls.clear();
      release.complete(SyncReport(0, 0, true));
      await Future.wait([old, forced]);
      expect(band.calls, isEmpty);
      expect(band.sessions, 1);
    },
  );
}
