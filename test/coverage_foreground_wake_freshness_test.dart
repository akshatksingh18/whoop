// Real foreground wake orchestration; only peripheral replies are authored.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/ble/ble_engine.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/sync/band_ownership.dart';
import 'package:whoop_companion/sync/file_log.dart';
import 'coverage_connection_lifecycle_test.dart' show LifecycleBand;
import 'support/coverage_store.dart';

class _WakeBand extends LifecycleBand {
  bool? worn;
  bool failDisconnect = false, failRequest = false;
  bool accepted = false;
  int records = 0;
  @override
  bool? get linkWristOn => worn;
  @override
  int get historyRecordCount => records;
  @override
  Future<void> disconnect() async {
    if (failDisconnect) {
      calls.add('refused disconnect');
      throw StateError('authored teardown refusal');
    }
    await super.disconnect();
  }

  @override
  Future<bool> requestForegroundSync() async {
    calls.add('foreground request');
    if (failRequest) throw StateError('authored wake request refusal');
    return accepted;
  }

  @override
  Future<SyncReport> runSync({
    Duration timeout = const Duration(seconds: 600),
  }) async {
    calls.add('wait');
    records++;
    return SyncReport(1, 1, true);
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late _WakeBand band;
  late AppState app;
  setUpAll(() async {
    await coverageStore('foreground-wake-freshness');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('flutter_timezone'),
      (_) async => 'UTC',
    );
  });
  setUp(() async {
    await resetCoverageStore();
    band = _WakeBand()
      ..connected = true
      ..rxAge = Duration.zero;
    app = AppState.forTesting(engine: band);
  });
  tearDown(() async {
    app.dispose();
    BandOwnership.resetForTest();
    await FileLog.write('Authored wake test barrier');
  });
  tearDownAll(() async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('flutter_timezone'),
      null,
    );
    await LocalDb.close();
  });
  for (final (label, live, worn, seconds, stale) in [
    ('fresh live', true, true, 29, false),
    ('live boundary', true, true, 30, true),
    ('stale live', true, true, 31, true),
    ('fresh quiet', false, true, 89, false),
    ('quiet boundary', false, true, 90, true),
    ('stale quiet', false, true, 91, true),
    ('off-wrist allowance', true, false, 600, false),
    ('off-wrist boundary', true, false, 660, true),
    ('stale off-wrist', true, false, 661, true),
  ]) {
    test(
      'COV-61 $label honors wake ownership before requesting history',
      () async {
        band
          ..streamsArmed = live
          ..worn = worn
          ..rxAge = Duration(seconds: seconds);
        await app.foregroundCatchUp();
        expect(band.calls, stale ? ['disconnect'] : ['foreground request']);
        expect(band.connected, !stale);
        expect(app.deriving, false);
        expect(app.derivePending, false);
        expect(await LocalDb.syncLedgerEntry(), isNull);
        expect(await LocalDb.getCursor('strap_trim'), isNull);
      },
    );
  }
  test('COV-61 a refused zombie teardown cannot start a flash pull', () async {
    band
      ..streamsArmed = true
      ..rxAge = const Duration(seconds: 31)
      ..failDisconnect = true;
    await expectLater(app.foregroundCatchUp(), throwsStateError);
    expect(band.calls, ['refused disconnect']);
    expect(await LocalDb.syncLedgerEntry(), isNull);
    band.failDisconnect = false;
    await app.foregroundCatchUp();
    expect(band.calls, ['refused disconnect', 'disconnect']);
    expect(band.connected, false);
  });
  test(
    'COV-61 a refused wake request preserves retry and reports new stored data',
    () async {
      band.failRequest = true;
      await app.foregroundCatchUp();
      expect(band.calls, ['foreground request']);
      expect(app.logLines.first, contains('authored wake request refusal'));
      expect(await LocalDb.syncLedgerEntry(), isNull);
      band
        ..failRequest = false
        ..accepted = true;
      await app.foregroundCatchUp();
      expect(band.calls, [
        'foreground request',
        'foreground request',
        'history',
        'wait',
      ]);
      expect(band.records, 1);
      expect((await LocalDb.syncLedgerEntry())!['status'], 'complete');
      expect(app.logLines.first, contains('1 records pulled'));
      expect(
        await LocalDb.getCursor('strap_trim'),
        isNull,
        reason: 'A transport report must never fabricate a durable trim token',
      );
    },
  );
}
