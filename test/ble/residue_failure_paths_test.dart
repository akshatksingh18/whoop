// Engine failure paths the journeys never reach: a derive the debouncer holds
// back, a transport body that throws, a link without a command characteristic,
// a defensive clock remedy that throws, and unbuffered persist failures.
// Synthetic frames only; no command reaches hardware.
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/ble/ble_engine.dart';
import 'package:whoop_companion/ble/ble_state.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/models.dart';
import 'package:whoop_protocol/whoop_protocol.dart' as p;
import '../data/decode_integrity_test.dart' show record;
import 'durable_boundary_test.dart' show historyStart, historyEnd, until;
import '../support/coverage_store.dart';

/// Holds the first evaluation back, then lets the derive fire.
class _HoldOnce extends DeriveDebouncer {
  _HoldOnce();
  int checks = 0;

  @override
  Duration nextCheckDelay({
    required Duration sinceLastRecord,
    required Duration sinceFirstPending,
    required Duration dataStaleness,
    bool isForeground = false,
    bool isBackgrounded = false,
  }) => const Duration(milliseconds: 1);

  @override
  bool shouldDerive({
    required bool hasPending,
    required Duration sinceLastRecord,
    required Duration sinceFirstPending,
    required Duration dataStaleness,
    bool isForeground = false,
    bool isBackgrounded = false,
  }) => ++checks > 1;
}

class _ClockThrows extends BleEngine {
  _ClockThrows({required super.onRecord, required super.onState, super.log});

  @override
  Future<void> setClock() async => throw StateError('authored clock failure');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('ble-residue-failure-paths'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  test('a derive the debouncer holds back re-arms and fires once', () async {
    final debouncer = _HoldOnce();
    var derived = 0;
    final engine = BleEngine(
      onRecord: (_, _) async {},
      onState: (_) {},
      onDataStored: () => derived++,
      deriveDebouncer: debouncer,
    );
    try {
      engine.debugInstallFakeLink(onWrite: (_) async => true);
      engine.debugIngestHistoricalFrame(p.Frame(record(24, 1), true, true));
      await until(() => derived == 1);
      expect(debouncer.checks, 2);
    } finally {
      await engine.disconnect();
    }
  });

  test('a transport body that throws reaches its caller', () async {
    var fail = false;
    final engine = BleEngine(
      onRecord: (_, _) async {},
      onState: (_) {
        if (fail) throw StateError('authored state sink failure');
      },
    );
    engine.debugInstallFakeLink(onWrite: (_) async => true);
    fail = true;
    await expectLater(engine.disconnect(), throwsStateError);
    fail = false;
    await engine.disconnect();
  });

  test('a link without a command characteristic skips the write', () async {
    final logs = <String>[];
    final engine = BleEngine(
      onRecord: (_, _) async {},
      onState: (_) {},
      log: logs.add,
    );
    try {
      engine.debugInstallFakeLink(onWrite: (_) async => true);
      engine.debugWriteHook = null;
      expect(await engine.debugWriteRaw(p.cmdGetClock(1)), false);
      expect(logs, contains('write skipped: link not ready.'));
    } finally {
      await engine.disconnect();
    }
  });

  test('a defensive clock remedy that throws still bounces the link', () async {
    final logs = <String>[];
    final engine = _ClockThrows(
      onRecord: (_, _) async {},
      onState: (_) {},
      log: logs.add,
    );
    final future = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 7 * 86400;
    try {
      for (var attempt = 1; attempt <= 3; attempt++) {
        engine.debugInstallFakeLink(
          onWrite: (_) async => false,
          onCommit: (raw, samples, token, {archives, deviceFamily}) =>
              SyncLedgerStore.commitBatch(
                raw,
                samples,
                trimToken: token,
                archives: archives,
                deviceFamily: deviceFamily,
              ),
        );
        final packet = record(24, 1);
        ByteData.sublistView(packet)
          ..setUint32(3, attempt, Endian.little)
          ..setUint32(7, future + attempt, Endian.little);
        for (final inner in [historyStart(), packet, historyEnd()]) {
          engine.debugReceiveFrame(p.Frame(inner, true, true));
        }
        await until(
          () =>
              logs.where((l) => l.contains('has no durable rows')).length ==
              attempt,
        );
        if (attempt < 3) await engine.disconnect();
      }
      await until(
        () => logs.any(
          (l) => l.contains(
            'defensive SET_CLOCK after no-durable refuse failed: '
            'Bad state: authored clock failure',
          ),
        ),
      );
      await until(() => !engine.offloadActive, attempts: 1200);
      expect(await CursorStore.read('strap_trim'), isNull);
    } finally {
      await engine.disconnect();
    }
  });

  test('unbuffered persist failures are logged, not thrown', () async {
    final logs = <String>[];
    final drain = DrainController(
      onRecord: (_, _) async => throw StateError('authored record failure'),
      onCommit: null,
      onArchive: (_) async => throw StateError('authored archive failure'),
      log: logs.add,
    );
    drain.onHistoricalRecord(
      RawRecord(
        counter: 1,
        packetType: 0x2f,
        hex: '2f1800000001',
        capturedAt: 1780000000000,
        recTs: 1780000000,
      ),
      Sample(tsEpoch: 1780000000, counter: 1, hr: 60),
      24,
    );
    drain.onUndecodableRecord(
      ArchiveRecord(
        counter: 2,
        hex: '2f6300000002',
        packetType: 0x2f,
        capturedAt: 1780000000000,
        reason: 'undecodable_rec_v99',
      ),
    );
    await until(() => logs.length == 2);
    expect(logs, [
      '[SYNC] unbuffered record persist failed: Bad state: authored record failure',
      '[SYNC] unbuffered archive persist failed: Bad state: authored archive failure',
    ]);
  });
}
